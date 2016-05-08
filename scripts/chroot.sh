#!/bin/bash -ex
#
# Copyright (c) 2012-2016 Robert Nelson <robertcnelson@gmail.com>
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

abi=aa

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
		deb_mirror=${deb_mirror:-"httpredir.debian.org/debian/"}
		;;
	ubuntu)
		deb_components=${deb_components:-"main universe multiverse"}
		deb_mirror=${deb_mirror:-"ports.ubuntu.com/ubuntu-ports/"}
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
			deb_additional_pkgs="$(echo ${base_pkg_list} | sed 's/,/ /g')"
		fi
	else
		deb_additional_pkgs="$(echo ${deb_additional_pkgs} | sed 's/,/ /g')"
	fi

	if [ ! "x${deb_include}" = "x" ] ; then
		include=$(echo ${deb_include} | sed 's/,/ /g')
		deb_additional_pkgs="${deb_additional_pkgs} ${include}"
	fi

	if [ "x${repo_rcnee}" = "xenable" ] ; then
		if [ ! "x${repo_rcnee_pkg_list}" = "x" ] ; then
			deb_additional_pkgs="${deb_additional_pkgs} ${repo_rcnee_pkg_list}"
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


if [ "x${deb_distribution}" = "xdebian" ] ; then
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

	#apt: /var/lib/apt/lists/, store compressed only
	echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' > /tmp/02compress-indexes
	sudo mv /tmp/02compress-indexes "${tempdir}/etc/apt/apt.conf.d/02compress-indexes"

	#apt: make sure apt-cacher-ng doesn't break oracle-java8-installer
	echo 'Acquire::http::Proxy::download.oracle.com "DIRECT";' > /tmp/03-proxy-oracle
	sudo mv /tmp/03-proxy-oracle "${tempdir}/etc/apt/apt.conf.d/03-proxy-oracle"

	#apt: make sure apt-cacher-ng doesn't break https repos
	echo 'Acquire::http::Proxy::deb.nodesource.com "DIRECT";' > /tmp/03-proxy-https
	sudo mv /tmp/03-proxy-https "${tempdir}/etc/apt/apt.conf.d/03-proxy-https"
fi

#set initial 'seed' time...
sudo sh -c "date --utc \"+%4Y%2m%2d%2H%2M\" > ${tempdir}/etc/timestamp"

wfile="/tmp/sources.list"
echo "deb http://${deb_mirror} ${deb_codename} ${deb_components}" > ${wfile}
echo "#deb-src http://${deb_mirror} ${deb_codename} ${deb_components}" >> ${wfile}
echo "" >> ${wfile}

case "${deb_codename}" in
stretch|buster|sid)
	echo "#deb http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "##deb-src http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	;;
*)
	echo "deb http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	echo "#deb-src http://${deb_mirror} ${deb_codename}-updates ${deb_components}" >> ${wfile}
	;;
esac

case "${deb_codename}" in
wheezy|jessie)
	echo "" >> ${wfile}
	echo "deb http://security.debian.org/ ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "#deb-src http://security.debian.org/ ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	if [ "x${chroot_enable_debian_backports}" = "xenable" ] ; then
		echo "deb http://httpredir.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
		echo "#deb-src http://httpredir.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
	else
		echo "#deb http://httpredir.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
		echo "##deb-src http://httpredir.debian.org/debian ${deb_codename}-backports ${deb_components}" >> ${wfile}
	fi
	;;
stretch)
	echo "" >> ${wfile}
	echo "#deb http://security.debian.org/ ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "##deb-src http://security.debian.org/ ${deb_codename}/updates ${deb_components}" >> ${wfile}
	echo "" >> ${wfile}
	;;
