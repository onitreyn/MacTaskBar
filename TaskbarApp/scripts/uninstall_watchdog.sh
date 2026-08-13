#!/bin/zsh
# Удаляет launchd-сторожа Dock. Перед удалением на всякий случай
# гарантированно восстанавливает Dock, если он был скрыт.
set -e

PLIST_TARGET="$HOME/Library/LaunchAgents/com.local.taskbarapp.dockwatchdog.plist"
MARKER_FILE="$HOME/Library/Application Support/TaskbarApp/dock_hidden_by_us"

if [[ -f "$MARKER_FILE" ]]; then
    /usr/bin/defaults delete com.apple.dock autohide-delay 2>/dev/null || true
    /usr/bin/defaults write com.apple.dock autohide -bool false
    /usr/bin/killall Dock 2>/dev/null || true
    rm -f "$MARKER_FILE"
    echo "Dock восстановлен перед удалением сторожа."
fi

launchctl unload "$PLIST_TARGET" 2>/dev/null || true
rm -f "$PLIST_TARGET"

echo "Watchdog удалён."
