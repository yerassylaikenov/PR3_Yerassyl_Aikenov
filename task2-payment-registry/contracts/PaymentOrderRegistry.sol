// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title PaymentOrderRegistry
 * @notice Ð ÐµÐµÑÑ‚Ñ€ ÑÑ‚Ð°Ñ‚ÑƒÑÐ¾Ð² Ð¼ÐµÐ¶Ð±Ð°Ð½ÐºÐ¾Ð²ÑÐºÐ¸Ñ… Ð¿Ð»Ð°Ñ‚Ñ‘Ð¶Ð½Ñ‹Ñ… Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ð¹ (ÐŸÐ  â„–3, Ð²Ð°Ñ€Ð¸Ð°Ð½Ñ‚ 1 Â«Ð‘Ð°Ð½ÐºÐ¸ Ð¸ Ñ„Ð¸Ð½Ñ‚ÐµÑ…Â»).
 *         On-chain Ñ…Ñ€Ð°Ð½Ð¸Ñ‚ÑÑ Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ð¿ÑÐµÐ²Ð´Ð¾Ð½Ð¸Ð¼Ð½Ñ‹Ð¹ paymentId, keccak256-Ñ…ÐµÑˆ Ð´Ð¾ÐºÑƒÐ¼ÐµÐ½Ñ‚Ð°, ÑÑƒÐ¼Ð¼Ð°,
 *         ÑÑ‚Ð°Ñ‚ÑƒÑ, Ð°Ð´Ñ€ÐµÑÐ° Ñ€Ð¾Ð»ÐµÐ¹ Ð¸ Ð²Ñ€ÐµÐ¼Ñ. ÐžÑ€Ð¸Ð³Ð¸Ð½Ð°Ð» Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ Ð¸ Ð¿ÐµÑ€ÑÐ¾Ð½Ð°Ð»ÑŒÐ½Ñ‹Ðµ/Ð±Ð°Ð½ÐºÐ¾Ð²ÑÐºÐ¸Ðµ Ð´Ð°Ð½Ð½Ñ‹Ðµ
 *         (Ð¤Ð˜Ðž, Ð˜Ð˜Ð/Ð‘Ð˜Ð, IBAN, Ð½Ð°Ð·Ð½Ð°Ñ‡ÐµÐ½Ð¸Ðµ Ð¿Ð»Ð°Ñ‚ÐµÐ¶Ð°, Ð½Ð¾Ð¼ÐµÑ€ Ð¾Ð¿ÐµÑ€Ð°Ñ†Ð¸Ð¸) Ñ…Ñ€Ð°Ð½ÑÑ‚ÑÑ off-chain Ð² ÐÐ‘Ð¡ Ð±Ð°Ð½ÐºÐ°.
 *
 * @dev Ð Ð¾Ð»Ð¸ (OpenZeppelin AccessControl, Ð¿Ñ€Ð¾Ð²ÐµÑ€ÐºÐ° ÑÑ‚Ñ€Ð¾Ð³Ð¾ Ð¿Ð¾ msg.sender, tx.origin Ð½Ðµ Ð¸ÑÐ¿Ð¾Ð»ÑŒÐ·ÑƒÐµÑ‚ÑÑ):
 *      - DEFAULT_ADMIN_ROLE â€” ÑƒÐ¿Ñ€Ð°Ð²Ð»ÐµÐ½Ð¸Ðµ Ñ€Ð¾Ð»ÑÐ¼Ð¸, pause/unpause (Ð½Ðµ Ð¸Ð¼ÐµÐµÑ‚ Ð¾Ð¿ÐµÑ€Ð°Ñ†Ð¸Ð¾Ð½Ð½Ñ‹Ñ… Ñ€Ð¾Ð»ÐµÐ¹);
 *      - OPERATOR_ROLE      â€” Ð¾Ð¿ÐµÑ€Ð°Ñ‚Ð¾Ñ€ Ð±Ð°Ð½ÐºÐ°-Ð¾Ñ‚Ð¿Ñ€Ð°Ð²Ð¸Ñ‚ÐµÐ»Ñ: registerPayment, cancelPayment;
 *      - SETTLEMENT_ROLE    â€” Ñ€Ð°ÑÑ‡Ñ‘Ñ‚Ð½Ñ‹Ð¹ (ÐºÐ»Ð¸Ñ€Ð¸Ð½Ð³Ð¾Ð²Ñ‹Ð¹) Ñ†ÐµÐ½Ñ‚Ñ€: markExecuted, markRejected;
 *      - Ð°ÑƒÐ´Ð¸Ñ‚Ð¾Ñ€ / Ð±Ð°Ð½Ðº-Ð¿Ð¾Ð»ÑƒÑ‡Ð°Ñ‚ÐµÐ»ÑŒ â€” Ð±ÐµÐ· Ñ€Ð¾Ð»Ð¸, Ñ‚Ð¾Ð»ÑŒÐºÐ¾ view-Ñ„ÑƒÐ½ÐºÑ†Ð¸Ð¸.
 *
 *      ÐÐ²Ñ‚Ð¾Ð¼Ð°Ñ‚ ÑÑ‚Ð°Ñ‚ÑƒÑÐ¾Ð²: None -> Registered -> {Executed | Rejected | Cancelled}.
 *      Executed / Rejected / Cancelled â€” Ñ„Ð¸Ð½Ð°Ð»ÑŒÐ½Ñ‹Ðµ, Ð½ÐµÐ¾Ð±Ñ€Ð°Ñ‚Ð¸Ð¼Ñ‹Ðµ; paymentId Ð½Ðµ Ð¿ÐµÑ€ÐµÐ¸ÑÐ¿Ð¾Ð»ÑŒÐ·ÑƒÐµÑ‚ÑÑ.
 *
 *      OWASP Smart Contract Top 10 (2025):
 *      - SC05:2025 Reentrancy / SC06:2025 Unchecked External Calls â€” Ð½Ðµ Ð¿Ñ€Ð¸Ð¼ÐµÐ½Ð¸Ð¼Ñ‹: ÐºÐ¾Ð½Ñ‚Ñ€Ð°ÐºÑ‚ Ð½Ðµ
 *        Ð¿ÐµÑ€ÐµÐ²Ð¾Ð´Ð¸Ñ‚ ETH/Ñ‚Ð¾ÐºÐµÐ½Ñ‹, Ð½Ðµ Ð´ÐµÐ»Ð°ÐµÑ‚ call/delegatecall/send/transfer Ð¸ Ð½Ðµ Ð²Ñ‹Ð·Ñ‹Ð²Ð°ÐµÑ‚ Ð²Ð½ÐµÑˆÐ½Ð¸Ðµ
 *        ÐºÐ¾Ð½Ñ‚Ñ€Ð°ÐºÑ‚Ñ‹; Ð½ÐµÑ‚ receive/fallback. Ð’ÑÐµ Ñ„ÑƒÐ½ÐºÑ†Ð¸Ð¸ Ð·Ð°Ð¿Ð¸ÑÐ¸ ÑÐ»ÐµÐ´ÑƒÑŽÑ‚ ÑÑ…ÐµÐ¼Ðµ CEI
 *        (Ð¿Ñ€Ð¾Ð²ÐµÑ€ÐºÐ¸ -> Ð¸Ð·Ð¼ÐµÐ½ÐµÐ½Ð¸Ðµ ÑÐ¾ÑÑ‚Ð¾ÑÐ½Ð¸Ñ -> ÑÐ¾Ð±Ñ‹Ñ‚Ð¸Ðµ), Ð¿Ð¾ÑÑ‚Ð¾Ð¼Ñƒ ReentrancyGuard Ð½Ðµ Ð½ÑƒÐ¶ÐµÐ½:
 *        Ð¿Ð¾Ð²ÐµÑ€Ñ…Ð½Ð¾ÑÑ‚Ð¸ Ð°Ñ‚Ð°ÐºÐ¸ Ð¿Ð¾Ð²Ñ‚Ð¾Ñ€Ð½Ð¾Ð³Ð¾ Ð²Ñ…Ð¾Ð´Ð° Ð½ÐµÑ‚.
 *      - SC07:2025 Flash Loan Attacks â€” Ð½Ðµ Ð¿Ñ€Ð¸Ð¼ÐµÐ½Ð¸Ð¼Ð¾: Ð½ÐµÑ‚ Ð±Ð°Ð»Ð°Ð½ÑÐ¾Ð², Ð»Ð¸ÐºÐ²Ð¸Ð´Ð½Ð¾ÑÑ‚Ð¸ Ð¸ Ñ†ÐµÐ½.
 *      - SC02:2025 Price Oracle Manipulation â€” Ð½Ðµ Ð¿Ñ€Ð¸Ð¼ÐµÐ½Ð¸Ð¼Ð¾: Ð½ÐµÑ‚ Ð¾Ñ€Ð°ÐºÑƒÐ»Ð¾Ð².
 *      - SC09:2025 Insecure Randomness â€” Ð½Ðµ Ð¿Ñ€Ð¸Ð¼ÐµÐ½Ð¸Ð¼Ð¾ on-chain: ÑÐ¾Ð»ÑŒ Ð´Ð»Ñ paymentId Ð³ÐµÐ½ÐµÑ€Ð¸Ñ€ÑƒÐµÑ‚ÑÑ
 *        off-chain ÐºÑ€Ð¸Ð¿Ñ‚Ð¾ÑÑ‚Ð¾Ð¹ÐºÐ¸Ð¼ Ð³ÐµÐ½ÐµÑ€Ð°Ñ‚Ð¾Ñ€Ð¾Ð¼ (CSPRNG).
 *      - SC10:2025 Denial of Service â€” Ð² ÐºÐ¾Ð½Ñ‚Ñ€Ð°ÐºÑ‚Ðµ Ð½ÐµÑ‚ Ñ†Ð¸ÐºÐ»Ð¾Ð² Ð¿Ð¾ Ð¼Ð°ÑÑÐ¸Ð²Ð°Ð¼ (mapping, O(1)) Ð¸
 *        Ð²Ð½ÐµÑˆÐ½Ð¸Ñ… Ð²Ñ‹Ð·Ð¾Ð²Ð¾Ð²; Ð°Ð²Ð°Ñ€Ð¸Ð¹Ð½Ð°Ñ Ð¿Ð°ÑƒÐ·Ð° Ð´Ð¾ÑÑ‚ÑƒÐ¿Ð½Ð° Ñ‚Ð¾Ð»ÑŒÐºÐ¾ DEFAULT_ADMIN_ROLE.
 */
