#!/bin/bash -ex
#
# Copyright (c) 2012-2020 Robert Nelson <robertcnelson@gmail.com>
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

DIR=$PWD
host_arch="$(uname -m)"
time=$(date +%Y-%m-%d)
OIB_DIR="$(dirname "$( cd "$(dirname "$0")" ; pwd -P )" )"
chroot_completed="false"

abi=ad

#ac=change /sys/kernel/debug mount persmissions
#ab=efi added 20180321
#aa

. "${DIR}/.project"

check_defines () {
	if [ ! "${tempdir}" ] ; then
		echo "scripts/deboostrap_first_stage.sh: Error: tempdir undefined"
		exit 1
	fi

	cd "${tempdir}/" || true
	test_tempdir=$(pwd -P)
	cd "${DIR}/" || true

	if [ ! "x${tempdir}" = "x${test_tempdir}" ] ; then
		tempdir="${test_tempdir}"
		echo "Log: tempdir is really: [${test_tempdir}]"
	fi

	if [ ! "${export_filename}" ] ; then
		echo "scripts/deboostrap_first_stage.sh: Error: export_filename undefined"
		exit 1
	fi

	if [ ! "${deb_distribution}" ] ; then
		echo "scripts/deboostrap_first_stage.sh: Error: deb_distribution undefined"
		exit 1
	fi

	if [ ! "${deb_codename}" ] ; then
		echo "scripts/deboostrap_first_stage.sh: Error: deb_codename undefined"
		exit 1
	fi

	if [ ! "${deb_arch}" ] ; then
		echo "scripts/deboostrap_first_stage.sh: Error: deb_arch undefined"
		exit 1
	fi

	if [ ! "${apt_proxy}" ] ; then
		apt_proxy=""
	fi

	case "${deb_distribution}" in
	debian)
		deb_components=${deb_components:-"main contrib non-free"}
		deb_mirror=${deb_mirror:-"deb.debian.org/debian"}
		;;
	ubuntu)
		deb_components=${deb_components:-"main universe multiverse"}
		deb_mirror=${deb_mirror:-"ports.ubuntu.com/"}
		;;
	esac

	if [ ! "${rfs_username}" ] ; then
		##Backwards compat pre variables.txt doc
		if [ "${user_name}" ] ; then
			rfs_username="${user_name}"
		else
			rfs_username="${deb_distribution}"
			echo "rfs_username: undefined using: [${rfs_username}]"
		fi
	fi

	if [ ! "${rfs_fullname}" ] ; then
		##Backwards compat pre variables.txt doc
		if [ "${full_name}" ] ; then
			rfs_fullname="${full_name}"
		else
			rfs_fullname="Demo User"
			echo "rfs_fullname: undefined using: [${rfs_fullname}]"
		fi
	fi

	if [ ! "${rfs_password}" ] ; then
		##Backwards compat pre variables.txt doc
		if [ "${password}" ] ; then
			rfs_password="${password}"
		else
			rfs_password="temppwd"
			echo "rfs_password: undefined using: [${rfs_password}]"
		fi
	fi

	if [ ! "${rfs_hostname}" ] ; then
		##Backwards compat pre variables.txt doc
		if [ "${image_hostname}" ] ; then
			rfs_hostname="${image_hostname}"
		else
			rfs_hostname="arm"
			echo "rfs_hostname: undefined using: [${rfs_hostname}]"
		fi
	fi

	if [ "x${deb_additional_pkgs}" = "x" ] ; then
		##Backwards compat pre configs
		if [ ! "x${base_pkg_list}" = "x" ] ; then
			deb_additional_pkgs="$(echo ${base_pkg_list} | sed 's/,/ /g' | sed 's/\t/,/g')"
		fi
	else
		deb_additional_pkgs="$(echo ${deb_additional_pkgs} | sed 's/,/ /g' | sed 's/\t/,/g')"
	fi

	if [ ! "x${deb_include}" = "x" ] ; then
		include=$(echo ${deb_include} | sed 's/,/ /g' | sed 's/\t/,/g')
		deb_additional_pkgs="${deb_additional_pkgs} ${include}"
	fi

	if [ "x${repo_rcnee}" = "xenable" ] ; then
		if [ ! "x${repo_rcnee_pkg_list}" = "x" ] ; then
			include=$(echo ${repo_rcnee_pkg_list} | sed 's/,/ /g' | sed 's/\t/,/g')
			deb_additional_pkgs="${deb_additional_pkgs} ${include}"
		fi

		if [ "x${repo_rcnee_sgx}" = "xenable" ] ; then
			if [ ! "x${repo_rcnee_sgx_pkg_list}" = "x" ] ; then
				include=$(echo ${repo_rcnee_sgx_pkg_list} | sed 's/,/ /g' | sed 's/\t/,/g')
				deb_additional_pkgs="${deb_additional_pkgs} ${include}"
			fi
		fi
	fi
}

report_size () {
	echo "Log: Size of: [${tempdir}]: $(du -sh ${tempdir} 2>/dev/null | awk '{print $1}')"
}

chroot_mount_run () {
	if [ ! -d "${tempdir}/run" ] ; then
		sudo mkdir -p ${tempdir}/run || true
		sudo chmod -R 755 ${tempdir}/run
	fi

	if [ "$(mount | grep ${tempdir}/run | awk '{print $3}')" != "${tempdir}/run" ] ; then
		sudo mount -t tmpfs run "${tempdir}/run"
	fi
}

chroot_mount () {
	if [ "$(mount | grep ${tempdir}/sys | awk '{print $3}')" != "${tempdir}/sys" ] ; then
		sudo mount -t sysfs sysfs "${tempdir}/sys"
	fi

	if [ "$(mount | grep ${tempdir}/proc | awk '{print $3}')" != "${tempdir}/proc" ] ; then
		sudo mount -t proc proc "${tempdir}/proc"
	fi

	if [ ! -d "${tempdir}/dev/pts" ] ; then
		sudo mkdir -p ${tempdir}/dev/pts || true
	fi

	if [ "$(mount | grep ${tempdir}/dev/pts | awk '{print $3}')" != "${tempdir}/dev/pts" ] ; then
		sudo mount -t devpts devpts "${tempdir}/dev/pts"
	fi
}

chroot_umount () {
	if [ "$(mount | grep ${tempdir}/dev/pts | awk '{print $3}')" = "${tempdir}/dev/pts" ] ; then
		echo "Log: umount: [${tempdir}/dev/pts]"
		sync
		sudo umount -fl "${tempdir}/dev/pts"

		if [ "$(mount | grep ${tempdir}/dev/pts | awk '{print $3}')" = "${tempdir}/dev/pts" ] ; then
			echo "Log: ERROR: umount [${tempdir}/dev/pts] failed..."
			exit 1
		fi
	fi

	if [ "$(mount | grep ${tempdir}/proc | awk '{print $3}')" = "${tempdir}/proc" ] ; then
		echo "Log: umount: [${tempdir}/proc]"
		sync
		sudo umount -fl "${tempdir}/proc"

		if [ "$(mount | grep ${tempdir}/proc | awk '{print $3}')" = "${tempdir}/proc" ] ; then
			echo "Log: ERROR: umount [${tempdir}/proc] failed..."
			exit 1
		fi
	fi

	if [ "$(mount | grep ${tempdir}/sys | awk '{print $3}')" = "${tempdir}/sys" ] ; then
		echo "Log: umount: [${tempdir}/sys]"
		sync
		sudo umount -fl "${tempdir}/sys"

		if [ "$(mount | grep ${tempdir}/sys | awk '{print $3}')" = "${tempdir}/sys" ] ; then
			echo "Log: ERROR: umount [${tempdir}/sys] failed..."
			exit 1
		fi
	fi

	if [ "$(mount | grep ${tempdir}/run | awk '{print $3}')" = "${tempdir}/run" ] ; then
		echo "Log: umount: [${tempdir}/run]"
		sync
		sudo umount -fl "${tempdir}/run"

		if [ "$(mount | grep ${tempdir}/run | awk '{print $3}')" = "${tempdir}/run" ] ; then
			echo "Log: ERROR: umount [${tempdir}/run] failed..."
			exit 1
		fi
	fi
}

chroot_stopped () {
	chroot_umount
	if [ ! "x${chroot_completed}" = "xtrue" ] ; then
		exit 1
	fi
}

trap chroot_stopped EXIT

check_defines

if [ "x${host_arch}" != "xarmv7l" ] && [ "x${host_arch}" != "xaarch64" ] ; then
	if [ "x${deb_arch}" = "xarmel" ] || [ "x${deb_arch}" = "xarmhf" ] ; then
		sudo cp $(which qemu-arm-static) "${tempdir}/usr/bin/"
	fi
	if [ "x${deb_arch}" = "xarm64" ] ; then
		sudo cp $(which qemu-aarch64-static) "${tempdir}/usr/bin/"
	fi
fi

