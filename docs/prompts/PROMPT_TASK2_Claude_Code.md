# ПРОМПТ ДЛЯ CLAUDE CODE — ПР №3, Задание 2 (Вариант 1: Банки и финтех)

Ты — senior Solidity / Web3 security engineer. Реализуй учебный, но промышленно аккуратный проект по заданию ниже. Главный критерий приёмки: **всё компилируется, все тесты зелёные, локальное развёртывание и взаимодействие проходят с первого запуска, команды для Sepolia готовы**. Проект будет показываться вживую преподавателю, поэтому важны воспроизводимость и чистый вывод в терминале.

Работай итерациями: создал часть → запустил → исправил → только потом дальше. Не завершай работу, пока не выполнен весь чек-лист приёмки в конце.

---

## 0. Контекст задания (нельзя нарушать)

- Предметная область (вариант 1): **проверка статуса межбанковского платёжного поручения**. Данные: ID операции, сумма, статус, hash документа.
- Вариант нечётный → **Hardhat 3.x** (не Foundry, не Hardhat 2).
- Требования преподавателя к контракту: ≥ 4 public/external функций, ≥ 2 событий, ≥ 2 ролей; custom errors; модификаторы / ролевая модель; проверка входных данных; конфиденциальные данные в открытом виде on-chain не хранить; если есть переводы ETH / внешние вызовы — защита от повторного входа (у нас их нет — это нужно явно обосновать в README).
- Тесты: ≥ 8 unit (корректные сценарии, ошибки доступа, некорректный вход, повторные операции, граничные значения, ожидаемые откаты) + ≥ 2 fuzz **и** ≥ 2 invariant (делаем и то и другое).
- Развёртывание: сначала локальная сеть, затем Sepolia. В отчёт: адрес контракта, deploy tx hash, ≥ 2 interaction tx hash, ссылки на block explorer.
- **Критическая ошибка:** реальные приватные ключи, секреты или персональные данные в репозитории. Никаких `.env` с ключами, никаких ключей в коде/конфиге/логах.

## 0.1 Связь с архитектурой Задания 1 (обязательно отразить в README)

Реализация должна совпадать с draw.io из Задания 1. В README сделай таблицу трассировки «элемент архитектуры → где реализован/проверен»:
- Роли ADMIN / OPERATOR / SETTLEMENT / аудитор (стр. 2.1) → `onlyRole`, unit-тесты доступа, разделение кошельков в `interact.ts`.
- Структура `PaymentOrder` и on-chain/off-chain (стр. 2.2–2.3) → контракт, `demo-data/*.xml`, вычисление `docHash`/`paymentId` в `interact.ts`.
- Автомат статусов (стр. 2.4) → проверки переходов, тест `test_FinalStatuses_CannotTransition`.
- Основной поток (стр. 3: регистрация → исполнение → `verifyDocument`) → `interact.ts` шаги 6–8.
- Угрозы T1–T8 (стр. 4.1) → мера в коде + тест (T6 и мультиподпись/timelock — описать как процедурную меру для продакшена, в учебном стенде не реализуются; T8 — обоснование отсутствия внешних вызовов).
- Инварианты INV-1…INV-5 (стр. 4.2) → `invariant_INV1…INV5`.
- Сопоставление с OWASP SC Top 10 (2025) (стр. 5) → раздел 0.2 ниже.

## 0.2 OWASP Smart Contract Top 10 (2025) — обязательная привязка

