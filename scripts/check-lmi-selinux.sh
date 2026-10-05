#!/usr/bin/env bash
set -euo pipefail

if [[ $# != 3 || ${1:-} == --help ]]; then
    printf 'Usage: bash %s RAMDISK_DIRECTORY IMAGE_INFO HOST_TOOLS_DIRECTORY\n' "$0"
    [[ ${1:-} == --help ]] && exit 0
    exit 2
fi

ramdisk=$(realpath -e "$1")
image_info=$(realpath -e "$2")
host_tools=$(realpath -e "$3")
builder_root=$(realpath "$(dirname "$0")/..")
policy="$ramdisk/sepolicy"
test -s "$policy"
test -s "$ramdisk/file_contexts"
grep -aFq 'tar_extract_file(): invalid archived SELinux context' "$ramdisk/system/bin/recovery"
grep -aFq 'tar_extract_file(): SELinux relabel denied for context' "$ramdisk/system/bin/recovery"
grep -Eq '(^|[[:space:]])androidboot.selinux=enforcing([[:space:]]|$)' "$image_info"
if grep -Eq 'androidboot.selinux=permissive|(^|[[:space:]])enforcing=0([[:space:]]|$)' "$image_info"; then
    printf 'Recovery boot configuration disables enforcement\n' >&2
    exit 1
fi

permissive=$("$host_tools/sepolicy-analyze" "$policy" permissive)
if [[ -n $permissive ]]; then
    printf 'Permissive domains remain:\n%s\n' "$permissive" >&2
    exit 1
fi
"$host_tools/checkfc" "$policy" "$ramdisk/file_contexts"
"$host_tools/checkfc" -T "$ramdisk/file_contexts" "$builder_root/port/lmi/sepolicy-labels.txt"
"$host_tools/sepolicy-analyze" "$policy" attribute -r recovery | grep -Fxq mlstrustedsubject

check_rule() {
    local expected=$1 source=$2 target=$3 class=$4 permission=$5 result status
    # This pinned Android tool returns 1 for a match, 0 for no match, not Unix success.
    if result=$("$host_tools/sepolicy-check" -s "$source" -t "$target" \
        -c "$class" -p "$permission" -P "$policy" 2>&1); then
        status=0
    else
        status=$?
    fi
    case "$expected:$status:$result" in
        'allow:1:Match found!'|'deny:0:') ;;
        *) printf 'Unexpected %s rule: %s -> %s:%s %s (%s)\n%s\n' \
            "$expected" "$source" "$target" "$class" "$permission" "$status" "$result" >&2
           return 1 ;;
    esac
}

check_rule allow init recovery process transition
check_rule allow recovery lmi_recovery_exec file entrypoint
check_rule allow init tee process transition
check_rule allow init hal_keymaster_default process transition
check_rule allow init hal_gatekeeper_default process transition
check_rule allow hal_keymaster_default hal_keymaster_hwservice hwservice_manager add
check_rule allow hal_gatekeeper_default hal_gatekeeper_hwservice hwservice_manager add
check_rule allow recovery hal_keymaster_hwservice hwservice_manager find
check_rule allow recovery hal_gatekeeper_hwservice hwservice_manager find
check_rule allow recovery vold_key keystore2_key manage_blob
check_rule allow recovery vold_key keystore2_key convert_storage_key_to_ephemeral
check_rule allow recovery locksettings_key keystore2_key use
check_rule allow recovery keystore keystore2 add_auth
check_rule allow recovery app_data_file dir read
check_rule allow recovery app_data_file file write
check_rule allow recovery app_data_file file relabelfrom
check_rule allow recovery app_data_file file relabelto
check_rule allow recovery kernel security check_context
check_rule allow recovery kernel security compute_av
check_rule allow recovery selinuxfs file write
for domain in tee hal_keymaster_default hal_gatekeeper_default; do
    check_rule allow "$domain" vendor_file file execute