chroot_mount_run
echo "Log: Running: debootstrap second-stage in [${tempdir}]"
sudo chroot "${tempdir}" debootstrap/debootstrap --second-stage
echo "Log: Complete: [sudo chroot ${tempdir} debootstrap/debootstrap --second-stage]"
report_size

if [ "x${chroot_very_small_image}" = "xenable" ] ; then
	#so debootstrap just extracts the *.deb's, so lets clean this up hackish now,
	#but then allow dpkg to delete these extra files when installed later..
	sudo rm -rf "${tempdir}"/usr/share/locale/* || true
	sudo rm -rf "${tempdir}"/usr/share/man/* || true
	sudo rm -rf "${tempdir}"/usr/share/doc/* || true

	#dpkg 1.15.8++, No Docs...
	sudo mkdir -p "${tempdir}/etc/dpkg/dpkg.cfg.d/" || true
	echo "# Delete locales" > /tmp/01_nodoc
	echo "path-exclude=/usr/share/locale/*" >> /tmp/01_nodoc
	echo ""  >> /tmp/01_nodoc

	echo "# Delete man pages" >> /tmp/01_nodoc
	echo "path-exclude=/usr/share/man/*" >> /tmp/01_nodoc
	echo "" >> /tmp/01_nodoc

	echo "# Delete docs" >> /tmp/01_nodoc
	echo "path-exclude=/usr/share/doc/*" >> /tmp/01_nodoc
	echo "path-include=/usr/share/doc/*/copyright" >> /tmp/01_nodoc
	echo "" >> /tmp/01_nodoc

	sudo mv /tmp/01_nodoc "${tempdir}/etc/dpkg/dpkg.cfg.d/01_nodoc"

	sudo mkdir -p "${tempdir}/etc/apt/apt.conf.d/" || true

	#apt: no local cache
	echo "Dir::Cache {" > /tmp/02nocache
	echo "  srcpkgcache \"\";" >> /tmp/02nocache
	echo "  pkgcache \"\";" >> /tmp/02nocache
	echo "}" >> /tmp/02nocache
	sudo mv  /tmp/02nocache "${tempdir}/etc/apt/apt.conf.d/02nocache"

	#apt: drop translations...
	echo "Acquire::Languages \"none\";" > /tmp/02translations
	sudo mv /tmp/02translations "${tempdir}/etc/apt/apt.conf.d/02translations"

	echo "Log: after locale/man purge"
	report_size
fi


sudo mkdir -p "${tempdir}/etc/dpkg/dpkg.cfg.d/" || true

echo "# neuter flash-kernel" > /tmp/01_noflash_kernel
echo "path-exclude=/usr/share/flash-kernel/db/all.db" >> /tmp/01_noflash_kernel
echo "path-exclude=/etc/initramfs/post-update.d/flash-kernel" >> /tmp/01_noflash_kernel
echo "path-exclude=/etc/kernel/postinst.d/zz-flash-kernel" >> /tmp/01_noflash_kernel
echo "path-exclude=/etc/kernel/postrm.d/zz-flash-kernel" >> /tmp/01_noflash_kernel
echo ""  >> /tmp/01_noflash_kernel

sudo mv /tmp/01_noflash_kernel "${tempdir}/etc/dpkg/dpkg.cfg.d/01_noflash_kernel"

sudo mkdir -p "${tempdir}/usr/share/flash-kernel/db/" || true
sudo cp -v "${OIB_DIR}/target/other/rcn-ee.db" "${tempdir}/usr/share/flash-kernel/db/"

#generic apt.conf tweaks for flash/mmc devices to save on wasted space...
sudo mkdir -p "${tempdir}/etc/apt/apt.conf.d/" || true

#apt: emulate apt-get clean:
echo '#Custom apt-get clean' > /tmp/02apt-get-clean
echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb || true"; };' >> /tmp/02apt-get-clean
echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb || true"; };' >> /tmp/02apt-get-clean
sudo mv /tmp/02apt-get-clean "${tempdir}/etc/apt/apt.conf.d/02apt-get-clean"

#apt: drop translations
echo 'Acquire::Languages "none";' > /tmp/02-no-languages
sudo mv /tmp/02-no-languages "${tempdir}/etc/apt/apt.conf.d/02-no-languages"

if [ "x${deb_distribution}" = "xdebian" ] ; then
	#apt: /var/lib/apt/lists/, store compressed only
	case "${deb_codename}" in
	stretch|buster)
		echo 'Acquire::GzipIndexes "true"; APT::Compressor::xz::Cost "40";' > /tmp/02compress-indexes
		sudo mv /tmp/02compress-indexes "${tempdir}/etc/apt/apt.conf.d/02compress-indexes"
		;;
	sid)
		###FIXME: close to release switch to ^ xz, right now <next> is slow on apt...
		echo 'Acquire::GzipIndexes "true"; APT::Compressor::gzip::Cost "40";' > /tmp/02compress-indexes
		sudo mv /tmp/02compress-indexes "${tempdir}/etc/apt/apt.conf.d/02compress-indexes"
		;;
	esac

	if [ "${apt_proxy}" ] ; then
		#apt: make sure apt-cacher-ng doesn't break https repos
		echo 'Acquire::http::Proxy::deb.nodesource.com "DIRECT";' > /tmp/03-proxy-https
		sudo mv /tmp/03-proxy-https "${tempdir}/etc/apt/apt.conf.d/03-proxy-https"
	fi
fi

#set initial 'seed' time...
sudo sh -c "date --utc \"+%4Y%2m%2d%2H%2M\" > ${tempdir}/etc/timestamp"

wfile="/tmp/sources.list"
echo "deb http://${deb_mirror} ${deb_codename} ${deb_components}" > ${wfile}
echo "#deb-src http://${deb_mirror} ${deb_codename} ${deb_components}" >> ${wfile}
echo "" >> ${wfile}

#https://wiki.debian.org/StableUpdates
case "${deb_codename}" in
sid)
	echo "#deb http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "##deb-src http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	;;
*)
	echo "deb http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "#deb-src http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	;;
esac

#https://wiki.debian.org/LTS/Using
case "${deb_codename}" in
stretch|buster)
	echo "deb http://deb.debian.org/debian-security ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "#deb-src http://deb.debian.org/debian-security ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	;;
sid)
	echo "#deb http://deb.debian.org/debian-security ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "##deb-src http://deb.debian.org/debian-security ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	;;
esac

#https://wiki.debian.org/Backports
if [ "x${chroot_enable_debian_backports}" = "xenable" ] ; then
	case "${deb_codename}" in
	stretch|buster)
		echo "deb http://deb.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
		echo "#deb-src http://deb.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
		echo "" >> ${wfile}
		;;
	esac
fi

if [ "x${repo_external}" = "xenable" ] ; then
	echo "" >> ${wfile}
	echo "deb [arch=${repo_external_arch}] ${repo_external_server} ${repo_external_dist} ${repo_external_components}" >> ${wfile}
	echo "#deb-src [arch=${repo_external_arch}] ${repo_external_server} ${repo_external_dist} ${repo_external_components}" >> ${wfile}
fi

if [ "x${repo_flat}" = "xenable" ] ; then
	echo "" >> ${wfile}
	for component in "${repo_flat_components[@]}" ; do
		echo "deb ${repo_flat_server} ${component}" >> ${wfile}
		echo "#deb-src ${repo_flat_server} ${component}" >> ${wfile}
	done
fi

if [ ! "x${repo_nodesource}" = "x" ] ; then
	echo "" >> ${wfile}
	echo "deb https://deb.nodesource.com/${repo_nodesource} ${repo_nodesource_dist} main" >> ${wfile}
	echo "#deb-src https://deb.nodesource.com/${repo_nodesource} ${repo_nodesource_dist} main" >> ${wfile}
	echo "" >> ${wfile}
	sudo cp -v "${OIB_DIR}/target/keyring/nodesource.gpg.key" "${tempdir}/tmp/nodesource.gpg.key"
fi

if [ "x${repo_azulsystems}" = "xenable" ] ; then
	echo "" >> ${wfile}
	echo "deb http://repos.azulsystems.com/${deb_distribution} stable main" >> ${wfile}
	echo "" >> ${wfile}
	sudo cp -v "${OIB_DIR}/target/keyring/repos.azulsystems.com.pubkey.asc" "${tempdir}/tmp/repos.azulsystems.com.pubkey.asc"
fi

if [ "x${repo_rcnee}" = "xenable" ] ; then
	#no: precise
	echo "" >> ${wfile}
	echo "#Kernel source (repos.rcn-ee.com) : https://github.com/RobertCNelson/linux-stable-rcn-ee" >> ${wfile}
	echo "#" >> ${wfile}
	echo "#git clone https://github.com/RobertCNelson/linux-stable-rcn-ee" >> ${wfile}
	echo "#cd ./linux-stable-rcn-ee" >> ${wfile}
	echo "#git checkout \`uname -r\` -b tmp" >> ${wfile}
	echo "#" >> ${wfile}
	echo "deb [arch=armhf] http://repos.rcn-ee.com/${deb_distribution}/ ${deb_codename} main" >> ${wfile}
	echo "#deb-src [arch=armhf] http://repos.rcn-ee.com/${deb_distribution}/ ${deb_codename} main" >> ${wfile}

	sudo cp -v "${OIB_DIR}/target/keyring/repos.rcn-ee.net-archive-keyring.asc" "${tempdir}/tmp/repos.rcn-ee.net-archive-keyring.asc"
