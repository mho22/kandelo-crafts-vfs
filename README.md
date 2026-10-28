# PhotoCraft

[PhotoCraft](https://github.com/storytold/photocraft) is an open-source image editor written in Rust. It is an eframe app: egui on winit's Wayland backend, rendered by wgpu's OpenGL ES backend. Kandelo runs it inside a virtual machine, alone on a Wayland compositor, and paints the compositor's output on a canvas.

This repository holds the scripts that build PhotoCraft for Kandelo and pack it into a Kandelo VFS image. It also builds the Kandelo browser app from the same Kandelo commit as the image, and publishes both as one static site. The image does not depend on the kernel that kandelo.dev serves today.

## Requirements

A Kandelo checkout of the `photocraft` branch of `Automattic/kandelo`, prepared with `./run.sh setup`. It provides the SDK, the Rust toolchain, and the libraries PhotoCraft links: libwayland, libxkbcommon, libffi, libEGL and libGLESv2. It also builds `wlcompositor`, the compositor that runs PhotoCraft, `zenity`, the file dialog PhotoCraft opens, and the Kandelo exchange programs. The scripts use the checkout in `$KANDELO`, else the `kandelo` submodule.

The submodule pins the Kandelo commit that builds the site. Fetch it with its own submodules:

```sh
git submodule update --init --recursive
```

To move to a newer commit of the branch, check it out in `kandelo`, rebuild the binaries, the image and the app, and commit the submodule.

The branch adds OpenGL ES 3.0 to the WebGL bridge, the Wayland platform to libEGL, and `sdk/rust/build-env.sh`. `main` has none of them, so a Kandelo app built from `main` cannot run the image.

The checkout's node modules, installed with `npm ci` at its root. `npm run vfs` writes the image with the checkout's `images/vfs/lib/kandelo-image-fs.ts`, loaded through the checkout's `tsx`.

Node 24 or later. It runs `scripts/vfs.ts` directly, so this repository declares no dependencies and needs no install step.

## Build and run

The build runs inside the checkout's dev shell, which pins the Rust toolchain. The dev shell finds its flake from the current directory, so start it from the checkout:

```sh
cd "$KANDELO"
scripts/dev-shell.sh bash -c 'cd <this repository> && npm run build && npm run vfs'
cd <this repository>
npm run kandelo
```

`npm run build` writes `binaries/photocraft.wasm` and copies the Kandelo programs the image runs to `binaries/`: `wlcompositor`, `zenity`, `dash`, `kxchgd`, `exchange-save` and `xdg-open`. `npm run vfs` writes `public/photocraft.vfs`. `npm run kandelo` writes the Kandelo browser app to `public/kandelo` and the checkout's commit to `public/kandelo/COMMIT`. It starts the dev shell itself, so it runs outside it.

`npm run kandelo` refuses a checkout whose kernel ABI differs from the `kernelAbi` of `public/photocraft.vfs`. Rebuild the image and the app with the same checkout, and publish them together.

`public/` is the site. Serve it with the headers of `public/_headers` and open `/kandelo/?vfs=/photocraft.vfs`.

Kandelo restores the image and reads `/etc/kandelo/demo.json`. Its `init` block starts `wlcompositor /usr/local/bin/photocraft` as the first process at boot. The compositor starts PhotoCraft once its socket is bound, maximizes its window, and exits with PhotoCraft's exit status.

## The build

`scripts/build.sh` downloads PhotoCraft at a pinned commit, checks its SHA-256, and applies `patches/photocraft.patch`. It then sources the SDK's `sdk/rust/build-env.sh`, which pins `libc` to Kandelo's fork, vendors the crates in `Cargo.lock`, applies `patches/crates/<crate>-<version>.patch` to each crate it names, and builds offline. `wasm32posix-cargo` compiles PhotoCraft and fork-instruments the result.

The crate patches select the Linux or native code paths on `target_os = "kandelo"`. Most crates treat every `wasm32` target as a browser, and Kandelo is a musl unix target with threads, epoll, EGL and Wayland.

`wlcompositor.wasm` and `zenity.wasm` come from the checkout's `wayland-demo` package, `dash.wasm` from its `dash` package, and `kxchgd.wasm`, `exchange-save.wasm` and `xdg-open.wasm` from its `kandelo-exchange` package. The script stamps each one with the checkout's ABI contract.

## The image

```
/etc/passwd                                              the root account
/etc/kandelo/demo.json                                   what the machine is
/etc/kandelo/experimental-terminal-session.json          what a terminal runs
/etc/kandelo/exchange.conf                               the account the exchange agent runs as
/etc/kandelo/exchange-handlers.d                         empty: the local exchange rules
/usr/local/bin/wlcompositor                              the Wayland compositor
/usr/local/bin/photocraft                                the editor
/usr/local/bin/dash                                      the terminal's shell
/usr/bin/zenity                                          the file dialog
/usr/bin/xdg-open                                        sends a link to the browser
/usr/libexec/kandelo/exchange-agent                      the exchange agent, kxchgd
/usr/libexec/kandelo/exchange-save                       saves a dropped file
/usr/share/kandelo/exchange-handlers.d/99-save.handler   saves every input to ~/Downloads
/usr/share/X11/xkb                                       empty: libxkbcommon needs it to exist
/root                                                    root's home
/tmp                                                     the compositor's socket directory
```

The files of `config/` are copied into the image byte for byte. Kandelo refuses to boot an image that is missing `demo.json` or `session.json`. `99-save.handler` is copied from the checkout's `images/rootfs`.

`demo.json` describes the machine: its title, the runtime features it needs, and the program it runs at boot. `kms` and `kms-gl-scanout` give the compositor `/dev/dri/card0` and present its GL output on the canvas. `evdev-input` attaches the keyboard and the pointer before the session starts.

`session.json` says what a terminal starts: `dash`. Kandelo starts it when the Terminal opens, not at boot, so the compositor cannot start from it. The image holds no other programs, so only `dash` builtins work there. The compositor's log is in Internals.

The compositor sends PhotoCraft its keymap, so the image carries no XKB data. libxkbcommon still refuses to create a context when its default include directory is missing, so the image holds that directory empty, as Kandelo's own root image does.

## The site

```
public/_headers         cross-origin isolation for the app
public/_redirects       sends / to the machine
public/photocraft.vfs   the image
public/kandelo          the Kandelo browser app
```

The app needs `SharedArrayBuffer`, so its pages, scripts and assets carry `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` and `Cross-Origin-Resource-Policy: same-origin`. The image is fetched from the same origin and needs no header.

`npm run kandelo` deletes the gallery images the build bundles from the checkout, and keeps `shell` and `rootfs`. The gallery entries of the other demos fail to open on this site.

## Spacefast

The site is the Space `clear-bloom` of the `kandelo` team, at `https://clear-bloom.space.fast/`. Spacefast cannot build the binaries, and git does not track `public/photocraft.vfs` and `public/kandelo`. Build them, then publish `public/` from this machine:

```sh
npm install
npx sf login
npx sf publish public --prebuilt --space clear-bloom
```

Log in before the first publish. An anonymous Space serves neither `.wasm` nor `.vfs` files until it is claimed.

## Notes

The image is about 39 MB, and `photocraft.wasm` alone is 35 MB.

"Open file" runs `zenity`, which browses the machine's files, not the computer's. A file dropped on the machine, or picked from the dock, lands in `/root/Downloads`, where the dialog finds it.

"Join us on Discord" runs `xdg-open`. The link appears in the exchange tray, and Open opens it in a new tab.
