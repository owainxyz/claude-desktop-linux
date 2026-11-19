# claude-desktop-linux

the windows claude desktop app, rebuilt to run on linux.

nothing from anthropic is in this repo. `build.sh` pulls the current windows release from their update feed and patches it locally.

## build

needs nix (electron 45, gcc lib), cargo, node/npx, 7z and imagemagick.

```
./build.sh
./install.sh
```

installs `claude-desktop` to `~/.local/bin`, a `Claude Desktop` launcher entry and the `claude://` handler. `CLAUDE_VERSION=x.y.z ./build.sh` pins a release. `PREFIX=...` changes the install dir.

## what changes

- `native/`: linux `@ant/claude-native` in rust (napi). safe-fs calls use `openat2` with `RESOLVE_BENEATH | RESOLVE_NO_SYMLINKS | RESOLVE_NO_MAGICLINKS`
- `shim/`: loads the module, stubs windows-only calls (registry, elevation, `AuthRequest`)
- `compat/`: no-op windows-only `BrowserWindow` apis
- node-pty linux prebuild in place of conpty
- `fontconfig/`: system-ui and sans fall back to inter
- launcher forces animations on (`--force-prefers-no-reduced-motion`)

## not working

office add-in, windows computer use, m365/github mcp helpers and ssh remote need windows binaries. no auto update, just rerun `build.sh`.
