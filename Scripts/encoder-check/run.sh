#!/bin/zsh
# The encoder checks that never touch an encoder, from any directory:
#   mailbox   EncoderMailbox (the real file) against a stand-in for VideoToolbox in virtual time
#             (Tests/checks/encoder-mailbox, which CI runs)
#   mutants   the same check against one-line mutants of EncoderMailbox: each must fail it
#   probe     EncoderProbe.throughput's loop (the real file) against a stand-in HEVCEncoder, in real
#             time, and SILL_TEST_PROBE_HOLD=0.08 through it
#   encoder   the real HEVCEncoder.swift (with EncoderMailbox.swift, EncoderSlowState.swift and
#             EncoderProbe.swift) against a stand-in VideoToolbox (encoder/FakeVT.swift), in real
#             time: with a new session for the slow state on (all of it), then off (E7 alone)
#   slowstate EncoderSlowState (the real file): when a stream's session is replaced for the slow
#             state, by hand at its edges and in streams in virtual time
#             (Tests/checks/encoder-slowstate, which CI runs)
#   mutants-slowstate   the same check against one-line mutants of EncoderSlowState: each must fail
# usage: Scripts/encoder-check/run.sh [mailbox] [mutants] [probe] [encoder] [slowstate]
#        [mutants-slowstate]   (no argument: all)
# The probe and encoder checks run in real time with tight timing bounds, so they stay here, out of
# CI. They build under .build/encoder-check/, the other two under .build/checks/. Every binary is
# checked with otool before it runs: one that links VideoToolbox is refused, so nothing here can
# open an encoder session, and these checks are safe while Sill.app streams. The hardware runs are
# verify-hardware.sh's, under its own rules.
set -u
ROOT=${0:A:h:h:h}
OUT=$ROOT/.build/encoder-check
mkdir -p $OUT
steps=("$@"); (( ${#steps} )) || steps=(mailbox mutants probe encoder slowstate mutants-slowstate)
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
  $ROOT/Tests/checks/encoder-mailbox/run.sh || failed=1
  ;;
mutants)
  echo "== mutants of EncoderMailbox"
  $ROOT/Tests/checks/encoder-mailbox/run.sh --mutants || failed=1
  ;;
probe)
  echo "== probe check"
  swiftc -O -package-name sill $ROOT/Sources/SillHost/EncoderProbe.swift $ROOT/Sources/SillHost/Stats.swift \
    $ROOT/Scripts/encoder-check/probe/main.swift -o $OUT/probe-check || { failed=1; continue }
  encoder_free $OUT/probe-check || { failed=1; continue }
  $OUT/probe-check || failed=1
  SILL_TEST_PROBE_HOLD=0.08 $OUT/probe-check hold || failed=1
  ;;
encoder)
  echo "== encoder check"
  # The real file, less the two imports FakeVT.swift stands in for; nothing else changes.
  src=$OUT/encoder-src; rm -rf $src; mkdir -p $src
  sed -e '/^import VideoToolbox$/d' -e '/^import StreamProtocol$/d' $ROOT/Sources/SillHost/HEVCEncoder.swift > $src/HEVCEncoder.swift
  swiftc -O -module-name EncoderCheck $src/HEVCEncoder.swift $ROOT/Sources/SillHost/EncoderMailbox.swift \
    $ROOT/Sources/SillHost/EncoderSlowState.swift \
    $ROOT/Sources/SillHost/EncoderProbe.swift $ROOT/Scripts/encoder-check/encoder/FakeVT.swift \
    $ROOT/Scripts/encoder-check/encoder/main.swift -o $OUT/encoder-check || { failed=1; continue }
  encoder_free $OUT/encoder-check || { failed=1; continue }
  if nm -u $OUT/encoder-check | grep -q '_VT'; then echo "REFUSED: encoder-check imports a VideoToolbox symbol"; failed=1; continue; fi
  SILL_TEST_ENCODER_RECYCLE=1 $OUT/encoder-check || failed=1
  SILL_TEST_ENCODER_RECYCLE=0 $OUT/encoder-check E7 || failed=1
  ;;
slowstate)
  echo "== slow-state check"
  $ROOT/Tests/checks/encoder-slowstate/run.sh || failed=1
  ;;
mutants-slowstate)
  echo "== mutants of EncoderSlowState"
  $ROOT/Tests/checks/encoder-slowstate/run.sh --mutants || failed=1
  ;;
*) echo "unknown step $step"; failed=1 ;;
esac
done
if (( failed )); then echo "encoder checks: FAILED"; else echo "encoder checks: all passed"; fi
exit $failed
