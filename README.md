# claude-desktop-linux

the official windows claude desktop app, checked and rebuilt to run natively on linux.

nothing from anthropic is in this repo. `build.sh` downloads the current windows release from anthropic's own update feed, proves it's genuine, swaps out the windows-only parts and packs it for linux. every build is made on your machine from anthropic's signed files.

not affiliated with or endorsed by anthropic. see [legal](#legal).

## status

| | |
|---|---|
| sign in (google) | works, opens your browser and comes back via `claude://` |
| wayland, x11 | works (`--ozone-platform-hint=auto`) |
| chat, projects, artifacts | should work, it's the same web frontend as windows |
| claude code tab | untested, the app downloads its own linux `claude` binary for it |
| terminal (node-pty) | untested |
| mcp servers from `claude_desktop_config.json` | untested |
| tray, notifications | untested, the app has linux code for both |
| office add-in, windows computer use | no, needs windows |
| bundled m365 and github mcp helpers | no, windows `.exe`/`.dll` only |
| ssh remote | no, helpers are windows binaries |
| auto update | no, rerun `build.sh` |

tested on nixos (x86_64, wayland, nvidia) against 6.6395.1.

## requirements

- linux x86_64
- [nix](https://nixos.org/download) with flakes enabled, for electron 45, gcc runtime libs and osslsigncode. versions come from `flake.lock`. works on any distro with nix installed, not just nixos
- rust (cargo)
- node 22+ with npx
- `7z`, `curl`, `xxd`, imagemagick (`magick`, `identify`)

## install

```
git clone https://github.com/owainxyz/claude-desktop-linux
cd claude-desktop-linux
./build.sh
./install.sh
```

then run `claude-desktop`, or pick **Claude Desktop** from your launcher (rofi, fuzzel, anything that reads `.desktop` files).

`install.sh` puts:

| path | what |
|---|---|
| `~/.local/bin/claude-desktop` | launcher |
| `~/.local/lib/claude-desktop/` | electron runtime + app |
| `~/.local/lib/claude-desktop-roots/` | nix gc roots so the runtime isn't garbage collected |
| `~/.local/share/applications/com.anthropic.Claude.desktop` | launcher entry + `claude://` handler |
| `~/.local/share/icons/hicolor/96x96/apps/claude-desktop.png` | icon, pulled from `claude.exe` |

`PREFIX=/opt/claude ./install.sh` installs somewhere else. it has to be an absolute path with no spaces.

app data lives in `~/.config/Claude`, same as the official apps.

## update

```
git pull
./build.sh
./install.sh
```

`build.sh` always takes the newest release in the feed. electron and the other nix tools stay on the revision in `flake.lock`, run `nix flake update` to move them forward (worth doing for electron security fixes). `CLAUDE_VERSION=6.6395.1 ./build.sh` pins one, as long as it's still in the feed. close the app before `install.sh`.

## uninstall

```
rm -rf ~/.local/lib/claude-desktop ~/.local/lib/claude-desktop-roots ~/.local/bin/claude-desktop \
  ~/.local/share/applications/com.anthropic.Claude.desktop \
  ~/.local/share/icons/hicolor/96x96/apps/claude-desktop.png
```

add `~/.config/Claude` to drop your settings and session too.

## how it works

the windows app is electron. nearly all of it is javascript that already handles linux: the web frontend says "claude for linux", claude code is fetched for `linux-x64`, there's a linux tray icon, freedesktop notifications and xdg activation. the only parts that need porting are a few native binaries.

```
downloads.claude.ai RELEASES
  -> AnthropicClaude-<ver>-full.nupkg        sha1 checked against the feed
    -> claude.exe                            authenticode: signed by Anthropic, PBC
      -> INTEGRITY/ELECTRONASAR resource     sha256 of each asar header
        -> app.asar, ion-dist.asar headers   sha256 of every file + every 4 MiB block
          -> 7560 files                      all checked before anything is extracted
```

then:

1. windows binaries are dropped: `claude-native-binding.node`, conpty, the m365/github helpers. the verifier lists exactly which ones and the build deletes that list
2. `@ant/claude-native` is replaced with the rust module from `native/`
3. node-pty gets its official linux prebuild (tarball sha512 pinned)
4. `compat/linux-compat.js` is loaded first in the main process and adds no-op versions of windows-only electron apis (`hookWindowMessage`, thumbar, jump lists)
5. the app is repacked into an asar and dropped next to a copy of nixpkgs electron 45 (the windows build uses 45.3.3)
6. `install.sh` sets the same electron fuses anthropic ships on windows

### native module

`native/` is a napi-rs crate that implements the linux side of `@ant/claude-native`. the important part is safe-fs, which the app uses so claude code and file tools can't be tricked into writing outside a chosen folder.

every path is resolved by the kernel with `openat2` and

```
RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS
```

so `..`, absolute paths, symlinks and `/proc` magic links are refused by the kernel, not by string checks that can race. leaf operations (`mkdirat`, `unlinkat`, `renameat2`, `linkat`, `statx`) run against a parent opened the same way. on top of that:

- `renameBeneathOntoFreeName` uses `RENAME_NOREPLACE`, so it can't clobber
- `verifyLeafBeneath` rejects files with extra hard links and files whose name was swapped after opening
- errors keep the `ENOENT:` / `ELOOP:` / `EXDEV:` prefixes the app maps to its own symlink and escape errors

everything else in the module (registry, windows elevation, macos auth sheets, office com) is windows or mac only. those calls are stubbed to report "not supported", which is what the app expects on a platform without them. `CLAUDE_NATIVE_TRACE=1 claude-desktop` logs any native call the app makes that the module doesn't have.

### launcher flags

| flag / env | why |
|---|---|
| `--ozone-platform-hint=auto` | native wayland when available |
| `--enable-wayland-ime` | input methods on wayland |
| `--force-prefers-no-reduced-motion` | gtk often reports "reduced motion" with no settings daemon, which kills every animation |
| `--enable-smooth-scrolling` | same cause, for scrolling |
| `FONTCONFIG_FILE` | maps `system-ui`, `sans-serif`, `Segoe UI`, `Arial` etc to inter so fallback text isn't dejavu. only applies to this app |
| `LD_LIBRARY_PATH` | gcc runtime for node-pty on nix |

## security

see [SECURITY.md](SECURITY.md) for reporting.

**what the build guarantees**

- the nupkg matches the sha1 in anthropic's release feed (over https, tls 1.2+)
- `claude.exe` has a valid authenticode signature that chains to a trusted root, and the signer is exactly `Anthropic, PBC` (delaware 4860621). checked with osslsigncode against your system ca bundle, including the timestamp
- both asar headers match the hashes embedded in that signed exe, and every file inside matches its header hash, block by block. one flipped byte anywhere stops the build
- node-pty's tarball matches a pinned sha512, and the rust crate builds with `--locked`
- nix tools come from a pinned nixpkgs revision (`flake.lock`), not whatever your registry points at
- the asar and fuse tools are installed from `tools/package-lock.json` with `npm ci --ignore-scripts`, so no install scripts run and every package is hash checked
- the native module has to pass `test/native.mjs` (24 escape and race tests) before it's packed
- the feed's version string is checked against a strict pattern before it's used in any path

if any check fails, `build.sh` stops and nothing is installed.

**what it changes**

only the files listed under [how it works](#how-it-works). the web frontend (`ion-dist.asar`) is copied untouched. `patches/apply.mjs` injects one `require` line into the main entry. no network endpoints, telemetry or auth are changed.

**runtime hardening**

the installed binary gets the same electron fuses as the official windows build:

| fuse | |
|---|---|
| RunAsNode | off, `ELECTRON_RUN_AS_NODE` can't turn the app into a node shell |
| EnableNodeOptionsEnvironmentVariable | off, `NODE_OPTIONS` is ignored |
| EnableNodeCliInspectArguments | off, no `--inspect` debugger |
| OnlyLoadAppFromAsar | on |
| EnableCookieEncryption | on, cookies are encrypted with your keyring (gnome keyring, kwallet, or chromium's fallback) |

the launcher also clears `ELECTRON_RUN_AS_NODE`, `NODE_OPTIONS`, `ELECTRON_EXTRA_LAUNCH_ARGS` and the electron debug variables before starting, and the install dir is read-only (`r-x`), so nothing running as you can quietly patch the app files without changing permissions first.

the chromium sandbox stays on: renderers and the gpu process run under seccomp-bpf in their own user namespace. electron's asar integrity check only exists for mac and windows, so on linux the app files are protected by normal file permissions under your prefix.

**what it doesn't protect against**

- a compromised anthropic release. this build trusts anthropic's signature, same as the official app does
- a compromised nixpkgs, crates.io or npm registry beyond the pinned hashes
- anything with write access to your install prefix

## troubleshooting

**sign in does nothing.** the app opens your default browser. after signing in, the browser opens a `claude://` link. if your browser asks, choose Claude Desktop. check the handler with `xdg-mime query default x-scheme-handler/claude`, it should say `com.anthropic.Claude.desktop`.

**two "Claude" entries in the launcher.** this one is called Claude Desktop. the other is probably a claude code terminal launcher.

**no animations.** make sure you're starting it through `claude-desktop` and not the raw binary, the flag is in the launcher.

**ugly fallback fonts.** install inter (`nixpkgs#inter`, `fonts-inter`), or edit `fontconfig/fonts.conf` and reinstall. to test a family with a dash, escape it: `fc-match 'system\-ui'`.

**blank window or gpu errors on nvidia.** try `claude-desktop --ozone-platform=x11`, or `--disable-gpu` as a last resort.

**logged out after reinstalling.** cookie encryption is on, so if your keyring changed or older cookies can't be read, sign in once more.

**a feature crashes.** run `CLAUDE_NATIVE_TRACE=1 claude-desktop` and open an issue with the `missing:` lines and `~/.config/Claude/logs/main.log`.

## development

```
./build.sh                 full verified build into build/<ver>
./dev.sh <name> <seconds>  repack the current build, run it on a hidden xvfb display, save .dev/<name>.png and .log
./run.sh                   run build/current against nix electron without installing
node test/native.mjs       escape tests for the native module
nix develop                shell with every build dependency
```

layout:

```
build.sh             download, verify, patch, pack
flake.nix, .lock     pinned nix tools
tools/               locked asar + fuses cli
test/native.mjs      native module escape tests
verify.mjs           asar integrity checker
install.sh           runtime, fuses, launcher, desktop entry
native/              rust @ant/claude-native for linux
shim/claude-native/  js wrapper + stubs for windows/mac-only calls
compat/              windows-only electron api no-ops
patches/apply.mjs    injects compat into the main entry
fontconfig/          app-only font fallbacks
```

## legal

this is an independent interoperability project, not affiliated with, endorsed by or supported by anthropic. "claude" and "anthropic" are trademarks of anthropic, pbc, used here only to say what this runs.

the repo contains no anthropic code, binaries, icons or assets. everything of theirs is downloaded by you, from them, at build time, and stays on your machine. don't upload `dl/`, `x/` or `build/` anywhere.

using the app is still covered by anthropic's [consumer terms](https://www.anthropic.com/legal/consumer-terms) or your organization's agreement with them. you need your own account. if anthropic ships an official linux build, use that.

the code in this repo is mit licensed, see [LICENSE](LICENSE).
