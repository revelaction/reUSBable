#!/bin/bash
set -eu
set -o pipefail

# exclude mem devices from menu
readonly EXCLUDED_DEVICES_MAJOR='1,7'
readonly PROGNAME=$(basename $0)

usage() {
    cat <<- EOF
usage: ${PROGNAME:-} [<Options>]

${PROGNAME:-} is a simple bash script to mount and unmount LUKS encrypted USB
devices.

Options:
   -u Unmount the LUKS partition after creation.
   -h Show this help

Examples:
   Mount the LUKS partition
   $PROGNAME  

   Unmount all partitions of the device
   $PROGNAME -u 
EOF
}

command_exist() {
    local cmd="${1:-}"

    # to func
    if hash "${cmd}" 2>/dev/null; then
        echo "1"
    else
        echo "0"
    fi
}

check_command() {
    local cmd="${1:-}"

    if [[ $(command_exist $cmd) = 0 ]]; then
        fmt "Could not find command @@bad%s. Please install it.\n" "${cmd}"
        exit 1

    fi
}

fmt ()      {
  local color_ok="\x1b[32m"
  local color_bad="\x1b[31m"
  local color_reset="\x1b[0m"
  local color_yellow="\x1b[33m"
  local str="$1"
  shift
  local tmplcolored=$(echo "${str}" | \
      sed -r -e "s/@@bad%([sd])/${color_bad}%\1${color_reset}/g" \
      -e "s/@@ylw%([sd])/${color_yellow}%\1${color_reset}/g" \
      -e "s/@@ok%([sd])/${color_ok}%\1${color_reset}/g" \
  )
  printf "${color_yellow}[%s]${color_reset} ${tmplcolored}" "$0" "${@}"
}

check_sudo() {
    if [[ $UID != 0 ]]; then
        fmt "@@bad%s Please run this script with sudo: @@ok%s \n\n" "No sudo:" "sudo $0 $*"
        exit 1
    fi
}

unmount_device_crypt_mapper_volume()
{
    fmt "Unmounting all crypt mapper devices from device @@ok%s:\n" "${1}"
    readarray -t dev_mappers < <(lsblk -lo PATH,TYPE ${1} | grep crypt | cut -d ' ' -f1)
    for p in "${dev_mappers[@]}"
    do
        fmt "- Unmounting crypt dev mapper @@ok%s\n" "${p}"
        umount ${p} || /bin/true
        fmt "- Closing crypt @@ok%s\n" "${p}"
        cryptsetup luksClose ${p}
    done
}

unmount_device_partitions()
{
    fmt "Unmounting all partitions from device @@ok%s:\n" "${1}"
    readarray -t partitions < <(lsblk -lo PATH,TYPE ${1} | grep part | cut -d ' ' -f1)
    for p in "${partitions[@]}"
    do
        fmt "- Unmounting partition @@ok%s\n" "${p}"
        umount ${p} || /bin/true
    done
}

build_dev_mapper_label()
{
    local serial="${1}"
    local part_name="${2}"
    # get only the name from the partition

    printf '%s_%s' "${serial}" "${part_name}"
}

unlock_luks_partition()
{
    local part="${1}"
    local dev_mapper_label="${2}"
    fmt "Open LUKS partition @@ok%s mapped to /dev/mapper/@@ok%s:\n" "${part}" "${dev_mapper_label}"
    cryptsetup open ${part} ${dev_mapper_label}
}

mount_filesystem()
{
    local dev_mapper_label="${1}"
    local user="${2}"
    local d="${3}"
    fmt "Creating directory @@ok%s\n" "${d}"
    mkdir -p ${d} 

    fmt "Previous/Non sudo user is @@ok%s\n" "${user}"
    chown ${user}:${user} ${d} 

    fmt "Mounting /dev/mapper/@@ok%s in @@ok%s\n" "${dev_mapper_label}" "${d}"
    mount /dev/mapper/${dev_mapper_label} ${d}
    chown -R ${user}:${user} ${d} 
}

get_partition()
{
    # TODO PATH only ubuntu 20
    local p="$(lsblk -lo PATH,TYPE ${1} | grep part | cut -d ' ' -f1)"
    echo -n "${p}"
}

# without /dev/
get_partition_name()
{
    local p="$(lsblk -lo NAME,TYPE ${1} | grep part | cut -d ' ' -f1)"
    # print
    echo -n "${p}"
} 

parse_options()
{
    local OPTIND option
    while getopts ":hu" option; do
        case $option in
            h) # display Help
                usage
                exit;;
            u) 
                readonly UMOUNT=1
                ;;
            \?) # Invalid option
                fmt "Error: @@bad%s\n" "Invalid option"
                usage
                exit;;
        esac
    done
    shift $((OPTIND-1))
} 

select_device()
{
    readarray -t serial < <(lsblk -e "${EXCLUDED_DEVICES_MAJOR}" -x SERIAL -ndo SERIAL)
    readarray -t dev_path < <(lsblk -e "${EXCLUDED_DEVICES_MAJOR}" -x SERIAL -ndo PATH)
    readarray -t model < <(lsblk -e "${EXCLUDED_DEVICES_MAJOR}" -x SERIAL -ndo MODEL)
    readarray -t humanReadable < <(lsblk -e "${EXCLUDED_DEVICES_MAJOR}" -x SERIAL -ndo MODEL,PATH,SERIAL,SIZE)

    num_devices=${#dev_path[@]}
    if [ ${num_devices} -eq 0 ]; then
        fmt "Found no devices\n"
        exit 0
    fi

    PS3=$(fmt "Please select the device: ")
    select opt in "${humanReadable[@]}"
    do
        # validate selected number
        if [[ ${REPLY} < 1 || ${REPLY} > ${num_devices} ]]; then
            fmt "Invalid selection: @@bad%s.\n" "${REPLY}"
            continue
        fi

        readonly index=$((REPLY-1))
        break
    done

    readonly DEVICE_PATH=${dev_path[$index]}
    if [ -z "${DEVICE_PATH}" ]
    then
        fmt "Device is empty\n"
        exit 1
    fi

    readonly DEVICE_SERIAL=${serial[$index]}

    local d_model=${model[$index]}
    fmt "Choosen device is 💽  @@ok%s (@@ok%s)\n" "${DEVICE_PATH}" "${d_model}"
    fmt "Choosen device has serial number 🔢  @@ok%s\n" "${DEVICE_SERIAL}"
}

main()
{
    check_sudo
    readonly previous_user="$(who am i | cut -d ' ' -f1)"

    check_command cryptsetup
    check_command lsblk

    parse_options "$@"
    select_device 

    unmount_device_crypt_mapper_volume "${DEVICE_PATH}"
    unmount_device_partitions "${DEVICE_PATH}"

    if [[ ${UMOUNT:-0} == 1 ]]; then
        fmt "🎉 Done!\n"
        exit 0
    fi

    d_partition=$(get_partition "${DEVICE_PATH}")

    d_partition_name=$(get_partition_name "${DEVICE_PATH}")
    d_mapper_label=$(build_dev_mapper_label "$DEVICE_SERIAL" "$d_partition_name")
    unlock_luks_partition "$d_partition" "${d_mapper_label}"

    readonly dir=/media/"${previous_user}"/"${d_mapper_label}"
    mount_filesystem "${d_mapper_label}" "${previous_user}" "${dir}"

    fmt "🎉 Done! You can copy files now to the directory @@ok%s\n" "${dir}"
}

main "$@"
