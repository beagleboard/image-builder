#!/bin/bash -e
#
# Copyright (c) 2013 Robert Nelson <robertcnelson@gmail.com>
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

system=$(uname -n)
HOST_ARCH=$(uname -m)
TIME=$(date +%Y-%m-%d)

OIB_DIR="$( cd "$(dirname "$0")" ; pwd -P )" 
DIR="$PWD"

usage () {
	echo "usage: ./RootStock-NG.sh -c bb.org-debian-stretch-lxqt-v4.14"
}

checkparm () {
	if [ "$(echo $1|grep ^'\-')" ] ; then
		echo "E: Need an argument"
		usage
	fi
}

check_project_config_legacy () {

	if [ ! -d ${DIR}/ignore ] ; then
		mkdir -p ${DIR}/ignore
	fi
	tempdir=$(mktemp -d -p ${DIR}/ignore)

	time=$(date +%Y-%m-%d)

	#/config/legacy/${project_config}.conf
	unset leading_slash
	leading_slash=$(echo ${project_config} | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		project_config=$(echo "${leading_slash##*/}")
	fi

	#${project_config}.conf
	project_config=$(echo ${project_config} | awk -F ".conf" '{print $1}')
	if [ -f ${DIR}/configs/legacy/${project_config}.conf ] ; then
		. <(m4 -P ${DIR}/configs/legacy/${project_config}.conf)
		export_filename="${deb_distribution}-${release}-${image_type}-${deb_arch}-${time}"

		# for automation
		echo "${export_filename}" > ${DIR}/latest_version

		echo "tempdir=\"${tempdir}\"" > ${DIR}/.project
		echo "time=\"${time}\"" >> ${DIR}/.project
		echo "export_filename=\"${export_filename}\"" >> ${DIR}/.project
		echo "#" >> ${DIR}/.project
		m4 -P ${DIR}/configs/legacy/${project_config}.conf >> ${DIR}/.project
	else
		echo "Invalid *.conf"
		exit
	fi
}

check_project_config () {

	if [ ! -d ${DIR}/ignore ] ; then
		mkdir -p ${DIR}/ignore
	fi
	tempdir=$(mktemp -d -p ${DIR}/ignore)

	time=$(date +%Y-%m-%d)

	#/config/${project_config}.conf
	unset leading_slash
	leading_slash=$(echo ${project_config} | grep "/" || unset leading_slash)
	if [ "${leading_slash}" ] ; then
		project_config=$(echo "${leading_slash##*/}")
	fi

	#${project_config}.conf
	project_config=$(echo ${project_config} | awk -F ".conf" '{print $1}')
	if [ -f ${DIR}/configs/${project_config}.conf ] ; then
		. <(m4 -P ${DIR}/configs/${project_config}.conf)
		export_filename="${deb_distribution}-${release}-${image_type}-${deb_arch}-${time}"

		# for automation
		echo "${export_filename}" > ${DIR}/latest_version

		echo "tempdir=\"${tempdir}\"" > ${DIR}/.project
		echo "time=\"${time}\"" >> ${DIR}/.project
		echo "export_filename=\"${export_filename}\"" >> ${DIR}/.project
		echo "#" >> ${DIR}/.project
		m4 -P ${DIR}/configs/${project_config}.conf >> ${DIR}/.project
	else
		echo "Invalid *.conf"
		exit
	fi
}

check_saved_config () {

	if [ ! -d ${DIR}/ignore ] ; then
		mkdir -p ${DIR}/ignore
	fi
	tempdir=$(mktemp -d -p ${DIR}/ignore)

	if [ ! -f ${DIR}/.project ] ; then
		echo "Couldn't find .project"
		exit
	fi
}

unset need_to_compress_rootfs
# parse commandline options
while [ ! -z "$1" ] ; do
	case $1 in
	-h|--help)
		usage
		exit
		;;
	-c|-C|--config)
		checkparm $2
		project_config="$2"
		check_project_config
		;;
	-l|-L|--legacy)
		checkparm $2
		project_config="$2"
		check_project_config_legacy
		;;
	--saved-config)
		check_saved_config
		;;
	esac
	shift
done

mkdir -p ${DIR}/ignore

if [ -f ${DIR}/.project ] ; then
	. ${DIR}/.project
fi

generic_git () {
	if [ ! -f ${DIR}/git/${git_project_name}/.git/config ] ; then
		git clone ${git_clone_address} ${DIR}/git/${git_project_name} --depth=1
	fi
}

generic_git_mirror () {
	if [ ! -f ${DIR}/git/${git_project_name}/.git/config ] ; then
		git clone -c http.sslVerify=false ${git_clone_address} ${DIR}/git/${git_project_name} --depth=1
	fi
}

update_git () {
	if [ -f ${DIR}/git/${git_project_name}/.git/config ] ; then
		cd ${DIR}/git/${git_project_name}/
		git remote -v
		git pull --rebase || true
		cd -
	fi
}

update_git_mirror () {
	if [ -f ${DIR}/git/${git_project_name}/.git/config ] ; then
		cd ${DIR}/git/${git_project_name}/
		git remote set-url origin ${git_clone_address}
		git remote -v
		git pull --rebase || true
		cd -
	fi
}

git_trees () {
	if [ ! -d ${DIR}/git/ ] ; then
		mkdir -p ${DIR}/git/
	fi

	git_project_name="linux-firmware"
	if [ -f ./.gitea.mirror ] ; then
		git_clone_address="http://forgejo.gfnd.rcn-ee.org:3000/kernel.org/linux-firmware.git"
		generic_git_mirror
		update_git_mirror
	else
		git_clone_address="https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware.git"
		generic_git
		update_git
	fi
	#update_git
}

run_roostock_ng () {
	if [ ! -f ${DIR}/.project ] ; then
		echo "error: [.project] file not defined"
		exit 1
	else
		echo "Debug: .project"
		echo "-----------------------------"
		cat ${DIR}/.project
		echo "-----------------------------"
	fi

	if [ ! "${tempdir}" ] ; then
		tempdir=$(mktemp -d -p ${DIR}/ignore)
		echo "tempdir=\"${tempdir}\"" >> ${DIR}/.project
	fi

	echo "Log: stat ${tempdir}"
	sudo chown root:root ${tempdir}
	sudo chmod 755 ${tempdir}
	stat ${tempdir}

	echo 'Log: /bin/bash -e "${OIB_DIR}/scripts/install_dependencies.sh"'
	/bin/bash -e "${OIB_DIR}/scripts/install_dependencies.sh" || { exit 1 ; }
	echo 'Log: /bin/bash -e "${OIB_DIR}/scripts/debootstrap.sh"'
	/bin/bash -e "${OIB_DIR}/scripts/debootstrap.sh" || { exit 1 ; }
	echo 'Log: /bin/bash -e "${OIB_DIR}/scripts/chroot.sh"'
	/bin/bash -e "${OIB_DIR}/scripts/chroot.sh" || { exit 1 ; }
	sudo rm -rf ${tempdir}/ || true
	echo 'Log: RootStock-NG.sh complete'
}

#git_trees

cd ${DIR}/

run_roostock_ng

#
