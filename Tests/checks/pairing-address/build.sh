#!/bin/bash
# usage: build.sh WT OUT [PairingWindowAddress.swift override]
# One module: StreamProtocol's sources, the host's AddressList and OriginPolicy (Noah's store goes
# through the real AddressList.build), the app's PairingWindowAddress and main.swift. Every
# `import StreamProtocol` is stripped, since it is all one module here. Nothing in WT is changed.
set -e
WT=$1; OUT=$2; T=$(mktemp -d)
cp $WT/Sources/StreamProtocol/*.swift $T/
sed '/^import StreamProtocol$/d' $WT/Sources/SillHost/AddressList.swift > $T/AddressList.swift
cp $WT/Sources/SillHost/OriginPolicy.swift $T/
sed '/^import StreamProtocol$/d' ${3:-$WT/Sources/SillMenuBar/PairingWindowAddress.swift} > $T/PairingWindowAddress.swift
cp $(dirname $0)/main.swift $T/main.swift
swiftc -O $T/*.swift -o $OUT 2>&1 | grep -E "error|warning: .*(PairingWindowAddress|main)\.swift" || true
rm -rf $T
