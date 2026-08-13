#!/bin/zsh
# Независимый сторож системного Dock. Запускается launchd-агентом каждые
# 15 секунд И при каждом входе в систему — полностью независимо от того,
# жив ли процесс TaskbarApp.
#
# Инвариант: если marker-файл существует ("мы скрыли Dock"), а TaskbarApp
# не запущен — Dock должен быть восстановлен. Это гарантия того, что Dock
# не может потеряться навсегда, даже если TaskbarApp был убит жёстко
# (kill -9, краш, обрыв сессии, сбой) и никогда больше не запустится.
set -e

MARKER_FILE="$HOME/Library/Application Support/TaskbarApp/dock_hidden_by_us"
TASKBAR_PROC_NAME="TaskbarApp"

is_taskbar_running() {
    pgrep -x "$TASKBAR_PROC_NAME" > /dev/null 2>&1
}

if [[ -f "$MARKER_FILE" ]] && ! is_taskbar_running; then
    /usr/bin/defaults delete com.apple.dock autohide-delay 2>/dev/null || true
    /usr/bin/defaults write com.apple.dock autohide -bool false
    /usr/bin/killall Dock 2>/dev/null || true
    rm -f "$MARKER_FILE"
    logger "TaskbarApp dock_watchdog: restored Dock (TaskbarApp was not running)"
fi
