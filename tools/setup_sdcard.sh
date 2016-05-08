#!/bin/bash -e
#
# Copyright (c) 2009-2016 Robert Nelson <robertcnelson@gmail.com>
# Copyright (c) 2010 Mario Di Francesco <mdf-code@digitalexile.it>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# Latest can be found at:
# https://github.com/RobertCNelson/omap-image-builder/blob/master/tools/setup_sdcard.sh

#REQUIREMENTS:
#uEnv.txt bootscript support

BOOT_LABEL="BOOT"

unset USE_BETA_BOOTLOADER
unset USE_LOCAL_BOOT
unset LOCAL_BOOTLOADER

#Defaults
ROOTFS_TYPE=ext4
ROOTFS_LABEL=rootfs

DIR="$PWD"
TEMPDIR=$(mktemp -d)

keep_net_alive () {
	while : ; do
		echo "running: $*"
		sleep 300
	done
}
keep_net_alive & KEEP_NET_ALIVE_PID=$!
cleanup_keep_net_alive () {
	[ -e /proc/$KEEP_NET_ALIVE_PID ] && kill $KEEP_NET_ALIVE_PID
}
trap cleanup_keep_net_alive EXIT

is_element_of () {
	testelt=$1
	for validelt in $2 ; do
		[ $testelt = $validelt ] && return 0
	done
	return 1
}

#########################################################################
#
#  Define valid "--rootfs" root filesystem types.
#
#########################################################################

VALID_ROOTFS_TYPES="ext2 ext3 ext4"

is_valid_rootfs_type () {
	if is_element_of $1 "${VALID_ROOTFS_TYPES}" ] ; then
		return 0
	else
		return 1
	fi
}

check_root () {
	if ! [ $(id -u) = 0 ] ; then
		echo "$0 must be run as sudo user or root"
		exit 1
	fi
}

find_issue () {
	check_root

	ROOTFS=$(ls "${DIR}/" | grep rootfs)
	if [ "x${ROOTFS}" != "x" ] ; then
		echo "Debug: ARM rootfs: ${ROOTFS}"
	else
		echo "Error: no armel-rootfs-* file"
		echo "Make sure your in the right dir..."
		exit
	fi

	unset has_uenvtxt
	unset check
	check=$(ls "${DIR}/" | grep uEnv.txt | grep -v post-uEnv.txt | head -n 1)
	if [ "x${check}" != "x" ] ; then
		echo "Debug: image has pre-generated uEnv.txt file"
		has_uenvtxt=1
	fi

	unset has_post_uenvtxt
	unset check
	check=$(ls "${DIR}/" | grep post-uEnv.txt | head -n 1)
	if [ "x${check}" != "x" ] ; then
		echo "Debug: image has post-uEnv.txt file"
		has_post_uenvtxt="enable"
	fi
}

check_for_command () {
	if ! which "$1" > /dev/null ; then
		echo -n "You're missing command $1"
		NEEDS_COMMAND=1
		if [ -n "$2" ] ; then
			echo -n " (consider installing package $2)"
		fi
		echo
	fi
}

detect_software () {
	unset NEEDS_COMMAND

	check_for_command mkfs.vfat dosfstools
	check_for_command wget wget
	check_for_command git git
	check_for_command partprobe parted

	if [ "x${build_img_file}" = "xenable" ] ; then
		check_for_command kpartx kpartx
	fi

	if [ "${NEEDS_COMMAND}" ] ; then
		echo ""
		echo "Your system is missing some dependencies"
		echo "Debian/Ubuntu: sudo apt-get install dosfstools git-core kpartx wget parted"
		echo "Fedora: yum install dosfstools dosfstools git-core wget"
		echo "Gentoo: emerge dosfstools git wget"
		echo ""
		exit
	fi

	unset test_sfdisk
	test_sfdisk=$(LC_ALL=C sfdisk -v 2>/dev/null | grep 2.17.2 | awk '{print $1}')
	if [ "x${test_sdfdisk}" = "xsfdisk" ] ; then
		echo ""
		echo "Detected known broken sfdisk:"
		echo "See: https://github.com/RobertCNelson/netinstall/issues/20"
		echo ""
		exit
	fi

	#Debian Stretch, mfks.ext4 default to metadata_csum,64bit disable till u-boot works again..
	unset ext4_options
	unset test_mke2fs
	LC_ALL=C mkfs.ext4 -V &> /tmp/mkfs
	test_mkfs=$(cat /tmp/mkfs | grep mke2fs | grep 1.43 || true)
	if [ "x${test_mkfs}" = "x" ] ; then
		unset ext4_options
	else
		ext4_options="-O ^metadata_csum,^64bit"
	fi

	unset wget_version
	wget_version=$(LC_ALL=C wget --version | grep "GNU Wget" | awk '{print $3}' | awk -F '.' '{print $2}' || true)
	case "${wget_version}" in
	12|13)
		#wget before 1.14 in debian does not support sni
		echo "wget: [`LC_ALL=C wget --version | grep \"GNU Wget\" | awk '{print $3}' || true`]"
		echo "wget: [this version of wget does not support sni, using --no-check-certificate]"
		echo "wget: [http://en.wikipedia.org/wiki/Server_Name_Indication]"
		dl="wget --no-check-certificate"
		;;
	*)
		dl="wget"
		;;
	esac

	dl_continue="${dl} -c"
	dl_quiet="${dl} --no-verbose"
}

