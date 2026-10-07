# DEMO — сценарий показа Задания 2 (~7 минут)

Все команды выполняются из папки `task2-payment-registry/`.

## 0. Заранее (дома, с интернетом)

```
npm ci
npm run compile      # скачивает solc 0.8.28 в кэш Hardhat
npm test             # ожидание: 32 passing
```

Развёртывание в Sepolia тоже делается заранее (`npm run deploy:sepolia`, `npm run interact:sepolia`).

## 1. Компиляция

- **Команда:** `npm run compile`
- **Ожидаемо:** `Compiled ... with solc 0.8.28` или `No contracts to compile`, без предупреждений.
- **Показать:** `contracts/PaymentOrderRegistry.sol` — роли, `onlyRole`, custom errors, теги OWASP.

## 2. Unit-тесты

- **Команда:** `npm run test:unit`
- **Ожидаемо:** 21 passing.
- **Сказать:** «Проверяются корректные сценарии, ошибки доступа, некорректный ввод, повторные операции, граничные суммы (1 и `uint128.max`), пауза и необратимость финальных статусов».

## 3. Fuzz-тесты

- **Команда:** `npm run test:fuzz`
- **Ожидаемо:** 3 passing, `(runs: 256)` у каждого.

## 4. Invariant-тесты

- **Команда:** `npm run test:invariant`
- **Ожидаемо:** 5 passing, `(runs: 64)` у каждого.
- **Сказать:** «Handler случайно вызывает регистрацию, отзыв, исполнение, отклонение и атаки постороннего адреса на пуле из 10 `paymentId`. Пять инвариантов из архитектуры не нарушаются ни на одной последовательности».

## 5. Интеграционные тесты (TypeScript + viem)

- **Команда:** `npm run test:integration`
- **Ожидаемо:** 3 passing. Проверяются полный поток с событиями, ошибка `SelfSettlementForbidden` и хеш реального XML-документа.

## 6. Локальная сеть

- **Терминал 1:** `npm run node` — нода на `127.0.0.1:8545`.
- **Терминал 2:**
  ```
  npm run deploy:local
  npm run interact:local
  ```
- **Ожидаемо:** адрес контракта и deploy tx; затем транзакции шагов 3a/3b (выдача ролей), 6a/6b (регистрация → исполнение), 7a/7b (регистрация → отклонение с кодом AC04); `verifyDocument` = true/false; два отказа доступа `AccessControlUnauthorizedAccount`; строка `INTERACTION SCENARIO COMPLETED SUCCESSFULLY`.
- **Показать:** в терминале 1 транзакции появляются в логах ноды. При повторном `npm run interact:local` выдача ролей пропускается, ошибок нет.

## 7. Sepolia

- **Показать:** `deployments/sepolia.json`, ссылки на Etherscan (адрес контракта, deploy tx, interaction tx).

## 8. Если что-то пошло не так

| Проблема | Решение |
|---|---|
| Порт 8545 занят | Закрыть старую ноду (Ctrl+C) или найти процесс: `Get-NetTCPConnection -LocalPort 8545` → `Stop-Process -Id <PID>` |
| `No contract at ... (node restarted?)` или нет `deployments/localhost.json` | После перезапуска ноды заново выполнить `npm run deploy:local` |
| `INTERACT FAILED: File deployments/... not found` | Сначала `npm run deploy:...` |
| Не хватает Sepolia ETH | Пополнить адрес admin через faucet; оператор и расчётный центр пополняются скриптом автоматически |
| Забыт пароль keystore | Удалить keystore (путь: `npx hardhat keystore path`) и заново выполнить `npx hardhat keystore set ...` для всех переменных |
| Ошибки после переноса папки | Удалить `artifacts`, `cache`, выполнить `npm run compile` |
| `npm ci` падает с EPERM (OneDrive) | Приостановить синхронизацию OneDrive на время установки |
