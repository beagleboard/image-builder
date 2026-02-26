#!/bin/bash

export apt_proxy=192.168.1.10:3142/

config=bb.org-debian-trixie-iot-v6.18-k3-arm64
filesize=8gb
rootfs="debian-arm64-13-iot-v6.18-k3"

debian_short="Debian 13"
debian_long="Debian 13 (Trixie)"

compress_snapshot_image () {
	yml_file="${device}-${export_filename}-${filesize}.img.xz.yml.txt"
	sudo -uvoodoo mkdir -p /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/
	sync

	echo "- name: ${r_board} ${debian_short} ${r_name}" >> ${yml_file}
	echo "  description: ${debian_long} with ${r_description} for ${r_board} based on ${r_processor} processor" >> ${yml_file}
	echo "  icon: https://media.githubusercontent.com/media/beagleboard/bb-imager-rs/refs/heads/main/assets/os/debian.png" >> ${yml_file}
	echo "  url: https://files.beagle.cc/file/beagleboard-public-2021/images/${device}-${export_filename}-${filesize}.img.xz" >> ${yml_file}
	echo "  bmap: https://raw.githubusercontent.com/beagleboard/distros/refs/heads/main/bmap-temp/${device}-${export_filename}-${filesize}.bmap" >> ${yml_file}

	extract_size=$(du -b ./${device}-${export_filename}-${filesize}.img | awk '{print $1}')
	echo "  extract_size: ${extract_size}" >> ${yml_file}
	extract_sha256=$(sha256sum ./${device}-${export_filename}-${filesize}.img | awk '{print $1}')
	echo "  extract_sha256: ${extract_sha256}" >> ${yml_file}

	echo "Creating... ${device}-${export_filename}-${filesize}.bmap"
	bmaptool -d create -o ./${device}-${export_filename}-${filesize}.bmap ./${device}-${export_filename}-${filesize}.img

	echo "Compressing... ${device}-${export_filename}-${filesize}.img"
	xz -T0 -z ${device}-${export_filename}-${filesize}.img
	sync

	image_download_size=$(du -b ./${device}-${export_filename}-${filesize}.img.xz | awk '{print $1}')
	echo "  image_download_size: ${image_download_size}" >> ${yml_file}
	image_download_sha256=$(sha256sum ./${device}-${export_filename}-${filesize}.img.xz | awk '{print $1}')
	echo "  image_download_sha256: ${image_download_sha256}" >> ${yml_file}

	echo "  release_date: '${time}'" >> ${yml_file}
	echo "  init_format: sysconf" >> ${yml_file}
	echo "  devices:" >> ${yml_file}
	echo "    - ${r_devices}" >> ${yml_file}
	echo "    - recommended" >> ${yml_file}

	sync

	sha256sum ${device}-${export_filename}-${filesize}.img.xz > ${device}-${export_filename}-${filesize}.img.xz.sha256sum
	sudo -uvoodoo cp -v ./${device}-${export_filename}-${filesize}.bmap /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/
	sudo -uvoodoo cp -v ./${device}-${export_filename}-${filesize}.img.xz /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/
	sudo -uvoodoo cp -v ./${device}-${export_filename}-${filesize}.img.xz.sha256sum /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/
	sudo -uvoodoo cp -v ./${device}-${export_filename}-${filesize}.img.xz.yml.txt /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/
	sudo -uvoodoo cp -v ./dpkg-sbom.txt /mnt/mirror/rcn-ee.us/rootfs/${rootfs}/${time}/${device}-${export_filename}-${filesize}.dpkg-sbom.txt || true
}

if [ -d ./deploy ] ; then
	sudo rm -rf ./deploy || true
fi

touch .notar
touch .gitea.mirror
echo "./RootStock-NG.sh -c ${config}"
./RootStock-NG.sh -c ${config}

source .project

if [ -d ./deploy/${export_filename}/ ] ; then
	cd ./deploy/${export_filename}/

	echo "sudo ./setup_sdcard.sh --img-${filesize} bbai64-${export_filename} --dtb bbai64-swap"
	sudo ./setup_sdcard.sh --img-${filesize} bbai64-${export_filename} --dtb bbai64-swap
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} bbai64-emmc-flasher-${export_filename} --dtb bbai64-swap --enable-extlinux-flasher"
	sudo ./setup_sdcard.sh --img-${filesize} bbai64-emmc-flasher-${export_filename} --dtb bbai64-swap --enable-extlinux-flasher
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} beagleplay-${export_filename} --dtb beagleplay-swap"
	sudo ./setup_sdcard.sh --img-${filesize} beagleplay-${export_filename} --dtb beagleplay-swap
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} beagleplay-emmc-flasher-${export_filename} --dtb beagleplay-swap --enable-extlinux-flasher"
	sudo ./setup_sdcard.sh --img-${filesize} beagleplay-emmc-flasher-${export_filename} --dtb beagleplay-swap --enable-extlinux-flasher
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} beagley-ai-${export_filename} --dtb beagley-ai"
	sudo ./setup_sdcard.sh --img-${filesize} beagley-ai-${export_filename} --dtb beagley-ai
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} pocketbeagle2-${export_filename} --dtb pocketbeagle2-swap"
	sudo ./setup_sdcard.sh --img-${filesize} pocketbeagle2-${export_filename} --dtb pocketbeagle2-swap
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	echo "sudo ./setup_sdcard.sh --img-${filesize} pocketbeagle2-workshop-${export_filename} --dtb pocketbeagle2-swap --enable-load-pb2-workshop"
	sudo ./setup_sdcard.sh --img-${filesize} pocketbeagle2-workshop-${export_filename} --dtb pocketbeagle2-swap --enable-load-pb2-workshop
	mv ./*.img ../
	cp -v ./dpkg-sbom.txt ../ || true

	cd ../

	r_description="no desktop environment"

	r_board="BeagleY-AI"
	r_processor="TI AM67A (J722S)"
	r_devices="beagle-am67"

	r_name="v6.18.x-k3 IoT (LTS-Dec-2028)"
	device="beagley-ai" ; compress_snapshot_image

	r_board="BeagleBone AI-64"
	r_processor="TI TDA4VM"
	r_devices="beagle-tda4vm"

	r_name="v6.18.x-k3 IoT (Recommended) (LTS-Dec-2028)"
	device="bbai64" ; compress_snapshot_image

	r_name="v6.18.x-k3 IoT Flasher (Recommended) (LTS-Dec-2028)"
	device="bbai64-emmc-flasher" ; compress_snapshot_image

	r_board="BeaglePlay"
	r_processor="TI AM62"
	r_devices="beagle-am62"

	r_name="v6.18.x-k3 IoT (Recommended) (LTS-Dec-2028)"
	device="beagleplay" ; compress_snapshot_image

	r_name="v6.18.x-k3 IoT Flasher (Recommended) (LTS-Dec-2028)"
	device="beagleplay-emmc-flasher" ; compress_snapshot_image

	r_board="PocketBeagle 2"
	r_processor="TI AM62"
	r_devices="pocketbeagle2-am62"

	r_name="v6.18.x-k3 IoT (LTS-Dec-2028)"
	device="pocketbeagle2" ; compress_snapshot_image

	r_name="v6.18.x-k3 IoT (TechLab Workshop) (LTS-Dec-2028)"
	device="pocketbeagle2-workshop" ; compress_snapshot_image

	rm -rf ${tempdir} || true
	cd ../
else
	echo "failure"
	exit 2
fi
#