fi

if [ "x${repo_ros}" = "xenable" ] ; then
	echo "" >> ${wfile}
	echo "deb [arch=armhf] http://packages.ros.org/ros/${deb_distribution} ${deb_codename} main" >> ${wfile}
	echo "#deb-src [arch=armhf] http://packages.ros.org/ros/${deb_distribution} ${deb_codename} main" >> ${wfile}

	sudo cp -v "${OIB_DIR}/target/keyring/ros-archive-keyring.asc" "${tempdir}/tmp/ros-archive-keyring.asc"
fi

if [ -f /tmp/sources.list ] ; then
	sudo mv /tmp/sources.list "${tempdir}/etc/apt/sources.list"
fi

if [ "x${repo_external}" = "xenable" ] ; then
	if [ ! "x${repo_external_key}" = "x" ] ; then
		sudo cp -v "${OIB_DIR}/target/keyring/${repo_external_key}" "${tempdir}/tmp/${repo_external_key}"
	fi
fi

if [ "x${repo_flat}" = "xenable" ] ; then
	if [ ! "x${repo_flat_key}" = "x" ] ; then
		sudo cp -v "${OIB_DIR}/target/keyring/${repo_flat_key}" "${tempdir}/tmp/${repo_flat_key}"
	fi
fi

if [ "${apt_proxy}" ] ; then
	echo "Acquire::http::Proxy \"http://${apt_proxy}\";" > /tmp/apt.conf
	sudo mv /tmp/apt.conf "${tempdir}/etc/apt/apt.conf"
fi

echo "127.0.0.1	localhost" > /tmp/hosts
echo "127.0.1.1	${rfs_hostname}.localdomain	${rfs_hostname}" >> /tmp/hosts
echo "" >> /tmp/hosts
echo "# The following lines are desirable for IPv6 capable hosts" >> /tmp/hosts
echo "::1     localhost ip6-localhost ip6-loopback" >> /tmp/hosts
echo "ff02::1 ip6-allnodes" >> /tmp/hosts
echo "ff02::2 ip6-allrouters" >> /tmp/hosts
sudo mv /tmp/hosts "${tempdir}/etc/hosts"
sudo chown root:root "${tempdir}/etc/hosts"

echo "${rfs_hostname}" > /tmp/hostname
sudo mv /tmp/hostname "${tempdir}/etc/hostname"
sudo chown root:root "${tempdir}/etc/hostname"

if [ "x${deb_arch}" = "xarmhf" ] ; then
	case "${deb_distribution}" in
	debian)
		case "${deb_codename}" in
		stretch|buster)
			#while bb-customizations installes "generic-board-startup.service" other boards/configs could use this default.
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-generic-board-startup.service" "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
			distro="Debian"
			;;
		esac
		;;
	ubuntu)
		case "${deb_codename}" in
		bionic|focal)
			#while bb-customizations installes "generic-board-startup.service" other boards/configs could use this default.
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-generic-board-startup.service" "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
			distro="Ubuntu"
			;;
		esac
		;;
	esac
fi

if [ "x${deb_arch}" = "xarmel" ] ; then
	sudo cp "${OIB_DIR}/target/init_scripts/systemd-generic-board-startup.service" "${tempdir}/lib/systemd/system/generic-board-startup.service"
	sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
	distro="Debian"
fi

#Backward compatibility, as setup_sdcard.sh expects [lsb_release -si > /etc/rcn-ee.conf]
echo "distro=${distro}" > /tmp/rcn-ee.conf
echo "deb_codename=${deb_codename}" >> /tmp/rcn-ee.conf
echo "rfs_username=${rfs_username}" >> /tmp/rcn-ee.conf
echo "release_date=${time}" >> /tmp/rcn-ee.conf
echo "third_party_modules=${third_party_modules}" >> /tmp/rcn-ee.conf
echo "abi=${abi}" >> /tmp/rcn-ee.conf
echo "image_type=${image_type}" >> /tmp/rcn-ee.conf
sudo mv /tmp/rcn-ee.conf "${tempdir}/etc/rcn-ee.conf"
sudo chown root:root "${tempdir}/etc/rcn-ee.conf"

#use /etc/dogtag for all:
if [ ! "x${rfs_etc_dogtag}" = "x" ] ; then
	sudo sh -c "echo '${rfs_etc_dogtag} ${time}' > '${tempdir}/etc/dogtag'"
fi

