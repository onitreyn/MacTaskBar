#!/bin/zsh
# Устанавливает независимого сторожа Dock как launchd LaunchAgent.
# После установки сторож работает ВСЕГДА, пока вы залогинены в систему —
# независимо от того, запущен TaskbarApp или нет, жив он или упал.
#
# ВАЖНО: launchd ненадёжно работает с не-ASCII путями в ProgramArguments
# (проверено на практике — путь с кириллицей "ИИ" ломал запуск скрипта).
# Поэтому актуальная копия скрипта хранится в ASCII-пути ~/.taskbarapp/
# и обновляется при каждом запуске install_watchdog.sh. Источник истины
# для редактирования — файл в репозитории (scripts/dock_watchdog.sh),
# просто не запускается напрямую оттуда.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/dock_watchdog.sh"
PLIST_TEMPLATE="$SCRIPT_DIR/com.local.taskbarapp.dockwatchdog.plist"
PLIST_TARGET="$HOME/Library/LaunchAgents/com.local.taskbarapp.dockwatchdog.plist"

INSTALL_DIR="$HOME/.taskbarapp"
WATCHDOG_SCRIPT="$INSTALL_DIR/dock_watchdog.sh"

mkdir -p "$INSTALL_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cp "$SOURCE_SCRIPT" "$WATCHDOG_SCRIPT"
chmod +x "$WATCHDOG_SCRIPT"

sed "s|__SCRIPT_PATH__|$WATCHDOG_SCRIPT|" "$PLIST_TEMPLATE" > "$PLIST_TARGET"

launchctl unload "$PLIST_TARGET" 2>/dev/null || true
launchctl load "$PLIST_TARGET"

echo "Watchdog установлен и запущен: $PLIST_TARGET"
echo "Проверить статус: launchctl list | grep taskbarapp"
echo "Удалить:          scripts/uninstall_watchdog.sh"
