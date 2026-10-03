#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 1 || $1 == --help ]]; then
    printf 'Usage: bash %s ANDROID_SOURCE_DIRECTORY\n' "$0"
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

source_root=$(realpath -e "$1")
kernel_source="${source_root}-inputs/kernel"
kernel_out="${source_root}-inputs/kernel-out"
device_prebuilt="$source_root/device/xiaomi/lmi/prebuilt"
test -f "$kernel_source/Makefile"

shopt -s nullglob
clang_dirs=("$source_root"/prebuilts/clang/host/linux-x86/clang-r*/bin)
test "${#clang_dirs[@]}" -gt 0
clang_bin=$(printf '%s\n' "${clang_dirs[@]}" | sort -V | tail -n 1)
export PATH="$clang_bin:$PATH"
clang --version

# The bundled kernel DTC creates local fragment targets that UFDT cannot resolve.
make -C "$source_root/external/dtc" -j2 NO_PYTHON=1 NO_YAML=1 dtc
"$source_root/external/dtc/dtc" --version

make_args=(
    -C "$kernel_source" O="$kernel_out" ARCH=arm64 LLVM=1 LLVM_IAS=1
    CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- CLANG_TRIPLE=aarch64-linux-gnu-
    HOSTCFLAGS=-fcommon
    DTC_EXT="$source_root/external/dtc/dtc"
)
mkdir -p "$kernel_out" "$device_prebuilt/dtb"
make "${make_args[@]}" vendor/kona-perf_defconfig
for fragment in vendor/debugfs.config vendor/xiaomi/sm8250-common.config vendor/xiaomi/lmi.config; do
    "$kernel_source/scripts/kconfig/merge_config.sh" -m -O "$kernel_out" \
        "$kernel_out/.config" "$kernel_source/arch/arm64/configs/$fragment"
    make "${make_args[@]}" olddefconfig
done

for option in FS_ENCRYPTION DM_DEFAULT_KEY BLK_INLINE_ENCRYPTION QSEECOM F2FS_FS MACH_XIAOMI_LMI; do
    grep -qx "CONFIG_${option}=y" "$kernel_out/.config"
done
make "${make_args[@]}" -j2 Image dtbs
cp "$kernel_out/arch/arm64/boot/Image" "$device_prebuilt/kernel"
for dtb in kona kona-v2 kona-v2.1; do
    cp "$kernel_out/arch/arm64/boot/dts/vendor/qcom/$dtb.dtb" "$device_prebuilt/dtb/"
done
python3 "$source_root/system/libufdt/utils/src/mkdtboimg.py" create \
    "$device_prebuilt/dtbo.img" --page_size=4096 \
    "$kernel_out/arch/arm64/boot/dts/vendor/qcom/lmi-sm8250-overlay.dtbo"
cp "$kernel_out/.config" "$device_prebuilt/kernel.config"
(
    cd "$device_prebuilt"
    sha256sum kernel dtb/*.dtb dtbo.img kernel.config > KERNEL-SHA256SUMS
)
