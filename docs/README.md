# Документация K.A.B.A.N.-MAX

## Для нового чата или разработчика

Начать с [AGENTS](../AGENTS.md), [PROJECT_STATE](PROJECT_STATE.md) и [DEVELOPMENT_INDEX](DEVELOPMENT_INDEX.md). Далее читать только тему задачи. [AI_HANDOFF](AI_HANDOFF.md) — короткий постоянный указатель для переноса контекста.

| Нужно | Документ |
| --- | --- |
| Текущие версии, незакоммиченные изменения, доказательства | [PROJECT_STATE](PROJECT_STATE.md) |
| Устройство и ответственность модулей | [ARCHITECTURE](ARCHITECTURE.md), [COMPONENTS](COMPONENTS.md), [NETWORKING](NETWORKING.md) |
| Правила одного ассистента, экономия и обновление документов | [WORKFLOW](WORKFLOW.md) |
| Причины и ограничения | [DECISIONS](DECISIONS.md), [KNOWN_ISSUES](KNOWN_ISSUES.md), [PITFALLS](PITFALLS.md) |
| Проверки, сборка, безопасность | [TESTING](TESTING.md), [BUILD_AND_DEPLOY](BUILD_AND_DEPLOY.md), [SECURITY](SECURITY.md) |
| История и качество документации | [архив](archive/README.md), [журнал контекста](CHANGELOG.md), [аудит](DOCUMENTATION_AUDIT.md) |

## Для пользователя приложения

[Главная](index.md), [установка](guide/install.md), [быстрый старт](guide/quick-start.md), [настройки](settings.md). Сайт собирается VitePress; пользовательские страницы отделены от инженерного контекста и архива. Локальная feature-документация не подтверждает выпуск пакетов.

Инженерные документы и архив не входят в VitePress pages (`srcExclude`). Весь проект остаётся в этой папке; `.local/` не является публичной документацией или источником сборки.
