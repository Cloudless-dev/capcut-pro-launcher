# macOS

[Скачать](https://github.com/Cloudless-dev/capcut-pro-launcher/releases/tag/macos-v0.054) — Apple Silicon, macOS 14+.

## Первый запуск

1. Перенесите приложение из DMG в «Программы».
2. Если запуск заблокирован, попробуйте открыть приложение, затем нажмите «Всё равно открыть» в «Системные настройки → Конфиденциальность и безопасность».
3. Включите «Управление приложениями → CapCut Launcher» в том же разделе настроек. Если лаунчера нет в списке, добавьте его кнопкой «+».
4. Добавьте профиль в лаунчере и запустите CapCut.

Иллюстрированная инструкция — `Installation.pdf` в DMG.

## Исходники

- `Sources/` — интерфейс и логика.
- `Browser/` — вход в аккаунт.
- `Runtime/` — интеграция с CapCut.
- `packaging/` — сборка приложения и DMG.

## Сборка

Из корня репозитория, на Apple Silicon с Command Line Tools и Python 3.14:

```sh
python3.14 -m venv .venv
.venv/bin/python -m pip install -r macos/requirements-build.txt
.venv/bin/python macos/scripts/fetch_dependencies.py
.venv/bin/python macos/packaging/build.py --dmg
```

Результат — в `releases/`. Для релизной сборки используются переменные `CODE_SIGN_IDENTITY`, `UPDATE_FEED_URL` и при необходимости `SPARKLE_PUBLIC_KEY`. Канал Mac: `macos/appcast.xml`.
