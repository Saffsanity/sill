#!/bin/zsh
# Builds the hardware harness twice, from the real files (compiling never touches the encoder;
# running the result does, so run it only through verify-hardware.sh):
#   .build/encoder-check/harness-base   the base commit's HEVCEncoder (ENCODER_CHECK_BASE, default
#                                       4fe37d4, encoder-recovery: one frame inside), from git archive
#   .build/encoder-check/harness-new    this working tree's HEVCEncoder, EncoderMailbox and
#                                       EncoderSlowState
# Each copy of HEVCEncoder.swift loses its `import StreamProtocol` line (StreamProtocol's sources are
# compiled into the same module) and gains one line at the top of `handle(_:)` that records the
# output's timestamp for the latency figure.
set -eu
ROOT=${0:A:h:h:h:h}
OUT=$ROOT/.build/encoder-check
BASE=${ENCODER_CHECK_BASE:-4fe37d4}
mkdir -p $OUT
base_tree=$OUT/tree-$BASE
if [[ ! -d $base_tree/Sources ]]; then
  rm -rf $base_tree; mkdir -p $base_tree
  git -C $ROOT archive $BASE | tar -x -C $base_tree
fi
build() {   # NAME TREE
  local name=$1 tree=$2
  local d=$OUT/harness-src-$name; rm -rf $d; mkdir -p $d
  sed -e '/^import StreamProtocol$/d' \
      -e 's/^    private func handle(_ sb: CMSampleBuffer) {$/    private func handle(_ sb: CMSampleBuffer) {\n        harnessOutputPTS = CMSampleBufferGetPresentationTimeStamp(sb)/' \
      $tree/Sources/SillHost/HEVCEncoder.swift > $d/HEVCEncoder.swift
  grep -q 'harnessOutputPTS = ' $d/HEVCEncoder.swift || { echo "patch failed for $name"; exit 1 }
  local extra=()
  [[ -f $tree/Sources/SillHost/EncoderMailbox.swift ]] && extra+=($tree/Sources/SillHost/EncoderMailbox.swift)
  [[ -f $tree/Sources/SillHost/EncoderSlowState.swift ]] && extra+=($tree/Sources/SillHost/EncoderSlowState.swift)
  swiftc -O -package-name sill -module-name Harness -o $OUT/harness-$name \
    $ROOT/Scripts/encoder-check/harness/main.swift $d/HEVCEncoder.swift $tree/Sources/SillHost/EncoderProbe.swift \
    $tree/Sources/SillHost/Stats.swift $tree/Sources/StreamProtocol/*.swift $extra
  echo "built $OUT/harness-$name"
}
build base $base_tree
build new $ROOT
