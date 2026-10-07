// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {PaymentOrderRegistry} from "../../../contracts/PaymentOrderRegistry.sol";
import {PaymentOrderHandler} from "./PaymentOrderHandler.sol";

/// @notice Инварианты безопасности INV-1…INV-5 из архитектуры (Задание 1, стр. 4.2).
contract PaymentOrderRegistryInvariantTest is Test {
    PaymentOrderRegistry internal registry;
    PaymentOrderHandler internal handler;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal operator2 = makeAddr("operator2");
    address internal settlement = makeAddr("settlement");
    address internal dualRole = makeAddr("dualRole");

    function setUp() public {
        vm.prank(admin);
        registry = new PaymentOrderRegistry(admin);

        vm.startPrank(admin);
        registry.grantRole(registry.OPERATOR_ROLE(), operator);
        registry.grantRole(registry.OPERATOR_ROLE(), operator2);
        registry.grantRole(registry.SETTLEMENT_ROLE(), settlement);
        registry.grantRole(registry.OPERATOR_ROLE(), dualRole);
        registry.grantRole(registry.SETTLEMENT_ROLE(), dualRole);
        vm.stopPrank();

        handler = new PaymentOrderHandler(registry, operator, operator2, settlement, dualRole);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = PaymentOrderHandler.register.selector;
        selectors[1] = PaymentOrderHandler.cancel.selector;
        selectors[2] = PaymentOrderHandler.execute.selector;
        selectors[3] = PaymentOrderHandler.reject.selector;
        selectors[4] = PaymentOrderHandler.strangerAttack.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    /// INV-1. OWASP SC01:2025 — состояние меняют только держатели ролей
    function invariant_INV1_OnlyRoleHoldersChangeState() public view {
        assertEq(handler.ghost_unauthorizedSuccess(), 0, "INV-1: unauthorized call succeeded");
        assertFalse(registry.paused(), "INV-1: stranger paused the registry");
    }

    /// INV-2. OWASP SC03:2025 — финальные статусы необратимы
    function invariant_INV2_FinalStatusesAreImmutable() public view {
        for (uint256 i = 0; i < handler.POOL_SIZE(); i++) {
            bytes32 id = handler.paymentIdAt(i);
            PaymentOrderRegistry.Status snap = handler.ghost_finalStatus(id);
            if (snap != PaymentOrderRegistry.Status.None) {
                assertEq(uint8(registry.getPayment(id).status), uint8(snap), "INV-2: final status changed");
            }
            assertEq(
                uint8(registry.getPayment(id).status), uint8(handler.ghost_status(id)), "INV-2: status != ghost model"
            );
        }
    }

    /// INV-3. OWASP SC03:2025 — docHash и amount неизменны после регистрации
    function invariant_INV3_PaymentDataImmutable() public view {
        for (uint256 i = 0; i < handler.POOL_SIZE(); i++) {
            bytes32 id = handler.paymentIdAt(i);
            PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(id);
            if (p.status == PaymentOrderRegistry.Status.None) continue;
            assertEq(p.docHash, handler.ghost_docHash(id), "INV-3: docHash changed");
            assertEq(p.amount, handler.ghost_amount(id), "INV-3: amount changed");
            assertEq(p.registeredBy, handler.ghost_registeredBy(id), "INV-3: registeredBy changed");
        }
    }

    /// INV-4. OWASP SC01:2025 — принцип «4 глаз»: исполнитель ≠ инициатор и имеет SETTLEMENT_ROLE
    function invariant_INV4_FourEyes() public view {
        bytes32 settlementRole = registry.SETTLEMENT_ROLE();
        for (uint256 i = 0; i < handler.POOL_SIZE(); i++) {
            PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(handler.paymentIdAt(i));
            if (p.status == PaymentOrderRegistry.Status.Executed || p.status == PaymentOrderRegistry.Status.Rejected) {
                assertTrue(p.settledBy != p.registeredBy, "INV-4: self-settlement");
                assertTrue(registry.hasRole(settlementRole, p.settledBy), "INV-4: settledBy without SETTLEMENT_ROLE");
            } else {
                assertEq(p.settledBy, address(0), "INV-4: settledBy set for non-settled payment");
            }
        }
    }

    /// INV-5. OWASP SC03:2025 — счётчик регистраций соответствует модели
    function invariant_INV5_TotalRegisteredMatchesGhost() public view {
        assertEq(registry.totalRegistered(), handler.ghost_totalRegistered(), "INV-5: counter != ghost");
        uint256 existing;
        for (uint256 i = 0; i < handler.POOL_SIZE(); i++) {
            if (registry.getPayment(handler.paymentIdAt(i)).status != PaymentOrderRegistry.Status.None) existing++;
        }
        assertEq(registry.totalRegistered(), existing, "INV-5: counter != number of existing payments");
    }
}
