#!/bin/sh

# ***** Mikrotik NAND flash devices code *****

# Flash kernel part of combined image to kernel partition
# and rootfs part(squashfs) to ubi_gluebi rootfs partition
nand_upgrade_combined() {
	local CI_BLKSZ=65536
	local kernelpart=$CI_KERNPART
	local rootfspart=rootfs
	local kern_length=0x$(dd if="$1" bs=2 skip=1 count=4 2>/dev/null)
	local kern_blocks=$(($kern_length / $CI_BLKSZ))
	local kern_magic_id=$(dd if="$1" bs=1 skip=$CI_BLKSZ count=8 2>/dev/null)
	local rootfs_length=0x$(dd if="$1" bs=2 skip=5 count=4 2>/dev/null)
	local root_blocks=$((0x$(dd if="$1" bs=2 skip=5 count=4 2>/dev/null) / $CI_BLKSZ))
	local rootfs_type=$(identify $1 $((($kern_length + $CI_BLKSZ) / 4)))

	# write kernel
	case "$kern_magic_id" in
		"MIKROTIK") ;; # Here I do not need to write kernel. I allready done this in platform_pre_upgrade.
		# Other platforms:
		# You can add your code here if you want to use combined  sysupgrade image on their NAND platform.
	esac

	# write rootfs to ubi0->rootfs
	nand_upgrade_prepare_ubi "$rootfs_length" "$rootfs_type" "0" "0"

	local ubidev="$(nand_find_ubi "$CI_UBIPART")"
	local root_ubivol="$(nand_find_volume $ubidev rootfs)"
	dd if="$1" bs=$CI_BLKSZ skip=$((1+$kern_blocks)) count=$root_blocks 2>/dev/null | \
		ubiupdatevol /dev/$root_ubivol -s $rootfs_length -
	nand_do_upgrade_success "jffs2"
}

# Return common sysupgrade platform name(NNDXXXXX or NORXXXXX) for Mikrotik devices
get_mikrotik_sysupgrade_platform_name(){
	local kern_mtd_index="$(find_mtd_index $CI_KERNPART)"
	local kern_mtd_dev="/dev/mtd$kern_mtd_index"
	[ -n "$kern_mtd_index" -a -e "$kern_mtd_dev" ] || return 1
	[ -x /usr/sbin/mtdinfo ] || {
		echo "Error! mtdinfo not found! Package nand-utils does not installed ?"
		return 1
	}
	local mtd_info=$(/usr/sbin/mtdinfo $kern_mtd_dev)
	local mtd_type=`echo "$mtd_info" | sed -n 's/^Type: *\(.\+\)$/\1/p'`
	local mtd_unit_size=`echo "$mtd_info" | sed -n 's/^Minimum input\/output unit size\: *\([0-9]\+\) *bytes$/\1/p'`
	[ -z "$mtd_type" -o -z "$mtd_unit_size" ] && return 1
	case "$mtd_type" in
		nand)
			mtd_type="NND"
			break
		;;
		nor)
			mtd_type="NOR"
			break
		;;
		*)
			return 1
		;;
	esac
	local res="$mtd_type$mtd_unit_size"
	while [ ${#res} -lt 8 ]; do
		mtd_unit_size="0$mtd_unit_size"
		res="$mtd_type$mtd_unit_size"
	done
	echo "$mtd_type$mtd_unit_size"
	return 0
}

# Flash MIKROTIK yaffs2 kernel part of combined image to kernel partition
# See https://github.com/adron-s/kernel2minor source code for details
nand_upgrade_mikrotik_yaffs2_kernel() {
	local CI_BLKSZ=65536
	local kernelpart=$CI_KERNPART
	local kern_mtd_index="$(find_mtd_index $CI_KERNPART)"
	local kern_mtd_dev="/dev/mtd$kern_mtd_index"
	local kern_ib_offset=$(($CI_BLKSZ / 8))
	local kern_magic_id=$(dd if="$1" bs=8 skip=$kern_ib_offset count=1 2>/dev/null)
	local kern_platform_name=$(dd if="$1" bs=8 skip=$(($kern_ib_offset+1)) count=1 2>/dev/null)
	local kern_info_block_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+2)) count=1 2>/dev/null)))
	local kern_block_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+4)) count=1 2>/dev/null)))
	local kern_blocks=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+5)) count=1 2>/dev/null)))
	local kern_align_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+10)) count=1 2>/dev/null)))
	local this_platform_name=$(get_mikrotik_sysupgrade_platform_name)
	[ $? -ne 0 ] && return 1 # if platform_name return error
	[ "$kern_magic_id" != "MIKROTIK" ] && {
		echo "Error! This image is not for MIKROTIK!"
		return 1
	}
	[ "$kern_platform_name" != "$this_platform_name" ] && {
		echo "Error! Image is for MIKROTIK but not for this platform!"
		echo "This platform := '$this_platform_name'"
		echo "Image platform := '$kern_platform_name'"
		return 1
	}
	[ "$kern_align_size" -ne "$CI_BLKSZ" ] && {
		echo "Error ! Kernel image align size '$kern_align_size' != '$CI_BLKSZ' !"
		echo "Kernel image is corrupted?"
		return 1
	}
	local kern_headers_size=$(($kern_align_size + $kern_info_block_size))
	[ $(($kern_headers_size % $kern_block_size)) -ne 0 ] && {
		echo "Error ! Kernel headers(sysupgrade + info_block) % block_size != 0"
		echo "   ---> ($kern_align_size + $kern_info_block_size) % $kern_block_size != 0"
		echo "Kernel image is corrupted?"
		return 1
	}
	local kern_headers_size_in_blocks=$((kern_headers_size / $kern_block_size))
	# final checks
	[ "$kern_blocks" != 0 -a -n "$kern_mtd_index" -a -e "$kern_mtd_dev" ] || return 1
	# write kernel
	mtd erase "$kern_mtd_dev" && \
	    dd if="$1" bs=$kern_block_size skip=$kern_headers_size_in_blocks \
	    count=$kern_blocks 2>/dev/null | \
	    nandwrite -o $kern_mtd_dev -
	return $?
}

