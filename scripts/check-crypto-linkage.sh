#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 == --help ]]; then
    printf 'Usage: bash %s RECOVERY_RAMDISK_DIRECTORY\n' "$0"
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

ramdisk=$(realpath -e "$1")
checker=$(realpath "$(dirname "$0")/../tools/ldcheck")
cd "$ramdisk"

binaries=(
    system/bin/recovery
    system/bin/qseecomd
    system/bin/android.hardware.keymaster@4.0-service-qti
    system/bin/android.hardware.gatekeeper@1.0-service-qti
    system/bin/keystore2
    system/lib64/libfscrypt.so
    vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so
)
for binary in "${binaries[@]}"; do
    test -s "$binary"
    report=$(LC_ALL=C python3 "$checker" -p vendor/lib64:vendor/lib64/hw:system/lib64 "$binary" 2>&1)
    printf '%s\n%s\n' "$binary" "$report"
    if grep -Eq 'UNRESOLVED #####|No such file|file format not recognized|Traceback|readelf: Error' <<< "$report"; then
        exit 1
    fi
done
