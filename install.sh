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
el=$(nix build --no-link --print-out-paths nixpkgs#electron_45)
real=$(sed -n 's/^exec "\(.*\)\/electron" .*/\1/p' "$el/bin/electron" | tail -1)
stdcpp=$(nix build --no-link --print-out-paths 'nixpkgs#stdenv.cc.cc.lib' | tail -1)
mkdir -p "$dest/lib/claude-desktop-roots"
nix-store --add-root "$dest/lib/claude-desktop-roots/electron" --realise "$el" >/dev/null
nix-store --add-root "$dest/lib/claude-desktop-roots/stdcpp" --realise "$stdcpp" >/dev/null

rm -rf "$lib.new"
mkdir -p "$lib.new"
cp -rL "$real/." "$lib.new/"
chmod -R u+w "$lib.new"
mv "$lib.new/electron" "$lib.new/claude-desktop"
(cd /tmp && npx -y @electron/fuses@1.8.0 write --app "$lib.new/claude-desktop" RunAsNode=off EnableCookieEncryption=on EnableNodeOptionsEnvironmentVariable=off EnableNodeCliInspectArguments=off OnlyLoadAppFromAsar=on >/dev/null)
rm -rf "$lib.new/resources"
cp -r "$src/resources" "$lib.new/resources"
cp "$here/fontconfig/fonts.conf" "$lib.new/fonts.conf"
rm -rf "$lib" && mv "$lib.new" "$lib"

mkdir -p "$dest/bin" "$dest/share/applications" "$dest/share/icons/hicolor/96x96/apps"
cat > "$dest/bin/claude-desktop" <<SH
#!/usr/bin/env bash
export LD_LIBRARY_PATH=$stdcpp/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
export CHROME_DEVEL_SANDBOX=$el/libexec/electron/chrome-sandbox
export ELECTRON_IS_DEV=0
export FONTCONFIG_FILE=$lib/fonts.conf
exec "$lib/claude-desktop" --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations,UseOzonePlatform --enable-wayland-ime --force-prefers-no-reduced-motion --enable-smooth-scrolling "\$@"
SH
chmod +x "$dest/bin/claude-desktop"

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