local_bootloader () {
	echo ""
	echo "Using Locally Stored Device Bootloader"
	echo "-----------------------------"
	mkdir -p ${TEMPDIR}/dl/

	if [ "${spl_name}" ] ; then
		cp ${LOCAL_SPL} ${TEMPDIR}/dl/
		SPL=${LOCAL_SPL##*/}
		echo "SPL Bootloader: ${SPL}"
	fi

	if [ "${boot_name}" ] ; then
		cp ${LOCAL_BOOTLOADER} ${TEMPDIR}/dl/
		UBOOT=${LOCAL_BOOTLOADER##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	fi
}

dl_bootloader () {
	echo ""
	echo "Downloading Device's Bootloader"
	echo "-----------------------------"
	minimal_boot="1"

	mkdir -p ${TEMPDIR}/dl/${DIST}
	mkdir -p "${DIR}/dl/${DIST}"

	${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" ${conf_bl_http}/${conf_bl_listfile}

	if [ ! -f ${TEMPDIR}/dl/${conf_bl_listfile} ] ; then
		echo "error: can't connect to rcn-ee.net, retry in a few minutes..."
		exit
	fi

	boot_version=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "VERSION:" | awk -F":" '{print $2}')
	if [ "x${boot_version}" != "x${minimal_boot}" ] ; then
		echo "Error: This script is out of date and unsupported..."
		echo "Please Visit: https://github.com/RobertCNelson to find updates..."
		exit
	fi

	if [ "${USE_BETA_BOOTLOADER}" ] ; then
		ABI="ABX2"
	else
		ABI="ABI2"
	fi

	if [ "${spl_name}" ] ; then
		SPL=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:SPL" | awk '{print $2}')
		${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" ${SPL}
		SPL=${SPL##*/}
		echo "SPL Bootloader: ${SPL}"
	else
		unset SPL
	fi

	if [ "${boot_name}" ] ; then
		UBOOT=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:BOOT" | awk '{print $2}')
		${dl} --directory-prefix="${TEMPDIR}/dl/" ${UBOOT}
		UBOOT=${UBOOT##*/}
		echo "UBOOT Bootloader: ${UBOOT}"
	else
		unset UBOOT
	fi

	if [ "x${oem_blank_eeprom}" = "xenable" ] ; then
		if [ "x${conf_board}" = "xbeagle_x15" ] ; then
			unset oem_blank_eeprom
		fi
	fi

	if [ "x${oem_blank_eeprom}" = "xenable" ] ; then
		ABI="ABI2"
		conf_board="am335x_boneblack"

		if [ "${spl_name}" ] ; then
			blank_SPL=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:SPL" | awk '{print $2}')
			${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" ${blank_SPL}
			blank_SPL=${blank_SPL##*/}
			echo "blank_SPL Bootloader: ${blank_SPL}"
		else
			unset blank_SPL
		fi

		if [ "${boot_name}" ] ; then
			blank_UBOOT=$(cat ${TEMPDIR}/dl/${conf_bl_listfile} | grep "${ABI}:${conf_board}:BOOT" | awk '{print $2}')
			${dl} --directory-prefix="${TEMPDIR}/dl/" ${blank_UBOOT}
			blank_UBOOT=${blank_UBOOT##*/}
			echo "blank_UBOOT Bootloader: ${blank_UBOOT}"
		else
			unset blank_UBOOT
		fi
	fi
}

generate_soc () {
	echo "#!/bin/sh" > ${wfile}
	echo "format=1.0" >> ${wfile}
	echo "" >> ${wfile}
	if [ ! "x${conf_bootloader_in_flash}" = "xenable" ] ; then
		echo "board=${board}" >> ${wfile}
		echo "" >> ${wfile}
		echo "bootloader_location=${bootloader_location}" >> ${wfile}
		echo "bootrom_gpt=${bootrom_gpt}" >> ${wfile}
		echo "" >> ${wfile}
		echo "dd_spl_uboot_count=${dd_spl_uboot_count}" >> ${wfile}
		echo "dd_spl_uboot_seek=${dd_spl_uboot_seek}" >> ${wfile}
		if [ "x${build_img_file}" = "xenable" ] ; then
			echo "dd_spl_uboot_conf=notrunc" >> ${wfile}
		else
			echo "dd_spl_uboot_conf=${dd_spl_uboot_conf}" >> ${wfile}
		fi
		echo "dd_spl_uboot_bs=${dd_spl_uboot_bs}" >> ${wfile}
		echo "dd_spl_uboot_backup=/opt/backup/uboot/${spl_uboot_name}" >> ${wfile}
		echo "" >> ${wfile}
		echo "dd_uboot_count=${dd_uboot_count}" >> ${wfile}
		echo "dd_uboot_seek=${dd_uboot_seek}" >> ${wfile}
		if [ "x${build_img_file}" = "xenable" ] ; then
			echo "dd_uboot_conf=notrunc" >> ${wfile}
		else
			echo "dd_uboot_conf=${dd_uboot_conf}" >> ${wfile}
		fi
		echo "dd_uboot_bs=${dd_uboot_bs}" >> ${wfile}
		echo "dd_uboot_backup=/opt/backup/uboot/${uboot_name}" >> ${wfile}
	else
		echo "uboot_CONFIG_CMD_BOOTZ=${uboot_CONFIG_CMD_BOOTZ}" >> ${wfile}
		echo "uboot_CONFIG_SUPPORT_RAW_INITRD=${uboot_CONFIG_SUPPORT_RAW_INITRD}" >> ${wfile}
		echo "uboot_CONFIG_CMD_FS_GENERIC=${uboot_CONFIG_CMD_FS_GENERIC}" >> ${wfile}
		echo "zreladdr=${conf_zreladdr}" >> ${wfile}
	fi
	echo "" >> ${wfile}
	echo "boot_fstype=${conf_boot_fstype}" >> ${wfile}
	echo "conf_boot_startmb=${conf_boot_startmb}" >> ${wfile}
	echo "conf_boot_endmb=${conf_boot_endmb}" >> ${wfile}
	echo "sfdisk_fstype=${sfdisk_fstype}" >> ${wfile}
	echo "" >> ${wfile}
	echo "boot_label=${BOOT_LABEL}" >> ${wfile}
	echo "rootfs_label=${ROOTFS_LABEL}" >> ${wfile}
	echo "" >> ${wfile}
	echo "#Kernel" >> ${wfile}
	echo "dtb=${dtb}" >> ${wfile}
	echo "serial_tty=${SERIAL}" >> ${wfile}
	echo "usbnet_mem=${usbnet_mem}" >> ${wfile}

	echo "" >> ${wfile}
}

drive_error_ro () {
	echo "-----------------------------"
	echo "Error: for some reason your SD card is not writable..."
	echo "Check: is the write protect lever set the locked position?"
	echo "Check: do you have another SD card reader?"
	echo "-----------------------------"
	echo "Script gave up..."

	exit
}

unmount_all_drive_partitions () {
	echo ""
	echo "Unmounting Partitions"
	echo "-----------------------------"

	NUM_MOUNTS=$(mount | grep -v none | grep "${media}" | wc -l)

##	for (i=1;i<=${NUM_MOUNTS};i++)
	for ((i=1;i<=${NUM_MOUNTS};i++))
	do
		DRIVE=$(mount | grep -v none | grep "${media}" | tail -1 | awk '{print $1}')
		umount ${DRIVE} >/dev/null 2>&1 || true
	done

	echo "Zeroing out Drive"
	echo "-----------------------------"
	dd if=/dev/zero of=${media} bs=1M count=100 || drive_error_ro
	sync
	dd if=${media} of=/dev/null bs=1M count=100
	sync
}

sfdisk_partition_layout () {
	sfdisk_options="--force --in-order --Linux --unit M"
	sfdisk_boot_startmb="${conf_boot_startmb}"
	sfdisk_boot_endmb="${conf_boot_endmb}"
	sfdisk_var_startmb="${conf_var_startmb}"

	test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
	if [ "x${test_sfdisk}" = "x" ] ; then
		echo "log: sfdisk: 2.26.x or greater detected"
		sfdisk_options="--force ${sfdisk_gpt}"
		sfdisk_boot_startmb="${sfdisk_boot_startmb}M"
		sfdisk_boot_endmb="${sfdisk_boot_endmb}M"
		sfdisk_var_startmb="${sfdisk_var_startmb}M"
	fi

	if [ "x${option_ro_root}" = "xenable" ] ; then
		echo "sfdisk: [$(LC_ALL=C sfdisk --version)]"
		echo "sfdisk: [${sfdisk_options} ${media}]"
		echo "sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*]"
		echo "sfdisk: [,${sfdisk_var_startmb},,-]"
		echo "sfdisk: [,,,-]"

		LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
			${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*
			,${sfdisk_var_startmb},,-
			,,,-
		__EOF__

		media_rootfs_var_partition=3
	else
		echo "sfdisk: [$(LC_ALL=C sfdisk --version)]"
		echo "sfdisk: [${sfdisk_options} ${media}]"
		echo "sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*]"
		echo "sfdisk: [,,,-]"

		LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
			${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*
			,,,-
		__EOF__

	fi

	sync
}

sfdisk_single_partition_layout () {
	sfdisk_options="--force --in-order --Linux --unit M"
	sfdisk_boot_startmb="${conf_boot_startmb}"
	sfdisk_var_startmb="${conf_var_startmb}"

	test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
	if [ "x${test_sfdisk}" = "x" ] ; then
		echo "log: sfdisk: 2.26.x or greater detected"
		sfdisk_options="--force ${sfdisk_gpt}"
		sfdisk_boot_startmb="${sfdisk_boot_startmb}M"
		sfdisk_var_startmb="${sfdisk_var_startmb}M"
	fi

	if [ "x${option_ro_root}" = "xenable" ] ; then
		echo "sfdisk: [$(LC_ALL=C sfdisk --version)]"
		echo "sfdisk: [${sfdisk_options} ${media}]"
		echo "sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*]"
		echo "sfdisk: [,,,-]"

		LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
			${sfdisk_boot_startmb},${sfdisk_var_startmb},${sfdisk_fstype},*
			,,,-
		__EOF__

		media_rootfs_var_partition=2
	else
		echo "sfdisk: [$(LC_ALL=C sfdisk --version)]"
		echo "sfdisk: [${sfdisk_options} ${media}]"
		echo "sfdisk: [${sfdisk_boot_startmb},,${sfdisk_fstype},*]"

		LC_ALL=C sfdisk ${sfdisk_options} "${media}" <<-__EOF__
			${sfdisk_boot_startmb},,${sfdisk_fstype},*
		__EOF__

	fi

	sync
}

dd_uboot_boot () {
	unset dd_uboot
	if [ ! "x${dd_uboot_count}" = "x" ] ; then
		dd_uboot="${dd_uboot}count=${dd_uboot_count} "
	fi

	if [ ! "x${dd_uboot_seek}" = "x" ] ; then
		dd_uboot="${dd_uboot}seek=${dd_uboot_seek} "
	fi

	if [ "x${build_img_file}" = "xenable" ] ; then
		dd_uboot="${dd_uboot}conv=notrunc "
	else
		if [ ! "x${dd_uboot_conf}" = "x" ] ; then
			dd_uboot="${dd_uboot}conv=${dd_uboot_conf} "
		fi
	fi

	if [ ! "x${dd_uboot_bs}" = "x" ] ; then
		dd_uboot="${dd_uboot}bs=${dd_uboot_bs}"
	fi

	if [ "x${oem_blank_eeprom}" = "xenable" ] ; then
		uboot_blob="${blank_UBOOT}"
	else
		uboot_blob="${UBOOT}"
	fi

	echo "${uboot_name}: dd if=${uboot_blob} of=${media} ${dd_uboot}"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${uboot_blob} of=${media} ${dd_uboot}
	echo "-----------------------------"
}

dd_spl_uboot_boot () {
	unset dd_spl_uboot
	if [ ! "x${dd_spl_uboot_count}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}count=${dd_spl_uboot_count} "
	fi

	if [ ! "x${dd_spl_uboot_seek}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}seek=${dd_spl_uboot_seek} "
	fi

	if [ "x${build_img_file}" = "xenable" ] ; then
			dd_spl_uboot="${dd_spl_uboot}conv=notrunc "
	else
		if [ ! "x${dd_spl_uboot_conf}" = "x" ] ; then
			dd_spl_uboot="${dd_spl_uboot}conv=${dd_spl_uboot_conf} "
		fi
	fi

	if [ ! "x${dd_spl_uboot_bs}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}bs=${dd_spl_uboot_bs}"
	fi

	if [ "x${oem_blank_eeprom}" = "xenable" ] ; then
		spl_uboot_blob="${blank_SPL}"
	else
		spl_uboot_blob="${SPL}"
	fi

	echo "${spl_uboot_name}: dd if=${spl_uboot_blob} of=${media} ${dd_spl_uboot}"
	echo "-----------------------------"
	dd if=${TEMPDIR}/dl/${spl_uboot_blob} of=${media} ${dd_spl_uboot}
	echo "-----------------------------"
}

format_partition_error () {
	echo "LC_ALL=C ${mkfs} ${mkfs_partition} ${mkfs_label}"
	echo "Failure: formating partition"
	exit
}

format_partition_try2 () {
	unset mkfs_options
	if [ "x${mkfs}" = "xmkfs.ext4" ] ; then
		mkfs_options="${ext4_options}"
	fi

	echo "-----------------------------"
	echo "BUG: [${mkfs_partition}] was not available so trying [${mkfs}] again in 5 seconds..."
	partprobe ${media}
	sync
	sleep 5
	echo "-----------------------------"

	echo "Formating with: [${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label}]"
	echo "-----------------------------"
	LC_ALL=C ${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label} || format_partition_error
	sync
}

format_partition () {
	unset mkfs_options
	if [ "x${mkfs}" = "xmkfs.ext4" ] ; then
		mkfs_options="${ext4_options}"
	fi

	echo "Formating with: [${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label}]"
	echo "-----------------------------"
	LC_ALL=C ${mkfs} ${mkfs_options} ${mkfs_partition} ${mkfs_label} || format_partition_try2
	sync
}

format_boot_partition () {
	mkfs_partition="${media_prefix}${media_boot_partition}"

	if [ "x${conf_boot_fstype}" = "xfat" ] ; then
		mount_partition_format="vfat"
		mkfs="mkfs.vfat -F 16"
		mkfs_label="-n ${BOOT_LABEL}"
	else
		mount_partition_format="${conf_boot_fstype}"
		mkfs="mkfs.${conf_boot_fstype}"
		mkfs_label="-L ${BOOT_LABEL}"
	fi

	format_partition
}

format_rootfs_partition () {
	if [ "x${option_ro_root}" = "xenable" ] ; then
		mkfs="mkfs.ext2"
	else
		mkfs="mkfs.${ROOTFS_TYPE}"
	fi
	mkfs_partition="${media_prefix}${media_rootfs_partition}"
	mkfs_label="-L ${ROOTFS_LABEL}"

	format_partition

	if [ "x${build_img_file}" = "xenable" ] ; then
		rootfs_drive="${conf_root_device}p${media_rootfs_partition}"
	else
		unset rootfs_uuid
		rootfs_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${mkfs_partition} || true)
		if [ ! "x${rootfs_uuid}" = "x" ] ; then
			rootfs_drive="UUID=${rootfs_uuid}"
		else
			rootfs_drive="${conf_root_device}p${media_rootfs_partition}"
		fi
	fi

	if [ "x${option_ro_root}" = "xenable" ] ; then

		mkfs="mkfs.${ROOTFS_TYPE}"
		mkfs_partition="${media_prefix}${media_rootfs_var_partition}"
		mkfs_label="-L var"

		format_partition

		if [ "x${build_img_file}" = "xenable" ] ; then
			rootfs_var_drive="${conf_root_device}p${media_rootfs_var_partition}"
		else
			unset rootfs_var_uuid
			rootfs_var_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${mkfs_partition} || true)
			if [ ! "x${rootfs_var_uuid}" = "x" ] ; then
				rootfs_var_drive="UUID=${rootfs_var_uuid}"
			else
				rootfs_var_drive="${conf_root_device}p${media_rootfs_var_partition}"
			fi
		fi
	fi
}

create_partitions () {
	unset bootloader_installed
	unset sfdisk_gpt

	media_boot_partition=1
	media_rootfs_partition=2

	echo ""
	case "${bootloader_location}" in
	fatfs_boot)
		conf_boot_endmb=${conf_boot_endmb:-"12"}
		echo "Using sfdisk to create partition layout"
		echo "Version: `LC_ALL=C sfdisk --version`"
		echo "-----------------------------"
		sfdisk_partition_layout
		;;
	dd_uboot_boot)
		echo "Using dd to place bootloader on drive"
		echo "-----------------------------"
		if [ "x${bootrom_gpt}" = "xenable" ] ; then
			sfdisk_gpt="--label gpt"
		fi
		dd_uboot_boot
		bootloader_installed=1
		sfdisk_single_partition_layout
		media_rootfs_partition=1
		;;
	dd_spl_uboot_boot)
		echo "Using dd to place bootloader on drive"
		echo "-----------------------------"
		if [ "x${bootrom_gpt}" = "xenable" ] ; then
			sfdisk_gpt="--label gpt"
		fi
		dd_spl_uboot_boot
		dd_uboot_boot
		bootloader_installed=1
		sfdisk_single_partition_layout
		media_rootfs_partition=1
		;;
	*)
		echo "Using sfdisk to create partition layout"
		echo "Version: `LC_ALL=C sfdisk --version`"
		echo "-----------------------------"
		sfdisk_partition_layout
		;;
	esac

	echo "Partition Setup:"
	echo "-----------------------------"
	LC_ALL=C fdisk -l "${media}"
	echo "-----------------------------"

	if [ "x${build_img_file}" = "xenable" ] ; then
		media_loop=$(losetup -f || true)
		if [ ! "${media_loop}" ] ; then
			echo "losetup -f failed"
			echo "Unmount some via: [sudo losetup -a]"
			echo "-----------------------------"
			losetup -a
			echo "sudo kpartx -d /dev/loopX ; sudo losetup -d /dev/loopX"
			echo "-----------------------------"
			exit
		fi

		losetup ${media_loop} "${media}"
		kpartx -av ${media_loop}
		sleep 1
		sync
		test_loop=$(echo ${media_loop} | awk -F'/' '{print $3}')
		if [ -e /dev/mapper/${test_loop}p${media_boot_partition} ] && [ -e /dev/mapper/${test_loop}p${media_rootfs_partition} ] ; then
			media_prefix="/dev/mapper/${test_loop}p"
		else
			ls -lh /dev/mapper/
			echo "Error: not sure what to do (new feature)."
			exit
		fi
	else
		partprobe ${media}
	fi

	if [ "x${media_boot_partition}" = "x${media_rootfs_partition}" ] ; then
		mount_partition_format="${ROOTFS_TYPE}"
		format_rootfs_partition
	else
		format_boot_partition
		format_rootfs_partition
	fi
}

populate_boot () {
	echo "Populating Boot Partition"
	echo "-----------------------------"

	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	partprobe ${media}
	if ! mount -t ${mount_partition_format} ${media_prefix}${media_boot_partition} ${TEMPDIR}/disk; then

		echo "-----------------------------"
		echo "BUG: [${media_prefix}${media_boot_partition}] was not available so trying to mount again in 5 seconds..."
		partprobe ${media}
		sync
		sleep 5
		echo "-----------------------------"

		if ! mount -t ${mount_partition_format} ${media_prefix}${media_boot_partition} ${TEMPDIR}/disk; then
			echo "-----------------------------"
			echo "Unable to mount ${media_prefix}${media_boot_partition} at ${TEMPDIR}/disk to complete populating Boot Partition"
			echo "Please retry running the script, sometimes rebooting your system helps."
			echo "-----------------------------"
			exit
		fi
	fi

	lsblk | grep -v sr0
	echo "-----------------------------"

	if [ "${spl_name}" ] ; then
		if [ -f ${TEMPDIR}/dl/${SPL} ] ; then
			if [ ! "${bootloader_installed}" ] ; then
				cp -v ${TEMPDIR}/dl/${SPL} ${TEMPDIR}/disk/${spl_name}
				echo "-----------------------------"
			fi
		fi
	fi


	if [ "${boot_name}" ] ; then
		if [ -f ${TEMPDIR}/dl/${UBOOT} ] ; then
			if [ ! "${bootloader_installed}" ] ; then
				cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/${boot_name}
				echo "-----------------------------"
			fi
		fi
	fi

	if [ "x${distro_defaults}" = "xenable" ] ; then
		${dl_quiet} --directory-prefix="${TEMPDIR}/dl/" https://raw.githubusercontent.com/RobertCNelson/netinstall/master/lib/distro_defaults.scr
		cp -v ${TEMPDIR}/dl/distro_defaults.scr ${TEMPDIR}/disk/boot.scr
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] || [ "x${conf_board}" = "xarduino-tre" ] ; then

		if [ ! "x${bbb_old_bootloader_in_emmc}" = "xenable" ] ; then
			wfile="${TEMPDIR}/disk/bbb-uEnv.txt"
			echo "##Rename as: uEnv.txt to override old bootloader in eMMC" > ${wfile}
			echo "##These are needed to be compliant with Angstrom's 2013.06.20 u-boot." >> ${wfile}
		else
			wfile="${TEMPDIR}/disk/uEnv.txt"
			echo "##These are needed to be compliant with Angstrom's 2013.06.20 u-boot." > ${wfile}
		fi

		if [ "x${conf_board}" = "xarduino-tre" ] ; then
			wfile="${TEMPDIR}/disk/uEnv.txt"
		fi

		echo "" >> ${wfile}
		echo "loadaddr=0x82000000" >> ${wfile}
		echo "fdtaddr=0x88000000" >> ${wfile}
		echo "rdaddr=0x88080000" >> ${wfile}
		echo "" >> ${wfile}
		echo "initrd_high=0xffffffff" >> ${wfile}
		echo "fdt_high=0xffffffff" >> ${wfile}
		echo "" >> ${wfile}
		echo "##These are needed to be compliant with Debian 2014-05-14 u-boot." >> ${wfile}
		echo "" >> ${wfile}
		echo "loadximage=echo debug: [/boot/vmlinuz-\${uname_r}] ... ; load mmc 0:${media_rootfs_partition} \${loadaddr} /boot/vmlinuz-\${uname_r}" >> ${wfile}
		echo "loadxfdt=echo debug: [/boot/dtbs/\${uname_r}/\${fdtfile}] ... ;load mmc 0:${media_rootfs_partition} \${fdtaddr} /boot/dtbs/\${uname_r}/\${fdtfile}" >> ${wfile}
		echo "loadxrd=echo debug: [/boot/initrd.img-\${uname_r}] ... ; load mmc 0:${media_rootfs_partition} \${rdaddr} /boot/initrd.img-\${uname_r}; setenv rdsize \${filesize}" >> ${wfile}
		echo "loaduEnvtxt=load mmc 0:${media_rootfs_partition} \${loadaddr} /boot/uEnv.txt ; env import -t \${loadaddr} \${filesize};" >> ${wfile}
		echo "check_dtb=if test -n \${dtb}; then setenv fdtfile \${dtb};fi;" >> ${wfile}
		echo "loadall=run loaduEnvtxt; run check_dtb; run loadximage; run loadxrd; run loadxfdt;" >> ${wfile}
		echo "" >> ${wfile}
		echo "mmcargs=setenv bootargs console=tty0 console=\${console} \${optargs} \${cape_disable} \${cape_enable} root=/dev/mmcblk0p${media_rootfs_partition} rootfstype=\${mmcrootfstype} \${cmdline}" >> ${wfile}
		echo "" >> ${wfile}

		if [ "x${conf_board}" = "xarduino-tre" ] ; then
			echo "uenvcmd=run loadall; run mmcargs; echo debug: [\${bootargs}] ... ; echo debug: [bootz \${loadaddr} - \${fdtaddr}] ... ; bootz \${loadaddr} - \${fdtaddr};" >> ${wfile}
		else
			echo "uenvcmd=run loadall; run mmcargs; echo debug: [\${bootargs}] ... ; echo debug: [bootz \${loadaddr} \${rdaddr}:\${rdsize} \${fdtaddr}] ... ; bootz \${loadaddr} \${rdaddr}:\${rdsize} \${fdtaddr};" >> ${wfile}
		fi

		echo "" >> ${wfile}

		wfile="${TEMPDIR}/disk/nfs-uEnv.txt"
		echo "##Rename as: uEnv.txt to boot via nfs" > ${wfile}
		echo "" >> ${wfile}
		echo "##https://www.kernel.org/doc/Documentation/filesystems/nfs/nfsroot.txt" >> ${wfile}
		echo "" >> ${wfile}
		echo "##SERVER: sudo apt-get install tftpd-hpa" >> ${wfile}
		echo "##SERVER:" >> ${wfile}
		echo "##SERVER: zImage boot:" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY defined in /etc/default/tftpd-hpa" >> ${wfile}
		echo "##SERVER: zImage/*.dtb need to be located here:" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY/zImage" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY/dtbs/*.dtb" >> ${wfile}
		echo "##SERVER:" >> ${wfile}
		echo "##SERVER: uname_r boot:" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY defined in /etc/default/tftpd-hpa" >> ${wfile}
		echo "##SERVER: Change TFTP_DIRECTORY to /NFSEXPORT/boot" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY/vmlinuz-\${uname_r}" >> ${wfile}
		echo "##SERVER: TFTP_DIRECTORY/dtbs/\${uname_r}/*.dtb" >> ${wfile}
		echo "" >> ${wfile}
		echo "##client_ip needs to be set for u-boot to try booting via nfs" >> ${wfile}
		echo "" >> ${wfile}
		echo "client_ip=192.168.1.101" >> ${wfile}
		echo "" >> ${wfile}
		echo "#u-boot defaults: uncomment and override where needed" >> ${wfile}
		echo "" >> ${wfile}
		echo "#server_ip=192.168.1.100" >> ${wfile}
		echo "#gw_ip=192.168.1.1" >> ${wfile}
		echo "#netmask=255.255.255.0" >> ${wfile}
		echo "#hostname=" >> ${wfile}
		echo "#device=eth0" >> ${wfile}
		echo "#autoconf=off" >> ${wfile}
		echo "#root_dir=/home/userid/targetNFS" >> ${wfile}
		echo "#nfs_options=,vers=3" >> ${wfile}
		echo "#nfsrootfstype=ext4 rootwait fixrtc" >> ${wfile}
		echo "" >> ${wfile}
		echo "##use uname_r= only if TFTP SERVER is setup for uname_r boot:" >> ${wfile}
		echo "#uname_r=" >> ${wfile}
		echo "" >> ${wfile}

	fi

	if [ -f "${DIR}/ID.txt" ] ; then
		cp -v "${DIR}/ID.txt" ${TEMPDIR}/disk/ID.txt
	fi

	if [ ${has_uenvtxt} ] ; then
		if [ ! "x${bbb_old_bootloader_in_emmc}" = "xenable" ] ; then
			cp -v "${DIR}/uEnv.txt" ${TEMPDIR}/disk/uEnv.txt
			echo "-----------------------------"
		fi
	fi

	cd ${TEMPDIR}/disk
	sync
	cd "${DIR}"/

	echo "Debug: Contents of Boot Partition"
	echo "-----------------------------"
	ls -lh ${TEMPDIR}/disk/
	du -sh ${TEMPDIR}/disk/
	echo "-----------------------------"

	sync
	sync

	umount ${TEMPDIR}/disk || true

	echo "Finished populating Boot Partition"
	echo "-----------------------------"
}

kernel_detection () {
	unset has_multi_armv7_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep armv7 | grep -v lpae | head -n 1)
	if [ "x${check}" != "x" ] ; then
		armv7_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep armv7 | grep -v lpae | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${armv7_kernel}"
		has_multi_armv7_kernel="enable"
	fi

	unset has_multi_armv7_lpae_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep armv7 | grep lpae | head -n 1)
	if [ "x${check}" != "x" ] ; then
		armv7_lpae_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep armv7 | grep lpae | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${armv7_lpae_kernel}"
		has_multi_armv7_lpae_kernel="enable"
	fi

	unset has_bone_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep bone | head -n 1)
	if [ "x${check}" != "x" ] ; then
		bone_dt_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep bone | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${bone_dt_kernel}"
		has_bone_kernel="enable"
	fi

	unset has_ti_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep ti | head -n 1)
	if [ "x${check}" != "x" ] ; then
		ti_dt_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep ti | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${ti_dt_kernel}"
		has_ti_kernel="enable"
	fi

	unset has_xenomai_kernel
	unset check
	check=$(ls "${dir_check}" | grep vmlinuz- | grep xenomai | head -n 1)
	if [ "x${check}" != "x" ] ; then
		xenomai_dt_kernel=$(ls "${dir_check}" | grep vmlinuz- | grep xenomai | head -n 1 | awk -F'vmlinuz-' '{print $2}')
		echo "Debug: image has: v${xenomai_dt_kernel}"
		has_xenomai_kernel="enable"
	fi
}

kernel_select () {
	unset select_kernel
	if [ "x${conf_kernel}" = "xarmv7" ] || [ "x${conf_kernel}" = "x" ] ; then
		if [ "x${has_multi_armv7_kernel}" = "xenable" ] ; then
			select_kernel="${armv7_kernel}"
		fi
	fi

	if [ "x${conf_kernel}" = "xarmv7_lpae" ] ; then
		if [ "x${has_multi_armv7_lpae_kernel}" = "xenable" ] ; then
			select_kernel="${armv7_lpae_kernel}"
		else
			if [ "x${has_multi_armv7_kernel}" = "xenable" ] ; then
				select_kernel="${armv7_kernel}"
			fi
		fi
	fi

	if [ "x${conf_kernel}" = "xbone" ] ; then
		if [ "x${has_ti_kernel}" = "xenable" ] ; then
			select_kernel="${ti_dt_kernel}"
		else
			if [ "x${has_bone_kernel}" = "xenable" ] ; then
				select_kernel="${bone_dt_kernel}"
			else
				if [ "x${has_multi_armv7_kernel}" = "xenable" ] ; then
					select_kernel="${armv7_kernel}"
				else
					if [ "x${has_xenomai_kernel}" = "xenable" ] ; then
						select_kernel="${xenomai_dt_kernel}"
					fi
				fi
			fi
		fi
	fi

	if [ "x${conf_kernel}" = "xti" ] ; then
		if [ "x${has_ti_kernel}" = "xenable" ] ; then
			select_kernel="${ti_dt_kernel}"
		else
			if [ "x${has_multi_armv7_kernel}" = "xenable" ] ; then
				select_kernel="${armv7_kernel}"
			fi
		fi
	fi

	if [ "${select_kernel}" ] ; then
		echo "Debug: using: v${select_kernel}"
	else
		echo "Error: [conf_kernel] not defined [armv7_lpae,armv7,bone,ti]..."
		exit
	fi
}

populate_rootfs () {
	echo "Populating rootfs Partition"
	echo "Please be patient, this may take a few minutes, as its transfering a lot of data.."
	echo "-----------------------------"

	if [ ! -d ${TEMPDIR}/disk ] ; then
		mkdir -p ${TEMPDIR}/disk
	fi

	partprobe ${media}
	if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_partition} ${TEMPDIR}/disk; then

		echo "-----------------------------"
		echo "BUG: [${media_prefix}${media_rootfs_partition}] was not available so trying to mount again in 5 seconds..."
		partprobe ${media}
		sync
		sleep 5
		echo "-----------------------------"

		if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_partition} ${TEMPDIR}/disk; then
			echo "-----------------------------"
			echo "Unable to mount ${media_prefix}${media_rootfs_partition} at ${TEMPDIR}/disk to complete populating rootfs Partition"
			echo "Please retry running the script, sometimes rebooting your system helps."
			echo "-----------------------------"
			exit
		fi
	fi

	if [ "x${option_ro_root}" = "xenable" ] ; then

		if [ ! -d ${TEMPDIR}/disk/var ] ; then
			mkdir -p ${TEMPDIR}/disk/var
		fi

		if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_var_partition} ${TEMPDIR}/disk/var; then

			echo "-----------------------------"
			echo "BUG: [${media_prefix}${media_rootfs_var_partition}] was not available so trying to mount again in 5 seconds..."
			partprobe ${media}
			sync
			sleep 5
			echo "-----------------------------"

			if ! mount -t ${ROOTFS_TYPE} ${media_prefix}${media_rootfs_var_partition} ${TEMPDIR}/disk/var; then
				echo "-----------------------------"
				echo "Unable to mount ${media_prefix}${media_rootfs_var_partition} at ${TEMPDIR}/disk/var to complete populating rootfs Partition"
				echo "Please retry running the script, sometimes rebooting your system helps."
				echo "-----------------------------"
				exit
			fi
		fi

	fi

	lsblk | grep -v sr0
	echo "-----------------------------"

	if [ -f "${DIR}/${ROOTFS}" ] ; then
		if which pv > /dev/null ; then
			pv "${DIR}/${ROOTFS}" | tar --numeric-owner --preserve-permissions -xf - -C ${TEMPDIR}/disk/
		else
			echo "pv: not installed, using tar verbose to show progress"
			tar --numeric-owner --preserve-permissions --verbose -xf "${DIR}/${ROOTFS}" -C ${TEMPDIR}/disk/
		fi

		echo "Transfer of data is Complete, now syncing data to disk..."
		sync
		sync

		if [ ! "x${oem_flasher_img}" = "x" ] ; then
			if [ ! -d "${TEMPDIR}/disk/opt/emmc/" ] ; then
				mkdir -p "${TEMPDIR}/disk/opt/emmc/"
			fi
			cp -v "${oem_flasher_img}" "${TEMPDIR}/disk/opt/emmc/"
			sync
			if [ ! "x${oem_flasher_bmap}" = "x" ] ; then
				cp -v "${oem_flasher_bmap}" "${TEMPDIR}/disk/opt/emmc/"
				sync
			fi
			if [ ! "x${oem_flasher_eeprom}" = "x" ] ; then
				cp -v "${oem_flasher_eeprom}" "${TEMPDIR}/disk/opt/emmc/"
				sync
			fi
			if [ ! "x${oem_flasher_job}" = "x" ] ; then
				cp -v "${oem_flasher_job}" "${TEMPDIR}/disk/opt/emmc/job.txt"
				sync
			fi
		fi

		echo "-----------------------------"
	fi

	dir_check="${TEMPDIR}/disk/boot/"
	kernel_detection
	kernel_select

	wfile="${TEMPDIR}/disk/boot/uEnv.txt"
	echo "#Docs: http://elinux.org/Beagleboard:U-boot_partitioning_layout_2.0" > ${wfile}
	echo "" >> ${wfile}

	if [ "x${kernel_override}" = "x" ] ; then
		echo "uname_r=${select_kernel}" >> ${wfile}
	else
		echo "uname_r=${kernel_override}" >> ${wfile}
	fi

	if [ ! "x${rootfs_uuid}" = "x" ] ; then
		echo "uuid=${rootfs_uuid}" >> ${wfile}
	else
		echo "#uuid=" >> ${wfile}
	fi

	if [ ! "x${dtb}" = "x" ] ; then
		echo "dtb=${dtb}" >> ${wfile}
	else
		echo "#dtb=" >> ${wfile}

		if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] ; then
			echo "" >> ${wfile}
			echo "##BeagleBone Black/Green dtb's for v4.1.x (BeagleBone White just works..)" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Black: HDMI (Audio/Video) disabled:" >> ${wfile}
			echo "#dtb=am335x-boneblack-emmc-overlay.dtb" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Black: eMMC disabled:" >> ${wfile}
			echo "#dtb=am335x-boneblack-hdmi-overlay.dtb" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Black: HDMI Audio/eMMC disabled:" >> ${wfile}
			echo "#dtb=am335x-boneblack-nhdmi-overlay.dtb" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Black: HDMI (Audio/Video)/eMMC disabled:" >> ${wfile}
			echo "#dtb=am335x-boneblack-overlay.dtb" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Black: wl1835" >> ${wfile}
			echo "#dtb=am335x-boneblack-wl1835mod.dtb" >> ${wfile}

			echo "" >> ${wfile}
			echo "##BeagleBone Green: eMMC disabled" >> ${wfile}
			echo "#dtb=am335x-bonegreen-overlay.dtb" >> ${wfile}

			echo "" >> ${wfile}
		fi
	fi

	cmdline="coherent_pool=1M quiet"
	if [ "x${enable_systemd}" = "xenabled" ] ; then
		cmdline="${cmdline} init=/lib/systemd/systemd"
	fi

	#if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] ; then
	#	cmdline="${cmdline} cape_universal=enable"
	#fi

	unset kms_video

	drm_device_identifier=${drm_device_identifier:-"HDMI-A-1"}
	drm_device_timing=${drm_device_timing:-"1024x768@60e"}
	if [ "x${drm_read_edid_broken}" = "xenable" ] ; then
		cmdline="${cmdline} video=${drm_device_identifier}:${drm_device_timing}"
		echo "cmdline=${cmdline}" >> ${wfile}
		echo "" >> ${wfile}
	else
		echo "cmdline=${cmdline}" >> ${wfile}
		echo "" >> ${wfile}

		echo "#In the event of edid real failures, uncomment this next line:" >> ${wfile}
		echo "#cmdline=${cmdline} video=${drm_device_identifier}:${drm_device_timing}" >> ${wfile}
		echo "" >> ${wfile}
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] ; then
		echo "##Example v3.8.x" >> ${wfile}
		echo "#cape_disable=capemgr.disable_partno=" >> ${wfile}
		echo "#cape_enable=capemgr.enable_partno=" >> ${wfile}
		echo "" >> ${wfile}

		echo "##Example v4.1.x" >> ${wfile}
		echo "#cape_disable=bone_capemgr.disable_partno=" >> ${wfile}
		echo "#cape_enable=bone_capemgr.enable_partno=" >> ${wfile}
		echo "" >> ${wfile}

		if [ ! "x${has_post_uenvtxt}" = "x" ] ; then
			cat "${DIR}/post-uEnv.txt" >> ${wfile}
			echo "" >> ${wfile}
		fi

		if [ "x${usb_flasher}" = "xenable" ] ; then
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-from-usb-media.sh" >> ${wfile}
		elif [ "x${emmc_flasher}" = "xenable" ] ; then
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh" >> ${wfile}
		elif [ "x${bbg_flasher}" = "xenable" ] ; then
			echo "##enable BBG: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbg.sh" >> ${wfile}
		elif [ "x${bbgw_flasher}" = "xenable" ] ; then
			echo "##enable BBG: eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3-bbgw.sh" >> ${wfile}
		elif [ "x${a335_flasher}" = "xenable" ] ; then
			echo "##enable a335: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-a335.sh" >> ${wfile}
		else
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "##make sure, these tools are installed: dosfstools rsync" >> ${wfile}
			echo "#cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh" >> ${wfile}
		fi
		echo "" >> ${wfile}
	else
		if [ "x${usb_flasher}" = "xenable" ] ; then
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-from-usb-media.sh" >> ${wfile}
		elif [ "x${emmc_flasher}" = "xenable" ] ; then
			echo "##enable Generic eMMC Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh" >> ${wfile}
		elif [ "x${a335_flasher}" = "xenable" ] ; then
			echo "##enable a335: eeprom Flasher:" >> ${wfile}
			echo "cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-a335.sh" >> ${wfile}
		fi
	fi

	#am335x_boneblack is a custom u-boot to ignore empty factory eeproms...
	if [ "x${conf_board}" = "xam335x_boneblack" ] ; then
		board="am335x_evm"
	else
		board=${conf_board}
	fi

	wfile="${TEMPDIR}/disk/boot/SOC.sh"
	generate_soc

	#RootStock-NG
	if [ -f ${TEMPDIR}/disk/etc/rcn-ee.conf ] ; then
		. ${TEMPDIR}/disk/etc/rcn-ee.conf

		mkdir -p ${TEMPDIR}/disk/boot/uboot || true

		wfile="${TEMPDIR}/disk/etc/fstab"
		echo "# /etc/fstab: static file system information." > ${wfile}
		echo "#" >> ${wfile}
		echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${wfile}
		echo "#" >> ${wfile}

		if [ "x${option_ro_root}" = "xenable" ] ; then
			echo "#With read only rootfs, we need to boot once as rw..." >> ${wfile}
			echo "${rootfs_drive}  /  ext2  noatime,errors=remount-ro  0  1" >> ${wfile}
			echo "#" >> ${wfile}
			echo "#Switch to read only rootfs:" >> ${wfile}
			echo "#${rootfs_drive}  /  ext2  noatime,ro,errors=remount-ro  0  1" >> ${wfile}
			echo "#" >> ${wfile}
			echo "${rootfs_var_drive}  /var  ${ROOTFS_TYPE}  noatime  0  2" >> ${wfile}
		else
			echo "${rootfs_drive}  /  ${ROOTFS_TYPE}  noatime,errors=remount-ro  0  1" >> ${wfile}
		fi

		echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> ${wfile}

		if [ "x${distro}" = "xDebian" ] ; then
			#/etc/inittab is gone in Jessie with systemd...
			if [ -f ${TEMPDIR}/disk/etc/inittab ] ; then
				wfile="${TEMPDIR}/disk/etc/inittab"
				serial_num=$(echo -n "${SERIAL}"| tail -c -1)
				echo "" >> ${wfile}
				echo "T${serial_num}:23:respawn:/sbin/getty -L ${SERIAL} 115200 vt102" >> ${wfile}
				echo "" >> ${wfile}
			fi
		fi

		if [ "x${distro}" = "xUbuntu" ] ; then
			wfile="${TEMPDIR}/disk/etc/init/serial.conf"
			echo "start on stopped rc RUNLEVEL=[2345]" > ${wfile}
			echo "stop on runlevel [!2345]" >> ${wfile}
			echo "" >> ${wfile}
			echo "respawn" >> ${wfile}
			echo "exec /sbin/getty 115200 ${SERIAL}" >> ${wfile}
		fi

		wfile="${TEMPDIR}/disk/etc/network/interfaces"
		echo "# This file describes the network interfaces available on your system" > ${wfile}
		echo "# and how to activate them. For more information, see interfaces(5)." >> ${wfile}
		echo "" >> ${wfile}
		echo "# The loopback network interface" >> ${wfile}
		echo "auto lo" >> ${wfile}
		echo "iface lo inet loopback" >> ${wfile}
		echo "" >> ${wfile}
		echo "# The primary network interface" >> ${wfile}

		if [ "${DISABLE_ETH}" ] ; then
			echo "#${DISABLE_ETH}" >> ${wfile}
		else
			echo "auto eth0"  >> ${wfile}
			echo "iface eth0 inet dhcp" >> ${wfile}
		fi

		#if we have systemd & wicd-gtk, disable eth0 in /etc/network/interfaces
		if [ -f ${TEMPDIR}/disk/lib/systemd/systemd ] ; then
			if [ -f ${TEMPDIR}/disk/usr/bin/wicd-gtk ] ; then
				sed -i 's/auto eth0/#auto eth0/g' ${wfile}
				sed -i 's/allow-hotplug eth0/#allow-hotplug eth0/g' ${wfile}
				sed -i 's/iface eth0 inet dhcp/#iface eth0 inet dhcp/g' ${wfile}
			fi
		fi

		#if we have connman, disable eth0 in /etc/network/interfaces
		if [ -f ${TEMPDIR}/disk/etc/init.d/connman ] ; then
			sed -i 's/auto eth0/#auto eth0/g' ${wfile}
			sed -i 's/allow-hotplug eth0/#allow-hotplug eth0/g' ${wfile}
			sed -i 's/iface eth0 inet dhcp/#iface eth0 inet dhcp/g' ${wfile}
		fi

		echo "# Example to keep MAC address between reboots" >> ${wfile}
		echo "#hwaddress ether DE:AD:BE:EF:CA:FE" >> ${wfile}

		echo "" >> ${wfile}
		echo "# The secondary network interface" >> ${wfile}
		echo "#auto eth1" >> ${wfile}
		echo "#iface eth1 inet dhcp" >> ${wfile}

		echo "" >> ${wfile}

		echo "# WiFi use: -> connmanctl" >> ${wfile}

		echo "" >> ${wfile}

		echo "# Ethernet/RNDIS gadget (g_ether)" >> ${wfile}
		echo "# Used by: /opt/scripts/boot/autoconfigure_usb0.sh" >> ${wfile}
		echo "auto usb0" >> ${wfile}
		echo "allow-hotplug usb0" >> ${wfile}
		echo "iface usb0 inet static" >> ${wfile}
		echo "    address 192.168.7.2" >> ${wfile}
		echo "    netmask 255.255.255.252" >> ${wfile}
		echo "    network 192.168.7.0" >> ${wfile}

		if [ -f ${TEMPDIR}/disk/var/www/index.html ] ; then
			rm -f ${TEMPDIR}/disk/var/www/index.html || true
		fi

		if [ -f ${TEMPDIR}/disk/var/www/html/index.html ] ; then
			rm -f ${TEMPDIR}/disk/var/www/html/index.html || true
		fi
		sync

	fi #RootStock-NG

	if [ ! "x${uboot_name}" = "x" ] ; then
		echo "Backup version of u-boot: /opt/backup/uboot/"
		mkdir -p ${TEMPDIR}/disk/opt/backup/uboot/
		cp -v ${TEMPDIR}/dl/${UBOOT} ${TEMPDIR}/disk/opt/backup/uboot/${uboot_name}
	fi

	if [ ! "x${spl_uboot_name}" = "x" ] ; then
		mkdir -p ${TEMPDIR}/disk/opt/backup/uboot/
		cp -v ${TEMPDIR}/dl/${SPL} ${TEMPDIR}/disk/opt/backup/uboot/${spl_uboot_name}
	fi

	if [ ! -f ${TEMPDIR}/etc/udev/rules.d/60-omap-tty.rules ] ; then
		file="/etc/udev/rules.d/60-omap-tty.rules"
		echo "#from: http://arago-project.org/git/meta-ti.git?a=commit;h=4ce69eff28103778508d23af766e6204c95595d3" > ${TEMPDIR}/disk${file}
		echo "" > ${TEMPDIR}/disk${file}
		echo "# Backward compatibility with old OMAP UART-style ttyO0 naming" > ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
		echo "SUBSYSTEM==\"tty\", ATTR{uartclk}!=\"0\", KERNEL==\"ttyS[0-9]\", SYMLINK+=\"ttyO%n\"" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
	fi

	if [ "x${conf_board}" = "xam335x_boneblack" ] || [ "x${conf_board}" = "xam335x_evm" ] || [ "x${conf_board}" = "xarduino-tre" ] ; then

		file="/etc/udev/rules.d/70-persistent-net.rules"
		echo "" > ${TEMPDIR}/disk${file}
		echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${TEMPDIR}/disk${file}
		echo "# udevadm info -q all -p /sys/class/net/eth0 --attribute-walk" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
		echo "# BeagleBone: net device ()" >> ${TEMPDIR}/disk${file}
		echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"cpsw\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"eth0\"" >> ${TEMPDIR}/disk${file}
		echo "" >> ${TEMPDIR}/disk${file}
	fi

	if [ ! -f ${TEMPDIR}/disk/opt/scripts/boot/generic-startup.sh ] ; then
		git clone https://github.com/RobertCNelson/boot-scripts ${TEMPDIR}/disk/opt/scripts/ --depth 1
		sudo chown -R 1000:1000 ${TEMPDIR}/disk/opt/scripts/
	else
		cd ${TEMPDIR}/disk/opt/scripts/
		git pull
		cd -
		sudo chown -R 1000:1000 ${TEMPDIR}/disk/opt/scripts/
	fi

	if [ "x${drm}" = "xomapdrm" ] ; then
		wfile="/etc/X11/xorg.conf"
		if [ -f ${TEMPDIR}/disk${wfile} ] ; then
			sudo sed -i -e 's:modesetting:omap:g' ${TEMPDIR}/disk${wfile}
			sudo sed -i -e 's:fbdev:omap:g' ${TEMPDIR}/disk${wfile}

			if [ "x${conf_board}" = "xomap3_beagle" ] ; then
				sudo sed -i -e 's:#HWcursor_false::g' ${TEMPDIR}/disk${wfile}
			else
				sudo sed -i -e 's:#HWcursor_false::g' ${TEMPDIR}/disk${wfile}
				sudo sed -i -e 's:16:24:g' ${TEMPDIR}/disk${wfile}
			fi
		fi
	fi

	if [ "${usbnet_mem}" ] ; then
		echo "vm.min_free_kbytes = ${usbnet_mem}" >> ${TEMPDIR}/disk/etc/sysctl.conf
	fi

	if [ "${need_wandboard_firmware}" ] ; then
		http_brcm="https://raw.githubusercontent.com/Freescale/meta-fsl-arm-extra/master/recipes-bsp/broadcom-nvram-config/files/wandboard"
		${dl_quiet} --directory-prefix="${TEMPDIR}/disk/lib/firmware/brcm/" ${http_brcm}/brcmfmac4329-sdio.txt
		${dl_quiet} --directory-prefix="${TEMPDIR}/disk/lib/firmware/brcm/" ${http_brcm}/brcmfmac4330-sdio.txt
	fi

	if [ ! "x${new_hostname}" = "x" ] ; then
		echo "Updating Image hostname too: [${new_hostname}]"

		wfile="/etc/hosts"
		echo "127.0.0.1	localhost" > ${TEMPDIR}/disk${wfile}
		echo "127.0.1.1	${new_hostname}.localdomain	${new_hostname}" >> ${TEMPDIR}/disk${wfile}
		echo "" >> ${TEMPDIR}/disk${wfile}
		echo "# The following lines are desirable for IPv6 capable hosts" >> ${TEMPDIR}/disk${wfile}
		echo "::1     localhost ip6-localhost ip6-loopback" >> ${TEMPDIR}/disk${wfile}
		echo "ff02::1 ip6-allnodes" >> ${TEMPDIR}/disk${wfile}
		echo "ff02::2 ip6-allrouters" >> ${TEMPDIR}/disk${wfile}

		wfile="/etc/hostname"
		echo "${new_hostname}" > ${TEMPDIR}/disk${wfile}
	fi

	cd ${TEMPDIR}/disk/
	sync
	sync
	cd "${DIR}/"

	if [ "x${option_ro_root}" = "xenable" ] ; then
		umount ${TEMPDIR}/disk/var || true
	fi

	umount ${TEMPDIR}/disk || true
	if [ "x${build_img_file}" = "xenable" ] ; then
		sync
		kpartx -d ${media_loop} || true
		losetup -d ${media_loop} || true
	fi

	echo "Finished populating rootfs Partition"
	echo "-----------------------------"

	echo "setup_sdcard.sh script complete"
	if [ -f "${DIR}/user_password.list" ] ; then
		echo "-----------------------------"
		echo "The default user:password for this image:"
		cat "${DIR}/user_password.list"
		echo "-----------------------------"
	fi
	if [ "x${build_img_file}" = "xenable" ] ; then
		echo "Image file: ${imagename}"
		echo "-----------------------------"

		if [ "x${usb_flasher}" = "x" ] && [ "x${emmc_flasher}" = "x" ] ; then
			wfile="${imagename}.xz.job.txt"
			echo "abi=aaa" > ${wfile}
			echo "conf_image=${imagename}.xz" >> ${wfile}
			bmapimage=$(echo ${imagename} | awk -F ".img" '{print $1}')
			echo "conf_bmap=${bmapimage}.bmap" >> ${wfile}
			echo "conf_resize=enable" >> ${wfile}
			echo "conf_partition1_startmb=${conf_boot_startmb}" >> ${wfile}

			case "${conf_boot_fstype}" in
			fat)
				echo "conf_partition1_fstype=0xE" >> ${wfile}
				;;
			ext2|ext3|ext4)
				echo "conf_partition1_fstype=0x83" >> ${wfile}
				;;
			esac

			if [ "x${media_rootfs_partition}" = "x2" ] ; then
				echo "conf_partition1_endmb=${conf_boot_endmb}" >> ${wfile}
				echo "conf_partition2_fstype=0x83" >> ${wfile}
			fi
			echo "conf_root_partition=${media_rootfs_partition}" >> ${wfile}
		fi
	fi
}

