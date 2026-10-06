#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 == --help ]]; then
    printf 'Usage: bash %s ANDROID_SOURCE_DIRECTORY\n' "$0"
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

source_root=$(realpath -e "$1")
builder_root=$(realpath "$(dirname "$0")/..")
ramdisk="$source_root/device/xiaomi/lmi/recovery/root"
test -f "$source_root/build/envsetup.sh"
test -f "$source_root/device/xiaomi/lmi/BoardConfig.mk"

# The patch is reviewed against these exact manifest inputs, not moving branches.
for input in \
    system/sepolicy:9641d92817ae79b2d4cd02dfe5c24de7de2014b4 \
    system/vold:953de9608eb78380b3c4e39e801c2bc0af7dbddc \
    bootable/recovery:0f7831d3240f4c3925a0b5fd7d2c907ddf8704c2 \
    device/qcom/twrp-common:98506f7919102378c8d52ee7d6a94a867f1b4c55; do
    project=${input%%:*}
    revision=${input#*:}
    test "$(GIT_MASTER=1 git -C "$source_root/$project" rev-parse HEAD)" = "$revision"
done

for policy_patch in recovery-selinux.patch recovery-data-policy.patch recovery-ramdisk-props.patch recovery-restore-labels.patch recovery-user-decryption.patch; do
    patch --dry-run --batch --fuzz=0 -d "$source_root" -p1 \
        < "$builder_root/port/lmi/$policy_patch"
    patch --batch --fuzz=0 -d "$source_root" -p1 \
        < "$builder_root/port/lmi/$policy_patch"
done

# Init must not create linker entries in an immutable, correctly labeled /system.
# Do this after crypto staging, whose checksums cover files in system/bin/*.
mkdir -p "$ramdisk/system/bin/bootstrap"
for linker in linker linker64 linker_asan linker_asan64 linker_hwasan64; do
    case "$linker" in
        linker|linker_asan) target=linker ;;
        *) target=linker64 ;;
    esac
    ln -s "/system/bin/$target" "$ramdisk/system/bin/bootstrap/$linker"
done

{
    printf 'SELinux: permissive boot, Recovery-only data exceptions, neverallow checks enabled\n'
    printf 'Recovery SELinux patch SHA256: %s\n' \
        "$(sha256sum "$builder_root/port/lmi/recovery-selinux.patch" | cut -d ' ' -f1)"
    printf 'Recovery data-policy patch SHA256: %s\n' \
        "$(sha256sum "$builder_root/port/lmi/recovery-data-policy.patch" | cut -d ' ' -f1)"
    printf 'Recovery RAMDISK property patch SHA256: %s\n' \
        "$(sha256sum "$builder_root/port/lmi/recovery-ramdisk-props.patch" | cut -d ' ' -f1)"
    printf 'Recovery restore-label patch SHA256: %s\n' \
        "$(sha256sum "$builder_root/port/lmi/recovery-restore-labels.patch" | cut -d ' ' -f1)"
    printf 'Recovery secondary-user decryption patch SHA256: %s\n' \
        "$(sha256sum "$builder_root/port/lmi/recovery-user-decryption.patch" | cut -d ' ' -f1)"
} >> "$source_root/device/xiaomi/lmi/PORT-SOURCES.txt"
