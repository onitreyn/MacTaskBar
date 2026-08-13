#!/bin/zsh
# Собирает universal release-сборку (arm64 + x86_64) и упаковывает в zip
# для распространения среди обычных пользователей.
#
# Результат: dist/TaskbarApp-<version>.zip — внутри TaskbarApp.app,
# который можно перетащить в /Applications.
set -e

cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)

echo "==> swift build -c release --arch arm64 --arch x86_64"
swift build -c release --arch arm64 --arch x86_64

BIN_PATH=".build/apple/Products/Release/TaskbarApp"
APP_DIR="dist/TaskbarApp.app"

rm -rf dist
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/TaskbarApp"
cp "Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

# Локализации: Localizable.strings + InfoPlist.strings для каждого языка.
for lproj in Resources/*.lproj; do
    if [ -d "$lproj" ]; then
        cp -R "$lproj" "$APP_DIR/Contents/Resources/"
    fi
done

SIGN_IDENTITY="TaskbarApp Local Dev"
if security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
    echo "==> codesign ($SIGN_IDENTITY)"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    echo "!! Сертификат '$SIGN_IDENTITY' не найден — ad-hoc подпись (fallback)."
    codesign --force --deep --sign - "$APP_DIR"
fi

ZIP="dist/TaskbarApp-${VERSION}.zip"
echo "==> Упаковка: $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"
rm -rf "$APP_DIR"

echo ""
echo "Готово: $ZIP"
echo "Размер: $(du -h "$ZIP" | cut -f1)"
