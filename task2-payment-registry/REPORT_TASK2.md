# Отчёт по Заданию 2 — реализация и тестирование смарт-контракта

**ПР №3, вариант 1 «Банки и финтех»** — проверка статуса межбанковского платёжного поручения.
Вариант нечётный, поэтому используется **Hardhat 3.x**. Все результаты ниже взяты из реальных запусков (`reports/*.log`, 2026-10-07).

## 1. Toolchain

| Компонент | Версия |
|---|---|
| Node.js / npm | 24.13.0 / 11.6.2 |
| Hardhat | 3.18.1 |
| @nomicfoundation/hardhat-toolbox-viem | 5.0.7 (node:test + viem, keystore, verify, network-helpers) |
| viem | 2.57.3 |
| OpenZeppelin Contracts | 5.6.1 (`AccessControl`, `Pausable`, `SafeCast`) |
| forge-std | 1.16.2 |
| Solidity | 0.8.28 (точная версия в pragma и конфиге), optimizer on, runs = 200, EVM cancun |
| TypeScript | 6.0.3 |

## 2. Исходный код

- Контракт: [contracts/PaymentOrderRegistry.sol](contracts/PaymentOrderRegistry.sol).
- Тесты: [test/solidity/](test/solidity/), [test/nodejs/](test/nodejs/).
- Скрипты: [scripts/](scripts/).

| Требование | Реализация |
|---|---|
| ≥ 4 public/external функций | 8: `registerPayment`, `cancelPayment`, `markExecuted`, `markRejected`, `pause`, `unpause`, `getPayment`, `verifyDocument` |
| ≥ 2 событий | `PaymentRegistered`, `PaymentStatusChanged` |
| ≥ 2 ролей | `DEFAULT_ADMIN_ROLE`, `OPERATOR_ROLE`, `SETTLEMENT_ROLE` (+ аудитор без роли) |
| Custom errors | 10 собственных + `AccessControlUnauthorizedAccount`, `EnforcedPause` из OZ |
| Модификаторы / RBAC | `onlyRole` (по `msg.sender`), `whenNotPaused` |
| Проверка входа | нулевые `paymentId` / `docHash` / `amount` / `reasonCode` / admin, дубликаты, несуществующие платежи |
| Конфиденциальность | on-chain только псевдонимный `paymentId`, keccak256 документа, сумма, статус, адреса ролей |
| Повторный вход | внешних вызовов и переводов ETH нет, CEI — ReentrancyGuard не нужен (см. README) |

## 3. Результаты тестирования

Сводка — [reports/TEST_SUMMARY.md](reports/TEST_SUMMARY.md). Полные логи — `reports/<stage>.log`.

| Этап | Команда | Результат |
|---|---|---|
| Компиляция | `npm run compile` | без ошибок и предупреждений |
| Unit | `npm run test:unit` | **21 passing**, 0 failing |
| Fuzz | `npm run test:fuzz` | **3 passing** (по 256 прогонов) |
| Invariant | `npm run test:invariant` | **5 passing** (64 прогона × глубина 32) |
| Integration (TS) | `npm run test:integration` | **3 passing** |
| Все | `npm test` | **32 passing (29 solidity, 3 nodejs)** |
| Покрытие | `npm run coverage` | **100%** строк и statements `PaymentOrderRegistry.sol` |

### 3.1 Unit — `npm run test:unit` (из `reports/unit.log`)

```
  test/solidity/PaymentOrderRegistry.unit.t.sol:PaymentOrderRegistryUnitTest
    ✔ test_VerifyDocument_TrueForOriginal_FalseForTampered()
    ✔ test_UnknownPayment_RevertsNotFound()
    ✔ test_Register_StoresDataAndEmitsEvents()
    ✔ test_Register_RevertsWhen_ZeroPaymentId()
    ✔ test_Register_RevertsWhen_ZeroDocHash()
    ✔ test_Register_RevertsWhen_ZeroAmount()
    ✔ test_Register_RevertsWhen_ReusingCancelledId()
    ✔ test_Register_RevertsWhen_Duplicate()
    ✔ test_Register_RevertsWhen_CallerHasNoOperatorRole()
    ✔ test_Register_AcceptsBoundaryAmounts()
    ✔ test_Pause_BlocksWrites_OnlyAdminCanPause()
    ✔ test_MarkRejected_StoresReasonAndEmits()
    ✔ test_MarkRejected_RevertsWhen_ZeroReasonCode()
    ✔ test_MarkExecuted_UpdatesStatusAndEmits()
    ✔ test_MarkExecuted_RevertsWhen_SelfSettlement()
    ✔ test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole()
    ✔ test_FinalStatuses_CannotTransition()
    ✔ test_Constructor_RevertsOnZeroAdmin()
    ✔ test_Constructor_GrantsAdminRole()
    ✔ test_Cancel_RevertsWhen_NotInitiator()
    ✔ test_AdminWithoutOperationalRole_CannotRegisterOrSettle()

  21 passing
```

