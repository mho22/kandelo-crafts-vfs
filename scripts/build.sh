#!/usr/bin/env bash
#
# Build binaries/photocraft.wasm, binaries/wlcompositor.wasm and
# binaries/dash.wasm with the Kandelo SDK, inside the dev shell of a Kandelo
# checkout.
#
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"

COMMIT="90df9cfc159e5916be92c6b25f30c13913dfdd70"
URL="https://github.com/storytold/photocraft/archive/$COMMIT.tar.gz"
SHA256="b980627cb085b7759245b869e71984f70f8b4df97a64ccb4f1f871ef22ced9f6"

DEPENDENCIES=( libwayland libxkbcommon libffi )

for candidate in "${KANDELO:-}" "$ROOT/../kandelo" "$ROOT/../../kandelo"; do
    [ -f "$candidate/sdk/rust/build-env.sh" ] || continue
    CHECKOUT="$(cd "$candidate" && pwd)"
    break
done

if [ -z "${CHECKOUT:-}" ]; then
    echo "kandelo checkout not found. Set KANDELO to its path." >&2
    exit 1
fi

source "$CHECKOUT/sdk/activate.sh"
source "$CHECKOUT/sdk/rust/build-env.sh"

resolve() {
    (cd "$CHECKOUT" && cargo xtask build-deps resolve "$1")
}

WORK="$ROOT/work"
SRC="$WORK/photocraft-src"
ARCHIVE="$WORK/photocraft-$COMMIT.tar.gz"
mkdir -p "$WORK" "$ROOT/binaries"

if [ ! -f "$ARCHIVE" ]; then
    curl -fsSL "$URL" -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -

rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$ARCHIVE" -C "$SRC" --strip-components=1
patch -d "$SRC" -p1 < "$ROOT/patches/photocraft.patch"

PKG_CONFIG_DIRS=""
for dependency in "${DEPENDENCIES[@]}"; do
    PKG_CONFIG_DIRS="$PKG_CONFIG_DIRS${PKG_CONFIG_DIRS:+:}$(resolve "$dependency")/lib/pkgconfig"
done

(
    kandelo_rust_build_env "$SRC" "$WORK" "$PKG_CONFIG_DIRS" "$ROOT/patches/crates"
    cd "$SRC"
    CARGO_TARGET_DIR="$WORK/target" wasm32posix-cargo build --locked --release \
        -p photocraft --bin photocraft
)

cp "$WORK/target/$KANDELO_RUST_TARGET/release/photocraft.wasm" "$ROOT/binaries/photocraft.wasm"
cp "$(resolve wayland-demo)/wlcompositor.wasm" "$ROOT/binaries/wlcompositor.wasm"
cp "$(resolve dash)/dash.wasm" "$ROOT/binaries/dash.wasm"

REPO_ROOT="$CHECKOUT"
source "$CHECKOUT/scripts/abi-contract-stamp.sh"
abi_contract_stamp_prepare
abi_contract_stamp "$ROOT/binaries/wlcompositor.wasm"
abi_contract_stamp "$ROOT/binaries/dash.wasm"

ls -lh "$ROOT/binaries"
