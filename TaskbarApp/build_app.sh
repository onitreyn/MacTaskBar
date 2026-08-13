#!/bin/zsh
# Собирает Swift Package и упаковывает результат в TaskbarApp.app,
# чтобы Info.plist (NSAccessibilityUsageDescription) подхватился системой
# при первом запросе Accessibility-доступа.
set -e

cd "$(dirname "$0")"

CONFIG="${1:-debug}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/TaskbarApp"
APP_DIR="build/TaskbarApp.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/TaskbarApp"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

SIGN_IDENTITY="TaskbarApp Local Dev"

echo "==> codesign ($SIGN_IDENTITY)"
# ВАЖНО: не используем ad-hoc (--sign -). Ad-hoc подпись не имеет стабильного
# CDHash/identity — Swift debug-сборки встраивают build UUID, который меняется
# при КАЖДОЙ компиляции даже без изменений кода. Из-за этого macOS TCC считает
# каждую пересборку новым приложением и сбрасывает разрешение Accessibility
# (диагностировано эмпирически: AXIsProcessTrusted()==false после пересборки,
# хотя toggle в System Settings оставался включённым для старого бинарника).
# Собственный self-signed сертификат даёт стабильный Subject/Team, к которому
# TCC привязывает разрешение независимо от смены хеша бинарника между сборками.
# Сертификат создаётся один раз через scripts/create_dev_cert.sh (см. README).
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "!! Сертификат '$SIGN_IDENTITY' не найден в Keychain — используем ad-hoc (fallback)."
    echo "!! Разрешение Accessibility будет сбрасываться при каждой пересборке."
    echo "!! Запустите scripts/create_dev_cert.sh один раз, чтобы это исправить."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "==> Собрано: $APP_DIR"
echo "Запуск: open \"$APP_DIR\""