done
check_rule allow recovery property_data_file file write
check_rule allow recovery stats_data_file file write
check_rule allow recovery credstore_data_file file write
check_rule allow recovery incident_data_file file write
check_rule allow recovery vold_data_file file write
check_rule allow recovery vold_metadata_file file read
check_rule allow recovery keystore_data_file file read
check_rule allow recovery lmi_keystore_tmp_file file write
check_rule allow recovery build_prop file write
check_rule allow recovery lmi_ramdisk_prop_file file write
check_rule allow tee lmi_tee_listener_prop property_service set
check_rule allow hwservicemanager lmi_hwservice_ready_prop property_service set
check_rule deny recovery hal_keymaster_hwservice hwservice_manager add
check_rule deny recovery hal_gatekeeper_hwservice hwservice_manager add
check_rule deny recovery kernel security setenforce
check_rule deny recovery kernel security load_policy
check_rule deny recovery app_data_file file execute
check_rule deny recovery nativetest_data_file file execute
check_rule deny recovery system_file file write
check_rule deny recovery system_file file relabelto
check_rule deny recovery vendor_file file write
check_rule deny recovery vendor_file file relabelto
check_rule deny recovery properties_device file write
check_rule deny recovery rootfs file write
check_rule deny recovery vold_metadata_file file write
check_rule deny recovery vold_metadata_file file relabelfrom
check_rule deny recovery vold_metadata_file file relabelto
check_rule deny recovery vold_metadata_file dir add_name
check_rule deny recovery keystore_data_file file write
check_rule deny recovery keystore_data_file file relabelfrom
check_rule deny recovery keystore_data_file file relabelto
check_rule deny recovery keystore_data_file dir add_name
check_rule deny recovery lmi_keystore_tmp_file file execute
check_rule deny recovery lmi_keystore_tmp_file file relabelto
check_rule deny recovery keystore keystore2 clear_ns

init_rc="$ramdisk/system/etc/init/hw/init.rc"
test -s "$init_rc"
grep -Fqx '    restorecon_recursive /system/bin /system/lib /system/lib64 /system/etc' "$init_rc"
grep -Fqx '    restorecon /prop.default' "$init_rc"
grep -Fq 'update_default_prop ro.build.version.release' "$ramdisk/system/bin/prepdecrypt.sh"
if grep -Fq 'sed -i' "$ramdisk/system/bin/prepdecrypt.sh"; then
    printf 'Crypto preparation still requires mutable rootfs directory entries\n' >&2
    exit 1
fi
grep -Fq -- '--root_seclabel=u:r:recovery:s0' "$init_rc"
for service in hwservicemanager servicemanager vndservicemanager keystore2; do
    rc="$ramdisk/system/etc/init/$service.rc"
    test -s "$rc"
    if grep -Fq 'seclabel u:r:recovery:s0' "$rc"; then
        printf '%s still shares the GUI recovery domain\n' "$service" >&2
        exit 1
    fi
done
for service in qseecomd keymaster-4-0-qti gatekeeper-1-0-qti; do
    if [[ $service == gatekeeper* ]]; then
        rc="$ramdisk/init.recovery.qcom_decrypt.fbe.rc"
    else
        rc="$ramdisk/init.recovery.qcom_decrypt.rc"
    fi
    test -s "$rc"
    section=$(awk -v service="$service" \
        '$1 == "service" { active = ($2 == service) } active { print }' "$rc")
    test -n "$section"
    if grep -Fq 'seclabel u:r:recovery:s0' <<< "$section"; then
        printf '%s still shares the GUI recovery domain\n' "$service" >&2
        exit 1
    fi
done
test "$(readlink "$ramdisk/system/bin/bootstrap/linker64")" = /system/bin/linker64
test "$(readlink "$ramdisk/system/bin/bootstrap/linker")" = /system/bin/linker
printf 'SELinux candidate verified: no permissive domains; labels, crypto access and isolation gates pass\n'
