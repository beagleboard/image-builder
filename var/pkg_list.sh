#!/bin/sh -e

#Note: These will be auto installed by chroot.sh script:
#initramfs-tools sudo wget

base_pkgs=""

#Base
base_pkgs="${base_pkgs} ca-certificates nano pastebinit file lsb-release"

#Tools
base_pkgs="${base_pkgs} bsdmainutils i2c-tools fbset hexedit hdparm memtester read-edid u-boot-tools"

#OS
base_pkgs="${base_pkgs} acpid dosfstools btrfs-tools cpufrequtils ntpdate"

#USB Dongles
base_pkgs="${base_pkgs} ppp usb-modeswitch usbutils"

#Server
base_pkgs="${base_pkgs} apache2 openssh-server udhcpd avahi-daemon"

#Wireless
base_pkgs="${base_pkgs} wireless-tools wpasupplicant lowpan-tools wvdial lshw hostapd bluez bluez-compat"

#Flasher
base_pkgs="${base_pkgs} rsync"

#shellinabox (breaks ssh over eth/usb)
#base_pkgs="${base_pkgs} shellinabox"

#Gateone:
#base_pkgs="${base_pkgs} python-tornado python-pyopenssl"
