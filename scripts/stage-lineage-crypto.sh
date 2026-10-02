#!/usr/bin/env bash
set -euo pipefail

source_root=$(realpath -e "${1:?Usage: stage-lineage-crypto.sh ANDROID_SOURCE_DIRECTORY}")
vendor_source="${source_root}-inputs/vendor-common"
device_root="$source_root/device/xiaomi/lmi/recovery/root"
revision=b4a9f9ab59190887fee4d882ff10a1a3cc7e7712

GIT_MASTER=1 git init "$vendor_source"
GIT_MASTER=1 git -C "$vendor_source" remote add origin \
    https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common.git
GIT_MASTER=1 git -C "$vendor_source" sparse-checkout set \
    proprietary/vendor/lib64 proprietary/vendor/bin/hw proprietary/vendor/bin/qseecomd
GIT_MASTER=1 git -C "$vendor_source" fetch --filter=blob:none --depth=1 origin "$revision"
GIT_MASTER=1 git -C "$vendor_source" checkout --detach FETCH_HEAD

mkdir -p "$device_root/system/bin" "$device_root/vendor/lib64/hw"
binaries=(qseecomd android.hardware.keymaster@4.0-service-qti android.hardware.gatekeeper@1.0-service-qti)
for binary in "${binaries[@]}"; do
    if [[ $binary == qseecomd ]]; then
        source_file="$vendor_source/proprietary/vendor/bin/$binary"
    else
        source_file="$vendor_source/proprietary/vendor/bin/hw/$binary"
    fi
    cp "$source_file" "$device_root/system/bin/"
    chmod 755 "$device_root/system/bin/$binary"
done
cp "$vendor_source/proprietary/vendor/lib64/hw/android.hardware.gatekeeper@1.0-impl-qti.so" \
    "$device_root/vendor/lib64/hw/"

queue=("$device_root/system/bin/"* "$device_root/vendor/lib64/hw/"*)
declare -A copied=()
for ((index=0; index<${#queue[@]}; index++)); do
    mapfile -t dependencies < <(LC_ALL=C readelf -d "${queue[index]}" | \
        sed -n 's/.*(NEEDED).*\[\(.*\)\].*/\1/p')
    for library in "${dependencies[@]}"; do
        vendor_library="$vendor_source/proprietary/vendor/lib64/$library"
        if [[ -f $vendor_library && -z ${copied[$library]:-} ]]; then
            copied[$library]=1
            cp "$vendor_library" "$device_root/vendor/lib64/"
            queue+=("$device_root/vendor/lib64/$library")
        fi
    done
done

printf 'LineageOS 23.2 crypto vendor: https://github.com/TheMuppets/proprietary_vendor_xiaomi_sm8250-common/commit/%s\n' \
    "$revision" >> "$source_root/device/xiaomi/lmi/PORT-SOURCES.txt"
(
    cd "$device_root"
    sha256sum system/bin/* vendor/lib64/*.so vendor/lib64/hw/*.so
) > "$source_root/device/xiaomi/lmi/CRYPTO-SHA256SUMS"
