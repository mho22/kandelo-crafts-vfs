# Kandelo Crafts

Four open-source desktop apps of [ArtCraft](https://getartcraft.com), written in Rust, running in the browser on Kandelo:

| App | What it is | Site |
| --- | --- | --- |
| [PhotoCraft](https://github.com/storytold/photocraft) | an image editor | https://photocraft.space.fast/ |
| [VectorCraft](https://github.com/storytold/vectorcraft) | a vector graphics editor | https://vectorcraft.space.fast/ |
| [WordCraft](https://github.com/storytold/wordcraft) | a word processor | https://wordcraft.space.fast/ |
| [GridCraft](https://github.com/storytold/gridcraft) | a spreadsheet | https://gridcraft.space.fast/ |

Each app is an eframe app: egui on winit's Wayland backend, rendered by wgpu's OpenGL ES backend. Kandelo runs it inside a virtual machine, alone on a Wayland compositor, and paints the compositor's output on a canvas.

This repository holds the scripts that build each app for Kandelo and pack it into a Kandelo VFS image. It also builds the Kandelo browser app from the same Kandelo commit as the images, and publishes each image with it as one static site. The images do not depend on the kernel that kandelo.dev serves today.

## Requirements

A Kandelo checkout of the `photocraft` branch of `Automattic/kandelo`, prepared with `./run.sh setup`. It provides the SDK, the Rust toolchain, and the libraries the apps link: libwayland, libxkbcommon, libffi, libEGL and libGLESv2. It also builds `wlcompositor`, the compositor that runs the app, `zenity`, the file dialog the app opens, and the Kandelo exchange programs. The scripts use the checkout in `$KANDELO`, else the `kandelo` submodule.

The submodule pins the Kandelo commit that builds the sites. Fetch it with its own submodules:

```sh
git submodule update --init --recursive
```

To move to a newer commit of the branch, check it out in `kandelo`, rebuild the binaries, the images and the app, and commit the submodule.

The branch adds OpenGL ES 3.0 to the WebGL bridge, the Wayland platform to libEGL, and `sdk/rust/build-env.sh`. `main` has none of them, so a Kandelo app built from `main` cannot run the images.

The checkout's node modules, installed with `npm ci` at its root. `npm run vfs` writes the image with the checkout's `images/vfs/lib/kandelo-image-fs.ts`, loaded through the checkout's `tsx`.

Node 24 or later. It runs `scripts/vfs.ts` directly.

## Build and run

`<app>` is `photocraft`, `vectorcraft`, `wordcraft` or `gridcraft`. The build runs inside the checkout's dev shell, which pins the Rust toolchain. The dev shell finds its flake from the current directory, so start it from the checkout:

```sh
cd "$KANDELO"
scripts/dev-shell.sh bash -c 'cd <this repository> && npm run build -- <app> && npm run vfs -- <app>'
cd <this repository>
npm run kandelo
```

`npm run build` writes `binaries/<app>/<app>.wasm` and copies the Kandelo programs the image runs next to it: `wlcompositor`, `zenity`, `dash`, `kxchgd`, `exchange-save` and `xdg-open`. `npm run vfs` writes `public/<app>/<app>.vfs`. `npm run kandelo` writes the Kandelo browser app to `work/kandelo`, and the checkout's commit to `work/kandelo/COMMIT`. It then copies the app to `public/<app>/kandelo` for every app with an image. It starts the dev shell itself, so it runs outside it.

`npm run kandelo` refuses a checkout whose kernel ABI differs from the `kernelAbi` of an image in `public/`. Rebuild the images and the app with the same checkout, and publish them together.

`public/<app>/` is the site of an app. Serve it with the headers of its `_headers` and open `/kandelo/?vfs=/<app>.vfs`.

Kandelo restores the image and reads `/etc/kandelo/demo.json`. Its `init` block starts `wlcompositor /usr/local/bin/<app>` as the first process at boot. The compositor starts the app once its socket is bound, maximizes its window, and exits with the app's exit status.

## The build

`scripts/build.sh` downloads the app at a pinned commit, checks its SHA-256, and applies `patches/<app>.patch`. It then sources the SDK's `sdk/rust/build-env.sh`, which pins `libc` to Kandelo's fork, vendors the crates in `Cargo.lock`, applies `patches/crates/<crate>-<version>.patch` to each crate it names, and builds offline. The SDK overrides crates.io crates only, so the script applies `patches/forks/<crate>-<version>.patch` to the vendored copies of the app's git forks of egui and winit itself. `wasm32posix-cargo` compiles the app and fork-instruments the result.

The crate patches select the Linux or native code paths on `target_os = "kandelo"`. Most crates treat every `wasm32` target as a browser, and Kandelo is a musl unix target with threads, epoll, EGL and Wayland. The SDK stops on a patch whose crate version is not in the app's `Cargo.lock`, so the script gives it only the patches of the crates in that `Cargo.lock`.

Each app patch starts with a header that says what it changes. All four make the app take its native code paths on Kandelo, and build eframe without X11:

- WordCraft and GridCraft also build winit without X11, and do not switch to XWayland when `DISPLAY` is set.
- WordCraft does not ask the desktop portal for the animation setting, because Kandelo has no D-Bus. "Use system setting" keeps animations on.
- GridCraft gives arboard its Wayland clipboard on Kandelo, as it does on Linux.

`wlcompositor.wasm` and `zenity.wasm` come from the checkout's `wayland-demo` package, `dash.wasm` from its `dash` package, and `kxchgd.wasm`, `exchange-save.wasm` and `xdg-open.wasm` from its `kandelo-exchange` package. The script stamps each one with the checkout's ABI contract.

## The image

```
/etc/passwd                                              the root account
/etc/kandelo/demo.json                                   what the machine is
/etc/kandelo/experimental-terminal-session.json          what a terminal runs
/etc/kandelo/exchange.conf                               the account the exchange agent runs as
/etc/kandelo/exchange-handlers.d                         empty: the local exchange rules
/usr/local/bin/wlcompositor                              the Wayland compositor
/usr/local/bin/<app>                                     the app
/usr/local/bin/dash                                      the terminal's shell
/usr/bin/zenity                                          the file dialog
/usr/bin/xdg-open                                        sends a link to the browser
/usr/bin/x-www-browser                                   VectorCraft and WordCraft only: xdg-open
/usr/libexec/kandelo/exchange-agent                      the exchange agent, kxchgd
/usr/libexec/kandelo/exchange-save                       saves a dropped file
/usr/share/kandelo/exchange-handlers.d/99-save.handler   saves every input to ~/Downloads
/usr/share/X11/xkb                                       empty: libxkbcommon needs it to exist
/root                                                    root's home
/tmp                                                     the compositor's socket directory
```

The files of `config/` are copied into the image byte for byte: `passwd`, `session.json` and `exchange.conf` into every image, and `config/<app>/demo.json` into the image of its app. Kandelo refuses to boot an image that is missing `demo.json` or `session.json`. `99-save.handler` is copied from the checkout's `images/rootfs`.

`demo.json` describes the machine: its title, the runtime features it needs, and the program it runs at boot. `kms` and `kms-gl-scanout` give the compositor `/dev/dri/card0` and present its GL output on the canvas. `evdev-input` attaches the keyboard and the pointer before the session starts. Its `presentation` block asks for the minimal dock and the WordPress dark theme.

`session.json` says what a terminal starts: `dash`. Kandelo starts it when the Terminal opens, not at boot, so the compositor cannot start from it. The image holds no other programs, so only `dash` builtins work there. The compositor's log is in Internals.

The compositor sends the app its keymap, so the image carries no XKB data. libxkbcommon still refuses to create a context when its default include directory is missing, so the image holds that directory empty, as Kandelo's own root image does.

## The site

```
public/<app>/_headers      cross-origin isolation for the app
public/<app>/_redirects    sends / to the machine
public/<app>/<app>.vfs     the image
public/<app>/kandelo       the Kandelo browser app
```

The app needs `SharedArrayBuffer`, so its pages, scripts and assets carry `Cross-Origin-Opener-Policy: same-origin`, `Cross-Origin-Embedder-Policy: require-corp` and `Cross-Origin-Resource-Policy: same-origin`. The image is fetched from the same origin and needs no header.

`npm run kandelo` deletes the gallery images the build bundles from the checkout, and keeps `shell` and `rootfs`. The gallery entries of the other demos fail to open on these sites.

## Spacefast

Each site is the Space of the `kandelo` team named after its app. Spacefast cannot build the binaries, and git does not track the images and `public/<app>/kandelo`. Build them, then publish each site from this machine:

```sh
npm install
npx sf login
npx sf publish public/<app> --prebuilt --space <app>
```

Log in before the first publish. An anonymous Space serves neither `.wasm` nor `.vfs` files until it is claimed. spacefast keeps the last Space it published to in `.spacefast/state.json`, so always name the Space.

## Notes

| App | Image | `<app>.wasm` | Opens a file | Opens a link |
| --- | --- | --- | --- | --- |
| PhotoCraft | 65 MB | 61 MB | "Open file" | "Join us on Discord" runs `xdg-open` |
| VectorCraft | 87 MB | 83 MB | "Open" | "Join our Discord" runs the `webbrowser` crate |
| WordCraft | 56 MB | 52 MB | Open › Browse | "Discord community" runs the `webbrowser` crate |
| GridCraft | 30 MB | 26 MB | Open › Browse | "Join the ArtCraft Discord", in Account › About GridCraft, runs `xdg-open` |

The file dialog is `zenity`, which browses the machine's files, not the computer's. A file dropped on the machine, or picked from the dock, lands in `/root/Downloads`, where the dialog finds it.

Without `xdg-settings`, the `webbrowser` crate falls back to `x-www-browser`, which the images of VectorCraft and WordCraft link to `xdg-open`. Every link appears in the exchange tray, and Open opens it in a new tab.
