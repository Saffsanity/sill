#!/bin/bash
# The agents' pair of simulators, made once and shared: "Sill agents Duo" (iPhone Duo, iOS 27.1) and
# "Sill agents iPad" (iPad Pro 13-inch (M5), iOS 27.0: the 27.1 runtimes take only the Duo), kept shut
# down between uses. harness-photos.sh boots
# one at a time and never any other simulator. Scripts/harness-photos/photos.py has the rules.
#   Scripts/agent-simulators.sh create    make whichever is missing (refused under 25 GB free)
#   Scripts/agent-simulators.sh list      both, their state and their size on disk, and the builds kept
exec python3 "$(cd "$(dirname "$0")" && pwd)/harness-photos/photos.py" simulators "$@"
