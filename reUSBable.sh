#!/bin/bash
set -eu
set -o pipefail

readonly LUKS_TYPE='luks2'
# exclude mem devices from menu
readonly EXCLUDED_DEVICES_MAJOR='1,7'
readonly PROGNAME=$(basename $0)

usage() {
    cat <<- EOF
usage: ${PROGNAME:-} [<Options>]

${PROGNAME:-} is a simple bash script to automate the creation of LUKS
encrypted USB devices.

Those USB devices can then be used to securely 'transport' sensitive data
between two computers, erasing any trace of previous data before each use.

Options:
   -q Do not ask for confirmation (only the LUKS password will be requested)
   -m Mount the LUKS partition after creation.
   -h --help            Show this help


Examples:
   Shred the device, creete a new partition while confirming each step:
   $PROGNAME  

   
   Shred the device, create a new partition without confirming each step:
   $PROGNAME -q 

   
   Shred the device, create a new partition. Mount the device after creation
   $PROGNAME -m 
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

ask_confirmation(){
    if [[ ${QUIET:-0} = 1 ]]; then
        return 0
    fi
    exec </dev/tty >/dev/tty
    local msg_default='Press Enter'
    local msg="${1:-"$msg_default"}"
    echo -e "$msg"
    read
}

shred_device()
{
    local path="${1}"
    if [[ $(command_exist shred) = 1 ]]; then
        fmt "Detected command @@ok%s for shred the device @@ok%s\n" "shred" "${path}"
        shred_device_shred "${path}"
    else
        fmt "Using command @@ok%s for shred the device @@ok%s\n" "dd" "${path}"
        shred_device_dd "${path}"
    fi
}    

shred_device_dd()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to shred device @@ok%s" "${path}")"
    fmt "Erasing device @@ok%s with dd command\n" "${path}"
    dd if=/dev/urandom of=${path} bs=1M status=progress
    #dd if=/dev/zero of=${path} bs=1M status=progress
    # |TODO dd: error writing '/dev/sda': No space left on device
    sync
}

shred_device_shred()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to shred device @@ok%s" "${path}")"
    fmt "Erasing device @@ok%s with scred command\n" "${path}"

    shred -v -n1 -z ${path}
    sync
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

shred_partition_table()
{
    local path="${1}"
    if [[ $(command_exist wipefs) = 1 ]]; then
        fmt "Detected command @@ok%s for shred the partition table of @@ok%s\n" "wipefs" "${path}"
        shred_partition_table_wipefs "${path}"
    fi

    fmt "Using command @@ok%s for shred the partition table of @@ok%s\n" "dd" "${path}"
    shred_partition_table_dd "${path}"
}

shred_partition_table_dd()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to shred @@ok%s of @@ok%s" "the partition table" "${path}")"

    fmt "Shreding partition table in @@ok%s with @@ok%s command\n" "${path}" "dd"
    # This will zap the MBR of the drive (Data is still intact).
    dd if=/dev/zero of=${path} bs=512 count=1 conv=notrunc
    sync
}

shred_partition_table_wipefs()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to shred @@ok%s of @@ok%s" "the partition table" "${path}")"
    fmt "Shreding partition table in @@ok%s with @@ok%s command\n" "${path}" "wipefs" 
    wipefs -a ${DEVICE_PATH}
    sync
}

create_partition_table()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to create @@ok%s in @@ok%s" "a new partition table" "${path}")"
    parted ${path} mklabel gpt 
}

create_partition()
{
    local path="${1}"
    ask_confirmation "$(fmt "Press Enter to create @@ok%s in @@ok%s" "a new partition" "${path}")"
    #parted --align optimal ${1} mkpart primary ext4 0% 100%
    #parted ${path} mkpart primary 2048s 100%
    parted ${path} mkpart primary 0% 100%
}

print_partition_table()
{
    parted ${1} print
}

create_luks_partition()
{
    local partition="${1}"
    ask_confirmation "$(fmt "Press Enter to create @@ok%s in @@ok%s" "a LUKS partition" "${partition}")"
    fmt "Creating LUKS partition in @@ok%s:\n" "${partition}"
    cryptsetup -v --type ${LUKS_TYPE} luksFormat ${partition}
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
    ask_confirmation "$(fmt "Press Enter to unlock @@ok%s in /dev/mapper/@@ok%s" "the luks partition" "${d_mapper_label}")"
    fmt "Open LUKS partition @@ok%s mapped to /dev/mapper/@@ok%s:\n" "${part}" "${dev_mapper_label}"
    cryptsetup open ${part} ${dev_mapper_label}
}

create_filesytem()
{
    local dev_mapper_label="${1}"
    fmt "Creating ext4 filesystem in /dev/mapper/@@ok%s:\n" "${dev_mapper_label}"
    mkfs.ext4 /dev/mapper/${dev_mapper_label}
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

list_devices()
{
    fmt "Found following devices:\n\n" 
    lsblk -e "${EXCLUDED_DEVICES_MAJOR}" -x SERIAL -ndo MODEL,PATH,SERIAL
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
    while getopts ":hqu" option; do
        case $option in
            h) # display Help
                usage
                exit;;
            q) 
                readonly QUIET=1
                ;;
            m) 
                readonly MOUNT=1
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

get_previous_user()
{
    local uw="$(who am i | cut -d ' ' -f1)"
    local ul="$(logname)"
    if [ ! -z "${uw}" ]; then
        echo -n "${uw}"
        return 0
    elif [ ! -z "${ul}" ]; then
        echo -n "${ul}"
        return 0
    else
        echo "Could not found previous user"
        exit 1
    fi
}

main()
{
    check_sudo
    readonly previous_user="$(get_previous_user)"

    check_command cryptsetup
    check_command lsblk
    check_command parted
    check_command dd
    check_command mkfs.ext4

    parse_options "$@"
    select_device 

    unmount_device_crypt_mapper_volume "${DEVICE_PATH}"
    unmount_device_partitions "${DEVICE_PATH}"

    shred_device "${DEVICE_PATH}"
    shred_partition_table "${DEVICE_PATH}"
    create_partition_table "${DEVICE_PATH}"
    print_partition_table "${DEVICE_PATH}"
    create_partition "${DEVICE_PATH}"
    print_partition_table "${DEVICE_PATH}"

    d_partition=$(get_partition "${DEVICE_PATH}")
    fmt "Created partiion @@ok%s in device @@ok%s\n\n" "${d_partition}" "${DEVICE_PATH}"

    create_luks_partition "$d_partition"

    d_partition_name=$(get_partition_name "${DEVICE_PATH}")
    d_mapper_label=$(build_dev_mapper_label "$DEVICE_SERIAL" "$d_partition_name")
    unlock_luks_partition "$d_partition" "${d_mapper_label}"

    create_filesytem "${d_mapper_label}"

    # always mount for permissions
    readonly mount_dir=/media/"${previous_user}"/"${DEVICE_SERIAL}"
    mount_filesystem "${d_mapper_label}" "${previous_user}" "${mount_dir}"

    # Stop if not -m flag
    if [[ ${MOUNT:-0} == 0 ]]; then
        sleep 3
        unmount_device_crypt_mapper_volume "${DEVICE_PATH}"
        unmount_device_partitions "${DEVICE_PATH}"
        fmt "🎉 Done!\n"
        exit 0
    fi

    fmt "🎉 Done! You can copy files now to the directory @@ok%s\n" "${mount_dir}"
}

main "$@"