check_mmc () {
	FDISK=$(LC_ALL=C fdisk -l 2>/dev/null | grep "Disk ${media}:" | awk '{print $2}')

	if [ "x${FDISK}" = "x${media}:" ] ; then
		echo ""
		echo "I see..."
		echo ""
		echo "lsblk:"
		lsblk | grep -v sr0
		echo ""
		unset response
		echo -n "Are you 100% sure, on selecting [${media}] (y/n)? "
		read response
		if [ "x${response}" != "xy" ] ; then
			exit
		fi
		echo ""
	else
		echo ""
		echo "Are you sure? I Don't see [${media}], here is what I do see..."
		echo ""
		echo "lsblk:"
		lsblk | grep -v sr0
		echo ""
		exit
	fi
}

process_dtb_conf () {
	if [ "${conf_warning}" ] ; then
		show_board_warning
	fi

	echo "-----------------------------"

	#defaults, if not set...
	conf_boot_startmb=${conf_boot_startmb:-"1"}
	#https://wiki.linaro.org/WorkingGroups/KernelArchived/Projects/FlashCardSurvey
	conf_root_device=${conf_root_device:-"/dev/mmcblk0"}

	#error checking...
	if [ ! "${conf_boot_fstype}" ] ; then
		conf_boot_fstype="${ROOTFS_TYPE}"
	fi

	case "${conf_boot_fstype}" in
	fat)
		sfdisk_fstype="0xE"
		;;
	ext2|ext3|ext4)
		sfdisk_fstype="L"
		;;
	*)
		echo "Error: [conf_boot_fstype] not recognized, stopping..."
		exit
		;;
	esac
}

