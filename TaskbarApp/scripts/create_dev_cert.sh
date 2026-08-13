#!/bin/zsh
# Создаёт локальный self-signed сертификат для стабильной подписи TaskbarApp.
#
# ЗАЧЕМ: ad-hoc подпись (codesign --sign -) не имеет постоянного identity.
# Swift debug-сборки встраивают build UUID, который меняется при КАЖДОЙ
# компиляции даже без изменений кода — из-за этого CDHash бинарника меняется
# каждый раз, и macOS TCC считает пересобранное приложение НОВЫМ, сбрасывая
# разрешение Accessibility, выданное для предыдущей сборки (диагностировано
# эмпирически 08.08: AXIsProcessTrusted()==false после пересборки, хотя
# toggle в System Settings оставался включён для старого бинарника).
#
# Self-signed сертификат с фиксированным Subject даёт TCC стабильный якорь:
# разрешение привязывается к identity подписи, а не к хешу конкретного файла,
# и переживает пересборки.
#
# Запускается ОДИН РАЗ на машине разработчика. Безопасно перезапускать —
# security import идемпотентен для одного и того же сертификата.
#
# По ходу выполнения появятся 1-2 системных диалога подтверждения (пароль/
# Touch ID) — это штатно, macOS всегда спрашивает подтверждение при
# добавлении доверенного code-signing сертификата в Keychain.
set -e

IDENTITY_NAME="TaskbarApp Local Dev"
WORKDIR=$(mktemp -d)
trap "rm -rf $WORKDIR" EXIT

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "==> Сертификат '$IDENTITY_NAME' уже существует в Keychain, пропускаем создание."
    security find-identity -v -p codesigning | grep "$IDENTITY_NAME"
    exit 0
fi

echo "==> Генерация ключа и self-signed сертификата"
cat > "$WORKDIR/cert_config.cnf" << EOF
[req]
default_bits = 2048
prompt = no
distinguished_name = dn
x509_extensions = v3_ext

[dn]
CN = $IDENTITY_NAME

[v3_ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "$WORKDIR/key.pem" \
    -out "$WORKDIR/cert.pem" \
    -days 3650 \
    -config "$WORKDIR/cert_config.cnf" \
    -nodes

echo "==> Экспорт в PKCS12 (используем -legacy: OpenSSL 3.x по умолчанию шифрует так,"
echo "    что 'security import' на macOS не может это прочитать без этого флага)"
openssl pkcs12 -export \
    -out "$WORKDIR/cert.p12" \
    -inkey "$WORKDIR/key.pem" \
    -in "$WORKDIR/cert.pem" \
    -password pass:taskbarapp \
    -legacy

echo "==> Импорт в login keychain (потребует подтверждения через диалог)"
security import "$WORKDIR/cert.p12" \
    -k ~/Library/Keychains/login.keychain-db \
    -P taskbarapp \
    -T /usr/bin/codesign \
    -A

echo "==> Установка доверия для code signing (потребует подтверждения через диалог)"
security add-trusted-cert -p codeSign \
    -k ~/Library/Keychains/login.keychain-db \
    "$WORKDIR/cert.pem"

echo "==> Проверка"
security find-identity -v -p codesigning | grep "$IDENTITY_NAME"

echo ""
echo "Готово. Теперь build_app.sh будет подписывать этим сертификатом автоматически."
echo "ВАЖНО: после первой сборки с новой подписью нужно ОДИН РАЗ вручную выдать"
echo "разрешение Accessibility в System Settings → Privacy & Security → Accessibility"
echo "(диалог появится сам при первом запуске, либо откройте настройки командой:"
echo "  open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"
echo "После этого разрешение будет переживать все последующие пересборки."
