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
   for file in /default.prop /system/build.prop /system/vendor/default.prop /system/vendor/build.prop /system/vendor/build.prop /system/vendor/odm/etc/build.prop /system/product/build.prop /system/system_ext/build.prop /vendor/build.prop /vendor/build.prop /vendor/odm/etc/build.prop /odm/etc/build.prop /product/build.prop /system_ext/build.prop; do
       result="$(grep_prop "$PROP" "/android$file")"
       [ ! -z "$result" ] && { echo "$result"; break; }
   done
}

debug_log(){
  if [ ! -z "$DEBUG" ]; then
      echo "$1" | tee -a /dev/kmsg
  else
      echo "$1" >/dev/kmsg
  fi
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
