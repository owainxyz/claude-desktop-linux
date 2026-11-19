#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
feed=https://downloads.claude.ai/releases/win32/x64
asar="$here/tools/node_modules/.bin/asar"
ptyVer=1.2.0-beta.14
ptyIntegrity=sha512-XORU9BQgpxVgqr7WivjJ17mLenOHUgKKWzuZZNaw3NDYgHc/wPJQMSaoLDrpEgqV6aU1nNwil1o/OqYj6lWmUA==
signer='CN=Anthropic\\, PBC,O=Anthropic\\, PBC,L=San Francisco,ST=California,C=US,serialNumber=4860621'

die() { echo "error: $*" >&2; exit 1; }

cd "$here"
mkdir -p dl vendor .dev
(cd tools && npm ci --ignore-scripts --no-audit --no-fund --silent)

releases=$(curl -fsSL --proto '=https' --tlsv1.2 "$feed/RELEASES" | tr -d '\r\357\273\277')
if [ -n "${CLAUDE_VERSION:-}" ]; then
  ver=$CLAUDE_VERSION
else
  ver=$(awk '/-full\.nupkg/{print $2}' <<<"$releases" | tail -1 | sed 's/^AnthropicClaude-\(.*\)-full\.nupkg$/\1/')
fi
[[ $ver =~ ^[0-9]+(\.[0-9]+){1,3}$ ]] || die "bad version: $ver"
sha1=$(awk -v f="AnthropicClaude-$ver-full.nupkg" '$2==f{print tolower($1)}' <<<"$releases")
[[ $sha1 =~ ^[0-9a-f]{40}$ ]] || die "$ver is not in the release feed"

nupkg=dl/AnthropicClaude-$ver-full.nupkg
[ -f "$nupkg" ] || curl -fL --proto '=https' --tlsv1.2 -o "$nupkg.part" "$feed/AnthropicClaude-$ver-full.nupkg"
[ -f "$nupkg.part" ] && mv "$nupkg.part" "$nupkg"
[ "$(sha1sum "$nupkg" | cut -d' ' -f1)" = "$sha1" ] || { rm -f "$nupkg"; die "nupkg sha1 does not match the feed"; }
echo "ok   claude $ver, nupkg matches feed"

rm -rf "x/$ver" "build/$ver"
mkdir -p "x/$ver" "build/$ver"
7z x -y -o"x/$ver" "$nupkg" 'lib/net45/resources/*' lib/net45/claude.exe >/dev/null
exe="x/$ver/lib/net45/claude.exe"
res="x/$ver/lib/net45/resources"

osslsigncode=$(nix build --no-link --print-out-paths "$here#osslsigncode" | tail -1)/bin/osslsigncode
ca=${SSL_CERT_FILE:-/etc/ssl/certs/ca-certificates.crt}
"$osslsigncode" verify -in "$exe" -CAfile "$ca" -TSA-CAfile "$ca" > ".dev/sig-$ver.txt" 2>&1 || die "claude.exe signature does not verify (.dev/sig-$ver.txt)"
awk '/^Signer.s certificate:/{getline; getline; getline; print; exit}' ".dev/sig-$ver.txt" | grep -qF "Subject: ${signer//\\\\/\\}" || die "claude.exe is not signed by Anthropic, PBC"
echo "ok   claude.exe signed by Anthropic, PBC"

7z x -y -o"x/$ver/rc" "$exe" '.rsrc/1033/INTEGRITY/ELECTRONASAR' '.rsrc/1033/ICON/*' >/dev/null
node verify.mjs "$res" "x/$ver/rc/.rsrc/1033/INTEGRITY/ELECTRONASAR" "x/$ver/drop.txt"

app="build/$ver/app"
(cd /tmp && $asar extract "$here/$res/app.asar" "$here/$app")
cp -r "$res/app.asar.unpacked/." "$app/"
while IFS= read -r f; do
  [ -n "$f" ] && rm -f -- "$app/$f"
done < "x/$ver/drop.txt"

(cd native && nice -n 19 cargo build --release --locked -j 6 --quiet)
cp native/target/release/libclaude_native_linux.so shim/claude-native/claude-native-binding.node
node test/native.mjs shim/claude-native | tail -1
rm -rf "$app/node_modules/@ant/claude-native"
cp -r shim/claude-native "$app/node_modules/@ant/claude-native"

tgz=vendor/node-pty-$ptyVer.tgz
[ -f "$tgz" ] || (cd vendor && npm pack "node-pty@$ptyVer" --silent >/dev/null)
[ "sha512-$(sha512sum "$tgz" | cut -d' ' -f1 | xxd -r -p | base64 -w0)" = "$ptyIntegrity" ] || die "node-pty tarball hash mismatch"
rm -rf vendor/pty && mkdir -p vendor/pty && tar xzf "$tgz" -C vendor/pty
rm -rf "$app/node_modules/node-pty/prebuilds/win32-x64"
cp -r vendor/pty/package/prebuilds/linux-x64 "$app/node_modules/node-pty/prebuilds/"
echo "ok   node-pty $ptyVer matches pinned hash"

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
