#!/bin/zsh
# Exit 0 when no encoder session completed frames in the last ~12 s (the kernel's AppleAVE2
# HeartBeat), else 1 with the busy sessions in .build/encoder-check/engine-busy.txt. Reads the log
# only; never touches the encoder.
ROOT=${0:A:h:h:h}
OUT=$ROOT/.build/encoder-check
mkdir -p $OUT
/usr/bin/log show --info --debug --style compact --last 12s --predicate 'sender == "AppleAVE2"' > $OUT/engine-now.txt 2>/dev/null
python3 $ROOT/Scripts/encoder-check/hbparse.py $OUT/engine-now.txt | grep -E "fps" | grep -vE " 0\.0 fps  \|" > $OUT/engine-busy.txt
[[ ! -s $OUT/engine-busy.txt ]]
