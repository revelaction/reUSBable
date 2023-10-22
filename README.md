<p align="center"><img alt="reUSBable" src="logo.png"/></p>

[![GitHub Release](https://img.shields.io/github/v/release/revelaction/reUSBable?style=flat)]() 

`reUSBable` is a simple bash script to automate the creation of LUKS encrypted USB devices. 

The devices can then be used to securely 'transport' sensitive data
between two computers, erasing any trace of previous data before each use,
making the USB devices **reusable**.

- [Installation](#installation)
- [usage](#usage)
- [How does it work](#how-does-it-work)
- [mount luks script](#mount-luks-script)

https://user-images.githubusercontent.com/96388231/185803287-0e45bbb9-0ffe-42f2-a7ee-52a4de452443.mp4

`reUSBable` was tested on linux.

# Installation 

## Install dependencies

On debian based operating system, install (if not already present) the folowing:

```console
sudo apt install cryptsetup parted util-linux
```

Optionally for the command `shred` instead of `dd`:

```console
sudo apt install coreutils
```

## Install script

```console
curl -LO https://raw.githubusercontent.com/revelaction/reUSBable/master/reUSBable.sh 
# make it executable
chmod +x reUSBable.sh
# copy it to your path
cp reUSBable.sh ~/bin
```

# Usage

Run the scrypt with `sudo`:

```console
⤷ sudo ./reUSBable.sh
[sudo] password for revelaction:
1) DataTraveler_3.0          /dev/sde     B0C54E757496FFB3K9F2
2) PC404 NVMe SK hynix 128GB /dev/nvme0n1 JJAN590010307L4V
[./reUSBable.sh] Please select the device: 1
[./reUSBable.sh] Choosen device is 💽  /dev/sde (DataTraveler_3.0)
[./reUSBable.sh] Choosen device has serial number 🔢  B0C54E757496FFB3K9F2
[./reUSBable.sh] Unmounting all crypt mapper devices from device /dev/sde:
[./reUSBable.sh] - Unmounting crypt dev mapper /dev/mapper/B0C54E757496FFB3K9F2_sde1
[./reUSBable.sh] - Closing crypt /dev/mapper/B0C54E757496FFB3K9F2_sde1
[./reUSBable.sh] Unmounting all partitions from device /dev/sde:
[./reUSBable.sh] - Unmounting partition /dev/sde1
umount: /dev/sde1: not mounted.
[./reUSBable.sh] Detected command shred for shred the device /dev/sde
[./reUSBable.sh] Press Enter to shred device /dev/sde
```
    
If you want to avoid confirmation in each step, run the script with the flag `-q`

```console
⤷ sudo ./reUSBable.sh -q
[sudo] password for revelaction:
1) DataTraveler_3.0          /dev/sde     B0C54E757496FFB3K9F2
2) PC404 NVMe SK hynix 128GB /dev/nvme0n1 JJAN590010307L4V
[./reUSBable.sh] Please select the device: 1
```

# How does it work

`reUSBable` should be run after (and before) using it for secure
transport of data between two computers.

`reUSBable` performs the following actions in a given USB (or other data device):

- It unmounts any previous partitions on the device.
- It shreds the entire device with the command `shred` (if present) or `dd`.
  This step can last many minutes/hours.
- It shreds the partition table of the device with `wipefs` and `dd`.
- It creates a new `gpt` partition table.
- It creates one partition using 100% of the device.
- It creates a LUKS2 partition on the previously create partition.
- It opens the LUKS2 partition and creates a ext4 filesystem inside.
- It mounts the filesystem in `/media/<user>`

# mount luks script

`mount-luks.sh` is a companion script to mount and unmount the files created by `reUSBable`.
