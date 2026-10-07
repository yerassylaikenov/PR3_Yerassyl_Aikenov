# Задание 2 — реестр статусов межбанковских платёжных поручений (вариант 1)

**ПР №3, вариант 1 «Банки и финтех»** — проверка статуса межбанковского платёжного поручения.
Данные: ID операции, сумма, статус, hash документа. Вариант нечётный → **Hardhat 3.x**.

Контракт: [contracts/PaymentOrderRegistry.sol](contracts/PaymentOrderRegistry.sol).
Архитектура (Задание 1): [../docs/PR3_Variant1_Task1_Architecture.drawio.png](../docs/PR3_Variant1_Task1_Architecture.drawio.png).

## Роли

| Роль | Кто | Может | Не может |
|---|---|---|---|
| `DEFAULT_ADMIN_ROLE` | администратор системы (в проде — Safe multisig 2/3 + timelock) | `grantRole` / `revokeRole`, `pause` / `unpause` | регистрировать, исполнять, отклонять платежи (нет операционных ролей) |
| `OPERATOR_ROLE` | оператор банка-отправителя | `registerPayment`, `cancelPayment` (только своё и только из `Registered`) | исполнять / отклонять |
| `SETTLEMENT_ROLE` | расчётный (клиринговый) центр | `markExecuted`, `markRejected` (только из `Registered`) | исполнить платёж, который сам зарегистрировал («4 глаза») |
| аудитор / банк-получатель | без роли | `getPayment`, `verifyDocument`, чтение событий | изменять состояние |

Авторизация — только `onlyRole` OpenZeppelin, то есть по `msg.sender`. `tx.origin` не используется.

## Данные on-chain / off-chain

| On-chain (`PaymentOrder`) | Off-chain (АБС банка, защищённое хранилище) |
|---|---|
| `paymentId` — псевдонимный `bytes32` = `keccak256(abi.encode(senderBic, operationRef, valueDate, salt))` | оригинал поручения (XML ISO 20022 pacs.008) |
| `docHash` — keccak256 документа | ФИО, ИИН/БИН, IBAN, назначение платежа, номер операции |
| `amount` (`uint128`, тиыны) | соль `salt` (CSPRNG) для `paymentId` |
| `status`, `registeredAt`, `updatedAt`, `registeredBy`, `settledBy` | |

Автомат статусов: `None → Registered → {Executed | Rejected | Cancelled}`. Финальные статусы необратимы, `paymentId` не переиспользуется даже после `Cancelled`. Изменять `docHash` и `amount` нельзя.

События: `PaymentRegistered(paymentId, docHash, amount, operator)`, `PaymentStatusChanged(paymentId, from, to, actor, reasonCode)` + стандартные `RoleGranted` / `RoleRevoked` / `Paused` / `Unpaused`.

## Почему нет ReentrancyGuard

Контракт **не переводит ETH и токены, не делает внешних вызовов** (`call` / `delegatecall` / `send` / `transfer` / вызовы других контрактов), не имеет `receive` / `fallback`. Все функции записи построены по схеме CEI: проверки → изменение состояния → событие. Управление никогда не передаётся чужому коду, поэтому поверхности атаки повторного входа нет (OWASP SC05/SC06 не применимы). В Задании 3 это подтверждает Slither: детекторы `reentrancy-*` дают 0 находок.

## Версии

| Компонент | Версия |
|---|---|
| Node.js | 24.13.0 (требуется ≥ 22.10) |
| npm | 11.6.2 |
| Hardhat | 3.18.1 |
| @nomicfoundation/hardhat-toolbox-viem | 5.0.7 |
| viem | 2.57.3 |
| @openzeppelin/contracts | 5.6.1 |
| forge-std | 1.16.2 |
| solc | 0.8.28, optimizer on, runs = 200 |
| TypeScript | 6.0.3 |

Все версии в `package.json` зафиксированы точно, `package-lock.json` закоммичен.

## Установка и команды

```
npm ci
npm run compile
```

