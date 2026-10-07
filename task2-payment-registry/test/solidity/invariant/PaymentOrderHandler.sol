// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CommonBase} from "forge-std/Base.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {PaymentOrderRegistry} from "../../../contracts/PaymentOrderRegistry.sol";

/// @notice Handler для invariant-тестов: вызывает реестр от имени правильных ролей и ведёт ghost-модель.
/// @dev Ограниченный пул из 10 paymentId — фаззер постоянно создаёт дубликаты и пытается
///      изменить финальные статусы. Все вызовы обёрнуты в try/catch (ожидаемые откаты не ломают прогон).
contract PaymentOrderHandler is CommonBase, StdUtils {
    PaymentOrderRegistry public immutable registry;

    address public immutable operator;
    address public immutable operator2;
    address public immutable settlement;
    /// @dev Держатель обеих ролей — проверяет принцип «4 глаз» (не может исполнить своё поручение).
    address public immutable dualRole;

    uint256 public constant POOL_SIZE = 10;

    // ----------------------------------------------------------- ghost-модель
    mapping(bytes32 => PaymentOrderRegistry.Status) public ghost_status;
    mapping(bytes32 => PaymentOrderRegistry.Status) public ghost_finalStatus; // снимок первого финального статуса
    mapping(bytes32 => bytes32) public ghost_docHash;
    mapping(bytes32 => uint128) public ghost_amount;
    mapping(bytes32 => address) public ghost_registeredBy;

    uint256 public ghost_totalRegistered;
    uint256 public ghost_unauthorizedSuccess;

    // статистика вызовов (для наглядности)
    uint256 public calls_register;
    uint256 public calls_cancel;
    uint256 public calls_execute;
    uint256 public calls_reject;
    uint256 public calls_strangerAttack;

    constructor(
        PaymentOrderRegistry registry_,
        address operator_,
        address operator2_,
        address settlement_,
        address dualRole_
    ) {
        registry = registry_;
        operator = operator_;
        operator2 = operator2_;
        settlement = settlement_;
        dualRole = dualRole_;
    }

    function paymentIdAt(uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encode("PAY", index % POOL_SIZE));
    }

    function _pickOperator(uint256 seed) internal view returns (address) {
        uint256 k = seed % 3;
        return k == 0 ? operator : (k == 1 ? operator2 : dualRole);
    }

    function _pickSettler(uint256 seed) internal view returns (address) {
        return seed % 2 == 0 ? settlement : dualRole;
    }

    function _isFinal(PaymentOrderRegistry.Status s) internal pure returns (bool) {
        return s == PaymentOrderRegistry.Status.Executed || s == PaymentOrderRegistry.Status.Rejected
            || s == PaymentOrderRegistry.Status.Cancelled;
    }

    function _recordTransition(bytes32 id, PaymentOrderRegistry.Status to) internal {
        ghost_status[id] = to;
        if (_isFinal(to) && ghost_finalStatus[id] == PaymentOrderRegistry.Status.None) {
            ghost_finalStatus[id] = to;
        }
    }

    // ---------------------------------------------------------------- actions

    function register(uint256 idSeed, bytes32 docHash, uint128 amount, uint256 actorSeed) external {
        calls_register++;
        bytes32 id = paymentIdAt(idSeed);
        if (docHash == bytes32(0)) docHash = keccak256(abi.encode(idSeed));
        amount = uint128(bound(amount, 1, type(uint128).max));
        address actor = _pickOperator(actorSeed);

        vm.prank(actor);
        try registry.registerPayment(id, docHash, amount) {
            if (ghost_status[id] == PaymentOrderRegistry.Status.None) {
                ghost_docHash[id] = docHash;
                ghost_amount[id] = amount;
                ghost_registeredBy[id] = actor;
                ghost_totalRegistered++;
            }
            _recordTransition(id, PaymentOrderRegistry.Status.Registered);
        } catch {}
    }

    function cancel(uint256 idSeed, uint256 actorSeed) external {
        calls_cancel++;
        bytes32 id = paymentIdAt(idSeed);
        address actor = _pickOperator(actorSeed);

        vm.prank(actor);
        try registry.cancelPayment(id) {
            _recordTransition(id, PaymentOrderRegistry.Status.Cancelled);
        } catch {}
    }

    function execute(uint256 idSeed, uint256 actorSeed) external {
        calls_execute++;
        bytes32 id = paymentIdAt(idSeed);
        address actor = _pickSettler(actorSeed);

        vm.prank(actor);
        try registry.markExecuted(id) {
            _recordTransition(id, PaymentOrderRegistry.Status.Executed);
        } catch {}
    }

    function reject(uint256 idSeed, bytes32 reasonCode, uint256 actorSeed) external {
        calls_reject++;
        bytes32 id = paymentIdAt(idSeed);
        address actor = _pickSettler(actorSeed);

        vm.prank(actor);
        try registry.markRejected(id, reasonCode) {
            _recordTransition(id, PaymentOrderRegistry.Status.Rejected);
        } catch {}
    }

    /// @notice Случайный адрес без ролей пытается вызвать каждую функцию записи.
    function strangerAttack(address attacker, uint256 idSeed, bytes32 data) external {
        calls_strangerAttack++;
        if (
            attacker == address(0) || registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), attacker)
                || registry.hasRole(registry.OPERATOR_ROLE(), attacker)
                || registry.hasRole(registry.SETTLEMENT_ROLE(), attacker)
        ) return;

        bytes32 id = paymentIdAt(idSeed);
        if (data == bytes32(0)) data = bytes32(uint256(1));

        vm.prank(attacker);
        try registry.registerPayment(id, data, 1) {
            ghost_unauthorizedSuccess++;
        } catch {}

        vm.prank(attacker);
        try registry.cancelPayment(id) {
            ghost_unauthorizedSuccess++;
        } catch {}

        vm.prank(attacker);
        try registry.markExecuted(id) {
            ghost_unauthorizedSuccess++;
        } catch {}

        vm.prank(attacker);
        try registry.markRejected(id, data) {
            ghost_unauthorizedSuccess++;
        } catch {}

        vm.prank(attacker);
        try registry.pause() {
            ghost_unauthorizedSuccess++;
        } catch {}

        bytes32 operatorRole = registry.OPERATOR_ROLE();
        vm.prank(attacker);
        try registry.grantRole(operatorRole, attacker) {
            ghost_unauthorizedSuccess++;
        } catch {}
    }
}