Тесты охватывают:
- корректные сценарии (3, 11, 14);
- ошибки доступа (4, 12, 13, 17, 21);
- некорректный ввод (2, 5–7, 15, 18);
- повторные операции (9, 10);
- граничные значения (8: 1 и `type(uint128).max`);
- ожидаемые откаты (16, 19).

Ошибки проверяются точными селекторами с аргументами.

### 3.2 Fuzz — `npm run test:fuzz`

```
  test/solidity/PaymentOrderRegistry.fuzz.t.sol:PaymentOrderRegistryFuzzTest
    ✔ testFuzz_Register_StoresExactData(bytes32,bytes32,uint128) (runs: 256)
    ✔ testFuzz_NonSettlementCannotFinalize(address,bool) (runs: 256)
    ✔ testFuzz_NonOperatorCannotRegister(address) (runs: 256)

  3 passing
```

### 3.3 Invariant — `npm run test:invariant`

```
  test/solidity/invariant/PaymentOrderRegistry.invariant.t.sol:PaymentOrderRegistryInvariantTest
    ✔ invariant_INV5_TotalRegisteredMatchesGhost() (runs: 64)
    ✔ invariant_INV4_FourEyes() (runs: 64)
    ✔ invariant_INV3_PaymentDataImmutable() (runs: 64)
    ✔ invariant_INV2_FinalStatusesAreImmutable() (runs: 64)
    ✔ invariant_INV1_OnlyRoleHoldersChangeState() (runs: 64)

  5 passing
```

Handler `PaymentOrderHandler` работает с пулом из 10 `paymentId`. Действия: `register`, `cancel`, `execute`, `reject` от легитимных ролей и держателя обеих ролей, а также `strangerAttack` — попытки постороннего адреса вызвать все функции записи, `pause` и `grantRole`.

**Мутационная проверка.** При временном удалении проверки статуса в `markExecuted` падает INV-2, при удалении проверки «4 глаз» — INV-4. Значит, инварианты действительно обнаруживают ошибки, а не проходят формально.

### 3.4 Integration — `npm run test:integration`

```
  PaymentOrderRegistry (integration, viem + node:test)
    ✔ full flow: register (operator) -> markExecuted (settlement) with events
    ✔ reverts with SelfSettlementForbidden when the initiator tries to settle
    ✔ verifyDocument: true for demo-data/payment-order-0001.xml, false for tampered content

  3 passing
```

## 4. Покрытие OWASP Smart Contract Top 10 (2025)

| Категория | Мера | Тесты | Результат |
|---|---|---|---|
| SC01 Access Control | `onlyRole` по `msg.sender`; admin без операционных ролей; «4 глаза» | 13 тестов: unit 1, 4, 12, 13, 17, 19, 21; fuzz NonOperator / NonSettlement; INV-1, INV-4; 2 integration | 13 passed |
| SC03 Logic Errors | автомат статусов, финальность, неизменность данных | 13 тестов: unit 3, 9, 10, 11, 14, 16, 17, 20; INV-2, INV-3, INV-5; 2 integration | 13 passed |
| SC04 Lack of Input Validation | custom errors на нулевые и неизвестные значения, дубликаты | 10 тестов: unit 2, 3, 5–9, 15, 18; fuzz StoresExactData | 10 passed |
| SC08 Integer Overflow/Underflow | checked arithmetic 0.8, `uint128`, `SafeCast.toUint64` | unit 8, fuzz StoresExactData | 2 passed |
| SC10 Denial of Service | нет циклов и внешних вызовов, пауза только admin | unit 19 | 1 passed |

Неприменимые категории (обоснование):
- **SC02** Price Oracle Manipulation — нет оракулов и цен.
- **SC05** Reentrancy и **SC06** Unchecked External Calls — нет внешних вызовов и переводов ETH; Slither в Задании 3 даёт 0 находок `reentrancy-*` / `unchecked-*` / `low-level-calls`.
- **SC07** Flash Loan Attacks — нет балансов и ликвидности.
- **SC09** Insecure Randomness — соль `paymentId` генерируется off-chain через `webcrypto.getRandomValues`.

Автоматическая таблица по тегам из комментариев тестов — в [reports/TEST_SUMMARY.md](reports/TEST_SUMMARY.md).