cat > "${DIR}/chroot_script.sh" <<-__EOF__
	#!/bin/sh -e
	export LC_ALL=C
	export DEBIAN_FRONTEND=noninteractive

	dpkg_check () {
		unset pkg_is_not_installed
		LC_ALL=C dpkg --list | awk '{print \$2}' | grep "^\${pkg}$" >/dev/null || pkg_is_not_installed="true"
	}

	dpkg_package_missing () {
		echo "Log: (chroot) package [\${pkg}] was not installed... (add to deb_include if functionality is really needed)"
	}

	is_this_qemu () {
		unset warn_qemu_will_fail
		if [ -f /usr/bin/qemu-arm-static ] ; then
			warn_qemu_will_fail=1
		fi
		if [ -f /usr/bin/qemu-aarch64-static ] ; then
			warn_qemu_will_fail=1
		fi
	}

	qemu_warning () {
		if [ "\${warn_qemu_will_fail}" ] ; then
			echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
			echo "Log: (chroot): [\${qemu_command}]"
		fi
	}

	stop_init () {
		echo "Log: (chroot): setting up: /usr/sbin/policy-rc.d"
		cat > /usr/sbin/policy-rc.d <<EOF
		#!/bin/sh
		exit 101
		EOF
		chmod +x /usr/sbin/policy-rc.d

		#set distro:
		. /etc/rcn-ee.conf

		if [ "x\${distro}" = "xUbuntu" ] ; then
			dpkg-divert --local --rename --add /sbin/initctl
			ln -s /bin/true /sbin/initctl
		fi
	}

	install_pkg_updates () {
		if [ -f /tmp/nodesource.gpg.key ] ; then
			apt-key add /tmp/nodesource.gpg.key
			rm -f /tmp/nodesource.gpg.key || true
		fi
		if [ -f /tmp/repos.azulsystems.com.pubkey.asc ] ; then
			apt-key add /tmp/repos.azulsystems.com.pubkey.asc
			rm -f /tmp/repos.azulsystems.com.pubkey.asc || true
		fi
		if [ "x${repo_rcnee}" = "xenable" ] ; then
			apt-key add /tmp/repos.rcn-ee.net-archive-keyring.asc
			rm -f /tmp/repos.rcn-ee.net-archive-keyring.asc || true
		fi
		if [ "x${repo_ros}" = "xenable" ] ; then
			apt-key add /tmp/ros-archive-keyring.asc
			rm -f /tmp/ros-archive-keyring.asc || true
		fi
		if [ "x${repo_external}" = "xenable" ] ; then
			apt-key add /tmp/${repo_external_key}
			rm -f /tmp/${repo_external_key} || true
		fi
		if [ "x${repo_flat}" = "xenable" ] ; then
			apt-key add /tmp/${repo_flat_key}
			rm -f /tmp/${repo_flat_key} || true
		fi

		if [ -f /etc/resolv.conf ] ; then
			echo "debug: networking: --------------"
			cat /etc/resolv.conf || true
			echo "---------------------------------"
			cp -v /etc/resolv.conf /etc/resolv.conf.bak
		fi

		echo "---------------------------------"
		echo "debug: apt-get update------------"
		apt-get update
		echo "---------------------------------"

		echo "debug: apt-get upgrade -y--------"
		apt-get upgrade -y

		if [ ! -f /etc/resolv.conf ] ; then
			echo "debug: /etc/resolv.conf was removed! Fixing..."
			#'/etc/resolv.conf.bak' -> '/etc/resolv.conf'
			#cp: not writing through dangling symlink '/etc/resolv.conf'
			cp -v --remove-destination /etc/resolv.conf.bak /etc/resolv.conf
		fi
		echo "---------------------------------"

		echo "debug: apt-get dist-upgrade -y---"
		apt-get dist-upgrade -y
		if [ ! -f /etc/resolv.conf ] ; then
			echo "debug: /etc/resolv.conf was removed! Fixing..."
			#'/etc/resolv.conf.bak' -> '/etc/resolv.conf'
			#cp: not writing through dangling symlink '/etc/resolv.conf'
			cp -v --remove-destination /etc/resolv.conf.bak /etc/resolv.conf
		fi
		echo "---------------------------------"

		if [ "x${chroot_very_small_image}" = "xenable" ] ; then
			if [ -f /bin/busybox ] ; then
				echo "Log: (chroot): Setting up BusyBox"

				busybox --install -s /usr/local/bin/

				#conflicts with systemd reboot...
				#BusyBox v1.22.1 (Debian 1:1.22.0-9+deb8u1) multi-call binary.
				if [ -f /usr/local/bin/reboot ] ; then
					rm -f /usr/local/bin/reboot
				fi

				#poweroff: broken...
				#BusyBox v1.22.1 (Debian 1:1.22.0-9+deb8u1) multi-call binary.
				if [ -f /usr/local/bin/poweroff ] ; then
					rm -f /usr/local/bin/poweroff
				fi

				#df: unrecognized option '--portability'
				#BusyBox v1.22.1 (Debian 1:1.22.0-9+deb8u1) multi-call binary.
				if [ -f /usr/local/bin/df ] ; then
					rm -f /usr/local/bin/df
				fi

				#tar: unrecognized option '--warning=no-timestamp'
				#BusyBox v1.22.1 (Debian 1:1.22.0-9+deb8u1) multi-call binary.
				if [ -f /usr/local/bin/tar ] ; then
					rm -f /usr/local/bin/tar
				fi

				#run-parts: unrecognized option '--list'
				#BusyBox v1.22.1 (Debian 1:1.22.0-9+deb8u1) multi-call binary.
				if [ -f /usr/local/bin/run-parts ] ; then
					rm -f /usr/local/bin/run-parts
				fi
			fi
		fi
	}

	install_pkgs () {
		if [ ! "x${deb_additional_pkgs}" = "x" ] ; then
			#Install the user choosen list.
			echo "Log: (chroot) Installing: ${deb_additional_pkgs}"
			apt-get update
			apt-get -y install ${deb_additional_pkgs}
		fi

		if [ "x${chroot_enable_debian_backports}" = "xenable" ] ; then
			if [ ! "x${chroot_debian_backports_pkg_list}" = "x" ] ; then
				echo "Log: (chroot) Installing (from backports): ${chroot_debian_backports_pkg_list}"
				sudo apt-get -y -t ${deb_codename}-backports install ${chroot_debian_backports_pkg_list}
			fi
		fi

		if [ ! "x${repo_external_pkg_list}" = "x" ] ; then
			echo "Log: (chroot) Installing (from external repo): ${repo_external_pkg_list}"
			apt-get -y install ${repo_external_pkg_list}
		fi

		if [ ! "x${repo_ros_pkg_list}" = "x" ] ; then
			echo "Log: (chroot) Installing (from external repo): ${repo_ros_pkg_list}"
			apt-get -y install ${repo_ros_pkg_list}
			#ROS: ubuntu, extra crude, cleanup....
			apt autoremove -y || true
		fi

		if [ ! "x${repo_rcnee_chromium_special}" = "x" ] ; then
			echo "Log: (chroot) Chromium Special:"
			apt-cache madison chromium || true
			apt -y --allow-downgrades install chromium=${repo_rcnee_chromium_special}* || true
			apt-mark hold chromium || true
		fi

		#Lets force depmod...
		if [ ! "x${repo_rcnee_depmod0}" = "x" ] ; then
			echo "Log: (chroot) Running depmod for: ${repo_rcnee_depmod0}"
			depmod -a ${repo_rcnee_depmod0}
			update-initramfs -u -k ${repo_rcnee_depmod0}
		fi

		#Lets force depmod...
		if [ ! "x${repo_rcnee_depmod1}" = "x" ] ; then
			echo "Log: (chroot) Running depmod for: ${repo_rcnee_depmod1}"
			depmod -a ${repo_rcnee_depmod1}
			update-initramfs -u -k ${repo_rcnee_depmod1}
		fi

		##Install last...
		if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
			echo "Log: (chroot) Installing modules for: ${repo_rcnee_pkg_version}"
			apt-get -y install libpruio-modules-${repo_rcnee_pkg_version} || true
			apt-get -y install rtl8723bu-modules-${repo_rcnee_pkg_version} || true
			apt-get -y install rtl8821cu-modules-${repo_rcnee_pkg_version} || true
			apt-get -y install seeed-modules-${repo_rcnee_pkg_version} || true

			if [ ! "x${repo_rcnee_cmem_version}" = "x" ] ; then
				apt-get -y install ti-cmem-${repo_rcnee_cmem_version}-modules-${repo_rcnee_pkg_version} || true
			else
				apt-get -y install ti-cmem-modules-${repo_rcnee_pkg_version} || true
			fi

			if [ ! "x${repo_rcnee_sgx_preinstall}" = "x" ] ; then
				apt-get -y install ${repo_rcnee_sgx_preinstall}-modules-${repo_rcnee_pkg_version} || true
			fi

			if [ -f /lib/firmware/am335x-pru0-fw.sleep ] ; then
				cp -v /lib/firmware/am335x-pru0-fw.sleep /lib/firmware/am335x-pru0-fw
				/bin/chgrp gpio /lib/firmware/am335x-pru0-fw
				/bin/chmod g=u /lib/firmware/am335x-pru0-fw
			fi

			if [ -f /lib/firmware/am335x-pru1-fw.sleep ] ; then
				cp -v /lib/firmware/am335x-pru1-fw.sleep /lib/firmware/am335x-pru1-fw
				/bin/chgrp gpio /lib/firmware/am335x-pru1-fw
				/bin/chmod g=u /lib/firmware/am335x-pru1-fw
			fi

			if [ -f /lib/firmware/am57xx-pru1_0-fw.sleep ] ; then
				cp -v /lib/firmware/am57xx-pru1_0-fw.sleep /lib/firmware/am57xx-pru1_0-fw
				/bin/chgrp gpio /lib/firmware/am57xx-pru1_0-fw
				/bin/chmod g=u /lib/firmware/am57xx-pru1_0-fw
			fi

			if [ -f /lib/firmware/am57xx-pru1_1-fw.sleep ] ; then
				cp -v /lib/firmware/am57xx-pru1_1-fw.sleep /lib/firmware/am57xx-pru1_1-fw
				/bin/chgrp gpio /lib/firmware/am57xx-pru1_1-fw
				/bin/chmod g=u /lib/firmware/am57xx-pru1_1-fw
			fi

			if [ -f /lib/firmware/am57xx-pru2_0-fw.sleep ] ; then
				cp -v /lib/firmware/am57xx-pru2_0-fw.sleep /lib/firmware/am57xx-pru2_0-fw
				/bin/chgrp gpio /lib/firmware/am57xx-pru2_0-fw
				/bin/chmod g=u /lib/firmware/am57xx-pru2_0-fw
			fi

			if [ -f /lib/firmware/am57xx-pru2_1-fw.sleep ] ; then
				cp -v /lib/firmware/am57xx-pru1_1-fw.sleep /lib/firmware/am57xx-pru2_1-fw
				/bin/chgrp gpio /lib/firmware/am57xx-pru2_1-fw
				/bin/chmod g=u /lib/firmware/am57xx-pru2_1-fw
			fi

			depmod -a ${repo_rcnee_pkg_version}
			update-initramfs -u -k ${repo_rcnee_pkg_version}
		fi
	}

	install_python_pkgs () {
		if [ ! "x${python3_pkgs}" = "x" ] ; then
			if [ ! "x${python3_extra_index}" = "x" ] ; then
				python3 -m pip install --extra-index-url ${python3_extra_index} ${python3_pkgs}
			else
				python3 -m pip install ${python3_pkgs}
			fi
		fi
	}

	system_tweaks () {
		echo "Log: (chroot): system_tweaks"
		echo "[options]" > /etc/e2fsck.conf
		echo "broken_system_clock = 1" >> /etc/e2fsck.conf

		if [ ! "x${rfs_ssh_banner}" = "x" ] || [ ! "x${rfs_ssh_user_pass}" = "x" ] ; then
			if [ -f /etc/ssh/sshd_config ] ; then
				sed -i -e 's:#Banner none:Banner /etc/issue.net:g' /etc/ssh/sshd_config
			fi
		fi

		# set system type
		echo "ICON_NAME=computer-embedded" > /etc/machine-info
		echo "CHASSIS=embedded" >> /etc/machine-info

		#https://github.com/RobertCNelson/omap-image-builder/issues/131
		if [ -f /var/lib/connman/settings ] ; then
			echo "Log: (chroot): /var/lib/connman/settings"
			cat /var/lib/connman/settings
			sed -i -e 's:OfflineMode=false:OfflineMode=false\nTimezoneUpdates=manual:g' /var/lib/connman/settings
			sed -i -e 's:OfflineMode=false:OfflineMode=false\nTimeUpdates=manual:g' /var/lib/connman/settings
			echo "Log: (chroot): Patched: /var/lib/connman/settings"
			cat /var/lib/connman/settings
		fi
	}

	set_locale () {
		echo "Log: (chroot): set_locale"
		pkg="locales"
		dpkg_check

		if [ "x\${pkg_is_not_installed}" = "x" ] ; then

			if [ ! "x${rfs_default_locale}" = "x" ] ; then

				case "\${distro}" in
				Debian)
					echo "Log: (chroot) Debian: setting up locales: [${rfs_default_locale}]"
					sed -i -e 's:# ${rfs_default_locale} UTF-8:${rfs_default_locale} UTF-8:g' /etc/locale.gen
					locale-gen
					;;
				Ubuntu)
					echo "Log: (chroot) Ubuntu: setting up locales: [${rfs_default_locale}]"
					locale-gen ${rfs_default_locale}
					;;
				esac

				echo "LANG=${rfs_default_locale}" > /etc/default/locale

				echo "Log: (chroot): [locale -a]"
				locale -a
			fi
		else
			dpkg_package_missing
		fi
	}

	run_deborphan () {
		echo "Log: (chroot): deborphan is not reliable, run manual and add pkg list to: [chroot_manual_deborphan_list]"
		apt-get -y install deborphan

		# Prevent deborphan from removing explicitly required packages
		deborphan -A ${deb_additional_pkgs} ${repo_external_pkg_list} ${deb_include}

		deborphan | xargs apt-get -y remove --purge

		# Purge keep file
		deborphan -Z

		#FIXME, only tested on jessie...
		apt-get -y remove deborphan dialog gettext-base libasprintf0c2 --purge
		apt-get clean
	}

	manual_deborphan () {
		echo "Log: (chroot): manual_deborphan"
		if [ ! "x${chroot_manual_deborphan_list}" = "x" ] ; then
			echo "Log: (chroot): cleanup: [${chroot_manual_deborphan_list}]"
			apt-get -y remove ${chroot_manual_deborphan_list} --purge
			apt-get -y autoremove --purge
			apt-get clean
		fi
	}

	dl_kernel () {
		echo "Log: (chroot): dl_kernel"
		wget --no-verbose --directory-prefix=/tmp/ \${kernel_url}

		#This should create a list of files on the server
		#<a href="file"></a>
		cat /tmp/index.html | grep "<a href=" > /tmp/temp.html

		#Note: cat drops one \...
		#sed -i -e "s/<a href/\\n<a href/g" /tmp/temp.html
		sed -i -e "s/<a href/\\\n<a href/g" /tmp/temp.html

		sed -i -e 's/\"/\"><\/a>\n/2' /tmp/temp.html
		cat /tmp/temp.html | grep href > /tmp/index.html

		deb_file=\$(cat /tmp/index.html | grep linux-image)
		deb_file=\$(echo \${deb_file} | awk -F ".deb" '{print \$1}')
		deb_file=\${deb_file##*linux-image-}

		kernel_version=\$(echo \${deb_file} | awk -F "_" '{print \$1}')
		echo "Log: Using: \${kernel_version}"

		deb_file="linux-image-\${deb_file}.deb"
		wget --directory-prefix=/tmp/ \${kernel_url}\${deb_file}

		dpkg -x /tmp/\${deb_file} /

		pkg="initramfs-tools"
		dpkg_check

		if [ "x\${pkg_is_not_installed}" = "x" ] ; then
			depmod \${kernel_version} -a
			update-initramfs -c -k \${kernel_version}
		else
			dpkg_package_missing
		fi

		unset source_file
		source_file=\$(cat /tmp/index.html | grep .diff.gz | head -n 1)
		source_file=\$(echo \${source_file} | awk -F "\"" '{print \$2}')

		if [ "\${source_file}" ] ; then
			wget --directory-prefix=/opt/source/ \${kernel_url}\${source_file}
		fi

		rm -f /tmp/index.html || true
		rm -f /tmp/temp.html || true
		rm -f /tmp/\${deb_file} || true
		rm -f /boot/System.map-\${kernel_version} || true
		mv /boot/config-\${kernel_version} /opt/source || true
		rm -rf /usr/src/linux-headers* || true
	}

	add_user () {
		echo "Log: (chroot): add_user"
		groupadd -r admin || true
		groupadd -r spi || true

		cat /etc/group | grep ^iio || groupadd -r iio || true
		cat /etc/group | grep ^i2c || groupadd -r i2c || true
		cat /etc/group | grep ^docker || groupadd -r docker || true
		cat /etc/group | grep ^kmem || groupadd -r kmem || true
		cat /etc/group | grep ^netdev || groupadd -r netdev || true
		cat /etc/group | grep ^systemd-journal || groupadd -r systemd-journal || true
		cat /etc/group | grep ^tisdk || groupadd -r tisdk || true
		cat /etc/group | grep ^weston-launch || groupadd -r weston-launch || true
		cat /etc/group | grep ^xenomai || groupadd -r xenomai || true
		cat /etc/group | grep ^bluetooth || groupadd -r bluetooth || true
		cat /etc/group | grep ^cloud9ide || groupadd -r cloud9ide || true
		cat /etc/group | grep ^gpio || groupadd -r gpio || true
		cat /etc/group | grep ^pwm || groupadd -r pwm || true
		cat /etc/group | grep ^eqep || groupadd -r eqep || true
		cat /etc/group | grep ^remoteproc || groupadd -r remoteproc || true

		echo "KERNEL==\"hidraw*\", GROUP=\"plugdev\", MODE=\"0660\"" > /etc/udev/rules.d/50-hidraw.rules
		echo "KERNEL==\"spidev*\", GROUP=\"spi\", MODE=\"0660\"" > /etc/udev/rules.d/50-spi.rules

		echo "#SUBSYSTEM==\"uio\", SYMLINK+=\"uio/%s{device/of_node/uio-alias}\"" > /etc/udev/rules.d/uio.rules
		echo "SUBSYSTEM==\"uio\", GROUP=\"users\", MODE=\"0660\"" >> /etc/udev/rules.d/uio.rules

		echo "SUBSYSTEM==\"cmem\", GROUP=\"tisdk\", MODE=\"0660\"" > /etc/udev/rules.d/tisdk.rules
		echo "SUBSYSTEM==\"rpmsg_rpc\", GROUP=\"tisdk\", MODE=\"0660\"" >> /etc/udev/rules.d/tisdk.rules

		default_groups="admin,adm,cloud9ide,dialout,docker,gpio,pwm,eqep,iio,i2c,input,remoteproc,kmem,spi,cdrom,floppy,audio,dip,video,netdev,plugdev,bluetooth,users,systemd-journal,tisdk,weston-launch,xenomai"

		pkg="sudo"
		dpkg_check

		if [ "x\${pkg_is_not_installed}" = "x" ] ; then
			if [ -f /etc/sudoers.d/README ] ; then
				echo "Log: (chroot) adding admin group to /etc/sudoers.d/admin"
				echo "Defaults	env_keep += \"NODE_PATH\"" >/etc/sudoers.d/admin
				echo "%admin ALL=(ALL:ALL) ALL" >>/etc/sudoers.d/admin
				chmod 0440 /etc/sudoers.d/admin
			else
				echo "Log: (chroot) adding admin group to /etc/sudoers"
				echo "Defaults	env_keep += \"NODE_PATH\"" >>/etc/sudoers
				echo "%admin  ALL=(ALL) ALL" >>/etc/sudoers
			fi
		else
			dpkg_package_missing
			if [ "x${rfs_disable_root}" = "xenable" ] ; then
				echo "Log: (Chroot) WARNING: sudo not installed and no root user"
			fi
		fi

		pass_crypt=\$(perl -e 'print crypt(\$ARGV[0], "rcn-ee-salt")' ${rfs_password})

		useradd -G "\${default_groups}" -s /bin/bash -m -p \${pass_crypt} -c "${rfs_fullname}" ${rfs_username}
		grep ${rfs_username} /etc/passwd

		mkdir -p /home/${rfs_username}/bin
		chown ${rfs_username}:${rfs_username} /home/${rfs_username}/bin

		if [ ! "x${rfs_desktop_icon}" = "x" ] ; then
			if [ -f /usr/share/applications/${rfs_desktop_icon} ] ; then
				mkdir -p /home/${rfs_username}/Desktop
				cp -v /usr/share/applications/${rfs_desktop_icon} home/${rfs_username}/Desktop/
				chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}/Desktop/
			fi
		fi

		case "\${distro}" in
		Debian)

			if [ "x${rfs_disable_root}" = "xenable" ] ; then
				passwd -l root || true
			else
				passwd <<-EOF
				${rfs_root_password}
				${rfs_root_password}
				EOF
				echo "export PATH=\$PATH:/usr/local/sbin:/usr/sbin:/sbin" >> /root/.bashrc
			fi

			sed -i -e 's:#EXTRA_GROUPS:EXTRA_GROUPS:g' /etc/adduser.conf
			sed -i -e 's:dialout:dialout i2c spi:g' /etc/adduser.conf
			sed -i -e 's:#ADD_EXTRA_GROUPS:ADD_EXTRA_GROUPS:g' /etc/adduser.conf

			;;
		Ubuntu)
			passwd -l root || true
			;;
		esac
	}

	debian_startup_script () {
		echo "Log: (chroot): debian_startup_script"
	}

	ubuntu_startup_script () {
		echo "Log: (chroot): ubuntu_startup_script"

		#Not Optional...
		#(protects your kernel, from Ubuntu repo which may try to take over your system on an upgrade)...
		if [ -f /etc/flash-kernel.conf ] ; then
			chown root:root /etc/flash-kernel.conf
		fi
	}

	startup_script () {
		echo "Log: (chroot): startup_script"
		case "\${distro}" in
		Debian)
			debian_startup_script
			;;
		Ubuntu)
			ubuntu_startup_script
			;;
		esac

		if [ -f /lib/systemd/system/generic-board-startup.service ] ; then
			systemctl enable generic-board-startup.service || true
		fi

		if [ ! "x${rfs_opt_scripts}" = "x" ] ; then
			mkdir -p /opt/scripts/ || true

			if [ -f /usr/bin/git ] ; then
				qemu_command="git clone ${rfs_opt_scripts} /opt/scripts/ --depth 1"
				qemu_warning
				git clone -v ${rfs_opt_scripts} /opt/scripts/ --depth 1
				sync
				if [ -f /opt/scripts/.git/config ] ; then
					echo "/opt/scripts/ : ${rfs_opt_scripts}" >> /opt/source/list.txt
					chown -R ${rfs_username}:${rfs_username} /opt/scripts/
				fi
				if [ -f /opt/scripts/boot/default/bb-boot ] ; then
					cp -v /opt/scripts/boot/default/bb-boot /etc/default/
				fi
			fi

		fi
	}

	systemd_tweaks () {
		echo "Log: (chroot): systemd_tweaks"
		#We have systemd, so lets use it..

		if [ -f /etc/systemd/systemd-journald.conf ] ; then
			sed -i -e 's:#SystemMaxUse=:SystemMaxUse=8M:g' /etc/systemd/systemd-journald.conf
		fi

		if [ -f /etc/systemd/journald.conf ] ; then
			sed -i -e 's:#SystemMaxUse=:SystemMaxUse=8M:g' /etc/systemd/journald.conf
		fi

		#systemd v215: systemd-timesyncd.service replaces ntpdate
		#enabled by default in v216 (not in jessie)
		if [ -f /lib/systemd/system/systemd-timesyncd.service ] ; then
			echo "Log: (chroot): enabling: systemd-timesyncd.service"
			systemctl enable systemd-timesyncd.service || true

			#set our own initial date stamp, otherwise we get July 2014
			touch /var/lib/systemd/clock

			#if systemd-timesync user exits, use that instead. (this user was removed in later systemd's)
			cat /etc/group | grep ^systemd-timesync && chown systemd-timesync:systemd-timesync /var/lib/systemd/clock || true

			#Remove ntpdate
			if [ -f /usr/sbin/ntpdate ] ; then
				apt-get remove -y ntpdate --purge || true
			fi
		fi

		#kill systemd/connman-wait-online.service, as it delays serial console upto 2 minutes...
		if [ -f /etc/systemd/system/network-online.target.wants/connman-wait-online.service ] ; then
			systemctl disable connman-wait-online.service || true
		fi

		#We manually start dnsmasq, usb0/SoftAp0 are not available till late in boot...
		if [ -f /lib/systemd/system/dnsmasq.service ] ; then
			systemctl disable dnsmasq.service || true
		fi

		#We use, so make sure udhcpd is disabled at bootup...
		if [ -f /lib/systemd/system/udhcpd.service ] ; then
			systemctl disable udhcpd.service || true
		fi

		#Our kernels do not have ubuntu's ureadahead patches...
		if [ -f /lib/systemd/system/ureadahead.service ] ; then
			systemctl disable ureadahead.service || true
		fi

		#No guarantee we will have an active network connection...
		#debian@beaglebone:~$ sudo systemd-analyze blame | grep apt-daily.service
		#     9.445s apt-daily.services
		if [ -f /lib/systemd/system/apt-daily.service ] ; then
			systemctl disable apt-daily.service || true
			systemctl disable apt-daily.timer || true
		fi

		#No guarantee we will have an active network connection...
		#debian@beaglebone:~$ sudo systemd-analyze blame | grep apt-daily-upgrade.service
		#     10.300s apt-daily-upgrade.service
		if [ -f /lib/systemd/system/apt-daily-upgrade.service ] ; then
			systemctl disable apt-daily-upgrade.service || true
			systemctl disable apt-daily-upgrade.timer || true
		fi

		#We use connman...
		if [ -f /lib/systemd/system/systemd-networkd.service ] ; then
			systemctl disable systemd-networkd.service || true
		fi

		#We use dnsmasq & connman...
		if [ -f /lib/systemd/system/systemd-resolved.service ] ; then
			systemctl disable systemd-resolved.service || true
		fi

		#Kill man-db
		#debian@beaglebone:~$ sudo systemd-analyze blame | grep man-db.service
		#    4min 10.587s man-db.service
		if [ -f /lib/systemd/system/man-db.service ] ; then
			systemctl disable man-db.service || true
			systemctl disable man-db.timer || true
		fi

		#Anyone who needs this can enable it...
		if [ -f /lib/systemd/system/pppd-dns.service ] ; then
			systemctl disable pppd-dns.service || true
		fi

		if [ -f /lib/systemd/system/hostapd.service ] ; then
			systemctl disable hostapd.service || true
		fi

		if [ -f /usr/bin/docker ] ; then
			sudo systemctl enable docker.service || true
		fi
	}

	grub_tweaks () {
		echo "Log: (chroot): grub_tweaks"

		echo "#rcn-ee: grub: set our standard boot args" >> /etc/default/grub
		echo "GRUB_CMDLINE_LINUX_DEFAULT=\"console=ttyO0,115200n8 rootwait coherent_pool=1M net.ifnames=0 quiet\"" >> /etc/default/grub
		echo "#rcn-ee: grub: disable LINUX_UUID, broken" >> /etc/default/grub
		echo "GRUB_DISABLE_LINUX_UUID=true" >> /etc/default/grub
		echo "#rcn-ee: grub: disable OS_PROBER, repeated OS entries" >> /etc/default/grub
		echo "GRUB_DISABLE_OS_PROBER=true" >> /etc/default/grub

		mkdir -p /boot/efi/EFI/BOOT/

		###FIXME: let the boot script take care of this... (for now)
		touch /boot/efi/EFI/efi.gen

		###FIXME... still needs work...

		#    fat iso9660 part_gpt part_msdos normal boot linux configfile loopback chain efifwsetup efi_gop \
		#    efi_uga ls search search_label search_fs_uuid search_fs_file gfxterm gfxterm_background \
		#    gfxterm_menu test all_video loadenv exfat ext2 ntfs btrfs hfsplus udf

		#echo "Log: (chroot): grub-mkimage -d /usr/lib/grub/arm-efi -o /boot/efi/EFI/BOOT/bootarm.efi -p /efi/boot -O arm-efi fat iso9660 part_gpt part_msdos normal boot linux configfile"

		#grub-mkimage -d /usr/lib/grub/arm-efi -o /boot/efi/EFI/BOOT/bootarm.efi -p /efi/boot -O arm-efi fat iso9660 part_gpt part_msdos normal boot linux configfile

	}

	#cat /chroot_script.sh
	is_this_qemu
	stop_init

	install_pkg_updates
	install_pkgs
	install_python_pkgs
	system_tweaks
	set_locale
	if [ "x${chroot_not_reliable_deborphan}" = "xenable" ] ; then
		run_deborphan
	fi
	manual_deborphan
	add_user

	mkdir -p /opt/source || true
	touch /opt/source/list.txt

	startup_script

	pkg="wget"
	dpkg_check

	if [ "x\${pkg_is_not_installed}" = "x" ] ; then
		if [ "${rfs_kernel}" ] ; then
			for kernel_url in ${rfs_kernel} ; do dl_kernel ; done
		fi
	else
		dpkg_package_missing
	fi

	pkg="c9-core-installer"
	dpkg_check

	if [ "x\${pkg_is_not_installed}" = "x" ] ; then
		apt-mark hold c9-core-installer || true
	fi

	if [ -f /lib/systemd/systemd ] ; then
		systemd_tweaks
	fi

	if [ -d /etc/update-motd.d/ ] ; then
		#disable the message of the day (motd) welcome message
		chmod -R 0644 /etc/update-motd.d/ || true
	fi

	echo "[global]" > /etc/pip.conf
	echo "extra-index-url=https://www.piwheels.org/simple" >> /etc/pip.conf

	if [ -f /etc/default/grub ] ; then
		grub_tweaks
	fi

	if [ -d /opt/sgx/ ] ; then
		chown -R ${rfs_username}:${rfs_username} /opt/sgx/
	fi

	rm -f /chroot_script.sh || true
