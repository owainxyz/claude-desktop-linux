# claude-desktop-linux

The official Windows Claude Desktop app, verified and rebuilt to run natively on Linux.

Nothing from Anthropic is in this repository. `build.sh` downloads the current Windows release from Anthropic's own update feed, proves it is genuine, replaces the Windows-only parts and packages it for Linux. Every build is made on your machine from Anthropic's signed files.

Not affiliated with or endorsed by Anthropic. See [Legal](#legal).

## Status

| Feature | Status |
| --- | --- |
| Sign in (Google) | Works. Opens your browser and returns through `claude://` |
| Wayland, X11 | Works (`--ozone-platform-hint=auto`) |
| Chat, projects, artifacts | Expected to work; it is the same web frontend as on Windows |
| Claude Code tab | Untested. The app downloads its own Linux `claude` binary for it |
| Terminal (node-pty) | Untested |
| MCP servers from `claude_desktop_config.json` | Untested |
| Tray, notifications | Untested. The app has Linux code for both |
| Office add-in, Windows computer use | Not supported, requires Windows |
| Bundled Microsoft 365 and GitHub MCP helpers | Not supported, Windows `.exe`/`.dll` only |
| SSH remote | Not supported, the helpers are Windows binaries |
| Automatic updates | Not supported. Rerun `build.sh` |

Tested on NixOS (x86_64, Wayland, NVIDIA) against version 6.6395.1.

## Requirements

- Linux on x86_64
- [Nix](https://nixos.org/download) with flakes enabled, which provides Electron 45, the GCC runtime libraries and osslsigncode at the versions pinned in `flake.lock`. Any distribution with Nix installed works, not only NixOS
- Rust (Cargo)
- Node.js 22 or later, with `npx`
- `7z`, `curl`, `xxd` and ImageMagick (`magick`, `identify`)

## Installation

```sh
git clone https://github.com/owainxyz/claude-desktop-linux
cd claude-desktop-linux
./build.sh
./install.sh
```

Then run `claude-desktop`, or choose **Claude Desktop** from your launcher (rofi, fuzzel or anything that reads `.desktop` files).

`install.sh` installs:

| Path | Contents |
| --- | --- |
| `~/.local/bin/claude-desktop` | Launcher |
| `~/.local/lib/claude-desktop/` | Electron runtime and app |
| `~/.local/lib/claude-desktop-roots/` | Nix GC roots, so the runtime is not garbage collected |
| `~/.local/share/applications/com.anthropic.Claude.desktop` | Desktop entry and `claude://` handler |
| `~/.local/share/icons/hicolor/96x96/apps/claude-desktop.png` | Icon, extracted from `claude.exe` |

To install elsewhere, use `PREFIX=/opt/claude ./install.sh`. The prefix must be an absolute path without spaces.

App data is stored in `~/.config/Claude`, the same as the official apps.

## Updating

```sh
git pull
./build.sh
./install.sh
```

`build.sh` always uses the newest release in the feed. Electron and the other Nix tools stay on the revision in `flake.lock`; run `nix flake update` to move them forward, which is worth doing for Electron security fixes. `CLAUDE_VERSION=6.6395.1 ./build.sh` pins a specific version, as long as it is still in the feed. Close the app before running `install.sh`.

## Uninstalling

```sh
rm -rf ~/.local/lib/claude-desktop ~/.local/lib/claude-desktop-roots ~/.local/bin/claude-desktop \
  ~/.local/share/applications/com.anthropic.Claude.desktop \
  ~/.local/share/icons/hicolor/96x96/apps/claude-desktop.png
```

Also remove `~/.config/Claude` to delete your settings and session.

## How it works

The Windows app is built on Electron. Nearly all of it is JavaScript that already handles Linux: the web frontend identifies itself as Claude for Linux, Claude Code is fetched for `linux-x64`, and there is a Linux tray icon, freedesktop notifications and XDG activation. Only a few native binaries need porting.

```
downloads.claude.ai RELEASES
  -> AnthropicClaude-<ver>-full.nupkg        SHA-1 checked against the feed
    -> claude.exe                            Authenticode: signed by Anthropic, PBC
      -> INTEGRITY/ELECTRONASAR resource     SHA-256 of each asar header
        -> app.asar, ion-dist.asar headers   SHA-256 of every file and every 4 MiB block
          -> 7560 files                      all checked before anything is extracted
```

The build then:

1. Removes the Windows binaries: `claude-native-binding.node`, ConPTY and the Microsoft 365 and GitHub helpers. The verifier lists exactly which files these are, and the build deletes that list
2. Replaces `@ant/claude-native` with the Rust module in `native/`
3. Installs the official Linux prebuild of node-pty (tarball SHA-512 pinned)
4. Loads `compat/linux-compat.js` first in the main process, which adds no-op versions of Windows-only Electron APIs (`hookWindowMessage`, thumbnail toolbars, jump lists)
5. Repacks the app into an asar next to a copy of nixpkgs Electron 45 (the Windows build uses 45.3.3)
6. Sets the same Electron fuses Anthropic ships on Windows, in `install.sh`

### Native module

`native/` is a napi-rs crate that implements the Linux side of `@ant/claude-native`. The most important part is safe-fs, which the app uses so Claude Code and file tools cannot be tricked into writing outside a chosen folder.

Every path is resolved by the kernel with `openat2` and

```
RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS
```

so `..`, absolute paths, symlinks and `/proc` magic links are refused by the kernel rather than by string checks that can race. Leaf operations (`mkdirat`, `unlinkat`, `renameat2`, `linkat`, `statx`) run against a parent directory opened the same way. In addition:

- `renameBeneathOntoFreeName` uses `RENAME_NOREPLACE`, so it cannot overwrite an existing file
- `verifyLeafBeneath` rejects files with extra hard links and files whose name was swapped after opening
- Errors keep the `ENOENT:`, `ELOOP:` and `EXDEV:` prefixes that the app maps to its own symlink and escape errors

Everything else in the module (registry, Windows elevation, macOS authorization sheets, Office COM) is Windows or macOS only. Those calls are stubbed to report "not supported", which is what the app expects on a platform without them. `CLAUDE_NATIVE_TRACE=1 claude-desktop` logs any native call the app makes that the module does not implement.

### Launcher flags

| Flag or variable | Reason |
| --- | --- |
| `--ozone-platform-hint=auto` | Native Wayland when available |
| `--enable-wayland-ime` | Input methods on Wayland |
| `--force-prefers-no-reduced-motion` | Without a settings daemon, GTK often reports reduced motion, which disables every animation |
| `--enable-smooth-scrolling` | Same cause, for scrolling |
| `FONTCONFIG_FILE` | Maps `system-ui`, `sans-serif`, `Segoe UI`, `Arial` and others to Inter so fallback text is not DejaVu. Applies to this app only |
| `LD_LIBRARY_PATH` | GCC runtime for node-pty on Nix |

## Security

See [SECURITY.md](SECURITY.md) to report a vulnerability.

### What the build guarantees

- The nupkg matches the SHA-1 in Anthropic's release feed, fetched over HTTPS with TLS 1.2 or later
- `claude.exe` has a valid Authenticode signature that chains to a trusted root, and the signer is exactly `Anthropic, PBC` (Delaware 4860621). This is checked with osslsigncode against your system CA bundle, including the timestamp
- Both asar headers match the hashes embedded in the signed executable, and every file inside matches its header hash, block by block. A single changed byte anywhere stops the build
- The node-pty tarball matches a pinned SHA-512, and the Rust crate builds with `--locked`
- Nix tools come from a pinned nixpkgs revision (`flake.lock`), not from whatever your registry points to
- The asar and fuse tools are installed from `tools/package-lock.json` with `npm ci --ignore-scripts`, so no install scripts run and every package is hash checked
- The native module must pass `test/native.mjs` (24 escape and race tests) before it is packaged
- The version string from the feed is checked against a strict pattern before it is used in any path

If any check fails, `build.sh` stops and nothing is installed.

### What it changes

Only the files listed under [How it works](#how-it-works). The web frontend (`ion-dist.asar`) is copied unmodified. `patches/apply.mjs` injects a single `require` line into the main entry point. No network endpoints, telemetry or authentication are changed.

### Runtime hardening

The installed binary has the same Electron fuses as the official Windows build:

| Fuse | Setting |
| --- | --- |
| RunAsNode | Off. `ELECTRON_RUN_AS_NODE` cannot turn the app into a Node.js shell |
| EnableNodeOptionsEnvironmentVariable | Off. `NODE_OPTIONS` is ignored |
| EnableNodeCliInspectArguments | Off. No `--inspect` debugger |
| OnlyLoadAppFromAsar | On |
| EnableCookieEncryption | On. Cookies are encrypted with your keyring (GNOME Keyring, KWallet or Chromium's fallback) |

The launcher also clears `ELECTRON_RUN_AS_NODE`, `NODE_OPTIONS`, `ELECTRON_EXTRA_LAUNCH_ARGS` and the Electron debug variables before starting. The install directory is read-only (`r-x`), so nothing running as your user can silently modify the app files without first changing permissions.

The Chromium sandbox stays enabled: renderers and the GPU process run under seccomp-bpf in their own user namespace. Electron's asar integrity check exists only on macOS and Windows, so on Linux the app files are protected by normal file permissions under your prefix.

### What it does not protect against

- A compromised Anthropic release. This build trusts Anthropic's signature, as the official app does
- A compromised nixpkgs, crates.io or npm registry, beyond the pinned hashes
- Anything with write access to your install prefix

## Troubleshooting

**Sign-in does nothing.** The app opens your default browser. After you sign in, the browser opens a `claude://` link; if it asks, choose Claude Desktop. Check the handler with `xdg-mime query default x-scheme-handler/claude`, which should print `com.anthropic.Claude.desktop`.

**Two "Claude" entries in the launcher.** This one is named Claude Desktop. The other is probably a Claude Code terminal launcher.

**No animations.** Start the app with `claude-desktop`, not the raw binary. The required flag is set in the launcher.

**Poor fallback fonts.** Install Inter (`nixpkgs#inter`, `fonts-inter`), or edit `fontconfig/fonts.conf` and reinstall. To test a family name containing a dash, escape it: `fc-match 'system\-ui'`.

**Blank window or GPU errors on NVIDIA.** Try `claude-desktop --ozone-platform=x11`, or `--disable-gpu` as a last resort.

**Signed out after reinstalling.** Cookie encryption is enabled, so if your keyring changed or older cookies cannot be read, sign in again.

**A feature crashes.** Run `CLAUDE_NATIVE_TRACE=1 claude-desktop` and open an issue with the `missing:` lines and `~/.config/Claude/logs/main.log`.

## Development

```
./build.sh                 Full verified build into build/<ver>
./dev.sh <name> <seconds>  Repack the current build, run it on a hidden Xvfb display, save .dev/<name>.png and .log
./run.sh                   Run build/current against Nix Electron without installing
node test/native.mjs       Escape tests for the native module
nix develop                Shell with every build dependency
```

### Repository layout

| Path | Contents |
| --- | --- |
| `build.sh` | Download, verify, patch, package |
| `flake.nix`, `flake.lock` | Pinned Nix tools |
| `tools/` | Locked asar and fuses CLI |
| `test/native.mjs` | Native module escape tests |
| `verify.mjs` | Asar integrity checker |
| `install.sh` | Runtime, fuses, launcher, desktop entry |
| `native/` | Rust `@ant/claude-native` for Linux |
| `shim/claude-native/` | JavaScript wrapper and stubs for Windows and macOS-only calls |
| `compat/` | No-ops for Windows-only Electron APIs |
| `patches/apply.mjs` | Injects the compatibility layer into the main entry point |
| `fontconfig/` | App-only font fallbacks |

## Legal

This is an independent interoperability project. It is not affiliated with, endorsed by or supported by Anthropic. "Claude" and "Anthropic" are trademarks of Anthropic, PBC, used here only to describe what this software runs.

The repository contains no Anthropic code, binaries, icons or assets. Everything of theirs is downloaded by you, from them, at build time, and stays on your machine. Do not upload `dl/`, `x/` or `build/` anywhere.

Use of the app is still governed by Anthropic's [Consumer Terms](https://www.anthropic.com/legal/consumer-terms) or your organization's agreement with them, and you need your own account. If Anthropic releases an official Linux build, use that instead.

The code in this repository is released under the [MIT License](LICENSE).