## 5. Развёртывание в локальной сети

```
npm run node            # терминал 1: hardhat node, chainId 31337
npm run deploy:local    # терминал 2
npm run interact:local  # запускался 2 раза подряд — оба без ошибок
```

| Параметр | Значение |
|---|---|
| Сеть | localhost (Hardhat node), chainId 31337 |
| Адрес контракта | `0x5FbDB2315678afecb367f032d93F642f64180aa3` |
| Deploy tx hash | `0x9da41388fe6d27e2b4b36725490d9bfc31cc1bcb523bd8c4d87ae66f465c20d1` |
| Блок / gasUsed | 1 / 963 400 |
| admin (только `DEFAULT_ADMIN_ROLE`) | `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266` |
| operator (только `OPERATOR_ROLE`) | `0x70997970c51812dc3a010c7d01b50e0d17dc79c8` |
| settlement (только `SETTLEMENT_ROLE`) | `0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc` |

Транзакции взаимодействия (первый запуск `interact:local`):

| Шаг | Функция | От | Tx hash | Блок | Статус |
|---|---|---|---|---|---|
| 3a | `grantRole(OPERATOR_ROLE, operator)` | admin | `0x49e312a77d9c5400bd65c1c1cf183e726d266ba9393bc03b019cc70c05809966` | 2 | success |
| 3b | `grantRole(SETTLEMENT_ROLE, settlement)` | admin | `0xb6ce34bcc2a54f092dfed6b6b659f9bf5372b342212ad955cbcf5e877d0e9abe` | 3 | success |
| 6a | `registerPayment(id1, docHash1, 12500000000)` | operator | `0x581f3e7dd11591c09cc9314db8beb014ae2c5704e1eba9f507f48c927fb81909` | 4 | success |
| 6b | `markExecuted(id1)` | settlement | `0xcdf946f19df6540f4dc8ce903b00be28c0ec97c42ddbf67fe5671ba69ba40b11` | 5 | success |
| 7a | `registerPayment(id2, docHash2, 475000000)` | operator | `0xdf3e655cfb77a71e0bfff63c4fcbb2a961b133ab0518392c78be849a7fec06fe` | 6 | success |
| 7b | `markRejected(id2, "AC04")` | settlement | `0xd019469c0203c5ecb93821aa3723de01331080ea4dc70022921079de51190567` | 7 | success |

Дополнительно в сценарии проверяется:
- `verifyDocument(id1, оригинал)` = **true**, `verifyDocument(id1, изменённый документ)` = **false**;
- симуляция без отправки транзакции: `markExecuted` от оператора → `AccessControlUnauthorizedAccount(operator, SETTLEMENT_ROLE)`; `registerPayment` от admin → `AccessControlUnauthorizedAccount(admin, OPERATOR_ROLE)`;
- разделение ролей: admin не имеет `OPERATOR_ROLE` и `SETTLEMENT_ROLE`.

При втором запуске выдача ролей пропускается (`skipped`), регистрируются два новых платежа с новыми `paymentId` (`totalRegistered = 4`).

## 6. Развёртывание в Sepolia

Команды и настройка keystore — в README, раздел «Развёртывание в Sepolia». После `npm run deploy:sepolia` и `npm run interact:sepolia` значения берутся из вывода скриптов и из `deployments/sepolia.json`.

| Параметр | Значение |
|---|---|
| Адрес контракта | `<заполнить после npm run deploy:sepolia>` — https://sepolia.etherscan.io/address/<адрес> |
| Deploy tx hash | `<заполнить после npm run deploy:sepolia>` — https://sepolia.etherscan.io/tx/<hash> |
| Interaction tx 1 — `registerPayment` | `<заполнить после npm run interact:sepolia>` |
| Interaction tx 2 — `markExecuted` | `<заполнить после npm run interact:sepolia>` |
| Interaction tx 3 — `registerPayment` | `<заполнить после npm run interact:sepolia>` |
| Interaction tx 4 — `markRejected` | `<заполнить после npm run interact:sepolia>` |

Скрипт `interact.ts` в конце печатает готовую markdown-таблицу со ссылками на Etherscan — её можно вставить сюда целиком.

## 7. Безопасность репозитория

- **Секреты** (RPC URL, приватные ключи, ключ Etherscan) хранятся только в зашифрованном `hardhat-keystore` и читаются через `configVariable(...)`.
- **`.env`** не используется и исключён в `.gitignore`.
- **`npm run check:secrets`** проверяет git-файлы на ключи, мнемоники и `.env`. Результат: OK.
- **Демо-документы** `demo-data/*.xml` — синтетические, данные явно вымышлены.
