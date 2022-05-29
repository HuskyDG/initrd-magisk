install_utils(){
local func
for func in getprop grep_prop mount_data_part cmdline loop_setup extract_system freboot tmpfs_file setprop open_tmpfile; do
	cat <<EOF >/bin/$func
#!/bin/busybox sh
PATH=/sbin:/bin:/system/bin:/system/xbin
dirname(){
    case "\$1" in
        /*)
            echo "\${1%/*}"
            ;;
        ./*)
            echo "\${1%/*}"
            ;;
        ../*)
            echo "\${1%/*}"
            ;;
        *)
            local dir="./\$1"
            echo "\${dir%/*}"
    esac
}

. "\${0%/*}/utils.sh"
"\$(basename "\$0")" \$@
EOF
    chmod 777 /bin/$func
done
}

freboot(){
	echo b >/proc/sysrq-trigger
}

open_tmpfile(){
    TMPFILE="/dev/$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20).tmp"
    if [ ! -z "$1" ] && [ -f "$(readlink -f "$1")" ]; then
        rm -f "$TMPFILE"
        cp -af "$(readlink -f "$1")" "$TMPFILE" && echo "$TMPFILE"
    fi
}

tmpfs_file(){
    local file="$1"
    local overlaydir="/dev/.overlay_$RANDOM"
    [ ! -f "$file" ] && return
    mkdir "$overlaydir"
    mount -t tmpfs tmpfs "$overlaydir"
    cp -af "$file" "$overlaydir/file"
    mount --bind "$overlaydir/file" "$file"
    umount -l "$overlaydir"
    rm -rf "$overlaydir"
}

setprop(){
    local prop="$1"
    local name="$2"
    local propfile="$(open_tmpfile /android/default.prop)"
    [ -z "$propfile" ] && return 1
    mount -t tmpfs | grep -q " /android/default.prop " || tmpfs_file /android/default.prop
    ( echo "$prop=$name"; grep -v "^$prop=" "$propfile" ) >/android/default.prop
    rm -rf "$propfile"
}


extract_system(){
get_src

if [ -f "/sfs/system.img" ] && [ -f "/mnt/$SOURCE_OS/system.sfs" ]; then
    echo "Extracting system image..."
    cp /sfs/system.img "/mnt/$SOURCE_OS/system.img" || abort "! Failed to create system.img"
    rm -rf "/mnt/$SOURCE_OS/system.sfs"
elif [ -f "/mnt/$SOURCE_OS/system.sfs" ]; then
    echo "Extracting system image..."
    mount -o ro "/mnt/$SOURCE_OS/system.sfs" /sfs || abort "! Failed to mount system.sfs"
    if [ -f "/sfs/system.img" ]; then 
        echo "Extracting system image..."
        cp /sfs/system.img "/mnt/$SOURCE_OS/system.img" || abort "! Failed to create system.img"
        rm -rf "/mnt/$SOURCE_OS/system.sfs"
    else 
        echo "Extracting system image..."
        dd if=/dev/zero of="/mnt/$SOURCE_OS/system.img" bs=4098 count=1220703 || abort "! Failed to create system.img"
        mkfs.ext4 "/mnt/$SOURCE_OS/system.img" # create ext4 filesystem image
        mkdir /image_loop
        mount -o ro,loop "/mnt/$SOURCE_OS/system.img" /image_loop
        mount -o rw,remount /image_loop || abort "! Failed to mount loop system.img"
        cp -af /sys/* /image_loop || abort "! Failed to copy files from system.sfs to system.img"
    fi
elif [ -f "/mnt/$SOURCE_OS/system.img" ]; then
    abort "! System is already extracted"
else
    abort "! Cannot find system image"
fi
echo "System image has been extracted successfully!"
echo "Reboot in 5 seconds..."
sleep 5
freboot
}


mount_data_part(){
MP="$1"
data_bind=false
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
       data_bind=true
		fi
	elif [ -d /mnt/$SRC/data ]; then
		remount_rw
		mount --bind /mnt/$SRC/data "$MP"
     data_bind=true
	elif [ -f /mnt/$SRC/data.img ]; then
		remount_rw
		mount -o loop,noatime /mnt/$SRC/data.img "$MP"
	fi
}

remount_rw()
{
	# "foo" as mount source is given to workaround a Busybox bug with NFS
	# - as it's ignored anyways it shouldn't harm for other filesystems.
	mount -o remount,rw foo /mnt
}


grep_prop() {
  local REGEX="s/^$1=//p"
  shift
  local FILES=$@
  [ -z "$FILES" ] && FILES='/android/system/build.prop'
  cat $FILES 2>/dev/null | dos2unix | sed -n "$REGEX" | head -n 1
}

getprop(){
   local result
   local PROP="$1"
   [ -z "$PROP" ] && {
       echo "Cannot list all properties in this mode" >&2
       return 1
   }
   for file in /default.prop /system/build.prop /system/vendor/default.prop /system/vendor/build.prop /system/vendor/build.prop /system/vendor/odm/etc/build.prop /system/product/build.prop /system/system_ext/build.prop /vendor/build.prop /vendor/build.prop /vendor/odm/etc/build.prop /odm/etc/build.prop /product/build.prop /system_ext/build.prop; do
       result="$(grep_prop "$PROP" "/android$file")"
       [ ! -z "$result" ] && { echo "$result"; break; }
   done
}

debug_log(){
  echo "$1" >/dev/kmsg
}

echo_log(){
  echo "$1" | tee -a /dev/kmsg
}


detect_sdk_abi(){
API=$(getprop ro.build.version.sdk)
ABI=$(getprop ro.product.cpu.abi)
  if [ "$ABI" = "x86" ]; then
    ARCH=x86
    ABI32=x86
    IS64BIT=false
  elif [ "$ABI" = "arm64-v8a" ]; then
    ARCH=arm64
    ABI32=armeabi-v7a
    IS64BIT=true
  elif [ "$ABI" = "x86_64" ]; then
    ARCH=x64
    ABI32=x86
    IS64BIT=true
 elif [ "$ABI" = "armeabi-v7a" ]; then
    ARCH=arm
    ABI=armeabi-v7a
    ABI32=armeabi-v7a
    IS64BIT=false
  fi
}

cmdline() { 
	awk -F"${1}=" '{print $2}' < /proc/cmdline | cut -d' ' -f1 2> /dev/null
}


abort(){
echo "$1"; exit 1;
umount -l /image_loop
}

get_src(){
SOURCE_OS="$(cmdline SRC)"
KERNEL_IMAGE="$(cmdline BOOT_IMAGE)"
[ -z "$SOURCE_OS" ] && SOURCE_OS="$(dirname "$KERNEL_IMAGE")"
}

loop_setup() {
  unset LOOPDEV
  local LOOP
  local MINORX=1
  [ -e /dev/block/loop1 ] && MINORX=$(stat -Lc '%T' /dev/block/loop1)
  local NUM=0
  while [ $NUM -lt 64 ]; do
    LOOP=/dev/block/loop$NUM
    [ -e $LOOP ] || mknod $LOOP b 7 $((NUM * MINORX))
    if losetup $LOOP "$1" 2>/dev/null; then
      LOOPDEV=$LOOP
      break
    fi
    NUM=$((NUM + 1))
  done
}
