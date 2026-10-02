#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 == --help ]]; then
    printf 'Usage: bash %s ANDROID_SOURCE_DIRECTORY\n' "$0"
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

source_root=$(realpath -e "$1")
builder_root=$(realpath "$(dirname "$0")/..")
inputs="${source_root}-inputs"
device="$source_root/device/xiaomi/lmi"
test -f "$source_root/build/envsetup.sh"
test ! -e "$device"
mkdir -p "$inputs" "$device"

clone_revision() {
    GIT_MASTER=1 git init "$3"
    GIT_MASTER=1 git -C "$3" remote add origin "$1"
    GIT_MASTER=1 git -C "$3" fetch --depth=1 origin "$2"
    GIT_MASTER=1 git -C "$3" checkout --detach FETCH_HEAD
    test "$(GIT_MASTER=1 git -C "$3" rev-parse HEAD)" = "$2"
}

clone_revision https://github.com/OctopusROM/device_xiaomi_lmi.git \
    3c3e3b87aad9f2fcf0d604b104e340c2c69e58c1 "$inputs/lmi"
clone_revision https://github.com/OctopusROM/device_xiaomi_sm8250-common.git \
    4fe792ee4c690c9eaf315ee5ab5ea373012a317f "$inputs/sm8250-common"
clone_revision https://github.com/Nyxal-GH/android_kernel_xiaomi_sm8250.git \
    712e4dee69ed5c4fedad123bf39de4bd0d31394b "$inputs/kernel"

cp -a "$builder_root/port/lmi/." "$device/"
cp "$inputs/sm8250-common/rootdir/etc/fstab.qcom" \
    "$device/recovery/root/system/etc/recovery.fstab"
sed -i -E 's/,avb_keys=[^,[:space:]]+//g; s/,avb(=[^,[:space:]]+)?//g; s/,first_stage_mount//g' \
    "$device/recovery/root/system/etc/recovery.fstab"
cp "$inputs/sm8250-common/rootdir/etc/init.recovery.qcom.rc" \
    "$device/recovery/root/init.recovery.qcom.rc"
cp "$inputs/sm8250-common/rootdir/etc/ueventd.qcom.rc" \
    "$device/recovery/root/ueventd.qcom.rc"
cat >> "$device/recovery/root/init.recovery.qcom.rc" <<'RC'

import /init.recovery.qcom_decrypt.rc

on early-init
    symlink /vendor/firmware_mnt /firmware
    symlink /vendor/bt_firmware /bt_firmware
    symlink /vendor/dsp /dsp
RC

cat > "$device/PORT-SOURCES.txt" <<SOURCES
Recovery target: lmi, A-only, boot header 2, recovery partition 134217728 bytes
Decryption target: LineageOS 23.2 / Android 16
Platform: OrangeFox fox_16.0 (exact projects in manifest.xml build artifact)
Recovery configuration: $(GIT_MASTER=1 git -C "$builder_root" rev-parse HEAD)
ROM device: https://github.com/OctopusROM/device_xiaomi_lmi/commit/3c3e3b87aad9f2fcf0d604b104e340c2c69e58c1
ROM common: https://github.com/OctopusROM/device_xiaomi_sm8250-common/commit/4fe792ee4c690c9eaf315ee5ab5ea373012a317f
Kernel source: https://github.com/Nyxal-GH/android_kernel_xiaomi_sm8250/commit/712e4dee69ed5c4fedad123bf39de4bd0d31394b
Kernel configuration: vendor/kona-perf_defconfig, vendor/debugfs.config, vendor/xiaomi/sm8250-common.config, vendor/xiaomi/lmi.config
Data encryption flags retained from ROM fstab: fileencryption=ice,wrappedkey,keydirectory=/metadata/vold/metadata_encryption
No MIUI 12 recovery donor kernel or blob package is used.
SOURCES

bash "$builder_root/scripts/stage-lineage-crypto.sh" "$source_root"
