#!/usr/bin/env bash
#
# Build binaries/<app>/<app>.wasm with the Kandelo SDK, and copy the Kandelo
# programs the image runs next to it, inside the dev shell of a Kandelo
# checkout.
#
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"
APP="${1:-}"

case "$APP" in
    photocraft)
        COMMIT="c645d5fcc92c4bdd0d925084450699d05a184850"
        SHA256="4b8385f7d2cdcf652f441d706f29e208bc7392d463cdf083c7ccdb16259430d7" ;;
    vectorcraft)
        COMMIT="6b3a6b8788ebcb420d69449199cbdf323888d27e"
        SHA256="80d265a380c3d3d4be1c9e5cefc1c53fade5768e4d9fdd35517a8690b8877ff7" ;;
    wordcraft)
        COMMIT="ccb8ce84947c3a2005cdf71de268698c472c6948"
        SHA256="28d12a3ee22aac5d1088b8b2b121068abd901333687980f5857621a347b12461" ;;
    gridcraft)
        COMMIT="43284377d2466037628e57d8ad0c891778fdb45c"
        SHA256="8f37cb93f2e0c6cc3c6e16d96ebc0a8fbe8b5095afff66485ebd57575ce812aa" ;;
    *)
        echo "usage: npm run build -- <photocraft|vectorcraft|wordcraft|gridcraft>" >&2
        exit 1 ;;
esac

URL="https://github.com/storytold/$APP/archive/$COMMIT.tar.gz"

DEPENDENCIES=( libwayland libxkbcommon libffi )

for candidate in "${KANDELO:-}" "$ROOT/kandelo"; do
    [ -f "$candidate/sdk/rust/build-env.sh" ] || continue
    CHECKOUT="$(cd "$candidate" && pwd)"
    break
done

if [ -z "${CHECKOUT:-}" ]; then
    echo "kandelo checkout not found. Run git submodule update --init --recursive, or set KANDELO to its path." >&2
    exit 1
fi

source "$CHECKOUT/sdk/activate.sh"
source "$CHECKOUT/sdk/rust/build-env.sh"

resolve() {
    (cd "$CHECKOUT" && cargo xtask build-deps resolve "$1")
}

PATCHES="$ROOT/patches"
BINARIES="$ROOT/binaries/$APP"
WORK="$ROOT/work/$APP"
SRC="$WORK/$APP-src"
ARCHIVE="$WORK/$APP-$COMMIT.tar.gz"
mkdir -p "$WORK" "$BINARIES"

if [ ! -f "$ARCHIVE" ]; then
    curl -fsSL "$URL" -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
echo "$SHA256  $ARCHIVE" | shasum -a 256 -c -

rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$ARCHIVE" -C "$SRC" --strip-components=1
patch -d "$SRC" -p1 < "$PATCHES/$APP.patch"
(cd "$SRC" && cargo update --quiet -p zip@9.1.0 --precise 9.0.0)

CRATES="$WORK/patches"
rm -rf "$CRATES"
mkdir -p "$CRATES"
for patch in "$PATCHES"/crates/*.patch; do
    crate="$(basename "$patch" .patch)"
    grep -A1 -x "name = \"${crate%-*}\"" "$SRC/Cargo.lock" | grep -qx "version = \"${crate##*-}\"" || continue
    cp "$patch" "$CRATES"
done

PKG_CONFIG_DIRS=""
for dependency in "${DEPENDENCIES[@]}"; do
    PKG_CONFIG_DIRS="$PKG_CONFIG_DIRS${PKG_CONFIG_DIRS:+:}$(resolve "$dependency")/lib/pkgconfig"
done

(
    kandelo_rust_build_env "$SRC" "$WORK" "$PKG_CONFIG_DIRS" "$CRATES"
    for patch in "$PATCHES"/forks/*.patch; do
        crate="$WORK/vendor/$(basename "$patch" .patch)"
        [ -d "$crate" ] || continue
        patch -d "$crate" -p1 < "$patch"
        printf '{"files":{},"package":null}' > "$crate/.cargo-checksum.json"
    done
    export CC_wasm32_unknown_kandelo_std=wasm32posix-cc AR_wasm32_unknown_kandelo_std=wasm32posix-ar
    cd "$SRC"
    CARGO_TARGET_DIR="$WORK/target" wasm32posix-cargo build --locked --release \
        -p "$APP" --bin "$APP"
)

cp "$WORK/target/$KANDELO_RUST_TARGET/release/$APP.wasm" "$BINARIES/$APP.wasm"
PROGRAMS=( wayland-demo/wlcompositor wayland-demo/zenity dash/dash
           kandelo-exchange/kxchgd kandelo-exchange/exchange-save kandelo-exchange/xdg-open )

REPO_ROOT="$CHECKOUT"
source "$CHECKOUT/scripts/abi-contract-stamp.sh"
abi_contract_stamp_prepare
for program in "${PROGRAMS[@]}"; do
    package="${program%/*}"
    name="${program#*/}"
    cp "$(resolve "$package")/$name.wasm" "$BINARIES/$name.wasm"
    abi_contract_stamp "$BINARIES/$name.wasm"
done

ls -lh "$BINARIES"
