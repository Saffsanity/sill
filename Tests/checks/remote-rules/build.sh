#!/bin/bash
# usage: build.sh WT OUT [DiscoveryPolicy override] [RemoteDialPolicy override] [SavedMacs override]
# Compiles the device's pure parts with StreamProtocol's sources as one module.
WT=$1; OUT=$2; T=$(mktemp -d)
cp $WT/Sources/StreamProtocol/*.swift $T/
for f in "${3:-$WT/iOSClient/DiscoveryPolicy.swift}" "${4:-$WT/iOSClient/RemoteDialPolicy.swift}" "${5:-$WT/iOSClient/SavedMacs.swift}"; do
  sed '/^import StreamProtocol$/d' "$f" > $T/$(basename "$f")
done
cp $(dirname $0)/main.swift $T/main.swift
swiftc -O $T/*.swift -o $OUT 2>&1 | grep -E "error" ; rm -rf $T