Преподаватель проверяет соответствие **OWASP Smart Contract Top 10 (2025)** (https://scs.owasp.org/sctop10/archive/2025/ — именно версия 2025, не 2026). Привязка уже сделана в архитектуре (draw.io, стр. 4–5) — повтори её в коде, тестах и документах:

| Категория | Применимость | Мера в коде | Тесты |
|---|---|---|---|
| SC01:2025 Access Control | применимо, ключевой риск | `onlyRole` по `msg.sender`, без `tx.origin`; admin без операционных ролей; «4 глаза» | unit 4, 12, 13, 21; fuzz NonOperator / NonSettlement; INV-1, INV-4 |
| SC02:2025 Price Oracle Manipulation | не применимо (нет оракулов/цен) | доверие к off-chain данным ограничено ролью и `verifyDocument` | — (обоснование) |
| SC03:2025 Logic Errors | применимо | автомат статусов, финальные статусы, неизменяемость данных, отзыв только инициатором | unit 9, 10, 16, 17; INV-2, INV-3, INV-5 |
| SC04:2025 Lack of Input Validation | применимо | `InvalidPaymentId/DocHash/Amount/ReasonCode`, `ZeroAddress`, `PaymentAlreadyExists`, `PaymentNotFound` | unit 2, 5–8, 15, 18; fuzz RegisterStoresExactData |
| SC05:2025 Reentrancy | низкий риск, устранён архитектурно | нет внешних вызовов/ETH, CEI | обоснование + Slither в Задании 3 |
| SC06:2025 Unchecked External Calls | не применимо | нет `call`/`delegatecall`/`send`/`transfer` | обоснование + Slither в Задании 3 |
| SC07:2025 Flash Loan Attacks | не применимо | нет балансов/ликвидности; запись требует роли | — (обоснование) |
| SC08:2025 Integer Overflow/Underflow | низкий риск | 0.8 checked arithmetic, без `unchecked`, `uint128` amount, `SafeCast.toUint64` | unit 8 (1 и max uint128); fuzz по uint128 |
| SC09:2025 Insecure Randomness | не применимо on-chain | salt для paymentId — CSPRNG off-chain | ревью `interact.ts` |
| SC10:2025 Denial of Service | применимо | нет циклов по массивам (mapping O(1)), нет внешних вызовов; `pause` только admin | unit 19 (pause) |

Что сделать:
1. В контракте — короткие комментарии-теги у соответствующих мест: `// OWASP SC01:2025 — role check by msg.sender`, `// OWASP SC04:2025 — input validation`, `// OWASP SC03:2025 — state machine`, `// OWASP SC08:2025 — SafeCast`, а в шапке NatSpec — абзац, почему SC05/SC06/SC07/SC09 не применимы и почему нет циклов (SC10).
2. В тестах — над каждым тестом комментарий `/// OWASP SCxx:2025` (номера из таблицы). Номера unit-тестов в таблице соответствуют списку в п. 4.1.
3. В README — таблица выше с реальными именами тестов вместо номеров.
4. В REPORT_TASK2.md — раздел «Покрытие OWASP Smart Contract Top 10 (2025)»: категория → мера → имя теста → результат (passed) из реальных логов; отдельно перечислить неприменимые категории с обоснованием.
5. `run-and-log.mjs` добавляет в `reports/TEST_SUMMARY.md` таблицу «OWASP категория → тесты → passed/failed» (сопоставление по тегам из комментариев или по статической карте в скрипте).

## 1. Окружение и версии

1. Перед началом **прочитай актуальную документацию Hardhat 3** (твои знания могут быть устаревшими): https://hardhat.org/docs/getting-started , https://hardhat.org/docs/guides/testing/using-solidity , https://hardhat.org/docs/reference/configuration , руководства по keystore / configuration variables, deployment и verify. Если API в установленной версии отличается от описанного в этом промпте — следуй документации, но сохрани все требования.
2. Требования: Node.js ≥ 22.10 (проверь `node -v`; если ниже — остановись и сообщи мне). npm.
3. Стек:
   - `hardhat` 3.x (последняя стабильная), проект ESM (`"type": "module"`), `hardhat.config.ts` через `defineConfig`.
   - Плагин-тулбокс для **viem + node:test** (`@nomicfoundation/hardhat-toolbox-viem` — версия, совместимая с Hardhat 3), `viem`, `typescript`, `@types/node`.
   - `@openzeppelin/contracts` 5.x (последняя 5.x).
   - `forge-std` для Solidity-тестов (как в официальном шаблоне Hardhat 3).
   - Solidity **0.8.28** (точная версия в pragma и в конфиге), optimizer включён, runs = 200.
4. **Не используй интерактивные команды**, которые требуют ответа в терминале (например, интерактивный `npx hardhat --init`). Если init интерактивный — создай файлы вручную по официальному шаблону «TypeScript + node:test + viem».
5. После установки **зафиксируй точные версии** в `package.json` (без `^`/`~`) и закоммить `package-lock.json`, чтобы `npm ci` давал идентичный результат на демонстрации.

## 2. Структура репозитория

Я запускаю тебя из корневой папки `pr3-variant1/`. Создай подпроект:

```
pr3-variant1/
├── .gitignore                       # общий (см. п. 9)
├── docs/                            # сюда я положу draw.io из Задания 1 (не трогай содержимое, если есть)
└── task2-payment-registry/
    ├── contracts/PaymentOrderRegistry.sol
    ├── test/solidity/PaymentOrderRegistry.unit.t.sol
    ├── test/solidity/PaymentOrderRegistry.fuzz.t.sol
    ├── test/solidity/invariant/PaymentOrderRegistry.invariant.t.sol
    ├── test/solidity/invariant/PaymentOrderHandler.sol
    ├── test/nodejs/PaymentOrderRegistry.integration.ts
    ├── scripts/deploy.ts
    ├── scripts/interact.ts
    ├── scripts/new-wallet.ts
    ├── scripts/run-and-log.mjs
    ├── scripts/check-secrets.mjs
    ├── demo-data/payment-order-0001.xml   # синтетический документ, вымышленные данные
    ├── deployments/                       # JSON с результатами развёртывания
    ├── reports/                           # логи запуска тестов
    ├── hardhat.config.ts, tsconfig.json, package.json, package-lock.json
    ├── README.md, DEMO.md, REPORT_TASK2.md
```

Если в корне нет git-репозитория — выполни `git init` в `pr3-variant1/`. Делай осмысленные коммиты по этапам.

В `hardhat.config.ts` явно задай пути тестов: `paths.tests.solidity = "./test/solidity"`, `paths.tests.nodejs = "./test/nodejs"`.

## 3. Смарт-контракт `PaymentOrderRegistry` — точная спецификация

Архитектура уже утверждена в Задании 1 (draw.io) — **имена, роли, события, ошибки и переходы должны совпадать один в один**.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
contract PaymentOrderRegistry is AccessControl, Pausable { ... }
```

**Роли:** `DEFAULT_ADMIN_ROLE` (админ: управление ролями, pause/unpause), `OPERATOR_ROLE = keccak256("OPERATOR_ROLE")` (оператор банка-отправителя), `SETTLEMENT_ROLE = keccak256("SETTLEMENT_ROLE")` (расчётный центр). Аудитор — без роли (только view). Авторизация **только** через `onlyRole` OpenZeppelin (т.е. по `msg.sender`). `tx.origin` нигде не используется.

**Типы и хранилище:**
```solidity
enum Status { None, Registered, Executed, Rejected, Cancelled }
struct PaymentOrder {
    bytes32 docHash;       // keccak256 канонического документа (оригинал — off-chain)
    uint128 amount;        // сумма в минимальных единицах (тиын), > 0
    uint64  registeredAt;
    uint64  updatedAt;
    Status  status;
    address registeredBy;  // оператор-инициатор
    address settledBy;     // расчётный центр (0 до исполнения/отклонения)
}
mapping(bytes32 => PaymentOrder) private _payments;   // ключ — paymentId
uint256 public totalRegistered;
```
`paymentId` — псевдонимный `bytes32`, вычисляется off-chain как `keccak256(abi.encode(senderBic, operationRef, valueDate, salt))`; в блокчейн не попадают ФИО, ИИН/БИН, IBAN, назначение платежа, номер операции.

**События (ровно такие сигнатуры):**
```solidity
event PaymentRegistered(bytes32 indexed paymentId, bytes32 docHash, uint128 amount, address indexed operator);
event PaymentStatusChanged(bytes32 indexed paymentId, Status from, Status to, address indexed actor, bytes32 reasonCode);
```

**Custom errors:**
```solidity
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
```
(+ стандартные `AccessControlUnauthorizedAccount`, `EnforcedPause` из OZ.)

**Функции** (порядок модификаторов: `onlyRole(...)` затем `whenNotPaused`; порядок проверок внутри — строго как указано, тесты на это опираются):

| Функция | Доступ | Проверки по порядку | Эффект |
|---|---|---|---|
| `constructor(address admin)` | — | `admin == 0` → `ZeroAddress` | `_grantRole(DEFAULT_ADMIN_ROLE, admin)` |
| `registerPayment(bytes32 paymentId, bytes32 docHash, uint128 amount) external` | OPERATOR, whenNotPaused | id==0 → `InvalidPaymentId`; hash==0 → `InvalidDocHash`; amount==0 → `InvalidAmount`; status≠None → `PaymentAlreadyExists` | сохранить структуру (status=Registered, registeredBy=msg.sender, registeredAt=updatedAt=`SafeCast.toUint64(block.timestamp)`), `totalRegistered++`, emit `PaymentRegistered` (только это событие — как на диаграмме последовательности, шаг 7) |
| `cancelPayment(bytes32 paymentId) external` | OPERATOR, whenNotPaused | None → `PaymentNotFound`; status≠Registered → `InvalidStatusTransition(cur, Cancelled)`; registeredBy≠msg.sender → `NotPaymentInitiator` | status=Cancelled, updatedAt, emit `PaymentStatusChanged` |
| `markExecuted(bytes32 paymentId) external` | SETTLEMENT, whenNotPaused | None → `PaymentNotFound`; status≠Registered → `InvalidStatusTransition(cur, Executed)`; registeredBy==msg.sender → `SelfSettlementForbidden` | status=Executed, settledBy=msg.sender, updatedAt, emit |
| `markRejected(bytes32 paymentId, bytes32 reasonCode) external` | SETTLEMENT, whenNotPaused | reasonCode==0 → `InvalidReasonCode`; None → `PaymentNotFound`; status≠Registered → `InvalidStatusTransition(cur, Rejected)`; registeredBy==msg.sender → `SelfSettlementForbidden` | status=Rejected, settledBy, updatedAt, emit с reasonCode (ISO 20022 код, напр. `"AC04"`) |
| `pause()` / `unpause()` external | DEFAULT_ADMIN | — | OZ Pausable |
| `getPayment(bytes32) external view returns (PaymentOrder memory)` | все | не ревертит (для несуществующего — нулевая структура) | — |
| `verifyDocument(bytes32 paymentId, bytes32 candidateHash) external view returns (bool)` | все | — | `status != None && candidateHash != 0 && docHash == candidateHash` |

Требования к коду: Solidity 0.8 checked arithmetic, **без `unchecked`**, время только через `SafeCast.toUint64` (OWASP SC08); шаблон «проверки → изменение состояния → событие» (CEI); никаких внешних вызовов и переводов ETH; нет `receive`/`fallback`; NatSpec (`@notice`, `@dev`, `@param`) на всех внешних функциях; комментарий в шапке контракта, почему ReentrancyGuard не нужен; финальные статусы необратимы; `paymentId` не переиспользуется даже после `Cancelled`; нет функций изменения `docHash`/`amount`.

## 4. Тесты

Все Solidity-тесты используют `forge-std/Test.sol`. Акторы: `admin`, `operator`, `operator2`, `settlement`, `stranger` (через `makeAddr`). В `setUp`: деплой от `admin`, выдача ролей `operator`, `operator2` → OPERATOR, `settlement` → SETTLEMENT. Проверяй ошибки **точными селекторами с аргументами** (`vm.expectRevert(abi.encodeWithSelector(...))`), события — через `vm.expectEmit`.

### 4.1 Unit (`PaymentOrderRegistry.unit.t.sol`) — не меньше 16, имена именно такие:
1. `test_Constructor_GrantsAdminRole`
2. `test_Constructor_RevertsOnZeroAdmin`
3. `test_Register_StoresDataAndEmitsEvents`
4. `test_Register_RevertsWhen_CallerHasNoOperatorRole` (stranger и settlement)
5. `test_Register_RevertsWhen_ZeroPaymentId`
6. `test_Register_RevertsWhen_ZeroDocHash`
7. `test_Register_RevertsWhen_ZeroAmount`
8. `test_Register_AcceptsBoundaryAmounts` (1 и `type(uint128).max`)
9. `test_Register_RevertsWhen_Duplicate`
10. `test_Register_RevertsWhen_ReusingCancelledId`
11. `test_MarkExecuted_UpdatesStatusAndEmits`
12. `test_MarkExecuted_RevertsWhen_CallerHasNoSettlementRole` (stranger и operator)
13. `test_MarkExecuted_RevertsWhen_SelfSettlement` (адрес с обеими ролями регистрирует и пытается исполнить)
14. `test_MarkRejected_StoresReasonAndEmits`
15. `test_MarkRejected_RevertsWhen_ZeroReasonCode`
16. `test_FinalStatuses_CannotTransition` (из Executed/Rejected/Cancelled все переходы → `InvalidStatusTransition`, повторный markExecuted тоже)
17. `test_Cancel_RevertsWhen_NotInitiator`
18. `test_UnknownPayment_RevertsNotFound`
19. `test_Pause_BlocksWrites_OnlyAdminCanPause` (+ после unpause запись снова работает)
20. `test_VerifyDocument_TrueForOriginal_FalseForTampered`
21. `test_AdminWithoutOperationalRole_CannotRegisterOrSettle`

### 4.2 Fuzz (`PaymentOrderRegistry.fuzz.t.sol`) — 3 теста:
- `testFuzz_Register_StoresExactData(bytes32 paymentId, bytes32 docHash, uint128 amount)` — с `vm.assume` на ненулевые значения; проверяет всё сохранённое и `verifyDocument`.
- `testFuzz_NonOperatorCannotRegister(address caller)` — caller без роли (исключи адреса с ролями и `address(0)`), всегда revert `AccessControlUnauthorizedAccount`.
- `testFuzz_NonSettlementCannotFinalize(address caller, bool reject)` — всегда revert, статус остаётся Registered.

### 4.3 Invariant (`invariant/` + handler) — 5 инвариантов из архитектуры:
Handler `PaymentOrderHandler` (обычный контракт в `test/solidity/invariant/`) вызывает реестр через `vm.prank` от имени правильных ролей. Используй **ограниченный пул из 10 paymentId** (`id = keccak256(abi.encode("PAY", seed % 10))`), чтобы фаззер создавал дубликаты и пытался менять финальные статусы. Действия: `register`, `cancel`, `execute`, `reject`, `strangerAttack` (случайный адрес без ролей пытается вызвать каждую функцию записи, `try/catch`). Все вызовы обёрнуты в `try/catch`, ghost-переменные: ожидаемый статус/данные по каждому id, счётчик успешных регистраций, `ghost_unauthorizedSuccess`.
Инварианты (имена):
- `invariant_INV1_OnlyRoleHoldersChangeState` — `ghost_unauthorizedSuccess == 0`.
- `invariant_INV2_FinalStatusesAreImmutable` — финальный статус по ghost-снимку не изменился.
- `invariant_INV3_PaymentDataImmutable` — docHash и amount равны значениям при регистрации.
- `invariant_INV4_FourEyes` — для Executed/Rejected `settledBy != registeredBy` и `settledBy` имеет SETTLEMENT_ROLE.
- `invariant_INV5_TotalRegisteredMatchesGhost`.
В тест-контракте используй `targetContract(address(handler))` (и при необходимости `targetSelector`). Если в установленной версии Hardhat какой-то cheatcode/функция invariant-тестирования не поддерживается — найди поддерживаемый аналог в документации, не удаляй инвариант.

### 4.4 Интеграционные TypeScript-тесты (`test/nodejs/...integration.ts`, node:test + viem) — 3 теста:
полный поток register → execute с проверкой событий; revert `SelfSettlementForbidden` с правильным custom error; `verifyDocument` для хеша файла `demo-data/payment-order-0001.xml` (true) и для изменённого содержимого (false).

### 4.5 Конфигурация тестов
В `test.solidity`: `fuzz.runs = 256`; `invariant.runs = 64`, `invariant.depth = 32`, `invariant.failOnRevert = false`. Если поддерживается фиксированный seed — задай его, чтобы прогон на демонстрации был воспроизводим. Полный прогон всех тестов должен укладываться примерно в 1 минуту.

## 5. Скрипты развёртывания и взаимодействия

Сети в `hardhat.config.ts`:
- `localhost`: `{ type: "http", chainType: "l1", url: "http://127.0.0.1:8545" }` (аккаунты — разблокированные аккаунты `hardhat node`).
- `sepolia`: `{ type: "http", chainType: "l1", url: configVariable("SEPOLIA_RPC_URL"), accounts: [configVariable("SEPOLIA_PRIVATE_KEY"), configVariable("SEPOLIA_OPERATOR_PRIVATE_KEY"), configVariable("SEPOLIA_SETTLEMENT_PRIVATE_KEY")] }`.
- **Разделение ролей из архитектуры (Задание 1) соблюдается и в демо:** wallet[0] — только `DEFAULT_ADMIN_ROLE`, wallet[1] — только `OPERATOR_ROLE`, wallet[2] — только `SETTLEMENT_ROLE`. Админ никогда не получает операционных ролей (мера против угрозы T6).
- verify: ключ `configVariable("ETHERSCAN_API_KEY")` (опционально).
Секреты — **только** через `hardhat-keystore` (зашифрованное хранилище Hardhat), никаких `.env`.

**`scripts/deploy.ts`** (`npx hardhat run scripts/deploy.ts --network <net>`): `network.connect()`, wallet[0] = admin/deployer. Деплой через функцию hardhat-viem, которая возвращает и контракт, и deploy-транзакцию (например `sendDeploymentTransaction`), дождаться receipt. Вывести: сеть, chainId, адрес, deploy tx hash, блок, gasUsed. Записать `deployments/<network>.json`. Для Sepolia — печатать ссылки `https://sepolia.etherscan.io/address/<addr>` и `/tx/<hash>` и готовую команду `npx hardhat verify --network sepolia <addr> <admin>`.

**`scripts/interact.ts`** (тот же формат запуска) — сценарий из диаграммы последовательности:
1. Прочитать адрес из `deployments/<network>.json` (понятная ошибка, если файла нет).
2. wallet[0] — admin, wallet[1] — оператор банка-отправителя, wallet[2] — расчётный центр (на localhost — аккаунты 0/1/2 ноды).
3. От admin: `grantRole(OPERATOR_ROLE, wallet1)` и `grantRole(SETTLEMENT_ROLE, wallet2)` — **пропускать, если роль уже есть** (повторный запуск не должен падать). В конце вывести проверку: admin не имеет OPERATOR/SETTLEMENT.
4. Только для Sepolia: если баланс wallet[1] или wallet[2] < 0.002 ETH — перевести ему 0.003 ETH с wallet[0] (порог и сумма — константы вверху файла). Пополнять через faucet нужно только wallet[0].
5. Посчитать `docHash = keccak256(bytes файла demo-data/payment-order-0001.xml)`, `paymentId = keccak256(abi.encode("DEMOKZKA", operationRef, "2026-10-06", salt))`, где `operationRef` уникален для каждого запуска (на основе времени), `salt` — случайные 32 байта из криптостойкого генератора (`crypto.getRandomValues` / `node:crypto`), не `Math.random` и не время (OWASP SC09). Скрипт можно запускать много раз подряд без ошибок `PaymentAlreadyExists`.
6. tx: `registerPayment(id1, docHash, 12_500_000_000)` от wallet[1] (оператор) → tx: `markExecuted(id1)` от wallet[2] (расчётный центр).
7. tx: `registerPayment(id2, docHash2, …)` от wallet[1] → tx: `markRejected(id2, "AC04")` от wallet[2].
8. view: `verifyDocument(id1, docHash)` → true; `verifyDocument(id1, keccak256(изменённого документа))` → false.
9. Без отправки транзакций (simulate/eth_call) показать два отказа и вывести имена ошибок: `markExecuted(id)` от wallet[1] (оператор без SETTLEMENT) → `AccessControlUnauthorizedAccount`; `registerPayment` от wallet[0] (admin без OPERATOR) → `AccessControlUnauthorizedAccount`. Отказ `SelfSettlementForbidden` уже покрыт unit-тестом №13.
10. Каждую транзакцию печатать понятной строкой: шаг, функция, tx hash, блок, статус; для Sepolia — ссылка на Etherscan. Все хеши дописать в `deployments/<network>.json` (`interactions: [...]`), в конце вывести готовую markdown-таблицу для отчёта.

`demo-data/payment-order-0001.xml` — короткий синтетический ISO 20022-подобный документ с **явно вымышленными** данными (например, «ТОО Демо-Плательщик», IBAN вида `KZ00DEMO0000000000001`), с комментарием, что это тестовые данные.

**`scripts/new-wallet.ts`** — генерирует новый тестовый приватный ключ через viem и печатает адрес и ключ один раз с предупреждением «только для Sepolia, не храните в файлах, сразу добавьте в keystore».

## 6. npm-скрипты (кроссплатформенно: Windows/macOS/Linux, без bash-специфики)

```
compile            hardhat compile
test               hardhat test                         (все: solidity + nodejs)
test:unit          hardhat test solidity test/solidity/PaymentOrderRegistry.unit.t.sol
test:fuzz          hardhat test solidity test/solidity/PaymentOrderRegistry.fuzz.t.sol
test:invariant     hardhat test solidity test/solidity/invariant/PaymentOrderRegistry.invariant.t.sol
test:integration   hardhat test nodejs
test:report        node scripts/run-and-log.mjs         (прогоняет все этапы, пишет reports/*.log и reports/TEST_SUMMARY.md: команда, exit code, кол-во passed/failed)
coverage           hardhat test --coverage              (если поддерживается)
node               hardhat node
deploy:local       hardhat run scripts/deploy.ts --network localhost
interact:local     hardhat run scripts/interact.ts --network localhost
deploy:sepolia     hardhat run scripts/deploy.ts --network sepolia
interact:sepolia   hardhat run scripts/interact.ts --network sepolia
wallet:new         hardhat run scripts/new-wallet.ts
check:secrets      node scripts/check-secrets.mjs
```
Если `hardhat test solidity <file>` в установленной версии требует другой синтаксис — проверь `npx hardhat test solidity --help` и адаптируй.

`run-and-log.mjs` запускает команды через `child_process.spawn` (с `shell: true` для Windows), сохраняет полный вывод в `reports/<stage>.log` и печатает его в консоль.
`check-secrets.mjs` проверяет отслеживаемые git файлы на: файлы `.env*`, строки вида `PRIVATE_KEY = "0x<64 hex>"`, мнемоники; при находке — exit 1.

## 7. Документация

- **README.md**: назначение, архитектура (ссылка на `../docs/*.drawio`), роли, on-chain/off-chain данные, точные версии (Node, Hardhat, toolbox, viem, OpenZeppelin, solc, forge-std — взять из `npm ls` и `npx hardhat --version`), установка (`npm ci`), все команды, объяснение отсутствия ReentrancyGuard, таблица «инвариант → тест».
- **DEMO.md** — сценарий живой демонстрации, по шагам, для каждого шага: команда, что показать, ожидаемый результат:
  0. Предварительно (до пары, с интернетом): `npm ci`, `npm run compile` (скачивание solc), `npm test`.
  1. `npm run compile` 2. `npm run test:unit` 3. `npm run test:fuzz` 4. `npm run test:invariant` 5. `npm run test:integration`
  6. Терминал 1: `npm run node`; Терминал 2: `npm run deploy:local`, затем `npm run interact:local` (показать транзакции в логах ноды).
  7. Sepolia: показать `deployments/sepolia.json` и ссылки Etherscan (развёртывание делается заранее).
  8. Раздел «Если что-то пошло не так»: порт 8545 занят, нет deployments/localhost.json после перезапуска ноды (заново `deploy:local`), нехватка Sepolia ETH, забытый пароль keystore.
- **REPORT_TASK2.md** (на русском): версии toolchain; исходный код контракта (ссылка на файл); для каждого тестового этапа — команда и **реальный** вывод (из `reports/*.log`, сокращённо); результаты локального развёртывания (реальные адреса и хеши из твоего прогона); раздел Sepolia с заполнителями `<заполнить после npm run deploy:sepolia>` и инструкцией, откуда взять значения.
- **Инструкция для меня по Sepolia** (в README, раздел «Развёртывание в Sepolia»):
  1. `npm run wallet:new` три раза (admin, operator, settlement; или 3 новых тестовых аккаунта MetaMask).
  2. `npx hardhat keystore set SEPOLIA_RPC_URL`, `... set SEPOLIA_PRIVATE_KEY` (admin), `... set SEPOLIA_OPERATOR_PRIVATE_KEY`, `... set SEPOLIA_SETTLEMENT_PRIVATE_KEY` (опц. `ETHERSCAN_API_KEY`); проверить `npx hardhat keystore list`.
  3. Пополнить тестовыми ETH через Sepolia faucet только адрес admin — скрипт сам переведёт газ оператору и расчётному центру.
  4. `npm run deploy:sepolia` → `npm run interact:sepolia` → (опц.) verify.

## 8. Чего НЕ делать

- Не запрашивай у меня приватные ключи и не запускай команды для Sepolia сам — подготовь всё и дай мне точные команды.
- Не используй Hardhat 2 API (`hre.ethers`, `require("hardhat")`, `hardhat.config.js` в CJS, `module.exports`).
- Не упрощай спецификацию контракта и не меняй имена — они уже на архитектурной схеме.
- Не отключай и не помечай `skip` упавшие тесты — исправляй причину.
- Не храни ничего чувствительного в `deployments/`, `reports/`, логах.

## 9. .gitignore (в корне pr3-variant1)
`node_modules/`, `artifacts/`, `cache/`, `coverage/`, `types/`, `.env*`, `*.key`, `deployments/localhost.json`, `.venv/`, `crytic-export/`, `.DS_Store`. `deployments/sepolia.json` и `reports/` — коммитить (публичные данные, доказательства).

## 10. Чек-лист приёмки (выполни сам и приложи вывод в финальном сообщении)

- [ ] `npm ci` с нуля (удалив node_modules) проходит без ошибок.
- [ ] `npm run compile` — без ошибок и без предупреждений компилятора.
- [ ] `npm run test:unit` — ≥ 16 passing, 0 failing.
- [ ] `npm run test:fuzz` — 3 passing (256 runs).
- [ ] `npm run test:invariant` — 5 passing.
- [ ] `npm run test:integration` — 3 passing.
- [ ] `npm test` — всё зелёное; `npm run test:report` создал `reports/*.log` и `reports/TEST_SUMMARY.md`.
- [ ] Реальный прогон: `hardhat node` в фоне → `deploy:local` → `interact:local` дважды подряд без ошибок → ноду останови.
- [ ] `npx hardhat run scripts/deploy.ts --network sepolia` без ключей завершается **понятным** сообщением о недостающей configuration variable (а не stack trace) — либо задокументировано, как это выглядит.
- [ ] `npm run check:secrets` — чисто; `git status` не содержит секретов.
- [ ] Таблица соответствия требованиям задания → файл/команда/тест и таблица трассировки к архитектуре Задания 1 (в README).
- [ ] В `interact.ts` admin, operator и settlement — три разных адреса; admin не имеет операционных ролей.
- [ ] В README есть таблица OWASP SC Top 10 (2025) по всем 10 категориям; в контракте и тестах стоят теги `OWASP SCxx:2025`; `grep -rn "OWASP SC" contracts test` показывает их; в REPORT_TASK2.md есть раздел «Покрытие OWASP».

В финальном сообщении дай: дерево проекта, таблицу результатов тестов (этап → команда → passed/failed), адрес и хеши локального развёртывания, и **точный список команд**, которые я должен выполнить сам для Sepolia.
