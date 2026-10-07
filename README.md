# ПР №3 — разработка и безопасность смарт-контрактов (вариант 1 «Банки и финтех»)

Сценарий: проверка статуса межбанковского платёжного поручения (ID операции, сумма, статус, hash документа).

| Папка | Содержание |
|---|---|
| [docs/](docs/) | Задание 1 — архитектурная схема (draw.io) |
| [task2-payment-registry/](task2-payment-registry/) | Задание 2 — контракт `PaymentOrderRegistry` (Hardhat 3), unit / fuzz / invariant / integration тесты, развёртывание local → Sepolia. См. `README.md`, `DEMO.md`, `REPORT_TASK2.md` |
| [task3-vulnerability-analysis/](task3-vulnerability-analysis/) | Задание 3 — отдельный проект: уязвимая версия (`tx.origin`, OWASP SC01:2025), Slither, проверка исправления «до/после». См. `README.md`, `DEMO.md`, `REPORT_TASK3.md`, `SLITHER_TRIAGE.md` |

Требования: Node.js ≥ 22.10, npm, Python ≥ 3.10 (только для Slither в Задании 3).

Быстрый старт:

```
cd task2-payment-registry && npm ci && npm test
cd ../task3-vulnerability-analysis && npm ci && npm run setup:python && npm run verify:fix
```

Секреты (RPC URL, приватные ключи) в репозитории не хранятся: только зашифрованный Hardhat keystore.