contract PaymentOrderRegistry is AccessControl, Pausable {
    /// @notice Ð Ð¾Ð»ÑŒ Ð¾Ð¿ÐµÑ€Ð°Ñ‚Ð¾Ñ€Ð° Ð±Ð°Ð½ÐºÐ°-Ð¾Ñ‚Ð¿Ñ€Ð°Ð²Ð¸Ñ‚ÐµÐ»Ñ.
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    /// @notice Ð Ð¾Ð»ÑŒ Ñ€Ð°ÑÑ‡Ñ‘Ñ‚Ð½Ð¾Ð³Ð¾ (ÐºÐ»Ð¸Ñ€Ð¸Ð½Ð³Ð¾Ð²Ð¾Ð³Ð¾) Ñ†ÐµÐ½Ñ‚Ñ€Ð°.
    bytes32 public constant SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE");

    /// @notice Ð¡Ñ‚Ð°Ñ‚ÑƒÑÑ‹ Ð¿Ð»Ð°Ñ‚Ñ‘Ð¶Ð½Ð¾Ð³Ð¾ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ (ÐºÐ¾Ð½ÐµÑ‡Ð½Ñ‹Ð¹ Ð°Ð²Ñ‚Ð¾Ð¼Ð°Ñ‚).
    enum Status {
        None,
        Registered,
        Executed,
        Rejected,
        Cancelled
    }

    /// @notice ÐœÐ¸Ð½Ð¸Ð¼Ð°Ð»ÑŒÐ½Ñ‹Ð¹ on-chain Ð½Ð°Ð±Ð¾Ñ€ Ð´Ð°Ð½Ð½Ñ‹Ñ… Ð¿Ð¾ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸ÑŽ.
    struct PaymentOrder {
        bytes32 docHash; // keccak256 ÐºÐ°Ð½Ð¾Ð½Ð¸Ñ‡ÐµÑÐºÐ¾Ð³Ð¾ Ð´Ð¾ÐºÑƒÐ¼ÐµÐ½Ñ‚Ð° (Ð¾Ñ€Ð¸Ð³Ð¸Ð½Ð°Ð» â€” off-chain)
        uint128 amount; // ÑÑƒÐ¼Ð¼Ð° Ð² Ð¼Ð¸Ð½Ð¸Ð¼Ð°Ð»ÑŒÐ½Ñ‹Ñ… ÐµÐ´Ð¸Ð½Ð¸Ñ†Ð°Ñ… (Ñ‚Ð¸Ñ‹Ð½), > 0
        uint64 registeredAt;
        uint64 updatedAt;
        Status status;
        address registeredBy; // Ð¾Ð¿ÐµÑ€Ð°Ñ‚Ð¾Ñ€-Ð¸Ð½Ð¸Ñ†Ð¸Ð°Ñ‚Ð¾Ñ€
        address settledBy; // Ñ€Ð°ÑÑ‡Ñ‘Ñ‚Ð½Ñ‹Ð¹ Ñ†ÐµÐ½Ñ‚Ñ€ (0 Ð´Ð¾ Ð¸ÑÐ¿Ð¾Ð»Ð½ÐµÐ½Ð¸Ñ/Ð¾Ñ‚ÐºÐ»Ð¾Ð½ÐµÐ½Ð¸Ñ)
    }

    /// @dev ÐšÐ»ÑŽÑ‡ â€” Ð¿ÑÐµÐ²Ð´Ð¾Ð½Ð¸Ð¼Ð½Ñ‹Ð¹ paymentId = keccak256(abi.encode(senderBic, operationRef, valueDate, salt)).
    mapping(bytes32 => PaymentOrder) private _payments;

    /// @notice ÐšÐ¾Ð»Ð¸Ñ‡ÐµÑÑ‚Ð²Ð¾ ÑƒÑÐ¿ÐµÑˆÐ½Ð¾ Ð·Ð°Ñ€ÐµÐ³Ð¸ÑÑ‚Ñ€Ð¸Ñ€Ð¾Ð²Ð°Ð½Ð½Ñ‹Ñ… Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ð¹.
    uint256 public totalRegistered;

    /// @notice ÐŸÐ¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ðµ Ð·Ð°Ñ€ÐµÐ³Ð¸ÑÑ‚Ñ€Ð¸Ñ€Ð¾Ð²Ð°Ð½Ð¾ Ð¾Ð¿ÐµÑ€Ð°Ñ‚Ð¾Ñ€Ð¾Ð¼.
    event PaymentRegistered(bytes32 indexed paymentId, bytes32 docHash, uint128 amount, address indexed operator);

    /// @notice Ð¡Ñ‚Ð°Ñ‚ÑƒÑ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ Ð¸Ð·Ð¼ÐµÐ½Ñ‘Ð½.
    event PaymentStatusChanged(
        bytes32 indexed paymentId, Status from, Status to, address indexed actor, bytes32 reasonCode
    );

    error ZeroAddress();
    error InvalidPaymentId();
    error InvalidDocHash();
    error InvalidAmount();
    error InvalidReasonCode();
    error PaymentAlreadyExists(bytes32 paymentId);
    error PaymentNotFound(bytes32 paymentId);
    error InvalidStatusTransition(Status from, Status to);
    error NotPaymentInitiator(address caller);
    error SelfSettlementForbidden(address caller);

    /**
     * @notice Ð Ð°Ð·Ð²Ñ‘Ñ€Ñ‚Ñ‹Ð²Ð°Ð½Ð¸Ðµ Ñ€ÐµÐµÑÑ‚Ñ€Ð°.
     * @param admin ÐÐ´Ñ€ÐµÑ Ð°Ð´Ð¼Ð¸Ð½Ð¸ÑÑ‚Ñ€Ð°Ñ‚Ð¾Ñ€Ð° (Ð² Ð¿Ñ€Ð¾Ð´Ð°ÐºÑˆÐµÐ½Ðµ â€” Safe multisig 2/3 + timelock).
     */
    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /**
     * @notice Ð ÐµÐ³Ð¸ÑÑ‚Ñ€Ð¸Ñ€ÑƒÐµÑ‚ Ð½Ð¾Ð²Ð¾Ðµ Ð¿Ð»Ð°Ñ‚Ñ‘Ð¶Ð½Ð¾Ðµ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ðµ.
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ OPERATOR_ROLE, Ð½Ðµ Ð½Ð° Ð¿Ð°ÑƒÐ·Ðµ. ÐŸÐµÑ€ÑÐ¾Ð½Ð°Ð»ÑŒÐ½Ñ‹Ðµ Ð´Ð°Ð½Ð½Ñ‹Ðµ Ð½Ðµ Ð¿Ñ€Ð¸Ð½Ð¸Ð¼Ð°ÑŽÑ‚ÑÑ â€” Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ñ…ÐµÑˆ.
     * @param paymentId ÐŸÑÐµÐ²Ð´Ð¾Ð½Ð¸Ð¼Ð½Ñ‹Ð¹ Ð¸Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ (â‰  0, ÑƒÐ½Ð¸ÐºÐ°Ð»ÑŒÐ½Ñ‹Ð¹ Ð½Ð°Ð²ÑÐµÐ³Ð´Ð°).
     * @param docHash keccak256 ÐºÐ°Ð½Ð¾Ð½Ð¸Ñ‡ÐµÑÐºÐ¾Ð³Ð¾ Ð´Ð¾ÐºÑƒÐ¼ÐµÐ½Ñ‚Ð° Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ (â‰  0).
     * @param amount Ð¡ÑƒÐ¼Ð¼Ð° Ð² Ñ‚Ð¸Ñ‹Ð½Ð°Ñ… (> 0).
     */
    function registerPayment(bytes32 paymentId, bytes32 docHash, uint128 amount)
        external
        onlyRole(OPERATOR_ROLE) // OWASP SC01:2025 â€” role check by msg.sender
        whenNotPaused
    {
        // OWASP SC04:2025 â€” input validation
        if (paymentId == bytes32(0)) revert InvalidPaymentId();
        if (docHash == bytes32(0)) revert InvalidDocHash();
        if (amount == 0) revert InvalidAmount();
        PaymentOrder storage p = _payments[paymentId];
        // OWASP SC03:2025 â€” state machine: paymentId is never reused (even after Cancelled)
        if (p.status != Status.None) revert PaymentAlreadyExists(paymentId);

        // OWASP SC08:2025 â€” SafeCast
        uint64 nowTs = SafeCast.toUint64(block.timestamp);
        p.docHash = docHash;
        p.amount = amount;
        p.registeredAt = nowTs;
        p.updatedAt = nowTs;
        p.status = Status.Registered;
        p.registeredBy = msg.sender;
        totalRegistered += 1;

        emit PaymentRegistered(paymentId, docHash, amount, msg.sender);
    }

    /**
     * @notice ÐžÑ‚Ð·Ñ‹Ð²Ð°ÐµÑ‚ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ðµ (Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ð¸Ð½Ð¸Ñ†Ð¸Ð°Ñ‚Ð¾Ñ€, Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ð¸Ð· ÑÑ‚Ð°Ñ‚ÑƒÑÐ° Registered).
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ OPERATOR_ROLE, Ð½Ðµ Ð½Ð° Ð¿Ð°ÑƒÐ·Ðµ.
     * @param paymentId Ð˜Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     */
    function cancelPayment(bytes32 paymentId)
        external
        onlyRole(OPERATOR_ROLE) // OWASP SC01:2025 â€” role check by msg.sender
        whenNotPaused
    {
        PaymentOrder storage p = _payments[paymentId];
        Status current = p.status;
        // OWASP SC04:2025 â€” input validation
        if (current == Status.None) revert PaymentNotFound(paymentId);
        // OWASP SC03:2025 â€” state machine
        if (current != Status.Registered) revert InvalidStatusTransition(current, Status.Cancelled);
        // OWASP SC01:2025 â€” only the initiating operator may cancel
        if (p.registeredBy != msg.sender) revert NotPaymentInitiator(msg.sender);

        p.status = Status.Cancelled;
        p.updatedAt = SafeCast.toUint64(block.timestamp); // OWASP SC08:2025 â€” SafeCast

        emit PaymentStatusChanged(paymentId, Status.Registered, Status.Cancelled, msg.sender, bytes32(0));
    }

    /**
     * @notice Ð Ð°ÑÑ‡Ñ‘Ñ‚Ð½Ñ‹Ð¹ Ñ†ÐµÐ½Ñ‚Ñ€ Ð¿Ð¾Ð´Ñ‚Ð²ÐµÑ€Ð¶Ð´Ð°ÐµÑ‚ Ð¸ÑÐ¿Ð¾Ð»Ð½ÐµÐ½Ð¸Ðµ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ SETTLEMENT_ROLE, Ð½Ðµ Ð½Ð° Ð¿Ð°ÑƒÐ·Ðµ. ÐŸÑ€Ð¸Ð½Ñ†Ð¸Ð¿ Â«4 Ð³Ð»Ð°Ð·Â»: Ð¸ÑÐ¿Ð¾Ð»Ð½Ð¸Ñ‚ÐµÐ»ÑŒ â‰  Ð¸Ð½Ð¸Ñ†Ð¸Ð°Ñ‚Ð¾Ñ€.
     * @param paymentId Ð˜Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     */
    function markExecuted(bytes32 paymentId)
        external
        onlyRole(SETTLEMENT_ROLE) // OWASP SC01:2025 â€” role check by msg.sender
        whenNotPaused
    {
        PaymentOrder storage p = _payments[paymentId];
        Status current = p.status;
        // OWASP SC04:2025 â€” input validation
        if (current == Status.None) revert PaymentNotFound(paymentId);
        // OWASP SC03:2025 â€” state machine
        if (current != Status.Registered) revert InvalidStatusTransition(current, Status.Executed);
        // OWASP SC01:2025 â€” four-eyes principle (segregation of duties)
        if (p.registeredBy == msg.sender) revert SelfSettlementForbidden(msg.sender);

        p.status = Status.Executed;
        p.settledBy = msg.sender;
        p.updatedAt = SafeCast.toUint64(block.timestamp); // OWASP SC08:2025 â€” SafeCast

        emit PaymentStatusChanged(paymentId, Status.Registered, Status.Executed, msg.sender, bytes32(0));
    }

    /**
     * @notice Ð Ð°ÑÑ‡Ñ‘Ñ‚Ð½Ñ‹Ð¹ Ñ†ÐµÐ½Ñ‚Ñ€ Ð¾Ñ‚ÐºÐ»Ð¾Ð½ÑÐµÑ‚ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ðµ Ñ ÐºÐ¾Ð´Ð¾Ð¼ Ð¿Ñ€Ð¸Ñ‡Ð¸Ð½Ñ‹.
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ SETTLEMENT_ROLE, Ð½Ðµ Ð½Ð° Ð¿Ð°ÑƒÐ·Ðµ. ÐŸÑ€Ð¸Ð½Ñ†Ð¸Ð¿ Â«4 Ð³Ð»Ð°Ð·Â»: Ð¸ÑÐ¿Ð¾Ð»Ð½Ð¸Ñ‚ÐµÐ»ÑŒ â‰  Ð¸Ð½Ð¸Ñ†Ð¸Ð°Ñ‚Ð¾Ñ€.
     * @param paymentId Ð˜Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     * @param reasonCode ÐšÐ¾Ð´ Ð¿Ñ€Ð¸Ñ‡Ð¸Ð½Ñ‹ Ð¾Ñ‚ÐºÐ»Ð¾Ð½ÐµÐ½Ð¸Ñ ISO 20022 (Ð½Ð°Ð¿Ñ€Ð¸Ð¼ÐµÑ€, "AC04"), â‰  0.
     */
    function markRejected(bytes32 paymentId, bytes32 reasonCode)
        external
        onlyRole(SETTLEMENT_ROLE) // OWASP SC01:2025 â€” role check by msg.sender
        whenNotPaused
    {
        // OWASP SC04:2025 â€” input validation
        if (reasonCode == bytes32(0)) revert InvalidReasonCode();
        PaymentOrder storage p = _payments[paymentId];
        Status current = p.status;
        if (current == Status.None) revert PaymentNotFound(paymentId);
        // OWASP SC03:2025 â€” state machine
        if (current != Status.Registered) revert InvalidStatusTransition(current, Status.Rejected);
        // OWASP SC01:2025 â€” four-eyes principle (segregation of duties)
        if (p.registeredBy == msg.sender) revert SelfSettlementForbidden(msg.sender);

        p.status = Status.Rejected;
        p.settledBy = msg.sender;
        p.updatedAt = SafeCast.toUint64(block.timestamp); // OWASP SC08:2025 â€” SafeCast

        emit PaymentStatusChanged(paymentId, Status.Registered, Status.Rejected, msg.sender, reasonCode);
    }

    /**
     * @notice ÐÐ²Ð°Ñ€Ð¸Ð¹Ð½Ð°Ñ Ð¾ÑÑ‚Ð°Ð½Ð¾Ð²ÐºÐ° Ð²ÑÐµÑ… Ð¾Ð¿ÐµÑ€Ð°Ñ†Ð¸Ð¹ Ð·Ð°Ð¿Ð¸ÑÐ¸.
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ DEFAULT_ADMIN_ROLE. OWASP SC10:2025 â€” Ð¿Ð°ÑƒÐ·Ð° Ð´Ð¾ÑÑ‚ÑƒÐ¿Ð½Ð° Ñ‚Ð¾Ð»ÑŒÐºÐ¾ Ð°Ð´Ð¼Ð¸Ð½Ð¸ÑÑ‚Ñ€Ð°Ñ‚Ð¾Ñ€Ñƒ.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Ð¡Ð½ÑÑ‚Ð¸Ðµ Ð°Ð²Ð°Ñ€Ð¸Ð¹Ð½Ð¾Ð¹ Ð¾ÑÑ‚Ð°Ð½Ð¾Ð²ÐºÐ¸.
     * @dev Ð¢Ð¾Ð»ÑŒÐºÐ¾ DEFAULT_ADMIN_ROLE.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Ð’Ð¾Ð·Ð²Ñ€Ð°Ñ‰Ð°ÐµÑ‚ Ð´Ð°Ð½Ð½Ñ‹Ðµ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ (Ð´Ð»Ñ Ð½ÐµÑÑƒÑ‰ÐµÑÑ‚Ð²ÑƒÑŽÑ‰ÐµÐ³Ð¾ â€” Ð½ÑƒÐ»ÐµÐ²Ð°Ñ ÑÑ‚Ñ€ÑƒÐºÑ‚ÑƒÑ€Ð°).
     * @param paymentId Ð˜Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     * @return Ð”Ð°Ð½Ð½Ñ‹Ðµ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     */
    function getPayment(bytes32 paymentId) external view returns (PaymentOrder memory) {
        return _payments[paymentId];
    }

    /**
     * @notice ÐŸÑ€Ð¾Ð²ÐµÑ€ÑÐµÑ‚, Ñ‡Ñ‚Ð¾ Ð´Ð¾ÐºÑƒÐ¼ÐµÐ½Ñ‚ Ð½Ðµ Ð±Ñ‹Ð» Ð¸Ð·Ð¼ÐµÐ½Ñ‘Ð½: ÑÑ€Ð°Ð²Ð½Ð¸Ð²Ð°ÐµÑ‚ Ñ…ÐµÑˆ Ñ Ð·Ð°Ñ€ÐµÐ³Ð¸ÑÑ‚Ñ€Ð¸Ñ€Ð¾Ð²Ð°Ð½Ð½Ñ‹Ð¼.
     * @param paymentId Ð˜Ð´ÐµÐ½Ñ‚Ð¸Ñ„Ð¸ÐºÐ°Ñ‚Ð¾Ñ€ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ñ.
     * @param candidateHash keccak256 Ð¿Ð¾Ð»ÑƒÑ‡ÐµÐ½Ð½Ð¾Ð³Ð¾ Ð´Ð¾ÐºÑƒÐ¼ÐµÐ½Ñ‚Ð°.
     * @return true, ÐµÑÐ»Ð¸ Ð¿Ð¾Ñ€ÑƒÑ‡ÐµÐ½Ð¸Ðµ ÑÑƒÑ‰ÐµÑÑ‚Ð²ÑƒÐµÑ‚ Ð¸ Ñ…ÐµÑˆ ÑÐ¾Ð²Ð¿Ð°Ð´Ð°ÐµÑ‚.
     */
    function verifyDocument(bytes32 paymentId, bytes32 candidateHash) external view returns (bool) {
        PaymentOrder storage p = _payments[paymentId];
        return p.status != Status.None && candidateHash != bytes32(0) && p.docHash == candidateHash;
    }
}
