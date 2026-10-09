#!/bin/sh -e

# SPDX-FileCopyrightText: 2014 Robert Nelson <robertcnelson@gmail.com>
#
# SPDX-License-Identifier: MIT

export LC_ALL=C

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

export HOME=/home/${rfs_username}
export USER=${rfs_username}
export USERNAME=${rfs_username}

echo "env: [`env`]"

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	chown -R 1000:1000 ${git_target_dir}
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

setup_system () {
	if [ -f /var/www/html/index.nginx-debian.html ] ; then
		if [ -f /etc/bbb.io/templates/nginx/nginx-autoindex ] ; then
			rm -f /etc/nginx/sites-enabled/default || true
			cp -v /etc/bbb.io/templates/nginx/nginx-autoindex /etc/nginx/sites-enabled/default
			cp -v /etc/bbb.io/templates/nginx/Cockpit.html /var/www/html/ || true
			cp -v /etc/bbb.io/templates/nginx/*.html /var/www/html/
			rm -f /var/www/html/index.nginx-debian.html || true
		fi
	fi
}

setup_desktop () {
	#From: xfce4-settings
	if [ -f /usr/share/xfce4/settings/appearance-install-theme ] ; then
		if [ -f /etc/bbb.io/templates/xfce4/xfce4-desktop.xml ] ; then
			mkdir -p /home/${rfs_username}/.config/xfce4/xfconf/xfce-perchannel-xml/ || true
			cp -v /etc/bbb.io/templates/xfce4/xfce4-*.xml /home/${rfs_username}/.config/xfce4/xfconf/xfce-perchannel-xml/
			chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}/.config/
		fi
	fi

#	if [ -f /etc/bbb.io/templates/beagleboard-logo.svg ] ; then
#		update-alternatives --install /usr/share/images/desktop-base/desktop-background desktop-background /etc/bbb.io/templates/beagleboard-logo.svg 100
#	fi

	#Disable dpms mode and screen blanking
	#Better fix for missing cursor
	wfile="/home/${rfs_username}/.xsessionrc"
	echo "#!/bin/sh" > ${wfile}
	echo "" >> ${wfile}
	echo "xset -dpms" >> ${wfile}
	echo "xset s off" >> ${wfile}
	echo "xsetroot -cursor_name left_ptr" >> ${wfile}
	chown -R ${rfs_username}:${rfs_username} ${wfile}

	if [ -f /usr/sbin/wpa_gui ] ; then
		mkdir -p /home/${rfs_username}/Desktop/ || true
		chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}/Desktop/

		wfile="/home/${rfs_username}/Desktop/wpa_gui.desktop"
		echo "[Desktop Entry]" > ${wfile}
		echo "Version=1.0" >> ${wfile}
		echo "Name=wpa_gui" >> ${wfile}
		echo "Comment=Graphical user interface for wpa_supplicant" >> ${wfile}
		echo "Exec=wpa_gui" >> ${wfile}
		echo "Icon=wpa_gui" >> ${wfile}
		echo "GenericName=wpa_supplicant user interface" >> ${wfile}
		echo "Terminal=false" >> ${wfile}
		echo "Type=Application" >> ${wfile}
		echo "Categories=Qt;Network;" >> ${wfile}
		chown -R ${rfs_username}:${rfs_username} ${wfile}
		chmod +x ${wfile}
	fi
}

install_git_repos () {
	if [ -f /usr/bin/beagle-dtb-source ] ; then
		echo "Log: (chroot): Running: [/usr/bin/beagle-dtb-source]"
		/usr/bin/beagle-dtb-source
	fi

	git_repo="https://github.com/beagleboard/vsx-examples.git"
	git_target_dir="/opt/vsx-examples"
	git_clone
}

setup_workshop () {
	if [ -f /opt/bb-code-server/app/bin/code-server ] ; then
		mkdir -p /opt/bb-code-server/extensions/

		echo "bb-code-server: Installing: ms-python.python"
		/opt/bb-code-server/app/bin/code-server --auth none --disable-telemetry --disable-update-check --extensions-dir /opt/bb-code-server/extensions/ --install-extension ms-python.python --force || true
		echo "bb-code-server: *****************"

		echo "bb-code-server: Installing: rust-lang.rust-analyzer"
		/opt/bb-code-server/app/bin/code-server --auth none --disable-telemetry --disable-update-check --extensions-dir /opt/bb-code-server/extensions/ --install-extension rust-lang.rust-analyzer --force || true
		echo "bb-code-server: *****************"

		echo "bb-code-server: --list-extensions"
		/opt/bb-code-server/app/bin/code-server --auth none --disable-telemetry --disable-update-check --extensions-dir /opt/bb-code-server/extensions/ --list-extensions
		echo "bb-code-server: *****************"

		chown -R ${rfs_username}:${rfs_username} /opt/bb-code-server/extensions/ || true
	fi
}

other_source_links () {
	chown -R ${rfs_username}:${rfs_username} /opt/source/
}

is_this_qemu

setup_system
setup_desktop

if [ -f /usr/bin/git ] ; then
	mkdir -p /opt/source/
	chown -R ${rfs_username}:${rfs_username} /opt/source/
	git config --global user.email "${rfs_username}@example.com"
	git config --global user.name "${rfs_username}"
	install_git_repos
	git config --global --unset-all user.email
	git config --global --unset-all user.name
	chown ${rfs_username}:${rfs_username} /home/${rfs_username}/.gitconfig
fi

setup_workshop

other_source_links
#
