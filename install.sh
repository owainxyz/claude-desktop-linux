#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
src=$(readlink -f "$here/build/current/claude")
ver=$(basename "$(dirname "$src")")
dest=${PREFIX:-$HOME/.local}
umask 022
[ -d "$src/resources" ] || { echo "error: run ./build.sh first" >&2; exit 1; }
[[ $dest = /* && $dest != / && $dest =~ ^[A-Za-z0-9/._-]+$ ]] || { echo "error: PREFIX must be an absolute path without spaces: $dest" >&2; exit 1; }
lib=$dest/lib/claude-desktop
if pgrep -f "^$lib/claude-desktop" >/dev/null; then echo "error: close Claude Desktop first" >&2; exit 1; fi
el=$(nix build --no-link --print-out-paths "$here#electron")
real=$(sed -n 's/^exec "\(.*\)\/electron" .*/\1/p' "$el/bin/electron" | tail -1)
stdcpp=$(nix build --no-link --print-out-paths "$here#gcclib" | tail -1)
mkdir -p "$dest/lib/claude-desktop-roots"
nix-store --add-root "$dest/lib/claude-desktop-roots/electron" --realise "$el" >/dev/null
nix-store --add-root "$dest/lib/claude-desktop-roots/stdcpp" --realise "$stdcpp" >/dev/null

[ -d "$lib.new" ] && chmod -R u+w "$lib.new"
rm -rf "$lib.new"
mkdir -p "$lib.new"
cp -rL "$real/." "$lib.new/"
chmod -R u+w "$lib.new"
mv "$lib.new/electron" "$lib.new/claude-desktop"
(cd "$here/tools" && npm ci --ignore-scripts --no-audit --no-fund --silent && cd /tmp && "$here/tools/node_modules/.bin/electron-fuses" write --app "$lib.new/claude-desktop" RunAsNode=off EnableCookieEncryption=on EnableNodeOptionsEnvironmentVariable=off EnableNodeCliInspectArguments=off OnlyLoadAppFromAsar=on >/dev/null)
rm -rf "$lib.new/resources"
cp -r "$src/resources" "$lib.new/resources"
cp "$here/fontconfig/fonts.conf" "$lib.new/fonts.conf"
chmod -R a-w,a+rX "$lib.new"
chmod u+w "$lib.new"
[ -d "$lib" ] && chmod -R u+w "$lib"
rm -rf "$lib" && mv "$lib.new" "$lib"
chmod u-w "$lib"

mkdir -p "$dest/bin" "$dest/share/applications" "$dest/share/icons/hicolor/96x96/apps"
cat > "$dest/bin/claude-desktop" <<SH
#!/usr/bin/env bash
unset ELECTRON_RUN_AS_NODE NODE_OPTIONS ELECTRON_ENABLE_LOGGING ELECTRON_DEBUG_NOTIFICATIONS ELECTRON_EXTRA_LAUNCH_ARGS
export LD_LIBRARY_PATH=$stdcpp/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export CHROME_DEVEL_SANDBOX=$el/libexec/electron/chrome-sandbox
export ELECTRON_IS_DEV=0
# terminal panel falls back to powershell.exe when SHELL is unset (desktop launch)
export CLAUDE_DESKTOP_TERMINAL_SHELL="\${CLAUDE_DESKTOP_TERMINAL_SHELL:-\${SHELL:-\$(getent passwd "\$(id -un)" | cut -d: -f7)}}"
export FONTCONFIG_FILE=$lib/fonts.conf
store=--password-store=basic
export CLAUDE_PLAINTEXT_STORE=1
if command -v busctl >/dev/null && busctl --user list 2>/dev/null | grep -q '^org\.freedesktop\.secrets '; then
  store=--password-store=gnome-libsecret
  unset CLAUDE_PLAINTEXT_STORE
fi
exec "$lib/claude-desktop" "\$store" --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,UseOzonePlatform --enable-wayland-ime --force-prefers-no-reduced-motion --enable-smooth-scrolling "\$@"
SH
chmod 755 "$dest/bin/claude-desktop"

big=$(identify "$here/x/$ver/rc/.rsrc/1033/ICON/"*.ico 2>/dev/null | sort -k3 -V | tail -1 | cut -d" " -f1); [ -n "$big" ] && magick "$big" "$here/x/$ver/icon.png"
cp "$here/x/$ver/icon.png" "$dest/share/icons/hicolor/96x96/apps/claude-desktop.png" 2>/dev/null || true
cat > "$dest/share/applications/com.anthropic.Claude.desktop" <<DE
[Desktop Entry]
Type=Application
Name=Claude Desktop
GenericName=Claude
Keywords=claude;ai;chat;anthropic;
Exec=$dest/bin/claude-desktop %u
Icon=claude-desktop
Terminal=false
Categories=Office;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
DE
update-desktop-database "$dest/share/applications" 2>/dev/null || true
xdg-mime default com.anthropic.Claude.desktop x-scheme-handler/claude 2>/dev/null || true
echo "installed claude $ver -> $dest/bin/claude-desktop"
