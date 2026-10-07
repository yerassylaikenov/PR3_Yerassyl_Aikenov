// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {PaymentOrderRegistry} from "../../contracts/PaymentOrderRegistry.sol";

/// @notice Fuzz-тесты (случайные входные данные) реестра платёжных поручений.
contract PaymentOrderRegistryFuzzTest is Test {
    PaymentOrderRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal operator = makeAddr("operator");
    address internal operator2 = makeAddr("operator2");
    address internal settlement = makeAddr("settlement");
    address internal stranger = makeAddr("stranger");

    bytes32 internal OPERATOR_ROLE;
    bytes32 internal SETTLEMENT_ROLE;

    bytes32 internal constant PAY_ID = keccak256("PAY-FUZZ");
    bytes32 internal constant DOC_HASH = keccak256("payment-order-fuzz.xml");

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

    /// OWASP SC04:2025, SC08:2025 — любые допустимые данные сохраняются точно (весь диапазон uint128)
    function testFuzz_Register_StoresExactData(bytes32 paymentId, bytes32 docHash, uint128 amount) public {
        vm.assume(paymentId != bytes32(0));
        vm.assume(docHash != bytes32(0));
        vm.assume(amount != 0);

        vm.prank(operator);
        registry.registerPayment(paymentId, docHash, amount);

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(paymentId);
        assertEq(p.docHash, docHash);
        assertEq(p.amount, amount);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.Registered));
        assertEq(p.registeredBy, operator);
        assertEq(p.settledBy, address(0));
        assertEq(p.registeredAt, block.timestamp);
        assertEq(registry.totalRegistered(), 1);

        assertTrue(registry.verifyDocument(paymentId, docHash));
        assertFalse(registry.verifyDocument(paymentId, bytes32(uint256(docHash) ^ 1)));
    }

    /// OWASP SC01:2025 — любой адрес без OPERATOR_ROLE не может зарегистрировать поручение
    function testFuzz_NonOperatorCannotRegister(address caller) public {
        vm.assume(caller != address(0));
        vm.assume(!registry.hasRole(OPERATOR_ROLE, caller));

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, OPERATOR_ROLE)
        );
        registry.registerPayment(PAY_ID, DOC_HASH, 1_000);

        assertEq(registry.totalRegistered(), 0);
        assertEq(uint8(registry.getPayment(PAY_ID).status), uint8(PaymentOrderRegistry.Status.None));
    }

    /// OWASP SC01:2025 — любой адрес без SETTLEMENT_ROLE не может исполнить/отклонить поручение
    function testFuzz_NonSettlementCannotFinalize(address caller, bool reject) public {
        vm.assume(caller != address(0));
        vm.assume(!registry.hasRole(SETTLEMENT_ROLE, caller));

        vm.prank(operator);
        registry.registerPayment(PAY_ID, DOC_HASH, 1_000);

        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, caller, SETTLEMENT_ROLE)
        );
        if (reject) {
            registry.markRejected(PAY_ID, bytes32("AC04"));
        } else {
            registry.markExecuted(PAY_ID);
        }

        PaymentOrderRegistry.PaymentOrder memory p = registry.getPayment(PAY_ID);
        assertEq(uint8(p.status), uint8(PaymentOrderRegistry.Status.Registered));
        assertEq(p.settledBy, address(0));
    }
}
