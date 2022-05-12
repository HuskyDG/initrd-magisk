#!MAGISK_FILES_BASE/busybox sh
export PATH=/sbin:/system/bin:/system/xbin
# initial function
mnt_tmpfs(){ (
    # MOUNT TMPFS ON A DIRECTORY
    MOUNTPOINT="$1"
    mkdir -p "$MOUNTPOINT"
    mount -t tmpfs -o "mode=0755" tmpfs "$MOUNTPOINT" 2>/dev/null
) }
mnt_bind(){ (
    # SHORTCUT BY BIND MOUNT
    FROM="$1"; TO="$2"
    if [ -L "$FROM" ]; then
        SOFTLN="$(readlink "$FROM")"
        ln -s "$SOFTLN" "$TO"
    elif [ -d "$FROM" ]; then
        mkdir -p "$TO" 2>/dev/null
        mount --bind "$FROM" "$TO"
    else
        echo -n 2>/dev/null >"$TO"
        mount --bind "$FROM" "$TO"
    fi
) }
cmdline() { 
awk -F"${1}=" '{print $2}' < /proc/cmdline | cut -d' ' -f1 2> /dev/null
}
revert_changes(){
     #remount system read-only to fix Magisk fail to mount mirror
     if mount -t rootfs | grep -q " / " || mount -t tmpfs | grep -q " / "; then
        mount -o rw,remount /
        rm -rf /magisk
     fi
     mount -o ro,remount /
     mount -o ro,remount /system
     mount -o ro,remount /vendor
     mount -o ro,remount /product
     mount -o ro,remount /system_ext
     # unmount patched files
     umount -l /system/etc/init
     umount -l /init.rc
     umount -l /system/etc/init/hw/init.rc
     umount -l /sepolicy
     umount -l /system/vendor/etc/selinux/precompiled_sepolicy
}
exit_magisk(){
     umount -l ${{MAGISKTMP}}
     revert_changes
     echo -n >/dev/.magisk_unblock
}

# make sure /dev/null exist
[ -c "/dev/null" ] || { rm -rf /dev/null; mknod -m 666 /dev/null c 1 3; }

# detect architecture
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
  else
    ARCH=arm
    ABI=armeabi-v7a
    ABI32=armeabi-v7a
    IS64BIT=false
  fi

magisk_name="magisk32"
[ "$IS64BIT" == true ] && magisk_name="magisk64"

# umount previous /sbin tmpfs overlay

count=0
( magisk --stop ) &

# force umount /sbin tmpfs

until ! mount | grep -q " /sbin "; do
    [ "$count" -gt 10 ] && break
    umount -l /sbin 2>/dev/null
    sleep 0.1
    count=1
    test ! -d /sbin && break
done

MAGISKTMP=${{MAGISKTMP}}

