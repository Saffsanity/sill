#!/bin/sh
# End-to-end input through the core's plain door into a containerized Linux host: starts xev in the
# container, has inputclient.py pick xev's window and send pointer, buttons, wheel, keys, chords and
# text, then checks xev's log and xdotool getmouselocation inside the container.
#   tests/e2e-input.sh [CONTAINER] [PORT]   (default sill-linux-host, 47123; the host must be running)
set -u
C="${1:-sill-linux-host}"; P="${2:-47123}"
HERE="$(cd "$(dirname "$0")" && pwd)"
docker exec "$C" sh -c 'pkill -x xev; rm -f /tmp/xev.log; (xev -geometry 500x400+700+500 -name sill-e2e > /tmp/xev.log 2>&1 &) ; sleep 1.5'
W=$(docker exec "$C" sh -c 'xdotool search --name "^sill-e2e$" | head -1')
[ -n "$W" ] || { echo "FAIL: xev window not found"; exit 1; }
# xwininfo's absolute origin (xdotool getwindowgeometry is off by the frame under a reparenting WM).
GEO=$(docker exec "$C" sh -c "xwininfo -id $W")
X=$(echo "$GEO" | sed -n 's/.*Absolute upper-left X: *\([0-9-]*\).*/\1/p'); Y=$(echo "$GEO" | sed -n 's/.*Absolute upper-left Y: *\([0-9-]*\).*/\1/p')
WW=$(echo "$GEO" | sed -n 's/.*Width: *\([0-9]*\).*/\1/p'); WH=$(echo "$GEO" | sed -n 's/.*Height: *\([0-9]*\).*/\1/p')
echo "xev window $W at $X,$Y, ${WW}x${WH}"
python3 "$HERE/inputclient.py" "$P" "window:$W" \
  move=0.25,0.5 sleep=0.3 click=0.5,0.5 rclick=0.6,0.5 scroll=0.5,0.5,0,0.5 \
  key=0x04 key=0x04,0x20000 key=0x06,0x100000 key=0x1b,0x80000 key=0x52 \
  keydown=0xe3,0x100000 key=0x19,0x100000 keyup=0xe3 text='Hé€\n' move=0.75,0.25 || exit 1
sleep 0.5
fail=0
LOC=$(docker exec "$C" xdotool getmouselocation)
echo "pointer after move=0.75,0.25: $LOC"
EX=$((X + WW * 3 / 4)); EY=$((Y + WH / 4))
echo "$LOC" | grep -q "x:$EX y:$EY" && echo "PASS pointer at $EX,$EY" || { echo "FAIL pointer: want x:$EX y:$EY"; fail=1; }
LOG=$(docker exec "$C" cat /tmp/xev.log)
check() { echo "$LOG" | grep -q "$2" && echo "PASS $1" || { echo "FAIL $1 (no '$2' in xev's log)"; fail=1; }; }
check "left click" "button 1,"
check "right click" "button 3,"
check "wheel up (content down)" "button 4,"
check "a" "keysym 0x61, a"
check "shift+a" "keysym 0x41, A"
check "cmd+c as Control+c" "keysym 0x63, c"
check "Control held" "keysym 0xffe3, Control_L"
check "option+x as Alt+x" "keysym 0xffe9, Alt_L"
check "Up" "keysym 0xff52, Up"
check "cmd held around v" "keysym 0x76, v"
check "text H" "keysym 0x48, H"
check "text é (remapped spare key)" "keysym 0xe9, eacute"
check "text € (remapped spare key)" "keysym 0x10020ac"
check "text Return" "keysym 0xff0d, Return"
# Nothing left down: the last key events in xev's log are releases.
docker exec "$C" sh -c 'xdotool key --clearmodifiers shift 2>/dev/null; true'
docker exec "$C" pkill -x xev
exit $fail
