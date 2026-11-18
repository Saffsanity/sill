#!/bin/bash
# Harness photos of a commit (and a baseline, compared pixel by pixel) on the agents' own simulator,
# one build per commit, inside the heavy lock: Scripts/harness-photos/photos.py says it all.
#   Scripts/harness-photos.sh CASES [--commit REV] [--baseline REV] [--device duo|ipad] [--repo DIR]
#   Scripts/harness-photos.sh --help
exec python3 "$(cd "$(dirname "$0")" && pwd)/harness-photos/photos.py" "$@"