| Команда | Что делает | Результат (реальный прогон) |
|---|---|---|
| `npm run compile` | компиляция | без ошибок и предупреждений |
| `npm run test:unit` | 21 unit-тест | 21 passing |
| `npm run test:fuzz` | 3 fuzz-теста (по 256 прогонов, фиксированный seed) | 3 passing |
| `npm run test:invariant` | 5 инвариантов (64 прогона × глубина 32) | 5 passing |
| `npm run test:integration` | 3 TS-теста (node:test + viem) | 3 passing |
| `npm test` | все тесты | 32 passing |
| `npm run test:report` | все этапы + `reports/*.log` + `reports/TEST_SUMMARY.md` | все этапы ✅ |
| `npm run coverage` | покрытие | 100% строк и statements |
| `npm run node` | локальная нода `127.0.0.1:8545` | — |
| `npm run deploy:local` / `npm run interact:local` | развёртывание и сценарий на локальной ноде | см. `REPORT_TASK2.md` |
| `npm run deploy:sepolia` / `npm run interact:sepolia` | то же в Sepolia | см. ниже |
| `npm run wallet:new` | новый тестовый кошелёк | — |
| `npm run check:secrets` | поиск секретов в git-файлах | OK |

`test:invariant` передаёт Hardhat два файла: тест и `PaymentOrderHandler.sol`. Если запустить только файл теста, Hardhat 3 не передаёт в EDR артефакт handler'а, и invariant-тесты падают с ошибкой «address does not have an associated contract».

## Соответствие требованиям Задания 2

| Требование | Где выполнено |
|---|---|
| Hardhat 3.x (нечётный вариант) | `package.json`, `hardhat.config.ts` (`defineConfig`, ESM) |
| ≥ 4 public/external функций | `registerPayment`, `cancelPayment`, `markExecuted`, `markRejected`, `pause`, `unpause`, `getPayment`, `verifyDocument` |
| ≥ 2 событий | `PaymentRegistered`, `PaymentStatusChanged` |
| ≥ 2 ролей | `DEFAULT_ADMIN_ROLE`, `OPERATOR_ROLE`, `SETTLEMENT_ROLE` |
| custom errors, модификаторы, RBAC, проверка входа | 10 custom errors, `onlyRole`, `whenNotPaused`, проверки нулевых значений |
| конфиденциальные данные не on-chain | только `docHash` и псевдонимный `paymentId`; см. таблицу on-chain / off-chain |
| защита от повторного входа | нет внешних вызовов, CEI (раздел выше) |
| ≥ 8 unit-тестов | 21 тест, `test/solidity/PaymentOrderRegistry.unit.t.sol` |
| ≥ 2 fuzz / invariant | 3 fuzz + 5 invariant |
| local → Sepolia, адрес, deploy tx, ≥ 2 interaction tx | `scripts/deploy.ts`, `scripts/interact.ts`, `deployments/*.json`, `REPORT_TASK2.md` |
| нет секретов в репозитории | `hardhat-keystore`, `.gitignore`, `npm run check:secrets` |

## Трассировка к архитектуре Задания 1

| Элемент архитектуры | Реализация | Проверка |
|---|---|---|
| Роли ADMIN / OPERATOR / SETTLEMENT / аудитор | `onlyRole(...)`; разные кошельки в `interact.ts` | `test_Register_RevertsWhen_CallerHasNoOperatorRole`, `test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole`, `test_AdminWithoutOperationalRole_CannotRegisterOrSettle` |
| Структура `PaymentOrder`, on-chain / off-chain | `struct PaymentOrder`; `demo-data/*.xml`; `docHash` / `paymentId` в `interact.ts` | `test_Register_StoresDataAndEmitsEvents`, `testFuzz_Register_StoresExactData` |
| Автомат статусов | проверки переходов, `InvalidStatusTransition` | `test_FinalStatuses_CannotTransition`, INV-2 |
| Основной поток: регистрация → исполнение → `verifyDocument` | `interact.ts`, шаги 6–8 | integration-тест «full flow», `test_VerifyDocument_TrueForOriginal_FalseForTampered` |
| Принцип «4 глаз» | `SelfSettlementForbidden` | `test_MarkExecuted_RevertsWhen_SelfSettlement`, INV-4 |
| Аварийная остановка | `Pausable`, только admin | `test_Pause_BlocksWrites_OnlyAdminCanPause` |
| Только hash on-chain | `docHash`, `verifyDocument` | integration-тест `verifyDocument` с реальным XML |
| Без внешних вызовов (CEI) | нет `call` / переводов ETH | обоснование выше + Slither в Задании 3 |