cp -af MAGISK_FILES_BASE/sbin/* $MAGISKTMP
chmod 755 "$MAGISKTMP"
set -x
mkdir -p $MAGISKTMP/.magisk
mkdir -p $MAGISKTMP/emu
exec 2>>$MAGISKTMP/emu/record_logs.txt
exec >>$MAGISKTMP/emu/record_logs.txt

cd MAGISK_FILES_BASE 
test ! -f "./$magisk_name" && magisk_name=magisk32
test ! -f "./$magisk_name" && { echo -n >/dev/.overlay_unblock; exit_magisk; exit 0; }

MAGISKBIN=/data/adb/magisk
mkdir /data/unencrypted
chmod 700 /data/unencrypted

# create some folder in magisk secure directory
for mdir in . modules post-fs-data.d service.d magisk; do
    chattr -i /data/adb/$mdir
    test ! -d /data/adb/$mdir && rm -rf /data/adb/$mdir
    mkdir -p /data/adb/$mdir 2>/dev/null
done

# make sure /data/adb/magisk is not immune
chattr -R -i /data/adb/magisk

# copy files to MAGISKBIN and MAGISKTMP
for file in magisk32 magisk64 magiskinit magiskpolicy busybox mount.fuse; do
  cp -af ./$file $MAGISKTMP/$file 2>/dev/null
  chmod 755 $MAGISKTMP/$file
  cp -af ./$file $MAGISKBIN/$file 2>/dev/null
  chmod 755 $MAGISKBIN/$file
done

# copy magiskboot and magisk.apk
cp -af ./magiskboot $MAGISKBIN/magiskboot
[ -f "./magisk.apk" ] && cp -af ./magisk.apk $MAGISKTMP/magisk.apk || ./magiskinit -x manager $MAGISKTMP/magisk.apk
ln $MAGISKTMP/magisk.apk $MAGISKTMP/stub.apk


# create symlink to magisk
ln -s ./$magisk_name $MAGISKTMP/magisk 2>/dev/null
ln -s ./magisk $MAGISKTMP/su 2>/dev/null
ln -s ./magisk $MAGISKTMP/resetprop 2>/dev/null
ln -s ./magisk $MAGISKTMP/magiskhide 2>/dev/null

# from 24302 magiskpolicy is no longer an applet of magiskinit
# only create symlink if magiskpolicy is not found
[ ! -f "$MAGISKTMP/magiskpolicy" ] && ln -s ./magiskinit $MAGISKTMP/magiskpolicy 2>/dev/null
ln -s ./magiskpolicy $MAGISKTMP/supolicy 2>/dev/null

# create some folder for magisk
mkdir -p $MAGISKTMP/.magisk/mirror
mkdir $MAGISKTMP/.magisk/block
cat MAGISK_FILES_BASE/config >$MAGISKTMP/.magisk/config
restorecon -R /data/adb/magisk

cat MAGISK_FILES_BASE/magisksu_survival.sh >$MAGISKTMP/emu/magisksu_survival.sh

OSROOT="$(cat MAGISK_FILES_BASE/osroot_dev)"
if [ ! -z "$OSROOT" ]; then
    BLOCKNAME="${OSROOT##*/}"
    ln -s "./$BLOCKNAME" "$MAGISKTMP/.magisk/mirror/osroot"
fi

SRC="$(cmdline SRC)"
BIPATH="$(cmdline BOOT_IMAGE)"
test -z "$SRC" && SRC="${BIPATH%/*}"
if [ ! -z "$SRC" ]; then
    ln -s "./osroot/$SRC" "$MAGISKTMP/.magisk/mirror/android"
fi

# if magisk does not exist
[ ! -f "$MAGISKTMP/magisk" ] && exit_magisk


( #fix mount data mirror
data_inode="$(ls -id "/data" | awk '{ print $1 }')"
[ "$data_inode" == "1" ] && exit
if [ "$data_inode" != "2" ] && [ "$data_inode" != "3" ]; then
    CHECKBLOCK="$(mountpoint -d "/data")"
    blk_major="${CHECKBLOCK%:*}"
    blk_minor="${CHECKBLOCK: ${#blk_major}+1}"
    mknod -m 660 "$MAGISKTMP/.magisk/block/data" b "$blk_major" "$blk_minor"
    mkdir -p "$MAGISKTMP/.magisk/mirror/data"
    mount "$MAGISKTMP/.magisk/block/data" "$MAGISKTMP/.magisk/mirror/data"
    rm -rf "$MAGISKTMP/.magisk/block/data"
    mknod -m 660 "$MAGISKTMP/.magisk/block/data" b 0 0
    touch "$MAGISKTMP/.magisk/block/data"
    chattr +i "$MAGISKTMP/.magisk/block/data"

    DATA="$(cmdline DATA)"
    test -z "$SRC" && SRC="${BIPATH%/*}"
    test -z "$SRC" && exit
    test -z "$DATA" && DATA=data

    inode_data1=$(ls -id "$MAGISKTMP/.magisk/mirror/data/$SRC/$DATA" | awk '{ print $1 }')
    inode_data2=$(ls -id "$MAGISKTMP/.magisk/mirror/data/$SRC/data" | awk '{ print $1 }')
    inode_data=$(ls -id "/data" | awk '{ print $1 }')

    if [ "$inode_data1" == "$inode_data" ]; then
        mount --bind "$MAGISKTMP/.magisk/mirror/data/$SRC/$DATA" "$MAGISKTMP/.magisk/mirror/data"
    elif [ "$inode_data2" == "$inode_data" ]; then
        mount --bind "$MAGISKTMP/.magisk/mirror/data/$SRC/data" "$MAGISKTMP/.magisk/mirror/data"
    fi
fi )


# revert all changes because all patch files have been loaded by init
revert_changes