check_dtb_board () {
	error_invalid_dtb=1

	#/hwpack/${dtb_board}.conf
	unset leading_slash
	leading_slash=$(echo ${dtb_board} | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		dtb_board=$(echo "${leading_slash##*/}")
	fi

	#${dtb_board}.conf
	dtb_board=$(echo ${dtb_board} | awk -F ".conf" '{print $1}')
	if [ -f "${DIR}"/hwpack/${dtb_board}.conf ] ; then
		. "${DIR}"/hwpack/${dtb_board}.conf

		boot=${boot_image}
		unset error_invalid_dtb
		process_dtb_conf
	else
		cat <<-__EOF__
			-----------------------------
			ERROR: This script does not currently recognize the selected: [--dtb ${dtb_board}] option..
			Please rerun $(basename $0) with a valid [--dtb <device>] option from the list below:
			-----------------------------
		__EOF__
		cat "${DIR}"/hwpack/*.conf | grep supported
		echo "-----------------------------"
		exit
	fi
}

usage () {
	echo "usage: sudo $(basename $0) --mmc /dev/sdX --dtb <dev board>"
	#tabed to match 
		cat <<-__EOF__
			-----------------------------
			Bugs email: "bugs at rcn-ee.com"

			Required Options:
			--mmc </dev/sdX> or --img <filename.img>

			--dtb <dev board>

			Additional Options:
			        -h --help

			--probe-mmc
			        <list all partitions: sudo ./setup_sdcard.sh --probe-mmc>

			__EOF__
	exit
}

checkparm () {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

error_invalid_dtb=1

# parse commandline options
while [ ! -z "$1" ] ; do
	case $1 in
	-h|--help)
		usage
		media=1
		;;
	--hostname)
		checkparm $2
		new_hostname="$2"
		;;
	--probe-mmc)
		media="/dev/idontknow"
		check_root
		check_mmc
		;;
	--mmc)
		checkparm $2
		media="$2"
		media_prefix="${media}"
		echo ${media} | grep mmcblk >/dev/null && media_prefix="${media}p"
		check_root
		check_mmc
		;;
	--img|--img-[1248]gb)
		checkparm $2
		name=${2:-image}
		gsize=$(echo "$1" | sed -ne 's/^--img-\([[:digit:]]\+\)gb$/\1/p')
		# --img defaults to --img-2gb
		gsize=${gsize:-2}
		imagename=${name%.img}-${gsize}gb.img
		media="${DIR}/${imagename}"
		build_img_file="enable"
		check_root
		if [ -f "${media}" ] ; then
			rm -rf "${media}" || true
		fi
		#FIXME: (should fit most microSD cards)
		#eMMC: (dd if=/dev/mmcblk1 of=/dev/null bs=1M #MB)
		#Micron   3744MB (bbb): 3925868544 bytes -> 3925.86 Megabyte
		#Kingston 3688MB (bbb): 3867148288 bytes -> 3867.15 Megabyte
		#Kingston 3648MB (x15): 3825205248 bytes -> 3825.21 Megabyte (3648)
		#
		### seek=$((1024 * (700 + (gsize - 1) * 1000)))
		## 1000 1GB = 700 #2GB = 1700 #4GB = 3700
		##  990 1GB = 700 #2GB = 1690 #4GB = 3670
		#
		### seek=$((1024 * (gsize * 850)))
		## x 850 (85%) #1GB = 850 #2GB = 1700 #4GB = 3400
		#
		dd if=/dev/zero of="${media}" bs=1024 count=0 seek=$((1024 * (gsize * 850)))
		;;
	--dtb)
		checkparm $2
		dtb_board="$2"
		dir_check="${DIR}/"
		kernel_detection
		check_dtb_board
		;;
	--ro)
		conf_var_startmb="2048"
		option_ro_root="enable"
		;;
	--rootfs)
		checkparm $2
		ROOTFS_TYPE="$2"
		;;
	--boot_label)
		checkparm $2
		BOOT_LABEL="$2"
		;;
	--rootfs_label)
		checkparm $2
		ROOTFS_LABEL="$2"
		;;
	--spl)
		checkparm $2
		LOCAL_SPL="$2"
		USE_LOCAL_BOOT=1
		;;
	--bootloader)
		checkparm $2
		LOCAL_BOOTLOADER="$2"
		USE_LOCAL_BOOT=1
		;;
	--use-beta-bootloader)
		USE_BETA_BOOTLOADER=1
		;;
	--a335-flasher)
		oem_blank_eeprom="enable"
		a335_flasher="enable"
		;;
	--bbg-flasher)
		oem_blank_eeprom="enable"
		bbg_flasher="enable"
		;;
	--bbgw-flasher)
		oem_blank_eeprom="enable"
		bbgw_flasher="enable"
		;;
	--bbb-usb-flasher|--usb-flasher|--oem-flasher)
		oem_blank_eeprom="enable"
		usb_flasher="enable"
		;;
	--bbb-flasher|--emmc-flasher)
		oem_blank_eeprom="enable"
		emmc_flasher="enable"
		;;
	--bbb-old-bootloader-in-emmc)
		bbb_old_bootloader_in_emmc="enable"
		;;
	--oem-flasher-img)
		checkparm $2
		oem_flasher_img="$2"
		;;
	--oem-flasher-bmap)
		checkparm $2
		oem_flasher_bmap="$2"
		;;
	--oem-flasher-eeprom)
		checkparm $2
		oem_flasher_eeprom="$2"
		;;
	--oem-flasher-job)
		checkparm $2
		oem_flasher_job="$2"
		;;
	--enable-systemd)
		enable_systemd="enabled"
		;;
	--offline)
		offline=1
		;;
	--kernel)
		checkparm $2
		kernel_override="$2"
		;;
	esac
	shift
done

if [ ! "${media}" ] ; then
	echo "ERROR: --mmc undefined"
	usage
fi

if [ "${error_invalid_dtb}" ] ; then
	echo "-----------------------------"
	echo "ERROR: --dtb undefined"
	echo "-----------------------------"
	usage
fi

if ! is_valid_rootfs_type ${ROOTFS_TYPE} ; then
	echo "ERROR: ${ROOTFS_TYPE} is not a valid root filesystem type"
	echo "Valid types: ${VALID_ROOTFS_TYPES}"
	exit
fi

find_issue
detect_software

if [ "${spl_name}" ] || [ "${boot_name}" ] ; then
	if [ "${USE_LOCAL_BOOT}" ] ; then
		local_bootloader
	else
		dl_bootloader
	fi
fi

if [ ! "x${build_img_file}" = "xenable" ] ; then
	unmount_all_drive_partitions
fi
create_partitions
populate_boot
populate_rootfs
exit 0
#
