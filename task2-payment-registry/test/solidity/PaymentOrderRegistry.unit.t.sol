// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PaymentOrderRegistry} from "../../contracts/PaymentOrderRegistry.sol";

/// @notice Unit-тесты реестра платёжных поручений (ПР №3, Задание 2, вариант 1).
contract PaymentOrderRegistryUnitTest is Test {
    PaymentOrderRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal operator2 = makeAddr("operator2");
    address internal settlement = makeAddr("settlement");
    address internal stranger = makeAddr("stranger");

    bytes32 internal OPERATOR_ROLE;
    bytes32 internal SETTLEMENT_ROLE;
    bytes32 internal constant ADMIN_ROLE = 0x00;

    bytes32 internal constant PAY_ID = keccak256("PAY-0001");
    bytes32 internal constant DOC_HASH = keccak256("payment-order-0001.xml");
    uint128 internal constant AMOUNT = 12_500_000_000; // 125 000 000.00 KZT в тиынах
    bytes32 internal constant REASON_AC04 = bytes32("AC04"); // ISO 20022: ClosedAccountNumber

    function setUp() public {
        vm.prank(admin);
        registry = new PaymentOrderRegistry(admin);
        OPERATOR_ROLE = registry.OPERATOR_ROLE();
        SETTLEMENT_ROLE = registry.SETTLEMENT_ROLE();

        vm.startPrank(admin);
        registry.grantRole(OPERATOR_ROLE, operator);
        registry.grantRole(OPERATOR_ROLE, operator2);
        registry.grantRole(SETTLEMENT_ROLE, settlement);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------- helpers

    function _register(bytes32 id) internal {
        vm.prank(operator);
        registry.registerPayment(id, DOC_HASH, AMOUNT);
    }

    function _unauthorized(address account, bytes32 role) internal pure returns (bytes memory) {
        return abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role);
    }

    function _transition(PaymentOrderRegistry.Status from, PaymentOrderRegistry.Status to)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(PaymentOrderRegistry.InvalidStatusTransition.selector, from, to);
    }

    // ------------------------------------------------------------------ tests

    /// 1. OWASP SC01:2025
    function test_Constructor_GrantsAdminRole() public view {
        assertTrue(registry.hasRole(ADMIN_ROLE, admin));
        assertFalse(registry.hasRole(OPERATOR_ROLE, admin));
        assertFalse(registry.hasRole(SETTLEMENT_ROLE, admin));
        assertEq(registry.totalRegistered(), 0);
        assertFalse(registry.paused());
    }

    /// 2. OWASP SC04:2025
    function test_Constructor_RevertsOnZeroAdmin() public {
        vm.expectRevert(PaymentOrderRegistry.ZeroAddress.selector);
        new PaymentOrderRegistry(address(0));
    }

    /// 3. OWASP SC03:2025, SC04:2025
    function test_Register_StoresDataAndEmitsEvents() public {
        vm.warp(1_760_000_000);
        vm.expectEmit(true, true, false, true, address(registry));
        emit PaymentOrderRegistry.PaymentRegistered(PAY_ID, DOC_HASH, AMOUNT, operator);
        vm.prank(operator);
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(PAY_ID);
        assertEq(p.docHash, DOC_HASH);
        assertEq(p.amount, AMOUNT);
        assertEq(p.registeredAt, 1_760_000_000);
        assertEq(p.updatedAt, 1_760_000_000);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.Registered));
        assertEq(p.registeredBy, operator);
        assertEq(p.settledBy, address(0));
        assertEq(registry.totalRegistered(), 1);
    }

    /// 4. OWASP SC01:2025
    function test_Register_RevertsWhen_CallerHasNoOperatorRole() public {
        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, OPERATOR_ROLE));
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);

        vm.prank(settlement);
        vm.expectRevert(_unauthorized(settlement, OPERATOR_ROLE));
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);

        assertEq(registry.totalRegistered(), 0);
    }

    /// 5. OWASP SC04:2025
    function test_Register_RevertsWhen_ZeroPaymentId() public {
        vm.prank(operator);
        vm.expectRevert(PaymentOrderRegistry.InvalidPaymentId.selector);
        registry.registerPayment(bytes32(0), DOC_HASH, AMOUNT);
    }

    /// 6. OWASP SC04:2025
    function test_Register_RevertsWhen_ZeroDocHash() public {
        vm.prank(operator);
        vm.expectRevert(PaymentOrderRegistry.InvalidDocHash.selector);
        registry.registerPayment(PAY_ID, bytes32(0), AMOUNT);
    }

    /// 7. OWASP SC04:2025
    function test_Register_RevertsWhen_ZeroAmount() public {
        vm.prank(operator);
        vm.expectRevert(PaymentOrderRegistry.InvalidAmount.selector);
        registry.registerPayment(PAY_ID, DOC_HASH, 0);
    }

    /// 8. OWASP SC04:2025, SC08:2025 — граничные значения суммы
    function test_Register_AcceptsBoundaryAmounts() public {
        bytes32 idMin = keccak256("PAY-MIN");
        bytes32 idMax = keccak256("PAY-MAX");
        vm.startPrank(operator);
        registry.registerPayment(idMin, DOC_HASH, 1);
        registry.registerPayment(idMax, DOC_HASH, type(uint128).max);
        vm.stopPrank();

        assertEq(registry.getPayment(idMin).amount, 1);
        assertEq(registry.getPayment(idMax).amount, type(uint128).max);
        assertEq(registry.totalRegistered(), 2);
    }

    /// 9. OWASP SC03:2025, SC04:2025 — повторная операция
    function test_Register_RevertsWhen_Duplicate() public {
        _register(PAY_ID);
        vm.prank(operator2);
        vm.expectRevert(abi.encodeWithSelector(PaymentOrderRegistry.PaymentAlreadyExists.selector, PAY_ID));
        registry.registerPayment(PAY_ID, keccak256("other-doc"), 1);

        // исходные данные не перезаписаны
        assertEq(registry.getPayment(PAY_ID).docHash, DOC_HASH);
        assertEq(registry.getPayment(PAY_ID).registeredBy, operator);
        assertEq(registry.totalRegistered(), 1);
    }

    /// 10. OWASP SC03:2025 — paymentId не переиспользуется после Cancelled
    function test_Register_RevertsWhen_ReusingCancelledId() public {
        _register(PAY_ID);
        vm.prank(operator);
        registry.cancelPayment(PAY_ID);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(PaymentOrderRegistry.PaymentAlreadyExists.selector, PAY_ID));
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);
        assertEq(uint8(registry.getPayment(PAY_ID).status), uint8(PaymentOrderRegistry.Status.Cancelled));
    }

    /// 11. OWASP SC03:2025
    function test_MarkExecuted_UpdatesStatusAndEmits() public {
        _register(PAY_ID);
        vm.warp(block.timestamp + 1 hours);

        vm.expectEmit(true, true, false, true, address(registry));
        emit PaymentOrderRegistry.PaymentStatusChanged(
            PAY_ID, PaymentOrderRegistry.Status.Registered, PaymentOrderRegistry.Status.Executed, settlement, bytes32(0)
        );
        vm.prank(settlement);
        registry.markExecuted(PAY_ID);

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(PAY_ID);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.Executed));
        assertEq(p.settledBy, settlement);
        assertEq(p.updatedAt, block.timestamp);
        assertLt(p.registeredAt, p.updatedAt);
    }

    /// 12. OWASP SC01:2025
    function test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole() public {
        _register(PAY_ID);

        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, SETTLEMENT_ROLE));
        registry.markExecuted(PAY_ID);

        vm.prank(operator);
        vm.expectRevert(_unauthorized(operator, SETTLEMENT_ROLE));
        registry.markExecuted(PAY_ID);

        assertEq(uint8(registry.getPayment(PAY_ID).status), uint8(PaymentOrderRegistry.Status.Registered));
    }

    /// 13. OWASP SC01:2025 — принцип «4 глаз»
    function test_MarkExecuted_RevertsWhen_SelfSettlement() public {
        address dual = makeAddr("dualRoleHolder");
        vm.startPrank(admin);
        registry.grantRole(OPERATOR_ROLE, dual);
        registry.grantRole(SETTLEMENT_ROLE, dual);
        vm.stopPrank();

        vm.startPrank(dual);
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(PaymentOrderRegistry.SelfSettlementForbidden.selector, dual));
        registry.markExecuted(PAY_ID);

        vm.expectRevert(abi.encodeWithSelector(PaymentOrderRegistry.SelfSettlementForbidden.selector, dual));
        registry.markRejected(PAY_ID, REASON_AC04);
        vm.stopPrank();

        assertEq(uint8(registry.getPayment(PAY_ID).status), uint8(PaymentOrderRegistry.Status.Registered));
    }

    /// 14. OWASP SC03:2025
    function test_MarkRejected_StoresReasonAndEmits() public {
        _register(PAY_ID);

        vm.expectEmit(true, true, false, true, address(registry));
        emit PaymentOrderRegistry.PaymentStatusChanged(
            PAY_ID, PaymentOrderRegistry.Status.Registered, PaymentOrderRegistry.Status.Rejected, settlement, REASON_AC04
        );
        vm.prank(settlement);
        registry.markRejected(PAY_ID, REASON_AC04);

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(PAY_ID);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.Rejected));
        assertEq(p.settledBy, settlement);
    }

    /// 15. OWASP SC04:2025
    function test_MarkRejected_RevertsWhen_ZeroReasonCode() public {
        _register(PAY_ID);
        vm.prank(settlement);
        vm.expectRevert(PaymentOrderRegistry.InvalidReasonCode.selector);
        registry.markRejected(PAY_ID, bytes32(0));
    }

    /// 16. OWASP SC03:2025 — финальные статусы необратимы
    function test_FinalStatuses_CannotTransition() public {
        bytes32 idExec = keccak256("PAY-EXEC");
        bytes32 idRej = keccak256("PAY-REJ");
        bytes32 idCanc = keccak256("PAY-CANC");
        _register(idExec);
        _register(idRej);
        _register(idCanc);

        vm.prank(settlement);
        registry.markExecuted(idExec);
        vm.prank(settlement);
        registry.markRejected(idRej, REASON_AC04);
        vm.prank(operator);
        registry.cancelPayment(idCanc);

        bytes32[3] memory ids = [idExec, idRej, idCanc];
        PaymentOrderRegistry.Status[3] memory finals = [
            PaymentOrderRegistry.Status.Executed,
            PaymentOrderRegistry.Status.Rejected,
            PaymentOrderRegistry.Status.Cancelled
        ];

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(settlement);
            vm.expectRevert(_transition(finals[i], PaymentOrderRegistry.Status.Executed));
            registry.markExecuted(ids[i]);

            vm.prank(settlement);
            vm.expectRevert(_transition(finals[i], PaymentOrderRegistry.Status.Rejected));
            registry.markRejected(ids[i], REASON_AC04);

            vm.prank(operator);
            vm.expectRevert(_transition(finals[i], PaymentOrderRegistry.Status.Cancelled));
            registry.cancelPayment(ids[i]);

            assertEq(uint8(registry.getPayment(ids[i]).status), uint8(finals[i]));
        }
    }

    /// 17. OWASP SC01:2025, SC03:2025 — отзыв только инициатором
    function test_Cancel_RevertsWhen_NotInitiator() public {
        _register(PAY_ID);
        vm.prank(operator2);
        vm.expectRevert(abi.encodeWithSelector(PaymentOrderRegistry.NotPaymentInitiator.selector, operator2));
        registry.cancelPayment(PAY_ID);
        assertEq(uint8(registry.getPayment(PAY_ID).status), uint8(PaymentOrderRegistry.Status.Registered));
    }

    /// 18. OWASP SC04:2025
    function test_UnknownPayment_RevertsNotFound() public {
        bytes32 unknown = keccak256("UNKNOWN");
        bytes memory notFound = abi.encodeWithSelector(PaymentOrderRegistry.PaymentNotFound.selector, unknown);

        vm.prank(operator);
        vm.expectRevert(notFound);
        registry.cancelPayment(unknown);

        vm.prank(settlement);
        vm.expectRevert(notFound);
        registry.markExecuted(unknown);

        vm.prank(settlement);
        vm.expectRevert(notFound);
        registry.markRejected(unknown, REASON_AC04);

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(unknown);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.None));
        assertEq(p.docHash, bytes32(0));
        assertFalse(registry.verifyDocument(unknown, DOC_HASH));
    }

    /// 19. OWASP SC10:2025, SC01:2025 — аварийная остановка только администратором
    function test_Pause_BlocksWrites_OnlyAdminCanPause() public {
        _register(PAY_ID);

        vm.prank(operator);
        vm.expectRevert(_unauthorized(operator, ADMIN_ROLE));
        registry.pause();

        vm.prank(admin);
        registry.pause();
        assertTrue(registry.paused());

        bytes memory paused = abi.encodeWithSelector(Pausable.EnforcedPause.selector);
        vm.prank(operator);
        vm.expectRevert(paused);
        registry.registerPayment(keccak256("PAY-2"), DOC_HASH, AMOUNT);

        vm.prank(operator);
        vm.expectRevert(paused);
        registry.cancelPayment(PAY_ID);

        vm.prank(settlement);
        vm.expectRevert(paused);
        registry.markExecuted(PAY_ID);

        vm.prank(settlement);
        vm.expectRevert(paused);
        registry.markRejected(PAY_ID, REASON_AC04);

        // чтение работает и на паузе
        assertTrue(registry.verifyDocument(PAY_ID, DOC_HASH));

        vm.prank(stranger);
        vm.expectRevert(_unauthorized(stranger, ADMIN_ROLE));
        registry.unpause();

        vm.prank(admin);
        registry.unpause();

        vm.prank(operator);
        registry.registerPayment(keccak256("PAY-2"), DOC_HASH, AMOUNT);
        assertEq(registry.totalRegistered(), 2);
    }

    /// 20. OWASP SC03:2025 — целостность off-chain документа
    function test_VerifyDocument_TrueForOriginal_FalseForTampered() public {
        _register(PAY_ID);
        assertTrue(registry.verifyDocument(PAY_ID, DOC_HASH));
        assertFalse(registry.verifyDocument(PAY_ID, keccak256("payment-order-0001.xml (tampered)")));
        assertFalse(registry.verifyDocument(PAY_ID, bytes32(0)));
        assertFalse(registry.verifyDocument(keccak256("OTHER"), DOC_HASH));
    }

    /// 21. OWASP SC01:2025 — админ не имеет операционных ролей
    function test_AdminWithoutOperationalRole_CannotRegisterOrSettle() public {
        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, OPERATOR_ROLE));
        registry.registerPayment(PAY_ID, DOC_HASH, AMOUNT);

        _register(PAY_ID);

        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, SETTLEMENT_ROLE));
        registry.markExecuted(PAY_ID);

        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, SETTLEMENT_ROLE));
        registry.markRejected(PAY_ID, REASON_AC04);

        vm.prank(admin);
        vm.expectRevert(_unauthorized(admin, OPERATOR_ROLE));
        registry.cancelPayment(PAY_ID);
    }
}
