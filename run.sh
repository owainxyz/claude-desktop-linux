#!/usr/bin/env bash
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
dir=$(readlink -f "$here/build/current/claude")
el=$(nix build --no-link --print-out-paths nixpkgs#electron_45-bin 2>/dev/null || nix build --no-link --print-out-paths nixpkgs#electron_45)
real=$(sed -n 's/^exec "\(.*\)\/electron" .*/\1/p' "$el/bin/electron" | tail -1)
[ -n "$real" ] || real=$el/libexec/electron
for f in "$real"/*; do
  b=$(basename "$f")
  [ "$b" = resources ] || [ "$b" = electron ] && continue
  ln -sfn "$f" "$dir/$b"
done
[ -f "$dir/claude-desktop" ] && cmp -s "$real/electron" "$dir/claude-desktop" || install -m755 "$real/electron" "$dir/claude-desktop"
stdcpp=$(nix build --no-link --print-out-paths 'nixpkgs#stdenv.cc.cc.lib' 2>/dev/null | tail -1)
export LD_LIBRARY_PATH=$stdcpp/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
export ELECTRON_IS_DEV=0
export CLAUDE_DESKTOP_TERMINAL_SHELL="${CLAUDE_DESKTOP_TERMINAL_SHELL:-${SHELL:-$(getent passwd "$(id -un)" | cut -d: -f7)}}"
exec "$dir/claude-desktop" --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations "$@"
