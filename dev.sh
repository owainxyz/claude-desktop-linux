#!/usr/bin/env bash
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
S=$here/.dev; mkdir -p "$S/shots"
app=$here/build/current/app
rm -rf "$app/node_modules/@ant/claude-native" && cp -r "$here/shim/claude-native" "$app/node_modules/@ant/claude-native"
(cd /tmp && npx -y @electron/asar@3.2.17 pack "$app" "$here/build/current/claude/resources/app.asar" --unpack '{*.node,**/spawn-helper}')
pgrep -f "Xvfb :97" >/dev/null || { Xvfb :97 -screen 0 1600x1000x24 >/dev/null 2>&1 & sleep 1; }
pkill -x claude-desktop; sleep 1
n=${1:-x}; t=${2:-30}
env -u WAYLAND_DISPLAY DISPLAY=:97 XDG_CONFIG_HOME=$S/xdg CLAUDE_NATIVE_TRACE=1 timeout $((t+5)) "$here/run.sh" --ozone-platform=x11 > $S/$n.log 2>&1 &
sleep $t; DISPLAY=:97 import -window root $S/shots/$n.png; sleep 6
command grep -vE "dbus|Fontconfig|libva|gpu_init|viz_main|ERROR:bus" $S/$n.log | head -${3:-50}
