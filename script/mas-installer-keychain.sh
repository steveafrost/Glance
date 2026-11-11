#!/bin/bash
# Create the keychain that holds Glance's Mac Installer Distribution identity.
# Run once per build machine.
#
#   script/mas-installer-keychain.sh /path/to/installer.p12
#
# Why a separate keychain: signing a .pkg with an installer identity from the
# login keychain hangs in SecurityServer::generateSignature waiting on a GUI
# authorization dialog, which no unattended or headless build can answer.
# Importing the same identity into a keychain with a known password, and setting
# its partition list, lets pkgbuild and productsign use it without a prompt.
#
# The p12 must be exported from a Mac that has the certificate's private key
# (Keychain Access > the "3rd Party Mac Developer Installer" cert > Export).
# Its password is passed in so it never lands in a file:
#
#   GLANCE_P12_PASSWORD=... script/mas-installer-keychain.sh installer.p12
#
# The keychain password is created here, printed once, and must be kept: it is
# what mas-build.sh passes back in GLANCE_INSTALLER_KEYCHAIN_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")/.."

P12=${1:-}
[[ -n $P12 && -f $P12 ]] || { echo "usage: script/mas-installer-keychain.sh INSTALLER.p12" >&2; exit 2; }

KC=${GLANCE_INSTALLER_KEYCHAIN:-$HOME/.appstoreconnect/mas-signing.keychain-db}
P12_PASS=${GLANCE_P12_PASSWORD:-}
KPASS=${GLANCE_INSTALLER_KEYCHAIN_PASSWORD:-}

if [[ -f $KC ]]; then
  echo "mas-installer-keychain: $KC already exists; delete it first to recreate" >&2
  exit 1
fi
if [[ -z $KPASS ]]; then
  echo "mas-installer-keychain: set GLANCE_INSTALLER_KEYCHAIN_PASSWORD to choose the keychain password" >&2
  exit 1
fi

echo "mas-installer-keychain: creating $KC"
security create-keychain -p "$KPASS" "$KC"
# -l: lock on sleep, -t: lock after timeout, -u: lock after inactivity.
security set-keychain-settings -lut 21600 "$KC"

security import "$P12" -k "$KC" -P "$P12_PASS" \
  -T /usr/bin/pkgbuild -T /usr/bin/productsign -T /usr/bin/productbuild \
  -T /usr/bin/codesign -A

# Without this the tools still prompt, because the ACL on the key only trusts
# the binaries named at import time.
security set-key-partition-list \
  -S apple-tool:,apple:,productbuild:,pkgbuild:,productsign:,codesign: \
  -s -k "$KPASS" "$KC" >/dev/null

echo "mas-installer-keychain: identities in $KC"
security find-identity -v -p basic "$KC"

cat <<EOF

Add these to the build environment:

  GLANCE_INSTALLER_KEYCHAIN=$KC
  GLANCE_INSTALLER_KEYCHAIN_PASSWORD=$KPASS

Then script/mas-build.sh signs without prompting.
EOF
