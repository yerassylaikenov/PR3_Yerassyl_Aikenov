# TEST SUMMARY — PaymentOrderRegistry (Задание 2)

Сгенерировано: 2026-10-07T08:27:57.078Z · Node v24.13.0 · `node scripts/run-and-log.mjs`

## Этапы

| Этап | Команда | Exit code | Passed | Failed | Лог |
|---|---|---|---|---|---|
| compile | `npx hardhat compile` | 0 | — | — | [compile.log](./compile.log) |
| unit | `npx hardhat test solidity test/solidity/PaymentOrderRegistry.unit.t.sol` | 0 | 21 | 0 | [unit.log](./unit.log) |
| fuzz | `npx hardhat test solidity test/solidity/PaymentOrderRegistry.fuzz.t.sol` | 0 | 3 | 0 | [fuzz.log](./fuzz.log) |
| invariant | `npx hardhat test solidity test/solidity/invariant/PaymentOrderRegistry.invariant.t.sol test/solidity/invariant/PaymentOrderHandler.sol` | 0 | 5 | 0 | [invariant.log](./invariant.log) |
| integration | `npx hardhat test nodejs` | 0 | 3 | 0 | [integration.log](./integration.log) |

## Покрытие OWASP Smart Contract Top 10 (2025)

| Категория | Тесты (по тегам в комментариях) | Passed | Failed |
|---|---|---|---|
| SC01:2025 Access Control Vulnerabilities | `full flow: register (operator) -> markExecuted (settlement) with events`, `reverts with SelfSettlementForbidden when the initiator tries to settle`, `invariant_INV1_OnlyRoleHoldersChangeState`, `invariant_INV4_FourEyes`, `testFuzz_NonOperatorCannotRegister`, `testFuzz_NonSettlementCannotFinalize`, `test_Constructor_GrantsAdminRole`, `test_Register_RevertsWhen_CallerHasNoOperatorRole`, `test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole`, `test_MarkExecuted_RevertsWhen_SelfSettlement`, `test_Cancel_RevertsWhen_NotInitiator`, `test_Pause_BlocksWrites_OnlyAdminCanPause`, `test_AdminWithoutOperationalRole_CannotRegisterOrSettle` | 13 | 0 |
| SC02:2025 Price Oracle Manipulation | — не применимо: нет оракулов и цен; доверие к off-chain данным ограничено ролью и verifyDocument | — | — |
| SC03:2025 Logic Errors | `full flow: register (operator) -> markExecuted (settlement) with events`, `verifyDocument: true for demo-data/payment-order-0001.xml, false for tampered content`, `invariant_INV2_FinalStatusesAreImmutable`, `invariant_INV3_PaymentDataImmutable`, `invariant_INV5_TotalRegisteredMatchesGhost`, `test_Register_StoresDataAndEmitsEvents`, `test_Register_RevertsWhen_Duplicate`, `test_Register_RevertsWhen_ReusingCancelledId`, `test_MarkExecuted_UpdatesStatusAndEmits`, `test_MarkRejected_StoresReasonAndEmits`, `test_FinalStatuses_CannotTransition`, `test_Cancel_RevertsWhen_NotInitiator`, `test_VerifyDocument_TrueForOriginal_FalseForTampered` | 13 | 0 |
| SC04:2025 Lack of Input Validation | `testFuzz_Register_StoresExactData`, `test_Constructor_RevertsOnZeroAdmin`, `test_Register_StoresDataAndEmitsEvents`, `test_Register_RevertsWhen_ZeroPaymentId`, `test_Register_RevertsWhen_ZeroDocHash`, `test_Register_RevertsWhen_ZeroAmount`, `test_Register_AcceptsBoundaryAmounts`, `test_Register_RevertsWhen_Duplicate`, `test_MarkRejected_RevertsWhen_ZeroReasonCode`, `test_UnknownPayment_RevertsNotFound` | 10 | 0 |
| SC05:2025 Reentrancy Attacks | — не применимо: нет внешних вызовов и переводов ETH, CEI; подтверждается Slither в Задании 3 | — | — |
| SC06:2025 Unchecked External Calls | — не применимо: нет call/delegatecall/send/transfer; подтверждается Slither в Задании 3 | — | — |
| SC07:2025 Flash Loan Attacks | — не применимо: нет балансов/ликвидности; запись требует роли | — | — |
| SC08:2025 Integer Overflow and Underflow | `testFuzz_Register_StoresExactData`, `test_Register_AcceptsBoundaryAmounts` | 2 | 0 |
| SC09:2025 Insecure Randomness | — не применимо: соль paymentId — CSPRNG off-chain (scripts/interact.ts, webcrypto.getRandomValues) | — | — |
| SC10:2025 Denial of Service (DoS) Attacks | `test_Pause_BlocksWrites_OnlyAdminCanPause` | 1 | 0 |

**Итог:** все этапы успешны ✅
