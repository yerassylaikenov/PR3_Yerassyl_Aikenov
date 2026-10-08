# ПРОМПТ ДЛЯ CLAUDE CODE — ПР №3, Задание 3 (Вариант 1): анализ уязвимости и проверка исправления

Ты — senior smart-contract security auditor. Нужно сделать **отдельный самостоятельный проект** для Задания 3, который я буду демонстрировать вживую после Задания 2. Главный критерий: каждая команда демонстрации даёт предсказуемый, понятный результат — атака **успешна** на уязвимой версии, **блокируется** на исправленной, а сравнение «до/после» формируется автоматически.

Работай итерациями (создал → запустил → исправил). Не завершай, пока не выполнен чек-лист приёмки в конце.

---

## 0. Контекст

- Запускаю тебя из корня `pr3-variant1/`. Рядом лежит Задание 2: `./task2-payment-registry/` (Hardhat 3, контракт `contracts/PaymentOrderRegistry.sol`). **Не изменяй ничего в task2.**
- Создай новую папку `./task3-vulnerability-analysis/` — полностью независимый Hardhat 3 проект (свой `package.json`, `package-lock.json`, `node_modules`). Те же точные версии Hardhat / toolbox-viem / viem / OpenZeppelin / forge-std / solc 0.8.28, что в task2 (возьми из его `package.json`).
- Перед началом прочитай актуальную документацию Hardhat 3 по Solidity-тестам, fuzz/invariant, cheatcodes, configuration (https://hardhat.org/docs) и README Slither (https://github.com/crytic/slither). Если API отличается от описанного здесь — следуй документации, сохраняя требования.
- Эксперименты **только локально** (in-process сеть Hardhat или `hardhat node`). Уязвимую версию в Sepolia не развёртывать.
- Никаких приватных ключей, `.env` и персональных данных в репозитории.

Требования преподавателя к Заданию 3 (все должны быть закрыты):
1. Отдельная уязвимая версия контракта с одним контролируемым дефектом.
2. Уязвимость, релевантная варианту — выбрана: **неправильное использование `tx.origin` для авторизации — OWASP SC01:2025 Access Control Vulnerabilities** (также SWC-115, CWE-284). Преподаватель проверяет привязку к OWASP Smart Contract Top 10 (2025) — см. раздел 1.1.
3. Slither: полный отчёт сохранён, найденные проблемы классифицированы: реальная уязвимость / ложное срабатывание / информационное замечание.
4. Воспроизведение тестом **и** атакующим контрактом; зафиксированы условия, последовательность транзакций, результат.
5. Исправление безопасным шаблоном и проверенной библиотекой (OpenZeppelin `AccessControl.onlyRole`, авторизация по `msg.sender`); тест подтверждает, что атака больше не проходит.
6. Повторный запуск unit, fuzz и invariant тестов, сравнение до/после, оставшиеся риски для ручного аудита; первопричина, нарушенное правило безопасности, условия эксплуатации.

## 1. Сценарий уязвимости (бизнес-смысл для варианта 1)

Реестр статусов межбанковских платёжных поручений. Банк-получатель зачисляет средства клиенту, увидев в реестре статус `Executed`. Разработчик уязвимой версии сделал авторизацию через `hasRole(role, tx.origin)`. Злоумышленник публикует безобидный на вид контракт «возврата комиссии за расчёты» (`SettlementRebatePhish.claimRebate()`). Сотрудник расчётного центра (держатель `SETTLEMENT_ROLE`) вызывает его своим кошельком; внутри контракт вызывает `registry.markExecuted(targetPaymentId)`. Так как `tx.origin` = сотрудник, проверка роли проходит: платёж, по которому не было расчёта, получает ложный статус `Executed`, а в событиях и в `settledBy` действие приписано сотруднику (следы атаки скрыты). На исправленной версии `msg.sender` = контракт злоумышленника без роли → revert `AccessControlUnauthorizedAccount(phish, SETTLEMENT_ROLE)`.

## 1.1 Привязка к OWASP Smart Contract Top 10 (2025)

Источник: https://scs.owasp.org/sctop10/archive/2025/ (именно 2025). В архитектуре Задания 1 (draw.io, стр. 4–5) уязвимость соответствует угрозе **T1 → SC01:2025**. Везде в Задании 3 используй эту классификацию:
- В уязвимом контракте комментарий у модификатора: `// VULNERABLE — OWASP SC01:2025 Access Control (SWC-115): authorization by tx.origin`.
- В исправленном контракте теги уже есть из Задания 2 (`// OWASP SC01:2025 — role check by msg.sender`) — не меняй файл, просто сошлись на них.
- Каждому тесту в `Exploit.t.sol`, `SecuritySuite`, `InvariantSuite` — комментарий `/// OWASP SC01:2025` (и `SC03:2025` для инвариантов автомата статусов).
- Последствия атаки тоже назвать в терминах OWASP: ложное `Executed` → нарушение бизнес-логики реестра (последствие уровня **SC03**), массовое ложное `Rejected` через тот же вектор → отказ в обслуживании платежей (последствие уровня **SC10**). Первопричина — SC01.
- В `SLITHER_TRIAGE.md` и `reports/COMPARISON.md` — колонка «OWASP SC Top 10 (2025)» для каждой находки/этапа.

## 2. Структура проекта

```
task3-vulnerability-analysis/
├── contracts/
│   ├── fixed/PaymentOrderRegistry.sol                 # побайтовая копия из ../task2-payment-registry/contracts/
│   ├── vulnerable/PaymentOrderRegistryVulnerable.sol  # один контролируемый дефект (tx.origin)
│   ├── interfaces/IPaymentOrderRegistryLike.sol       # общий ABI-совместимый интерфейс для тестов и атакующего
│   └── attack/SettlementRebatePhish.sol               # атакующий контракт
├── test/solidity/
│   ├── common/RegistryTestBase.sol        # abstract: акторы, setUp, виртуальный _deployRegistry()
│   ├── common/UnitSuite.sol               # abstract: функциональные + access-тесты (EOA-вызовы)
│   ├── common/SecuritySuite.sol           # abstract: fuzz-тесты на «посредника» и атакующий контракт
│   ├── common/InvariantSuite.sol          # abstract: инварианты
│   ├── common/RegistryHandler.sol         # handler для invariant-тестов (включая действие «фишинг»)
│   ├── before-fix/Unit_Vulnerable.t.sol
│   ├── before-fix/Security_Vulnerable.t.sol
│   ├── before-fix/Invariant_Vulnerable.t.sol
│   ├── after-fix/Unit_Fixed.t.sol
│   ├── after-fix/Security_Fixed.t.sol
│   ├── after-fix/Invariant_Fixed.t.sol
│   └── exploit/Exploit.t.sol              # PoC: атака успешна на vulnerable, ревертит на fixed
├── scripts/
│   ├── exploit-demo.ts        # живая демонстрация атаки транзакциями (локально)
│   ├── slither.mjs            # запуск Slither, сохранение txt/json/md
│   ├── expect-fail.mjs        # запуск этапа, который ДОЛЖЕН упасть (exit 0, если упал как ожидалось)
│   └── matrix.mjs             # полный прогон «до/после» + reports/COMPARISON.md
├── reports/ (slither/, logs/, COMPARISON.md, exploit-demo.md)
├── requirements.txt           # slither-analyzer, solc-select (точные версии)
├── hardhat.config.ts, package.json, package-lock.json, tsconfig.json
├── README.md, DEMO.md, REPORT_TASK3.md, SLITHER_TRIAGE.md
```

## 3. Контракты

### 3.1 Исправленная версия `contracts/fixed/PaymentOrderRegistry.sol`
Скопируй **без изменений** из `../task2-payment-registry/contracts/PaymentOrderRegistry.sol` и проверь идентичность (`git diff --no-index` или сравнение хешей) — запиши результат проверки в README. Если файла нет — остановись и сообщи мне.
Справка (спецификация Task 2): `AccessControl` + `Pausable` (OZ 5.x), роли `OPERATOR_ROLE`, `SETTLEMENT_ROLE`, `enum Status {None, Registered, Executed, Rejected, Cancelled}`, struct `PaymentOrder {docHash, amount(uint128), registeredAt, updatedAt, status, registeredBy, settledBy}`, функции `registerPayment`, `cancelPayment`, `markExecuted`, `markRejected(paymentId, reasonCode)`, `pause/unpause`, `getPayment`, `verifyDocument`, события `PaymentRegistered`, `PaymentStatusChanged`, ошибки `InvalidPaymentId, InvalidDocHash, InvalidAmount, InvalidReasonCode, PaymentAlreadyExists, PaymentNotFound, InvalidStatusTransition, NotPaymentInitiator, SelfSettlementForbidden, ZeroAddress`.

### 3.2 Уязвимая версия `contracts/vulnerable/PaymentOrderRegistryVulnerable.sol`
Контракт `PaymentOrderRegistryVulnerable` — копия fixed с **одним** контролируемым дефектом, всё остальное идентично (тот же ABI, события, ошибки, порядок проверок):
- Добавлен модификатор:
  ```solidity
  // VULNERABLE (PR3 Task 3, SWC-115): authorization by tx.origin instead of msg.sender
  modifier onlyRoleOrigin(bytes32 role) {
      if (!hasRole(role, tx.origin)) revert AccessControlUnauthorizedAccount(tx.origin, role);
      _;
  }
  ```
- В `registerPayment`, `cancelPayment`, `markExecuted`, `markRejected` вместо `onlyRole(...)` используется `onlyRoleOrigin(...)`, а «актор» везде (`registeredBy`, `settledBy`, проверки `NotPaymentInitiator` и `SelfSettlementForbidden`, поле `actor` в событиях) берётся из `tx.origin`.
- `pause/unpause`, `grantRole/revokeRole` — без изменений (OZ, `msg.sender`).
- В шапке NatSpec: «INTENTIONALLY VULNERABLE — for local educational experiment only, never deploy to a public network». Каждая изменённая строка помечена комментарием `// VULNERABLE`.
- Сделай `diff` между fixed и vulnerable и сохрани в `reports/vulnerable-vs-fixed.diff` — это доказательство «одного контролируемого дефекта».

### 3.3 Интерфейс `IPaymentOrderRegistryLike`
Собственные `enum Status` и `struct PaymentOrder` с тем же порядком полей (ABI-совместимо), все внешние функции, `hasRole`, константы ролей. Используется атакующим контрактом и абстрактными тестами, чтобы одни и те же тесты работали для обеих версий.

### 3.4 Атакующий контракт `contracts/attack/SettlementRebatePhish.sol`
```solidity
contract SettlementRebatePhish {
    IPaymentOrderRegistryLike public immutable registry;
    address public immutable attacker;
    bytes32 public target;
    event RebateClaimed(address indexed claimer);
    error NotAttacker();
    constructor(address registry_) { registry = IPaymentOrderRegistryLike(registry_); attacker = msg.sender; }
    function setTarget(bytes32 paymentId) external { if (msg.sender != attacker) revert NotAttacker(); target = paymentId; }
    /// @notice Выглядит как безобидный «возврат комиссии». Скрыто подтверждает исполнение чужого платежа.
    function claimRebate() external { registry.markExecuted(target); emit RebateClaimed(msg.sender); }
}
```

## 4. Тесты

Общие правила: `forge-std/Test.sol`; акторы через `makeAddr`: `admin`, `operator`, `operator2`, `settlementOfficer`, `stranger`, `attacker`. **Все «легитимные» вызовы делай как EOA: `vm.startPrank(actor, actor)` (msg.sender = tx.origin)** — тогда unit-тесты одинаково проходят на обеих версиях. Ошибки проверяй точными селекторами с аргументами. Каждый абстрактный suite наследуется дважды: в `before-fix/*_Vulnerable.t.sol` (деплой vulnerable) и `after-fix/*_Fixed.t.sol` (деплой fixed) — переопределяется только `_deployRegistry(address admin)`.

### 4.1 `UnitSuite` (≥ 12 тестов)
Регистрация и события; отказ без OPERATOR (EOA stranger); нулевые id/hash/amount; граничные amount (1 и `type(uint128).max`); дубликат и повтор после Cancelled; markExecuted/markRejected; отказ без SETTLEMENT (EOA); SelfSettlementForbidden; финальные статусы необратимы; отзыв только инициатором; pause блокирует записи; verifyDocument true/false.
**Ожидание: PASS на обеих версиях** — это важный вывод отчёта: обычные unit-тесты дефект `tx.origin` не обнаруживают.

### 4.2 `SecuritySuite` (fuzz + адресные тесты)
- `testFuzz_RegisterStoresExactData(bytes32,bytes32,uint128)` — PASS на обеих.
- `testFuzz_NonRoleEOACannotFinalize(address caller)` — `prank(caller, caller)`, PASS на обеих.
- `testFuzz_IntermediaryCannotActForSettlementOfficer(address intermediary)` — `vm.prank(intermediary, settlementOfficer)` (msg.sender = посредник, tx.origin = сотрудник), `vm.assume(intermediary` без роли, ≠ officer, ≠ 0`)`, ожидается revert и статус остаётся `Registered`. **Vulnerable: FAIL (фаззер находит контрпример), Fixed: PASS.**
- `test_PhishingContractCannotFinalize` — сотрудник вызывает `SettlementRebatePhish.claimRebate()` (`vm.prank(officer, officer)`), ожидается revert `AccessControlUnauthorizedAccount(address(phish), SETTLEMENT_ROLE)`. **Vulnerable: FAIL, Fixed: PASS.**

### 4.3 `InvariantSuite` + `RegistryHandler`
Handler с пулом из 10 paymentId и действиями: `register`, `cancel`, `execute`, `reject` (легитимные, от правильных EOA через `prank(x, x)`), `strangerAttack` (EOA без ролей) и **`phishSettlementOfficer(uint256 seed)`**: регистрирует свежий платёж от operator, атакующий выставляет target, затем `vm.prank(settlementOfficer, settlementOfficer); phish.claimRebate()` в `try/catch`. Ghost-модель: ожидаемый статус по каждому id меняется **только** легитимными действиями; любой успешный вызов через нелегитимный путь увеличивает `ghost_unauthorizedStateChanges`.
Инварианты:
- `invariant_NoStateChangeViaUnauthorizedPath` — `ghost_unauthorizedStateChanges == 0`;
- `invariant_StatusMatchesGhostModel` — статусы в контракте совпадают с ghost-моделью;
- `invariant_FinalStatusesImmutable`;
- `invariant_FourEyes` — для Executed/Rejected `settledBy != registeredBy`.
**Vulnerable: первые два FAIL (с выводом последовательности вызовов-контрпримера), Fixed: все PASS.**

### 4.4 `exploit/Exploit.t.sol` — Proof of Concept (все тесты PASS — они доказывают факт атаки и факт защиты)
- `test_PoC_Vulnerable_PhishingMarksPaymentExecuted` — шаги с комментариями: (1) operator регистрирует платёж; (2) attacker деплоит phish и выставляет target; (3) officer вызывает `claimRebate()`; проверки: статус `Executed`, `settledBy == settlementOfficer` (атака приписана жертве), событие `PaymentStatusChanged` с `actor == settlementOfficer`, при этом officer **не вызывал** реестр напрямую.
- `test_PoC_Vulnerable_Precondition_AttackerAloneFails` — без участия жертвы атакующий (EOA без роли) не может вызвать `markExecuted` ни напрямую, ни через свой контракт → показывает необходимое условие эксплуатации.
- `test_PoC_Fixed_PhishingReverts` — та же последовательность на fixed: точный revert `AccessControlUnauthorizedAccount(address(phish), SETTLEMENT_ROLE)`, статус остаётся `Registered`.
- `test_PoC_Fixed_LegitimateSettlementStillWorks` — исправление не ломает бизнес-процесс: officer напрямую исполняет платёж.

### 4.5 Конфигурация
`test.solidity`: `fuzz.runs = 256`, `invariant.runs = 64`, `invariant.depth = 32`, `failOnRevert = false`; фиксированный seed, если поддерживается. Проверь, что `vm.prank(sender, origin)` / `vm.startPrank(sender, origin)` работают в Hardhat 3 — если нет, найди поддерживаемый способ задать `tx.origin` в документации. Если фаззер не находит контрпример на vulnerable — это ошибка теста/handler'а: исправь, а не ослабляй ожидание.

## 5. Slither

- Python venv в `task3-vulnerability-analysis/.venv`, `requirements.txt` с точными версиями `slither-analyzer`, `solc-select` (и `crytic-compile` ≥ 0.4.0). `solc-select install 0.8.28 && solc-select use 0.8.28`.
- `scripts/slither.mjs <vulnerable|fixed>` (кроссплатформенно: сам находит `.venv/bin/slither` или `.venv\Scripts\slither.exe`) запускает Slither **по отдельному файлу** с ремаппингом OpenZeppelin, например:
  `slither contracts/vulnerable/PaymentOrderRegistryVulnerable.sol --solc-remaps "@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/" --exclude-dependencies --json reports/slither/vulnerable.json`
  Сохраняет: полный человекочитаемый вывод → `reports/slither/<name>.txt`, JSON → `.json` (удалить старый перед запуском), отдельным запуском с `--checklist` → `.md`. Ненулевой exit code Slither при наличии находок не считать ошибкой скрипта; ошибкой считать только сбой компиляции.
- Дополнительно попробуй режим проекта (`slither . --filter-paths "node_modules|test|attack"`); если он работает с Hardhat 3 — сохрани `reports/slither/project.txt`, если нет — запиши причину в README и используй пофайловый режим (он основной для демонстрации).
- **Ожидаемо:** на vulnerable есть детектор `tx-origin`; на fixed его нет. Если ожидание не выполняется — разберись, почему.
- `SLITHER_TRIAGE.md`: таблица по **реальному** выводу (ничего не выдумывать): № | Детектор | Impact/Confidence | Контракт и строка | OWASP SC Top 10 (2025) (или «—» для информационных стилевых замечаний) | Классификация (Реальная уязвимость / Ложное срабатывание / Информационное) | Обоснование | Мера исправления. `tx-origin` → SC01:2025. Дополнительно — таблица «детекторы Slither, относящиеся к SC05/SC06/SC08/SC10 (reentrancy-*, unchecked-*, low-level-calls, calls-loop, costly-loop и т.п.) → 0 находок до и после». Отдельная таблица «до/после» по количеству находок каждого уровня. Отдельный абзац: какие проблемы Slither **не** находит в принципе (ошибки бизнес-логики автомата статусов, «4 глаза», компрометация admin-ключа, корректность off-chain хеша) и почему отсутствие High-находок ≠ безопасность.

## 6. Живая демонстрация атаки `scripts/exploit-demo.ts`

Запуск: `npx hardhat run scripts/exploit-demo.ts` (in-process сеть, ничего поднимать не нужно) и `--network localhost` (при запущенном `npx hardhat node`, чтобы показать транзакции в логах ноды). Аккаунты: [0] admin, [1] operator, [2] settlementOfficer, [3] attacker.
Сценарий выполнить **дважды** — для `PaymentOrderRegistryVulnerable` и `PaymentOrderRegistry` (fixed), с понятным русским выводом по шагам:
1. Развёртывание реестра, выдача ролей (tx hash).
2. Operator регистрирует платёж (tx hash) → статус `Registered`.
3. Attacker деплоит `SettlementRebatePhish` и выставляет target (tx hash).
4. Officer вызывает `claimRebate()` (tx hash или перехваченная ошибка).
5. Итог: статус платежа, `settledBy`, событие; для fixed — расшифрованное имя ошибки и аргументы (`AccessControlUnauthorizedAccount(account=<phish>, neededRole=SETTLEMENT_ROLE)`).
6. Финальная строка: `VULNERABLE: ATTACK SUCCEEDED — payment falsely marked Executed` / `FIXED: ATTACK BLOCKED — status remains Registered`.
Результат также записать в `reports/exploit-demo.md` (условия, последовательность транзакций с хешами, результат для обеих версий).

## 7. Автоматическое сравнение «до/после» `scripts/matrix.mjs` (`npm run matrix`)

Последовательно выполняет этапы, сохраняет полный вывод каждого в `reports/logs/<stage>.log`, сравнивает фактический результат с ожидаемым:

| Этап | Команда | Ожидание |
|---|---|---|
| compile | hardhat compile | OK |
| unit-before | test solidity before-fix/Unit_Vulnerable.t.sol | PASS |
| unit-after | test solidity after-fix/Unit_Fixed.t.sol | PASS |
| security-before | test solidity before-fix/Security_Vulnerable.t.sol | FAIL (ожидаемо) |
| security-after | test solidity after-fix/Security_Fixed.t.sol | PASS |
| invariant-before | test solidity before-fix/Invariant_Vulnerable.t.sol | FAIL (ожидаемо) |
| invariant-after | test solidity after-fix/Invariant_Fixed.t.sol | PASS |
| exploit-poc | test solidity exploit/Exploit.t.sol | PASS |
| slither-before | scripts/slither.mjs vulnerable | есть `tx-origin` |
| slither-after | scripts/slither.mjs fixed | нет `tx-origin` |

Для тестовых этапов парсить количество passing/failing и имена упавших тестов (при неудаче парсинга — использовать exit code). Сгенерировать `reports/COMPARISON.md` (таблица: этап, OWASP категория, команда, ожидание, факт, passed/failed, ✅/❌ соответствия) и вывести её в консоль. Exit code 0 только если **все** этапы совпали с ожиданием. Все процессы через `child_process.spawn` с `shell: true` (Windows-совместимо).

## 8. npm-скрипты

```
compile              hardhat compile
test                 только «зелёные» наборы: after-fix + exploit + unit-before (не запускать before-fix security/invariant)
test:exploit         hardhat test solidity test/solidity/exploit/Exploit.t.sol
test:before:unit     hardhat test solidity test/solidity/before-fix/Unit_Vulnerable.t.sol
test:before:security node scripts/expect-fail.mjs <команда для Security_Vulnerable + Invariant_Vulnerable>
test:after           hardhat test solidity <все файлы after-fix>
slither:before       node scripts/slither.mjs vulnerable
slither:after        node scripts/slither.mjs fixed
exploit:demo         hardhat run scripts/exploit-demo.ts
exploit:demo:local   hardhat run scripts/exploit-demo.ts --network localhost
node                 hardhat node
matrix               node scripts/matrix.mjs
setup:python         кроссплатформенная установка venv + requirements + solc-select (node-скрипт)
```
Важно: в README и DEMO.md явно предупреди, что голый `npx hardhat test` запускает и before-fix наборы, которые **специально** падают — для демонстрации использовать npm-скрипты. `expect-fail.mjs` печатает баннер `EXPECTED FAILURE CONFIRMED: <имена упавших тестов>` и возвращает 0, если команда упала, и возвращает 1 с баннером `UNEXPECTED PASS`, если не упала.

## 9. Документы

- **README.md**: цель, структура, версии (Node, Hardhat, toolbox, viem, OZ, solc, forge-std, Python, Slither, crytic-compile), установка (`npm ci`, `npm run setup:python`), все команды, результат проверки идентичности fixed ↔ task2.
- **DEMO.md** — сценарий показа (~5–7 минут), для каждого шага: команда → что показать → ожидаемый результат → что сказать (1–2 предложения):
  0. Заранее с интернетом: `npm ci`, `npm run setup:python`, `npm run compile`, `npm run matrix`.
  1. Открыть `reports/vulnerable-vs-fixed.diff` — один дефект.
  2. `npm run slither:before` → находка `tx-origin`; открыть `SLITHER_TRIAGE.md` — это OWASP SC01:2025 (угроза T1 на архитектурной схеме).
  3. `npm run test:before:unit` → зелёные (unit-тесты дефект не видят).
  4. `npm run test:exploit` → PoC.
  5. `npm run exploit:demo` (или `:local` с нодой) → атака успешна / заблокирована.
  6. `npm run test:before:security` → ожидаемые падения fuzz/invariant с контрпримером.
  7. `npm run test:after` и `npm run slither:after` → всё зелёное, `tx-origin` исчез.
  8. `npm run matrix` → итоговая таблица до/после.
  9. «Если что-то пошло не так» (Python/solc-select не найден, порт 8545 занят и т.п.).
- **REPORT_TASK3.md** (на русском, только реальные результаты из `reports/`):
  1. Выбранная уязвимость, её классификация (**OWASP SC01:2025 Access Control**, SWC-115, CWE-284), связь с угрозой T1 из архитектуры и релевантность варианту.
  2. Первопричина: авторизация по `tx.origin` проверяет инициатора всей транзакции, а не непосредственного вызывающего; любой контракт в цепочке вызовов действует с полномочиями жертвы.
  3. Нарушенное правило безопасности: аутентификация/авторизация — только по `msg.sender` (SWC-115, рекомендации Solidity docs), принцип полного посредничества и наименьших привилегий.
  4. Условия эксплуатации: (a) авторизация через `tx.origin`; (b) жертва — держатель `SETTLEMENT_ROLE` — подписывает транзакцию к контракту злоумышленника (фишинговый dApp, «возврат комиссии», вредоносная зависимость/интеграция); (c) целевой платёж в статусе `Registered` и зарегистрирован другим адресом; (d) контракт не на паузе. Упомяни EIP-7702: проверки вида `tx.origin == msg.sender` больше не гарантируют, что вызывающий — «чистый» EOA.
  5. Последовательность транзакций и результат (из `reports/exploit-demo.md` и PoC-теста).
  6. Slither: краткая таблица + ссылка на полный отчёт и `SLITHER_TRIAGE.md`.
  7. Исправление: OZ `AccessControl.onlyRole` (по `_msgSender()`), актор = `msg.sender`; почему это устраняет **причину**, а не один сценарий: (a) в коде не осталось ни одного использования `tx.origin` (`grep`), (b) fuzz-тест с произвольным посредником, (c) инвариант «нет изменений состояния по нелегитимному пути» на произвольных последовательностях, (d) Slither без `tx-origin`, (e) легитимный бизнес-процесс не сломан.
  8. Таблица сравнения до/после из `reports/COMPARISON.md`.
  9. Остающиеся риски, требующие ручного аудита: компрометация admin-ключа (нужны multisig + timelock), злоупотребления легитимного держателя роли, гонка `cancelPayment`/`markExecuted` (порядок транзакций), корректность и целостность off-chain хешей и хранилища, сговор операторов (обход «4 глаз» двумя адресами), отсутствие верхнего лимита суммы, фишинг самой подписи сотрудника (социальная инженерия), ограничения fuzz/invariant (покрывают только смоделированные действия).
  10. **Покрытие OWASP Smart Contract Top 10 (2025)** — таблица по всем 10 категориям: применимость к контракту → чем проверено автоматически (тест / Slither, результат до и после) → что остаётся на ручной аудит. Ожидаемо: SC01 — найдено и исправлено; SC03 — частично покрыто инвариантами, остальное ручной аудит (Slither логику не видит); SC04, SC08 — покрыто тестами; SC05, SC06 — Slither 0 находок + архитектура без внешних вызовов; SC10 — нет циклов, `pause` только admin; SC02, SC07, SC09 — не применимы (обоснование).
  11. Вывод: какие меры реально снижают риск, а какие требуют дополнительного аудита (с указанием категорий OWASP).
  12. Краткие ответы на 5 контрольных вопросов практической работы (где уместно — со ссылкой на категории OWASP 2025) (компрометация admin-ключа; почему ReentrancyGuard недостаточен без CEI; формулировка инварианта для invariant testing и отличие от функционального требования; ограничения Slither; как доказать устранение причины, а не одного сценария).

## 10. Чего НЕ делать
- Не менять task2 и не трогать его файлы.
- Не вносить в vulnerable больше одного дефекта и не менять в fixed ничего относительно task2.
- Не ослаблять тесты, чтобы они «совпали с ожиданием», и не использовать `skip`.
- Не разворачивать уязвимую версию в публичных сетях, не запрашивать приватные ключи.
- Не выдумывать результаты Slither или тестов в отчётах — только из реальных логов.

## 11. Чек-лист приёмки (выполни и приложи вывод)
- [ ] `npm ci` с нуля и `npm run setup:python` проходят; `npm run compile` без ошибок.
- [ ] `fixed/PaymentOrderRegistry.sol` идентичен файлу task2 (проверка записана в README); `reports/vulnerable-vs-fixed.diff` показывает только изменения, связанные с `tx.origin`.
- [ ] `npm run test:exploit` — 4 passing.
- [ ] `npm run test:before:unit` и `npm run test:after` — 0 failing.
- [ ] `npm run test:before:security` — exit 0 с баннером `EXPECTED FAILURE CONFIRMED` и именами упавших тестов (fuzz-посредник, фишинг-тест, 2 инварианта).
- [ ] `npm run slither:before` — `tx-origin` найден; `npm run slither:after` — `tx-origin` отсутствует; отчёты txt/json/md сохранены.
- [ ] `npm run exploit:demo` — для vulnerable «ATTACK SUCCEEDED», для fixed «ATTACK BLOCKED»; то же с `--network localhost` при запущенной ноде.
- [ ] `npm run matrix` — все этапы ✅, exit 0, создан `reports/COMPARISON.md`.
- [ ] `npm test` — зелёный.
- [ ] Классификация OWASP SC01:2025 присутствует в контракте, тестах, `SLITHER_TRIAGE.md`, `COMPARISON.md` и `REPORT_TASK3.md`; в отчёте есть таблица по всем 10 категориям OWASP 2025.
- [ ] В репозитории нет секретов и `.env`; `.venv`, `node_modules`, `artifacts`, `cache`, `crytic-export` в `.gitignore`.

В финальном сообщении: дерево проекта, таблица из `COMPARISON.md`, краткая таблица Slither до/после и точная последовательность команд для демонстрации.
