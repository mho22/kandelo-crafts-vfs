#!/usr/bin/env bash
#
# Build the Kandelo browser app with the Kandelo checkout that builds the
# binaries, and copy it into public/<app>/kandelo for every app with an image,
# so the app's kernel matches the image's ABI.
#
set -euo pipefail
cd "$(dirname "$0")/.."

ROOT="$(pwd)"

BASE="/kandelo/"
OUT="$ROOT/work/kandelo"

KEEP=( shell rootfs )

for candidate in "${KANDELO:-}" "$ROOT/kandelo"; do
    [ -f "$candidate/run.sh" ] || continue
    CHECKOUT="$(cd "$candidate" && pwd)"
    break
done

if [ -z "${CHECKOUT:-}" ]; then
    echo "kandelo checkout not found. Run git submodule update --init --recursive, or set KANDELO to its path." >&2
    exit 1
fi

ABI="$(grep -o 'ABI_VERSION = [0-9]*' "$CHECKOUT/host/src/generated/abi.ts" | grep -o '[0-9]*$')"
IMAGES=( "$ROOT"/public/*/*.vfs )

for image in "${IMAGES[@]}"; do
    IMAGE_ABI="$(LC_ALL=C grep -a -o -m1 '"kernelAbi":[0-9]*' "$image" | grep -o '[0-9]*$')"
    [ "$ABI" = "$IMAGE_ABI" ] && continue
    echo "the checkout's kernel has ABI $ABI and ${image#$ROOT/} has ABI $IMAGE_ABI. Build both with the same checkout." >&2
    exit 1
done

cd "$CHECKOUT"

bash run.sh prepare-browser

bash scripts/dev-shell.sh bash -c '
    set -euo pipefail
    cd "$1"
    export WASM_POSIX_RESOLUTION_POLICY=source-only-v1
    export WASM_POSIX_SOURCE_ONLY_BINARY_ROOT="$PWD/local-binaries/source-only-v1"
    if [ ! -d apps/browser-demos/node_modules ] ||
       [ apps/browser-demos/package-lock.json -nt apps/browser-demos/node_modules ]; then
        npm --prefix apps/browser-demos ci --no-audit --no-fund
    fi
    VITE_BASE="$2" npm --prefix apps/browser-demos run build -- --outDir "$3" --emptyOutDir
' kandelo "$CHECKOUT" "$BASE" "$OUT"

for image in "$OUT"/assets/*.vfs-*.zst; do
    name="$(basename "$image")"
    [[ " ${KEEP[*]} " == *" ${name%%.vfs-*} "* ]] && continue
    rm "$image"
done

git -C "$CHECKOUT" rev-parse HEAD > "$OUT/COMMIT"

for image in "${IMAGES[@]}"; do
    site="$(dirname "$image")"
    rm -rf "$site/kandelo"
    cp -R "$OUT" "$site/kandelo"
done

du -sh "$OUT"