__EOF__

sudo mv "${DIR}/chroot_script.sh" "${tempdir}/chroot_script.sh"

if [ "x${include_firmware}" = "xenable" ] ; then
	if [ ! -d "${tempdir}/lib/firmware/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/" || true
	fi

	if [ -d "${DIR}/git/linux-firmware/brcm/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/brcm"
		sudo cp "${DIR}/git/linux-firmware/LICENCE.broadcom_bcm43xx" "${tempdir}/lib/firmware/"
		sudo cp "${DIR}"/git/linux-firmware/brcm/* "${tempdir}/lib/firmware/brcm"
	fi

	if [ -f "${DIR}/git/linux-firmware/carl9170-1.fw" ] ; then
		sudo cp "${DIR}/git/linux-firmware/carl9170-1.fw" "${tempdir}/lib/firmware/"
	fi

	if [ -f "${DIR}/git/linux-firmware/htc_9271.fw" ] ; then
		sudo cp "${DIR}/git/linux-firmware/LICENCE.atheros_firmware" "${tempdir}/lib/firmware/"
		sudo cp "${DIR}/git/linux-firmware/htc_9271.fw" "${tempdir}/lib/firmware/"
	fi

	if [ -d "${DIR}/git/linux-firmware/rtlwifi/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/rtlwifi"
		sudo cp "${DIR}/git/linux-firmware/LICENCE.rtlwifi_firmware.txt" "${tempdir}/lib/firmware/"
		sudo cp "${DIR}"/git/linux-firmware/rtlwifi/* "${tempdir}/lib/firmware/rtlwifi"
	fi

	if [ -d "${DIR}/git/linux-firmware/ti-connectivity/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/ti-connectivity"
		sudo cp "${DIR}/git/linux-firmware/LICENCE.ti-connectivity" "${tempdir}/lib/firmware/"
		sudo cp "${DIR}"/git/linux-firmware/ti-connectivity/* "${tempdir}/lib/firmware/ti-connectivity"
	fi

	if [ -f "${DIR}/git/linux-firmware/mt7601u.bin" ] ; then
		sudo cp "${DIR}/git/linux-firmware/mt7601u.bin" "${tempdir}/lib/firmware/mt7601u.bin"
	fi
fi

#repo_rcnee_sgx_preinstall: we've pre-selected ti335x or jacinto6evm, no decision on first bootup...
if [ "x${repo_rcnee_sgx_preinstall}" = "x" ] ; then
	if [ "x${repo_rcnee_sgx}" = "xenable" ] ; then
		sgx_http="https://rcn-ee.net/repos/debian/pool/main"
		sudo mkdir -p "${tempdir}/opt/sgx/"
		sudo wget --directory-prefix="${tempdir}/opt/sgx/" ${sgx_http}/t/ti-sgx-ti33x-ddk-um/ti-sgx-ti33x-ddk-um_1.14.3699939-git20171201.0-0rcnee9~stretch+20190328_armhf.deb
		sudo wget --directory-prefix="${tempdir}/opt/sgx/" ${sgx_http}/t/ti-sgx-ti335x-modules-${repo_rcnee_pkg_version}/ti-sgx-ti335x-modules-${repo_rcnee_pkg_version}_1${deb_codename}_armhf.deb
		sudo wget --directory-prefix="${tempdir}/opt/sgx/" ${sgx_http}/t/ti-sgx-jacinto6evm-modules-${repo_rcnee_pkg_version}/ti-sgx-jacinto6evm-modules-${repo_rcnee_pkg_version}_1${deb_codename}_armhf.deb
		wfile="${tempdir}/opt/sgx/status"
		sudo sh -c "echo 'not_installed' >> ${wfile}"
	fi
else
	if [ "x${repo_rcnee_sgx}" = "xenable" ] ; then
		sudo mkdir -p "${tempdir}/opt/sgx/"
		wfile="${tempdir}/opt/sgx/status"
		sudo sh -c "echo 'installed' >> ${wfile}"
	fi
fi

if [ -n "${early_chroot_script}" -a -r "${DIR}/target/chroot/${early_chroot_script}" ] ; then
	report_size
	echo "Calling early_chroot_script script: ${early_chroot_script}"
	sudo cp -v "${DIR}/.project" "${tempdir}/etc/oib.project"
	sudo /bin/bash -e "${DIR}/target/chroot/${early_chroot_script}" "${tempdir}"
	early_chroot_script=""
	sudo rm -f "${tempdir}/etc/oib.project" || true
fi

chroot_mount
sudo chroot "${tempdir}" /bin/bash -e chroot_script.sh
echo "Log: Complete: [sudo chroot ${tempdir} /bin/bash -e chroot_script.sh]"

#Do /etc/issue & /etc/issue.net after chroot_script:
#
#Unpacking base-files (7.2ubuntu5.1) over (7.2ubuntu5) ...
#Setting up base-files (7.2ubuntu5.1) ...
#
#Configuration file '/etc/issue'
# ==> Modified (by you or by a script) since installation.
# ==> Package distributor has shipped an updated version.
#   What would you like to do about it ?  Your options are:
#    Y or I  : install the package maintainer's version
#    N or O  : keep your currently-installed version
#      D     : show the differences between the versions
#      Z     : start a shell to examine the situation
# The default action is to keep your current version.
#*** issue (Y/I/N/O/D/Z) [default=N] ? n

if [ ! "x${rfs_console_banner}" = "x" ] || [ ! "x${rfs_console_user_pass}" = "x" ] ; then
	echo "Log: setting up: /etc/issue"
	wfile="${tempdir}/etc/issue"
	if [ ! "x${rfs_etc_dogtag}" = "x" ] ; then
		sudo sh -c "cat '${tempdir}/etc/dogtag' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
	if [ ! "x${rfs_console_banner}" = "x" ] ; then
		sudo sh -c "echo '${rfs_console_banner}' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
	if [ ! "x${rfs_console_user_pass}" = "x" ] ; then
		sudo sh -c "echo 'default username:password is [${rfs_username}:${rfs_password}]' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
fi

if [ ! "x${rfs_ssh_banner}" = "x" ] || [ ! "x${rfs_ssh_user_pass}" = "x" ] ; then
	echo "Log: setting up: /etc/issue.net"
	wfile="${tempdir}/etc/issue.net"
	sudo sh -c "echo '' >> ${wfile}"
	if [ ! "x${rfs_etc_dogtag}" = "x" ] ; then
		sudo sh -c "cat '${tempdir}/etc/dogtag' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
	if [ ! "x${rfs_ssh_banner}" = "x" ] ; then
		sudo sh -c "echo '${rfs_ssh_banner}' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
	if [ ! "x${rfs_ssh_user_pass}" = "x" ] ; then
		sudo sh -c "echo 'default username:password is [${rfs_username}:${rfs_password}]' >> ${wfile}"
		sudo sh -c "echo '' >> ${wfile}"
	fi
fi

#usually a qemu failure...
if [ ! "x${rfs_opt_scripts}" = "x" ] ; then
	#we might not have read permissions:
	if [ -r "${tempdir}/opt/scripts/" ] ; then
		if [ ! -f "${tempdir}/opt/scripts/.git/config" ] ; then
			echo "Log: ERROR: git clone of ${rfs_opt_scripts} failed.."
			exit 1
		fi
	else
		echo "Log: unable to test /opt/scripts/.git/config no read permissions, assuming git clone success"
	fi
fi

if [ -n "${chroot_before_hook}" -a -r "${DIR}/${chroot_before_hook}" ] ; then
	report_size
	echo "Calling chroot_before_hook script: ${chroot_before_hook}"
	. "${DIR}/${chroot_before_hook}"
	chroot_before_hook=""
fi

if [ -n "${chroot_script}" -a -r "${DIR}/target/chroot/${chroot_script}" ] ; then
	report_size
	echo "Calling chroot_script script: ${chroot_script}"
	sudo cp -v "${DIR}/.project" "${tempdir}/etc/oib.project"
	sudo cp -v "${DIR}/target/chroot/${chroot_script}" "${tempdir}/final.sh"
	sudo chroot "${tempdir}" /bin/bash -e final.sh
	sudo rm -f "${tempdir}/final.sh" || true
	sudo rm -f "${tempdir}/etc/oib.project" || true
	chroot_script=""
	if [ -f "${tempdir}/npm-debug.log" ] ; then
		echo "Log: ERROR: npm error in script, review log [cat ${tempdir}/npm-debug.log]..."
		exit 1
	fi
fi

##Building final tar file...

if [ -d "${DIR}/deploy/${export_filename}/" ] ; then
	rm -rf "${DIR}/deploy/${export_filename}/" || true
fi
mkdir -p "${DIR}/deploy/${export_filename}/" || true
cp -v "${DIR}/.project" "${DIR}/deploy/${export_filename}/image-builder.project"

if [ -n "${chroot_after_hook}" -a -r "${DIR}/${chroot_after_hook}" ] ; then
	report_size
	echo "Calling chroot_after_hook script: ${DIR}/${chroot_after_hook}"
	. "${DIR}/${chroot_after_hook}"
	chroot_after_hook=""
fi

cat > "${DIR}/cleanup_script.sh" <<-__EOF__
	#!/bin/sh -e
	export LC_ALL=C
	export DEBIAN_FRONTEND=noninteractive

	#set distro:
	. /etc/rcn-ee.conf

	cleanup () {
		echo "Log: (chroot): cleanup"
		mkdir -p /boot/uboot/

		if [ -f /etc/apt/apt.conf ] ; then
			rm -rf /etc/apt/apt.conf || true
		fi
		apt-get clean
		rm -rf /var/lib/apt/lists/*

		rm -rf /root/.cache/pip

		if [ -d /var/cache/c9-core-installer/ ] ; then
			rm -rf /var/cache/c9-core-installer/ || true
		fi
		if [ -d /var/cache/ti-c6000-cgt-v8.0.x-installer/ ] ; then
			rm -rf /var/cache/ti-c6000-cgt-v8.0.x-installer/ || true
		fi
		if [ -d /var/cache/ti-c6000-cgt-v8.1.x-installer/ ] ; then
			rm -rf /var/cache/ti-c6000-cgt-v8.1.x-installer/ || true
		fi
		if [ -d /var/cache/ti-c6000-cgt-v8.2.x-installer/ ] ; then
			rm -rf /var/cache/ti-c6000-cgt-v8.2.x-installer/ || true
		fi
		if [ -d /var/cache/ti-pru-cgt-installer/ ] ; then
			rm -rf /var/cache/ti-pru-cgt-installer/ || true
		fi
		rm -f /usr/sbin/policy-rc.d

		if [ "x\${distro}" = "xUbuntu" ] ; then
			rm -f /sbin/initctl || true
			dpkg-divert --local --rename --remove /sbin/initctl
		fi

		if [ -f /etc/apt/apt.conf.d/03-proxy-https ] ; then
			rm -rf /etc/apt/apt.conf.d/03-proxy-https || true
		fi

		#update time stamp before final cleanup...
		if [ -f /lib/systemd/system/systemd-timesyncd.service ] ; then
			touch /var/lib/systemd/clock

			cat /etc/group | grep ^systemd-timesync && chown systemd-timesync:systemd-timesync /var/lib/systemd/clock || true
		fi

#		#This is tmpfs, clear out any left overs...
#		if [ -d /run/ ] ; then
#			rm -rf /run/* || true
#		fi

		# Clear out the /tmp directory
		rm -rf /tmp/* || true
	}

	cleanup

	if [ -f /usr/bin/connmanctl ] ; then
		rm -rf /etc/resolv.conf.bak || true
		rm -rf /etc/resolv.conf || true
		ln -s /run/connman/resolv.conf /etc/resolv.conf
	fi

	rm -f /cleanup_script.sh || true
__EOF__

###MUST BE LAST...
sudo mv "${DIR}/cleanup_script.sh" "${tempdir}/cleanup_script.sh"
sudo chroot "${tempdir}" /bin/bash -e cleanup_script.sh
echo "Log: Complete: [sudo chroot ${tempdir} /bin/bash -e cleanup_script.sh]"

#add /boot/uEnv.txt update script
if [ -d "${tempdir}/etc/kernel/postinst.d/" ] ; then
	if [ ! -f "${tempdir}/etc/kernel/postinst.d/zz-uenv_txt" ] ; then
		sudo cp -v "${OIB_DIR}/target/other/zz-uenv_txt" "${tempdir}/etc/kernel/postinst.d/"
		sudo chmod +x "${tempdir}/etc/kernel/postinst.d/zz-uenv_txt"
		sudo chown root:root "${tempdir}/etc/kernel/postinst.d/zz-uenv_txt"
	fi
fi

if [ -f "${tempdir}/usr/bin/qemu-arm-static" ] ; then
	sudo rm -f "${tempdir}/usr/bin/qemu-arm-static" || true
fi

if [ -f "${tempdir}/usr/bin/qemu-aarch64-static" ] ; then
	sudo rm -f "${tempdir}/usr/bin/qemu-aarch64-static" || true
fi

echo "${rfs_username}:${rfs_password}" > /tmp/user_password.list
sudo mv /tmp/user_password.list "${DIR}/deploy/${export_filename}/user_password.list"

#Fixes:
if [ -d "${tempdir}/etc/ssh/" -a "x${keep_ssh_keys}" = "x" ] ; then
	#Remove pre-generated ssh keys, these will be regenerated on first bootup...
	sudo rm -rf "${tempdir}"/etc/ssh/ssh_host_* || true
	sudo touch "${tempdir}/etc/ssh/ssh.regenerate" || true
fi

#ID.txt:
if [ -f "${tempdir}/etc/dogtag" ] ; then
	sudo cp "${tempdir}/etc/dogtag" "${DIR}/deploy/${export_filename}/ID.txt"
	sudo chown root:root "${DIR}/deploy/${export_filename}/ID.txt"
fi

#Add Google IPv4 nameservers
if [ -f "${tempdir}/etc/resolv.conf" ] ; then
	wfile="${tempdir}/etc/resolv.conf"
	sudo sh -c "echo 'nameserver 8.8.8.8' > ${wfile}"
	sudo sh -c "echo 'nameserver 8.8.4.4' >> ${wfile}"
fi

report_size
chroot_umount

if [ "x${chroot_COPY_SETUP_SDCARD}" = "xenable" ] ; then
	echo "Log: copying setup_sdcard.sh related files"
        if [ "x${chroot_custom_setup_sdcard}" = "x" ] ; then
                sudo cp "${DIR}/tools/setup_sdcard.sh" "${DIR}/deploy/${export_filename}/"
        else
                sudo cp "${DIR}/tools/${chroot_custom_setup_sdcard}" "${DIR}/deploy/${export_filename}"
        fi
	sudo mkdir -p "${DIR}/deploy/${export_filename}/hwpack/"
	sudo cp "${DIR}"/tools/hwpack/*.conf "${DIR}/deploy/${export_filename}/hwpack/"

	if [ -n "${chroot_uenv_txt}" -a -r "${OIB_DIR}/target/boot/${chroot_uenv_txt}" ] ; then
		sudo cp "${OIB_DIR}/target/boot/${chroot_uenv_txt}" "${DIR}/deploy/${export_filename}/uEnv.txt"
	fi

	if [ -n "${chroot_flasher_uenv_txt}" -a -r "${OIB_DIR}/target/boot/${chroot_flasher_uenv_txt}" ] ; then
		sudo cp "${OIB_DIR}/target/boot/${chroot_flasher_uenv_txt}" "${DIR}/deploy/${export_filename}/eMMC-flasher.txt"
	fi

	if [ -n "${chroot_post_uenv_txt}" -a -r "${OIB_DIR}/target/boot/${chroot_post_uenv_txt}" ] ; then
		sudo cp "${OIB_DIR}/target/boot/${chroot_post_uenv_txt}" "${DIR}/deploy/${export_filename}/post-uEnv.txt"
	fi

fi

if [ "x${chroot_directory}" = "xenable" ]; then
	echo "Log: moving rootfs to directory: [${deb_arch}-rootfs-${deb_distribution}-${deb_codename}]"
	sudo mv -v "${tempdir}" "${DIR}/deploy/${export_filename}/${deb_arch}-rootfs-${deb_distribution}-${deb_codename}"
	sudo du -h --max-depth=0 "${DIR}/deploy/${export_filename}/${deb_arch}-rootfs-${deb_distribution}-${deb_codename}"
else
	cd "${tempdir}" || true
	echo "Log: packaging rootfs: [${deb_arch}-rootfs-${deb_distribution}-${deb_codename}.tar]"
	sudo LANG=C tar --numeric-owner -cf "${DIR}/deploy/${export_filename}/${deb_arch}-rootfs-${deb_distribution}-${deb_codename}.tar" .
	cd "${DIR}/" || true
	ls -lh "${DIR}/deploy/${export_filename}/${deb_arch}-rootfs-${deb_distribution}-${deb_codename}.tar"
	sudo chown -R ${USER}:${USER} "${DIR}/deploy/${export_filename}/"
fi

echo "Log: USER:${USER}"

if [ "x${chroot_tarball}" = "xenable" ] ; then
	echo "Creating: ${export_filename}.tar"
	cd "${DIR}/deploy/" || true
	sudo tar cvf ${export_filename}.tar ./${export_filename}
	sudo chown -R ${USER}:${USER} "${export_filename}.tar"
	cd "${DIR}/" || true
fi

chroot_completed="true"
#
#