esac

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
	echo "deb https://deb.nodesource.com/${repo_nodesource} ${deb_codename} main" >> ${wfile}
	echo "#deb-src https://deb.nodesource.com/${repo_nodesource} ${deb_codename} main" >> ${wfile}
	echo "" >> ${wfile}
	sudo cp -v "${OIB_DIR}/target/keyring/nodesource.gpg.key" "${tempdir}/tmp/nodesource.gpg.key"
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
		wheezy)
			sudo cp "${OIB_DIR}/target/init_scripts/generic-${deb_distribution}.sh" "${tempdir}/etc/init.d/generic-boot-script.sh"
			sudo chown root:root "${tempdir}/etc/init.d/generic-boot-script.sh"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr-${deb_distribution}.sh" "${tempdir}/etc/init.d/capemgr.sh"
			sudo chown root:root "${tempdir}/etc/init.d/capemgr.sh"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr" "${tempdir}/etc/default/"
			sudo chown root:root "${tempdir}/etc/default/capemgr"
			distro="Debian"
			;;
		jessie|stretch)
			#while bb-customizations installes "generic-board-startup.service" other boards/configs could use this default.
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-generic-board-startup.service" "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-capemgr.service" "${tempdir}/lib/systemd/system/capemgr.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/capemgr.service"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr" "${tempdir}/etc/default/"
			sudo chown root:root "${tempdir}/etc/default/capemgr"
			distro="Debian"
			;;
		esac
		;;
	ubuntu)
		case "${deb_codename}" in
		trusty)
			sudo cp "${OIB_DIR}/target/init_scripts/generic-${deb_distribution}.conf" "${tempdir}/etc/init/generic-boot-script.conf"
			sudo chown root:root "${tempdir}/etc/init/generic-boot-script.conf"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr-${deb_distribution}.sh" "${tempdir}/etc/init/capemgr.sh"
			sudo chown root:root "${tempdir}/etc/init/capemgr.sh"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr" "${tempdir}/etc/default/"
			sudo chown root:root "${tempdir}/etc/default/capemgr"
			distro="Ubuntu"

			if [ -f "${tempdir}/etc/init/failsafe.conf" ] ; then
				#Ubuntu: with no ethernet cable connected it can take up to 2 mins to login, removing upstart sleep calls..."
				sudo sed -i -e 's:sleep 20:#sleep 20:g' "${tempdir}/etc/init/failsafe.conf"
				sudo sed -i -e 's:sleep 40:#sleep 40:g' "${tempdir}/etc/init/failsafe.conf"
				sudo sed -i -e 's:sleep 59:#sleep 59:g' "${tempdir}/etc/init/failsafe.conf"
			fi
			;;
		vivid|wily|xenial)
			#while bb-customizations installes "generic-board-startup.service" other boards/configs could use this default.
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-generic-board-startup.service" "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo cp "${OIB_DIR}/target/init_scripts/systemd-capemgr.service" "${tempdir}/lib/systemd/system/capemgr.service"
			sudo chown root:root "${tempdir}/lib/systemd/system/generic-board-startup.service"
			sudo cp "${OIB_DIR}/target/init_scripts/capemgr" "${tempdir}/etc/default/"
			sudo chown root:root "${tempdir}/etc/default/capemgr"
			distro="Ubuntu"
			;;
		esac
		;;
	esac
fi

if [ -d "${tempdir}/usr/share/initramfs-tools/hooks/" ] ; then
	if [ ! -f "${tempdir}/usr/share/initramfs-tools/hooks/dtbo" ] ; then
		echo "log: adding: [initramfs-tools hook: dtbo]"
		sudo cp "${OIB_DIR}/target/other/dtbo" "${tempdir}/usr/share/initramfs-tools/hooks/"
		sudo chmod +x "${tempdir}/usr/share/initramfs-tools/hooks/dtbo"
		sudo chown root:root "${tempdir}/usr/share/initramfs-tools/hooks/dtbo"
	fi
fi

