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

```
npm run deploy:sepolia
npm run interact:sepolia
```

Данные — из вывода скриптов и [deployments/sepolia.json](deployments/sepolia.json). Все статусы перепроверены напрямую через RPC (`eth_getTransactionReceipt`).

| Параметр | Значение |
|---|---|
| Сеть | Ethereum Sepolia, chainId 11155111 |
| Адрес контракта | [`0x83328cc06A4337E7695b1045EdC11D538F862674`](https://sepolia.etherscan.io/address/0x83328cc06A4337E7695b1045EdC11D538F862674) |
| Deploy tx hash | [`0x71d6b55e92fed5c7a20f914e70039163f56a68141221f20ed79ba759fb67379d`](https://sepolia.etherscan.io/tx/0x71d6b55e92fed5c7a20f914e70039163f56a68141221f20ed79ba759fb67379d) |
| Блок развёртывания | 11863985 |
| admin (только `DEFAULT_ADMIN_ROLE`) | [`0xCf8CD8D95432B90d22975481B3C25A1f4f72A713`](https://sepolia.etherscan.io/address/0xCf8CD8D95432B90d22975481B3C25A1f4f72A713) |
| operator (только `OPERATOR_ROLE`) | [`0x8390a5B2D1077b21679b4cA2bFF96922818d4127`](https://sepolia.etherscan.io/address/0x8390a5B2D1077b21679b4cA2bFF96922818d4127) |
| settlement (только `SETTLEMENT_ROLE`) | [`0x39ae003c95AfEe14e2FD7E386608D6E04E303Ab5`](https://sepolia.etherscan.io/address/0x39ae003c95AfEe14e2FD7E386608D6E04E303Ab5) |
| Исходный код проверен | [Blockscout](https://eth-sepolia.blockscout.com/address/0x83328cc06A4337E7695b1045EdC11D538F862674#code), [Sourcify](https://sourcify.dev/server/repo-ui/11155111/0x83328cc06A4337E7695b1045EdC11D538F862674) |

### Транзакции взаимодействия (основной сценарий)

| Шаг | Функция | От | Tx hash | Блок | Статус |
|---|---|---|---|---|---|
| 6a | `registerPayment(id1, docHash1, 12500000000)` | operator | [`0x7b8526c6…cdfa50`](https://sepolia.etherscan.io/tx/0x7b8526c66891393c54da6ed7638954b026e71d69cbf462322418ea5a35cdfa50) | 11864014 | success |
| 6b | `markExecuted(id1)` | settlement | [`0xd57dad73…85eb04b`](https://sepolia.etherscan.io/tx/0xd57dad73f468275d23be7e558c2feed853ea757bd0512ea0df4c0e88685eb04b) | 11864015 | success |
| 7a | `registerPayment(id2, docHash2, 475000000)` | operator | [`0x15717949…fdf8548`](https://sepolia.etherscan.io/tx/0x15717949aefd53fc46c0f347af4db33a6dd18f7b9ed458d94b29ec431fdf8548) | 11864016 | success |
| 7b | `markRejected(id2, "AC04")` | settlement | [`0x62fb3d62…6154b7c2`](https://sepolia.etherscan.io/tx/0x62fb3d62db54244236f634d71b00b2ab47b3795766620e593a45927a6154b7c2) | 11864017 | success |

Итоговое состояние: `id1` — **Executed**, `id2` — **Rejected**, `settledBy` = расчётный центр. Дополнительно проверено:
- `verifyDocument(id1, оригинал)` = **true**, для изменённого документа — **false**;
- симуляция `markExecuted` от оператора → `AccessControlUnauthorizedAccount(operator, SETTLEMENT_ROLE)`;
- симуляция `registerPayment` от admin → `AccessControlUnauthorizedAccount(admin, OPERATOR_ROLE)`;
- admin не имеет операционных ролей.

### Подготовительные транзакции (первый запуск)

| Шаг | Функция | Tx hash | Блок | Статус |
|---|---|---|---|---|
| 3a | `grantRole(OPERATOR_ROLE, operator)` | [`0xde79c499…eef2ea6`](https://sepolia.etherscan.io/tx/0xde79c49998a9ac59f21ab4b3359fb4f5a535f63b46b815cfb8d095873eef2ea6) | 11863991 | success |
| 3b | `grantRole(SETTLEMENT_ROLE, settlement)` | [`0x3163e7c6…1e03799`](https://sepolia.etherscan.io/tx/0x3163e7c626a31f758b3a1527f1b9e6c54d6d4d9641bfc7230fe8ad60a1e03799) | 11863992 | success |
| 4 | пополнение operator 0.003 ETH | [`0xdca2cb9b…e41be`](https://sepolia.etherscan.io/tx/0xdca2cb9b0567dff05976d4f89f154cb4d5449d730550058c8e97fd735e1e41be) | 11863993 | success |
| 4 | пополнение settlement 0.003 ETH | [`0x3ed5ae43…338f51`](https://sepolia.etherscan.io/tx/0x3ed5ae434841bb3d0263456a99b9ecdad71478840a3badcd64e3b5d0cf338f51) | 11863994 | success |
| 6a | `registerPayment` | [`0x13775e5b…116120b`](https://sepolia.etherscan.io/tx/0x13775e5b4a46a2dcec80b317462eb0ceab7377ffad4b31d6f23bf0dbc116120b) | 11863995 | success |
| 6b | `markExecuted` | [`0xf9c3fede…458e321`](https://sepolia.etherscan.io/tx/0xf9c3fedeaf24dbee35e6096ff72c83218d239e187976b6d8709c11143458e321) | 11863996 | **reverted (out of gas)** |

### Наблюдения при развёртывании в публичной сети

1. **Нехватка газа в первом запуске.** Транзакция `markExecuted` отменилась из-за нехватки газа: `gasUsed` = `gasLimit` = 149 321. Узел занизил оценку (`eth_estimateGas`), при повторной оценке он вернул 159 360. Логика контракта не нарушена: откат не изменил состояние, платёж остался в статусе `Registered` — это видно и по ходу сценария.

   **Исправление в скрипте:** `scripts/interact.ts` добавляет 30% запаса к оценке газа для каждой транзакции (`GAS_BUFFER_PERCENT`); неизрасходованный газ не списывается. Кроме того, хеши теперь сохраняются в `deployments/<network>.json` после каждой транзакции. После исправления сценарий прошёл полностью.

2. **Газ развёртывания в Sepolia выше, чем локально:** 6 619 888 против 963 400. Развёрнутый байткод идентичен локальному артефакту — 4070 байт, проверено через `eth_getCode`. Разница объясняется текущим набором правил расчёта газа в Sepolia; локальная сеть Hardhat считает газ по-другому. Цена газа — 1 gwei, стоимость развёртывания около 0.0066 тестового ETH.

**Связь с Заданием 3.** Это же развёртывание — адрес **исправленного** контракта для Задания 3: файл `contracts/fixed/PaymentOrderRegistry.sol` побайтово совпадает с контрактом Задания 2.

## 7. Безопасность репозитория

- **Секреты** (RPC URL, приватные ключи, ключ Etherscan) хранятся только в Hardhat keystore вне репозитория и читаются через `configVariable(...)`. Для Sepolia созданы три отдельных **тестовых** кошелька без реальной ценности. Их ключи записаны напрямую в development keystore Hardhat (`%APPDATA%\hardhat-nodejs\Config\dev.keystore.json`), не выводились в консоль и не попадали в проект.
- **`.env`** не используется и исключён в `.gitignore`.
- **`npm run check:secrets`** проверяет git-файлы на ключи, мнемоники и `.env`. Результат: OK.
- **Демо-документы** `demo-data/*.xml` — синтетические, данные явно вымышлены.
