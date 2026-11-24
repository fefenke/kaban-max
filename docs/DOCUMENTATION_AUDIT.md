# Аудит инженерной документации — 2026-11-23

## Объём и исходное состояние

Работа выполнена одним ассистентом без агентов, с `resource budgeting`. Продуктовый diff авторутинга r23/r24 оставлен в рабочем дереве. Изменены документация, её проверка/CI/PR-template и исключение архива из сайта; runtime-код не исправлялся попутно.

Найдены противоречивые точки входа: старый навигатор начинал с 0.2.0/r14, handoff — с 0.1.7/r12; архитектура и security смешивали manual-only/64-record этапы с последующими контрактами. PROJECT_STATE и TESTING разрослись в хронологию, что заставляло перечитывать прошлые задачи. Часть старых вставок содержала повреждённый текст.

Решение: актуальные короткие entrypoints, раздельные роли документов, машинная карта путей, source-derived facts и история отдельно. 17 прежних файлов (350125 bytes) сохранены побайтно с SHA256; [manifest](archive/context-2026-11-23/manifest.json). Приватный `.local/` не переносился в документацию.

## Использованные первичные рекомендации

- [Diátaxis](https://diataxis.fr/) — разделение справки, объяснений, практических инструкций и обучения. Пользовательский сайт отделён от инженерного контекста.
- [ADR](https://adr.github.io/) — причина, последствия и условия пересмотра значимого решения. Текущий реестр использует устойчивые ID вместо повторяющихся исторических D13.
- [maintainer AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) — проектные инструкции; сюда внесены один ассистент, экономный контекст и обязанность обновления документов.
- [GitHub PR templates](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/creating-a-pull-request-template-for-your-repository) — checklist сопровождает изменение; формальная часть проверяется отдельным read-only workflow.

Рекомендации адаптированы к существующему проекту, не скопированы как универсальная архитектура. Не создавался новый глобальный skill и не менялись настройки аккаунта/плагинов.

## Проверки этой задачи

Свежая локальная приёмка 2026-11-23:

```sh
python -m unittest discover -s tests/docs -p 'test_*.py'
python scripts/check-project-docs.py --write-facts
python scripts/check-project-docs.py
python scripts/check-project-docs.py --no-diff
git diff --check
```

Результат: **9/9 unit tests**, **22 поддерживаемых документа**, source facts/пути/UTF-8/startup budgets/change coverage — PASS (83 changed paths, включая прежний продуктовый diff). Режим `--no-diff` также PASS. SHA256/размеры всех **17 архивных снимков** проверены gate и совпали. `git diff --check` — PASS.

Из `docs` выполнено `npm.cmd run build`: VitePress **1.6.4**, build PASS. Зависимости для этой проверки установлены локально по frozen `yarn.lock` через `npm.cmd exec --yes --cache ../.local/docs-npm-cache --package=yarn@1.22.22 -- yarn install --frozen-lockfile --ignore-scripts --non-interactive --cache-folder ../.local/docs-yarn-cache`. Yarn сообщил peer dependency warnings; lockfiles не изменялись, глобальная установка не выполнялась. YAML нового workflow разобран существующим `js-yaml` из frontend dependencies: syntax PASS. GitHub runner не запускался локально.

Размер обязательного стартового контекста AGENTS + PROJECT_STATE + DEVELOPMENT_INDEX — **13475 bytes** на этой проверке; подробности вынесены по ссылкам. AI_HANDOFF — отдельный короткий указатель. Gate ограничивает дальнейшее разрастание entrypoints.

Это проверки документации, а не повторный запуск frontend/backend/core runtime suites. Их прежние результаты остаются в [storage report](AUTO_ROUTING_STORAGE.md).

## Пределы

- Gate проверяет локальные пути ссылок, UTF-8, SHA256 архива, бюджеты стартовых документов, generated facts и наличие doc update по компоненту. Он не понимает семантику произвольного изменения и не доказывает точность каждого предложения или anchor ссылки.
- CI-файл подготовлен локально. Он начнёт выполняться после принятия изменений в GitHub; required status/branch protection не настраивались.
- Нет фонового наблюдателя, который сочиняет документацию после каждой записи файла. Рабочая инструкция требует обновление в той же задаче, локальная проверка контролирует changeset, CI проверяет PR/push.
- Сведения о 0.2.2 — из локальных Git/README; состояние live GitHub release и устройств в этой задаче не проверялось.
- Нельзя обещать, что произвольный другой чат прочтёт папку. Для клиента с доступом используются AGENTS/entrypoints; без доступа нужен handoff.
- Проверена структура и опорные пути/инварианты; полного нового аудита всех алгоритмов проекта не проводилось. Следующий чат проверяет изменяемые символы и изучает компонент глубже при противоречии.
