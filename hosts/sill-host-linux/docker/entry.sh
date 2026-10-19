#!/bin/sh
# The container's desktop: Xvfb (1920x1080), D-Bus and Avahi, openbox (an EWMH window manager) and a
# few apps, then the given command:
#   selftest [ARGS]   sill-host-linux --selftest /out ARGS
#   host [ARGS]       sill-host-linux ARGS (the host; its port published to 127.0.0.1 only)
#   shell             a shell, for poking around (docker run -it)
#   anything else     run as it is
set -e
export DISPLAY="${DISPLAY:-:99}"
SIZE="${SILL_SCREEN:-1920x1080x24}"
Xvfb "$DISPLAY" -screen 0 "$SIZE" -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &
for i in $(seq 100); do xdpyinfo >/dev/null 2>&1 && break; sleep 0.1; done
xdpyinfo >/dev/null 2>&1 || { echo "Xvfb did not start:"; cat /tmp/xvfb.log; exit 1; }

mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || true
avahi-daemon --daemonize --no-rlimits 2>/dev/null || echo "entry: avahi-daemon did not start"

openbox >/tmp/openbox.log 2>&1 &
sleep 0.5
xsetroot -solid '#335577' 2>/dev/null || true
xterm -title "Sill xterm" -geometry 100x30+60+60 -e sh -c 'while true; do date; sleep 1; done' &
xeyes -geometry 320x220+1000+80 &
xclock -update 1 -geometry 260x260+1400+80 &
mousepad >/dev/null 2>&1 &
# Until the four windows are mapped (Mousepad's first start takes a while), at most 15 s.
for i in $(seq 150); do
  [ "$(xdotool search --onlyvisible --name '.' 2>/dev/null | wc -l)" -ge 8 ] && \
    xdotool search --onlyvisible --name 'Mousepad' >/dev/null 2>&1 && break
  sleep 0.1
done
sleep 0.5

cmd="${1:-selftest}"
[ $# -gt 0 ] && shift
case "$cmd" in
  selftest) mkdir -p /out; exec sill-host-linux --selftest /out "$@" ;;
  host) exec sill-host-linux "$@" ;;
  shell) exec /bin/sh ;;
  *) exec "$cmd" "$@" ;;
esac
