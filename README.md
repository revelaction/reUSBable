# luks-usb-transporter

`luks-usb-transporter` is a simple `bash` script to automate the creation of LUKS encrypted USB devices. 

Those USB devices can then be used to securely 'transport' sensitive data
between two computers, erasing any trace of previous data before each use.

https://user-images.githubusercontent.com/96388231/185803287-0e45bbb9-0ffe-42f2-a7ee-52a4de452443.mp4

`luks-usb-transporter` was tested on linux.

# Installation 

## Install script

    curl -LO https://raw.githubusercontent.com/revelaction/luks-usb-transporter/master/luks-usb-transporter.sh 
    # make it executable
    chmod +x luks-usb-transporter.sh
    # copy it to your path
    cp luks-usb-transporter.sh ~/bin

## Install dependencies

On debian based operating system, install (if not already present) the folowing:

    sudo apt install cryptsetup parted util-linux

Optionally for the command `shred` instead of `dd`:

    sudo apt install coreutils

# Usage

Run the scrypt with `sudo`:

    ⤷ sudo ./luks-usb-transporter.sh
    [sudo] password for revelaction:
    1) DataTraveler_3.0          /dev/sde     B0C54E757496FFB3K9F2
    2) PC404 NVMe SK hynix 128GB /dev/nvme0n1 JJAN590010307L4V
    [./luks-usb-transporter.sh] Please select the device: 1
    [./luks-usb-transporter.sh] Choosen device is 💽  /dev/sde (DataTraveler_3.0)
    [./luks-usb-transporter.sh] Choosen device has serial number 🔢  B0C54E757496FFB3K9F2
    [./luks-usb-transporter.sh] Unmounting all crypt mapper devices from device /dev/sde:
    [./luks-usb-transporter.sh] - Unmounting crypt dev mapper /dev/mapper/B0C54E757496FFB3K9F2_sde1
    [./luks-usb-transporter.sh] - Closing crypt /dev/mapper/B0C54E757496FFB3K9F2_sde1
    [./luks-usb-transporter.sh] Unmounting all partitions from device /dev/sde:
    [./luks-usb-transporter.sh] - Unmounting partition /dev/sde1
    umount: /dev/sde1: not mounted.
    [./luks-usb-transporter.sh] Detected command shred for shred the device /dev/sde
    [./luks-usb-transporter.sh] Press Enter to shred device /dev/sde
    ....
    
If you want to avoid confirmation in each step, run the script with the flag `-q`

    ⤷ sudo ./luks-usb-transporter.sh
    [sudo] password for revelaction:
    1) DataTraveler_3.0          /dev/sde     B0C54E757496FFB3K9F2
    2) PC404 NVMe SK hynix 128GB /dev/nvme0n1 JJAN590010307L4V
    [./luks-usb-transporter.sh] Please select the device: 1
    ...


# How it works

`luks-usb-transporter` should be run after (and before) using it for secure
transport of data between two computers.

`luks-usb-transporter` performs the following actions in a given USB (or other data device):

- It unmounts any previous partitions on the device.
- It shreds the entire device with the command `shred` (if present) or `dd`.
  This step can last many minutes/hours.
- It shreds the partition table of the device with `wipefs` and `dd`.
- It creates a new `gpt` partition table.
- It creates one partition using 100% of the device.
- It creates a LUKS2 partition on the previously create partition.
- It opens the LUKS2 partition and creates a ext4 filesystem inside.
- It mounts the filesystem in `/media/<user>`