# ***** Mikrotik NOR flash devices code *****

platform_find_rootfspart() {
	local part
	for part in "${1%:*}" "${1#*:}"; do
		[ "$part" != "$2" ] && echo "$part"; break
	done
}

platform_do_upgrade_combined_mikrotik_helper(){
	local kernelpart="$2"
	local kern_blocks_with_info_hdr="$3" # kernel image info_header size in blocks + kernel body size in blocks
	local rootfspart="$4"
	local root_blocks="$5"
	local append="$6"
	local kern_ib_offset=$(($CI_BLKSZ / 8))
	local kern_platform_name=$(dd if="$1" bs=8 skip=$(($kern_ib_offset+1)) count=1 2>/dev/null)
	local kern_info_block_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+2)) count=1 2>/dev/null)))
	local kern_block_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+4)) count=1 2>/dev/null)))
	local kern_align_size=$((0x$(dd if="$1" bs=8 skip=$(($kern_ib_offset+10)) count=1 2>/dev/null)))
	[ "$kern_platform_name" != "NOR01024" ] && {
		echo "Error! Image is for MIKROTIK but not for NOR01024 platform!"
		echo "Image platform is '$kern_platform_name'"
		reboot
		exit 1
	}
	local kern_headers_size=$kern_info_block_size # for NOR we have only one(info_block) header
	[ "$kern_align_size" -ne "0" ] || # align size must be == 0 for NOR !
	[ "$kern_block_size" -ne "$CI_BLKSZ" ] ||
	[ $(($kern_headers_size % $kern_block_size)) -ne 0 ] && {
		echo "Error! Kernel image is corrupted?"
		reboot
		exit 1
        }
	local kern_headers_size_in_blocks=$((kern_headers_size / $kern_block_size))
	local kernel_body_size_in_blocks=$(($kern_blocks_with_info_hdr - kern_headers_size_in_blocks))
	# skip combined image header(1 block) and kernel_headers(only info_block kernel header for NOR)
	dd if="$1" bs=$kern_block_size skip=$((1 + $kern_headers_size_in_blocks)) count=$kernel_body_size_in_blocks 2>/dev/null | \
		mtd write - $kernelpart
	# skip combined image header(1 block) and all kernel image(info_block kernel header + yaffs2 kernel body)
	dd if="$1" bs=$kern_block_size skip=$((1 + $kern_blocks_with_info_hdr)) \
		count=$root_blocks 2>/dev/null | mtd -r $append write - $rootfspart
}
