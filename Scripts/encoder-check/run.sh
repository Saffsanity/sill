#!/bin/zsh
# The encoder checks that never touch an encoder, from any directory:
#   mailbox   EncoderMailbox (the real file) against a stand-in for VideoToolbox in virtual time
#   mutants   the same check against one-line mutants of EncoderMailbox: each must fail it
#   probe     EncoderProbe.throughput's loop (the real file) against a stand-in HEVCEncoder, in real
#             time, and SILL_TEST_PROBE_HOLD=0.08 through it
# usage: Scripts/encoder-check/run.sh [mailbox] [mutants] [probe]      (no argument: all of them)
# Builds under .build/encoder-check/. Every binary is checked with otool before it runs: one that
# links VideoToolbox is refused, so nothing here can open an encoder session, and these checks are
# safe while Sill.app streams. The hardware runs are verify-hardware.sh's, under its own rules.
set -u
ROOT=${0:A:h:h:h}
OUT=$ROOT/.build/encoder-check
mkdir -p $OUT
steps=("$@"); (( ${#steps} )) || steps=(mailbox mutants probe)
failed=0

encoder_free() {   # BINARY: refuse it if it links VideoToolbox
  if otool -L $1 | grep -q VideoToolbox; then
    echo "REFUSED: $1 links VideoToolbox"; return 1
  fi
}

for step in $steps; do
case $step in
mailbox)
  echo "== mailbox check"
  swiftc -O $ROOT/Sources/SillHost/EncoderMailbox.swift $ROOT/Scripts/encoder-check/mailbox/main.swift -o $OUT/mailbox-check || { failed=1; continue }
  encoder_free $OUT/mailbox-check || { failed=1; continue }
  $OUT/mailbox-check || failed=1
  ;;
mutants)
  echo "== mutants of EncoderMailbox"
  python3 $ROOT/Scripts/encoder-check/mailbox/mutants.py || failed=1
  for b in $OUT/mutants/*/check(N); do encoder_free $b || failed=1; done
  ;;
probe)
  echo "== probe check"
  swiftc -O -package-name sill $ROOT/Sources/SillHost/EncoderProbe.swift $ROOT/Sources/SillHost/Stats.swift \
    $ROOT/Scripts/encoder-check/probe/main.swift -o $OUT/probe-check || { failed=1; continue }
  encoder_free $OUT/probe-check || { failed=1; continue }
  $OUT/probe-check || failed=1
  SILL_TEST_PROBE_HOLD=0.08 $OUT/probe-check hold || failed=1
  ;;
*) echo "unknown step $step"; failed=1 ;;
esac
done
if (( failed )); then echo "encoder checks: FAILED"; else echo "encoder checks: all passed"; fi
exit $failed
