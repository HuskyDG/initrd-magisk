mount_data_part(){
MP="$1"
	mountpoint -q "$MP" && return
	if [ -n "$DATA" ]; then
		blk=`basename $DATA`
		if [ -b "/dev/$blk" ]; then
			[ ! -e /dev/block/$blk ] && ln /dev/$blk /dev/block
			mount -o noatime /dev/block/$blk "$MP"
		elif [ "$DATA" = "9p" ]; then
			modprobe 9pnet_virtio
			mount -t 9p -o trans=virtio data "$MP" -oversion=9p2000.L,posixacl,cache=loose
		else
			remount_rw
			mkdir -p /mnt/$SRC/$DATA
			mount --bind /mnt/$SRC/$DATA "$MP"
		fi
	elif [ -d /mnt/$SRC/data ]; then
		remount_rw
		mount --bind /mnt/$SRC/data "$MP"
	elif [ -f /mnt/$SRC/data.img ]; then
		remount_rw
		mount -o loop,noatime /mnt/$SRC/data.img "$MP"
	else
		device_mount_data || mount -t tmpfs tmpfs "$MP"
	fi
}