### Угрозы → меры → тесты

Нумерация угроз приведена по мерам защиты со схемы. Сверьте её со спецификацией Задания 1.

| Угроза | Мера в коде | Тест |
|---|---|---|
| T1 Несанкционированный доступ | `onlyRole` по `msg.sender` | unit 4, 12, 21; `testFuzz_NonOperatorCannotRegister`, `testFuzz_NonSettlementCannotFinalize`; INV-1 |
| T2 Подмена данных / документа | `docHash` неизменен; `verifyDocument` | `test_VerifyDocument_TrueForOriginal_FalseForTampered`; INV-3 |
| T3 Повторное использование / дубликат | `PaymentAlreadyExists`, без переиспользования после `Cancelled` | `test_Register_RevertsWhen_Duplicate`, `test_Register_RevertsWhen_ReusingCancelledId` |
| T4 Злоупотребление бизнес-логикой | автомат статусов, «4 глаза», отзыв только инициатором | `test_FinalStatuses_CannotTransition`, `test_MarkExecuted_RevertsWhen_SelfSettlement`, `test_Cancel_RevertsWhen_NotInitiator`; INV-2, INV-4 |
| T5 Опережение транзакции / гонка | финальные статусы необратимы; `paymentId` с CSPRNG-солью непредсказуем | INV-2 (процедурные меры — мониторинг) |
| T6 Компрометация admin-ключа | admin без операционных ролей; в проде multisig + timelock (**процедурная мера, в учебном стенде не реализуется**) | `test_AdminWithoutOperationalRole_CannotRegisterOrSettle` |
| T7 Некорректный вход / DoS | валидация, нет циклов, пауза только admin | unit 2, 5–8, 15, 18, 19 |
| T8 Повторный вход | нет внешних вызовов и ETH, CEI | обоснование + Slither (Задание 3) |

### Инварианты → тесты

| Инвариант | Тест (`test/solidity/invariant/`) |
|---|---|
| INV-1 Состояние меняют только держатели ролей | `invariant_INV1_OnlyRoleHoldersChangeState` |
| INV-2 Финальные статусы необратимы | `invariant_INV2_FinalStatusesAreImmutable` |
| INV-3 `docHash` и `amount` неизменны | `invariant_INV3_PaymentDataImmutable` |
| INV-4 «4 глаза»: `settledBy ≠ registeredBy`, `settledBy` имеет `SETTLEMENT_ROLE` | `invariant_INV4_FourEyes` |
| INV-5 `totalRegistered` = числу существующих платежей | `invariant_INV5_TotalRegisteredMatchesGhost` |

Инварианты проверены мутационно: при временном удалении проверки финального статуса падает INV-2, при удалении проверки «4 глаз» — INV-4.

## OWASP Smart Contract Top 10 (2025)