#Backward compatibility, as setup_sdcard.sh expects [lsb_release -si > /etc/rcn-ee.conf]
echo "distro=${distro}" > /tmp/rcn-ee.conf
echo "rfs_username=${rfs_username}" >> /tmp/rcn-ee.conf
echo "release_date=${time}" >> /tmp/rcn-ee.conf
echo "third_party_modules=${third_party_modules}" >> /tmp/rcn-ee.conf
echo "abi=${abi}" >> /tmp/rcn-ee.conf
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
		if [ "x${repo_rcnee}" = "xenable" ] ; then
			apt-key add /tmp/repos.rcn-ee.net-archive-keyring.asc
			rm -f /tmp/repos.rcn-ee.net-archive-keyring.asc || true
		fi
		if [ "x${repo_external}" = "xenable" ] ; then
			apt-key add /tmp/${repo_external_key}
			rm -f /tmp/${repo_external_key} || true
		fi
		if [ "x${repo_flat}" = "xenable" ] ; then
			apt-key add /tmp/${repo_flat_key}
			rm -f /tmp/${repo_flat_key} || true
		fi

		apt-get update
		apt-get upgrade -y --force-yes

		if [ "x${chroot_very_small_image}" = "xenable" ] ; then
			if [ -f /bin/busybox ] ; then
				echo "Log: (chroot): Setting up BusyBox"

				busybox --install -s /usr/local/bin/

				#conflicts with systemd reboot...
				if [ -f /usr/local/bin/reboot ] ; then
					rm -f /usr/local/bin/reboot
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
			apt-get -y --force-yes install ${deb_additional_pkgs}
		fi

		if [ ! "x${repo_rcnee_pkg_version}" = "x" ] ; then
			echo "Log: (chroot) Installing modules for: ${repo_rcnee_pkg_version}"
			apt-get -y --force-yes install mt7601u-modules-${repo_rcnee_pkg_version} || true
			apt-get -y --force-yes install rtl8723bu-modules-${repo_rcnee_pkg_version} || true
			depmod -a ${repo_rcnee_pkg_version}
			update-initramfs -u -k ${repo_rcnee_pkg_version}
		fi

		if [ "x${chroot_enable_debian_backports}" = "xenable" ] ; then
			if [ ! "x${chroot_debian_backports_pkg_list}" = "x" ] ; then
				echo "Log: (chroot) Installing (from backports): ${chroot_debian_backports_pkg_list}"
				sudo apt-get -y --force-yes -t ${deb_codename}-backports install ${chroot_debian_backports_pkg_list}
			fi
		fi

		if [ ! "x${repo_external_pkg_list}" = "x" ] ; then
			echo "Log: (chroot) Installing (from external repo): ${repo_external_pkg_list}"
			apt-get -y --force-yes install ${repo_external_pkg_list}
		fi
	}

	system_tweaks () {
		echo "Log: (chroot): system_tweaks"
		echo "[options]" > /etc/e2fsck.conf
		echo "broken_system_clock = 1" >> /etc/e2fsck.conf

		if [ ! "x${rfs_ssh_banner}" = "x" ] || [ ! "x${rfs_ssh_user_pass}" = "x" ] ; then
			if [ -f /etc/ssh/sshd_config ] ; then
				sed -i -e 's:#Banner:Banner:g' /etc/ssh/sshd_config
			fi
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

			fi
		else
			dpkg_package_missing
		fi
	}

	run_deborphan () {
		echo "Log: (chroot): deborphan is not reliable, run manual and add pkg list to: [chroot_manual_deborphan_list]"
		apt-get -y --force-yes install deborphan

		# Prevent deborphan from removing explicitly required packages
		deborphan -A ${deb_additional_pkgs} ${repo_external_pkg_list} ${deb_include}

		deborphan | xargs apt-get -y remove --purge

		# Purge keep file
		deborphan -Z

		#FIXME, only tested on wheezy/jessie...
		apt-get -y remove deborphan dialog gettext-base libasprintf0c2 --purge
		apt-get clean
	}

	manual_deborphan () {
		echo "Log: (chroot): manual_deborphan"
		if [ ! "x${chroot_manual_deborphan_list}" = "x" ] ; then
			echo "Log: (chroot): cleanup: [${chroot_manual_deborphan_list}]"
			apt-get -y remove ${chroot_manual_deborphan_list} --purge
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

		cat /etc/group | grep ^i2c || groupadd -r i2c || true
		cat /etc/group | grep ^kmem || groupadd -r kmem || true
		cat /etc/group | grep ^netdev || groupadd -r netdev || true
		cat /etc/group | grep ^systemd-journal || groupadd -r systemd-journal || true
		cat /etc/group | grep ^tisdk || groupadd -r tisdk || true
		cat /etc/group | grep ^weston-launch || groupadd -r weston-launch || true
		cat /etc/group | grep ^xenomai || groupadd -r xenomai || true

		echo "KERNEL==\"hidraw*\", GROUP=\"plugdev\", MODE=\"0660\"" > /etc/udev/rules.d/50-hidraw.rules
		echo "KERNEL==\"spidev*\", GROUP=\"spi\", MODE=\"0660\"" > /etc/udev/rules.d/50-spi.rules

		echo "#SUBSYSTEM==\"uio\", SYMLINK+=\"uio/%s{device/of_node/uio-alias}\"" > /etc/udev/rules.d/uio.rules
		echo "SUBSYSTEM==\"uio\", GROUP=\"users\", MODE=\"0660\"" >> /etc/udev/rules.d/uio.rules

		echo "SUBSYSTEM==\"cmem\", GROUP=\"tisdk\", MODE=\"0660\"" > /etc/udev/rules.d/tisdk.rules
		echo "SUBSYSTEM==\"rpmsg_rpc\", GROUP=\"tisdk\", MODE=\"0660\"" >> /etc/udev/rules.d/tisdk.rules

		default_groups="admin,adm,dialout,i2c,kmem,spi,cdrom,floppy,audio,dip,video,netdev,plugdev,users,systemd-journal,tisdk,weston-launch,xenomai"

		pkg="sudo"
		dpkg_check

		if [ "x\${pkg_is_not_installed}" = "x" ] ; then
			echo "Log: (chroot) adding admin group to /etc/sudoers"
			echo "%admin  ALL=(ALL) ALL" >>/etc/sudoers
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

		case "\${distro}" in
		Debian)

			if [ "x${rfs_disable_root}" = "xenable" ] ; then
				passwd -l root || true
			else
				passwd <<-EOF
				root
				root
				EOF
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
		if [ "x${rfs_startup_scripts}" = "xenable" ] ; then
			if [ -f /etc/init.d/generic-boot-script.sh ] ; then
				chown root:root /etc/init.d/generic-boot-script.sh
				chmod +x /etc/init.d/generic-boot-script.sh
				insserv generic-boot-script.sh || true
			fi

			if [ -f /etc/init.d/capemgr.sh ] ; then
				chown root:root /etc/init.d/capemgr.sh
				chown root:root /etc/default/capemgr
				chmod +x /etc/init.d/capemgr.sh
				insserv capemgr.sh || true
			fi
		fi
	}

	ubuntu_startup_script () {
		echo "Log: (chroot): ubuntu_startup_script"
		if [ "x${rfs_startup_scripts}" = "xenable" ] ; then
			if [ -f /etc/init/generic-boot-script.conf ] ; then
				chown root:root /etc/init/generic-boot-script.conf
			fi
		fi

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

		if [ -f /lib/systemd/system/capemgr.service ] ; then
			systemctl enable capemgr.service || true
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
			fi

		fi
	}

	systemd_tweaks () {
		echo "Log: (chroot): systemd_tweaks"
		#We have systemd, so lets use it..

		if [ -f /etc/systemd/systemd-journald.conf ] ; then
			sed -i -e 's:#SystemMaxUse=:SystemMaxUse=8M:g' /etc/systemd/systemd-journald.conf
		fi

		#systemd v215: systemd-timesyncd.service replaces ntpdate
		#enabled by default in v216 (not in jessie)
		if [ -f /lib/systemd/system/systemd-timesyncd.service ] ; then
			echo "Log: (chroot): enabling: systemd-timesyncd.service"
			systemctl enable systemd-timesyncd.service || true

			#set our own initial date stamp, otherwise we get July 2014
			touch /var/lib/systemd/clock
			chown systemd-timesync:systemd-timesync /var/lib/systemd/clock

			#Remove ntpdate
			if [ -f /usr/sbin/ntpdate ] ; then
				apt-get remove -y --force-yes ntpdate --purge || true
			fi
		fi
	}

	#cat /chroot_script.sh
	is_this_qemu
	stop_init

	install_pkg_updates
	install_pkgs
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

	if [ -f /lib/systemd/systemd ] ; then
		systemd_tweaks
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
		sudo cp -v "${DIR}/git/linux-firmware/LICENCE.broadcom_bcm43xx" "${tempdir}/lib/firmware/"
		sudo cp -v "${DIR}"/git/linux-firmware/brcm/* "${tempdir}/lib/firmware/brcm"
	fi

	if [ -f "${DIR}/git/linux-firmware/carl9170-1.fw" ] ; then
		sudo cp -v "${DIR}/git/linux-firmware/carl9170-1.fw" "${tempdir}/lib/firmware/"
	fi

	if [ -f "${DIR}/git/linux-firmware/htc_9271.fw" ] ; then
		sudo cp -v "${DIR}/git/linux-firmware/LICENCE.atheros_firmware" "${tempdir}/lib/firmware/"
		sudo cp -v "${DIR}/git/linux-firmware/htc_9271.fw" "${tempdir}/lib/firmware/"
	fi

	if [ -d "${DIR}/git/linux-firmware/rtlwifi/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/rtlwifi"
		sudo cp -v "${DIR}/git/linux-firmware/LICENCE.rtlwifi_firmware.txt" "${tempdir}/lib/firmware/"
		sudo cp -v "${DIR}"/git/linux-firmware/rtlwifi/* "${tempdir}/lib/firmware/rtlwifi"
	fi

	if [ -d "${DIR}/git/linux-firmware/ti-connectivity/" ] ; then
		sudo mkdir -p "${tempdir}/lib/firmware/ti-connectivity"
		sudo cp -v "${DIR}/git/linux-firmware/LICENCE.ti-connectivity" "${tempdir}/lib/firmware/"
		sudo cp -v "${DIR}"/git/linux-firmware/ti-connectivity/* "${tempdir}/lib/firmware/ti-connectivity"
	fi

	if [ -f "${DIR}/git/linux-firmware/mt7601u.bin" ] ; then
		sudo cp -v "${DIR}/git/linux-firmware/mt7601u.bin" "${tempdir}/lib/firmware/mt7601u.bin"
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

		if [ -d /var/cache/c9-core-installer/ ] ; then
			rm -rf /var/cache/c9-core-installer/ || true
		fi
		if [ -d /var/cache/ipumm-dra7xx-installer/ ] ; then
			rm -rf /var/cache/ipumm-dra7xx-installer/ || true
		fi
		if [ -d /var/cache/ti-c6000-cgt-v8.0.x-installer/ ] ; then
			rm -rf /var/cache/ti-c6000-cgt-v8.0.x-installer/ || true
		fi
		if [ -d /var/cache/ti-c6000-cgt-v8.1.x-installer/ ] ; then
			rm -rf /var/cache/ti-c6000-cgt-v8.1.x-installer/ || true
		fi
		if [ -d /var/cache/ti-pru-cgt-installer/ ] ; then
			rm -rf /var/cache/ti-pru-cgt-installer/ || true
		fi
		if [ -d /var/cache/vpdma-dra7xx-installer/ ] ; then
			rm -rf /var/cache/vpdma-dra7xx-installer/ || true
		fi
		rm -f /usr/sbin/policy-rc.d

		if [ "x\${distro}" = "xUbuntu" ] ; then
			rm -f /sbin/initctl || true
			dpkg-divert --local --rename --remove /sbin/initctl
		fi

#		#This is tmpfs, clear out any left overs...
#		if [ -d /run/ ] ; then
#			rm -rf /run/* || true
#		fi
	}

	cleanup
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

report_size
chroot_umount

if [ "x${chroot_COPY_SETUP_SDCARD}" = "xenable" ] ; then
	echo "Log: copying setup_sdcard.sh related files"
	sudo cp "${DIR}/tools/setup_sdcard.sh" "${DIR}/deploy/${export_filename}/"
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
	du -h --max-depth=0 "${DIR}/deploy/${export_filename}/${deb_arch}-rootfs-${deb_distribution}-${deb_codename}"
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
