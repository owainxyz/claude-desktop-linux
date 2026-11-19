#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
feed=https://downloads.claude.ai/releases/win32/x64
asar="npx -y @electron/asar@3.2.17"
ptyVer=1.2.0-beta.14

cd "$here"
mkdir -p dl vendor

ver=${CLAUDE_VERSION:-$(curl -fsSL "$feed/RELEASES" | tr -d '\r\357\273\277' | awk '/full\.nupkg/{print $2}' | tail -1 | sed 's/AnthropicClaude-\(.*\)-full\.nupkg/\1/')}
nupkg=dl/AnthropicClaude-$ver-full.nupkg
[ -f "$nupkg" ] || curl -fL -o "$nupkg" "$feed/AnthropicClaude-$ver-full.nupkg"
echo "claude $ver"

rm -rf "x/$ver" "build/$ver"
mkdir -p "x/$ver" "build/$ver"
7z x -y -o"x/$ver" "$nupkg" 'lib/net45/resources/*' lib/net45/claude.exe >/dev/null
7z x -y -o"x/$ver/ico" "x/$ver/lib/net45/claude.exe" '.rsrc/1033/ICON/*' >/dev/null
res="x/$ver/lib/net45/resources"

app="build/$ver/app"
(cd /tmp && $asar extract "$here/$res/app.asar" "$here/$app")
cp -r "$res/app.asar.unpacked/." "$app/"

(cd native && nice -n 19 cargo build --release -j 6 --quiet)
cp native/target/release/libclaude_native_linux.so shim/claude-native/claude-native-binding.node
rm -rf "$app/node_modules/@ant/claude-native"
cp -r shim/claude-native "$app/node_modules/@ant/claude-native"

if [ ! -d vendor/pty/package ]; then
  (cd vendor && npm pack "node-pty@$ptyVer" --silent && mkdir -p pty && tar xzf "node-pty-$ptyVer.tgz" -C pty)
fi
rm -rf "$app/node_modules/node-pty/prebuilds/win32-x64"
cp -r vendor/pty/package/prebuilds/linux-x64 "$app/node_modules/node-pty/prebuilds/"

find "$app" \( -iname '*.exe' -o -iname '*.dll' \) -delete
rm -f "$app/resources/office365-mcp/msal-node-runtime.node"

node patches/apply.mjs "$app"

out="build/$ver/claude"
mkdir -p "$out/resources"
(cd /tmp && $asar pack "$here/$app" "$here/$out/resources/app.asar" --unpack '{*.node,**/spawn-helper}')
cp "$res/ion-dist.asar" "$out/resources/"
cp "$res"/*.png "$out/resources/"
[ -d "$res/ion-dist.asar.unpacked" ] && cp -r "$res/ion-dist.asar.unpacked" "$out/resources/"

ln -sfn "$ver" build/current
echo "built build/$ver/claude/resources"