| Категория | Применимость | Мера в коде | Тесты |
|---|---|---|---|
| SC01 Access Control | применимо, ключевой риск | `onlyRole` по `msg.sender`, без `tx.origin`; admin без операционных ролей; «4 глаза» | `test_Register_RevertsWhen_CallerHasNoOperatorRole`, `test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole`, `test_MarkExecuted_RevertsWhen_SelfSettlement`, `test_AdminWithoutOperationalRole_CannotRegisterOrSettle`, `testFuzz_NonOperatorCannotRegister`, `testFuzz_NonSettlementCannotFinalize`, INV-1, INV-4 |
| SC02 Price Oracle Manipulation | не применимо | нет оракулов и цен | — |
| SC03 Logic Errors | применимо | автомат статусов, финальность, неизменность данных, отзыв только инициатором | `test_Register_RevertsWhen_Duplicate`, `test_Register_RevertsWhen_ReusingCancelledId`, `test_FinalStatuses_CannotTransition`, `test_Cancel_RevertsWhen_NotInitiator`, INV-2, INV-3, INV-5 |
| SC04 Lack of Input Validation | применимо | `InvalidPaymentId` / `DocHash` / `Amount` / `ReasonCode`, `ZeroAddress`, `PaymentAlreadyExists`, `PaymentNotFound` | `test_Constructor_RevertsOnZeroAdmin`, `test_Register_RevertsWhen_ZeroPaymentId` / `ZeroDocHash` / `ZeroAmount`, `test_MarkRejected_RevertsWhen_ZeroReasonCode`, `test_UnknownPayment_RevertsNotFound`, `testFuzz_Register_StoresExactData` |
| SC05 Reentrancy | низкий риск, устранён архитектурно | нет внешних вызовов и ETH, CEI | обоснование + Slither (Задание 3) |
| SC06 Unchecked External Calls | не применимо | нет `call` / `delegatecall` / `send` / `transfer` | обоснование + Slither (Задание 3) |
| SC07 Flash Loan Attacks | не применимо | нет балансов и ликвидности | — |
| SC08 Integer Overflow/Underflow | низкий риск | checked arithmetic 0.8, без `unchecked`, `uint128`, `SafeCast.toUint64` | `test_Register_AcceptsBoundaryAmounts` (1 и `uint128.max`), `testFuzz_Register_StoresExactData` |
| SC09 Insecure Randomness | не применимо on-chain | соль `paymentId` — `webcrypto.getRandomValues` off-chain | ревью `scripts/interact.ts` |
| SC10 Denial of Service | применимо | нет циклов (mapping, O(1)), нет внешних вызовов; `pause` только admin | `test_Pause_BlocksWrites_OnlyAdminCanPause` |

Теги `OWASP SCxx:2025` стоят в контракте и над каждым тестом: `grep -rn "OWASP SC" contracts test`.

## Развёртывание в Sepolia

Секреты хранятся **только** в зашифрованном Hardhat keystore. `.env` не используется.

1. Создать 3 тестовых кошелька: admin, operator, settlement. Для этого выполнить `npm run wallet:new` три раза (или взять 3 новых тестовых аккаунта MetaMask).
2. Положить ключи в keystore:
   ```
   npx hardhat keystore set SEPOLIA_RPC_URL
   npx hardhat keystore set SEPOLIA_PRIVATE_KEY               # admin / deployer
   npx hardhat keystore set SEPOLIA_OPERATOR_PRIVATE_KEY
   npx hardhat keystore set SEPOLIA_SETTLEMENT_PRIVATE_KEY
   npx hardhat keystore set ETHERSCAN_API_KEY                 # опционально, для verify
   npx hardhat keystore list
   ```
3. Проверить адреса и балансы командой `npm run accounts:sepolia` (транзакции не отправляются). Пополнить тестовыми ETH через Sepolia faucet **только адрес admin**, то есть `[0]`. Скрипт сам переведёт по 0.003 ETH оператору и расчётному центру, если у них меньше 0.002 ETH.
4. Запустить:
   ```
   npm run deploy:sepolia
   npm run interact:sepolia
   npx hardhat verify --network sepolia <address> <admin>   # опционально
   ```
   Hardhat попросит пароль keystore. Результаты сохраняются в `deployments/sepolia.json`, ссылки на Etherscan печатаются в консоли.

Сценарий для Sepolia заранее проверен на локальной эмуляции: `hardhat node --chain-id 11155111`, три аккаунта через `configVariable`, у оператора и расчётного центра нулевой баланс. Проверено:
- деплой и ссылки на Etherscan;
- подпись транзакций тремя разными ключами;
- автопополнение газом;
- повторный запуск без ошибок.

Порог и сумма пополнения — константы `MIN_ROLE_BALANCE` / `TOP_UP_AMOUNT` вверху `scripts/interact.ts`. Если газ в Sepolia дорогой, `TOP_UP_AMOUNT` можно увеличить.

Если какой-то переменной нет в keystore, Hardhat после ввода пароля завершится сообщением о ненайденной configuration variable с её именем. Значит, её нужно добавить командой `npx hardhat keystore set <ИМЯ>`.
