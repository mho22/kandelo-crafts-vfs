# PhotoCraft

[PhotoCraft](https://github.com/storytold/photocraft) is an open-source image editor written in Rust. It is an eframe app: egui on winit's Wayland backend, rendered by wgpu's OpenGL ES backend. Kandelo runs it inside a virtual machine, alone on a Wayland compositor, and paints the compositor's output on a canvas.

This repository holds the scripts that build PhotoCraft for Kandelo and pack it into a Kandelo VFS image. It holds no host code: Kandelo is the host.

## Requirements

A Kandelo checkout, prepared with `./run.sh setup`. It provides the SDK, the Rust toolchain, and the libraries PhotoCraft links: libwayland, libxkbcommon, libffi, libEGL and libGLESv2. It also builds `wlcompositor`, the compositor that runs PhotoCraft. The scripts look for the checkout in `$KANDELO`, then next to this repository, then one directory higher.

The checkout's host bundle, built with `npm run build` in its `host` directory. `./run.sh setup` does not build it. `host/dist` is what writes the image.

Node 24 or later. It runs `scripts/vfs.ts` directly, so this repository declares no dependencies and needs no install step.

## Build and run

The build runs inside the checkout's dev shell, which pins the Rust toolchain. The dev shell finds its flake from the current directory, so start it from the checkout:

```sh
cd "$KANDELO"
scripts/dev-shell.sh bash -c 'cd <this repository> && npm run build && npm run vfs'
```

`npm run build` writes `binaries/photocraft.wasm`, `binaries/wlcompositor.wasm` and `binaries/dash.wasm`. `npm run vfs` writes `vfs/photocraft.vfs`.

Serve `vfs/` over HTTP. The server must send `Access-Control-Allow-Origin` and `Cross-Origin-Resource-Policy`, because Kandelo enforces cross-origin isolation and refuses an image without them.

Start the Kandelo browser app from the Kandelo checkout:

```sh
./run.sh browser
```

Open the machine, naming the image URL:

```
http://127.0.0.1:5401/?vfs=<url of photocraft.vfs>
```

Kandelo restores the image and reads `/etc/kandelo/demo.json`. Its `init` block starts `wlcompositor /usr/local/bin/photocraft` as the first process at boot. The compositor starts PhotoCraft once its socket is bound, maximizes its window, and exits with PhotoCraft's exit status.

## The build

`scripts/build.sh` downloads PhotoCraft at a pinned commit, checks its SHA-256, and applies `patches/photocraft.patch`. It then sources the SDK's `sdk/rust/build-env.sh`, which pins `libc` to Kandelo's fork, vendors the crates in `Cargo.lock`, applies `patches/crates/<crate>-<version>.patch` to each crate it names, and builds offline. `wasm32posix-cargo` compiles PhotoCraft and fork-instruments the result.

The crate patches select the Linux or native code paths on `target_os = "kandelo"`. Most crates treat every `wasm32` target as a browser, and Kandelo is a musl unix target with threads, epoll, EGL and Wayland.

`wlcompositor.wasm` comes from the checkout's `wayland-demo` package and `dash.wasm` from its `dash` package. The script stamps both with the checkout's ABI contract.

## The image

```
/etc/kandelo/demo.json                          what the machine is
/etc/kandelo/experimental-terminal-session.json what a terminal runs
/usr/local/bin/wlcompositor                     the Wayland compositor
/usr/local/bin/photocraft                       the editor
/usr/local/bin/dash                             the terminal's shell
/usr/share/X11/xkb                              empty: libxkbcommon needs it to exist
/tmp                                            the compositor's socket directory
```

`config/demo.json` and `config/session.json` are copied into the image byte for byte. Kandelo refuses to boot an image that is missing either one.

`demo.json` describes the machine: its title, the runtime features it needs, and the program it runs at boot. `kms` and `kms-gl-scanout` give the compositor `/dev/dri/card0` and present its GL output on the canvas. `evdev-input` attaches the keyboard and the pointer before the session starts.

`session.json` says what a terminal starts: `dash`. Kandelo starts it when the Terminal opens, not at boot, so the compositor cannot start from it. The image holds no other programs, so only `dash` builtins work there. The compositor's log is in Internals.

The compositor sends PhotoCraft its keymap, so the image carries no XKB data. libxkbcommon still refuses to create a context when its default include directory is missing, so the image holds that directory empty, as Kandelo's own root image does.

## Notes

The image is about 44 MB, and `photocraft.wasm` alone is 39 MB.

The file dialog needs an XDG desktop portal or `zenity`, and the machine has neither.

The image is served over HTTP, so open Kandelo over HTTP too. A page served over HTTPS refuses to fetch it.
