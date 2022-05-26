( # MAGISK SCRIPT
. /bin/utils.sh
. /bin/info.sh
debug_log "initrd-magisk: MAGISKTMP = [$MAGISKTMP]"

# get source name of android x86
get_src

lazy_umount(){
    umount -l "$1" && debug_log "initrd-magisk unmount: $1"
}

bind_debug(){
    mount --bind "$1" "$2" && debug_log "initrd-magisk: mnt_bind: $2 <- $1"
}

bind_policy(){
policy="$1"
umount -l "$1"
/magisk/magiskpolicy --load "$policy" --save "$inittmp/.overlay/policy" --magisk "allow * magisk_file lnk_file *" 2>>/tmp/magiskpolicy.txt && debug_log "initrd-magisk: magiskpolicy: inject magisk built-in rules"
/magisk/magiskpolicy --load "$inittmp/.overlay/policy" --save "$inittmp/.overlay/policy" --apply "$module_policy" 2>>/tmp/magiskpolicy.txt && debug_log "initrd-magisk: magiskpolicy: inject magisk modules sepolicy.rule"
bind_debug $inittmp/.overlay/policy "$policy"
}

load_policy(){

[ ! -f "$MAGISKCORE/magiskpolicy" ] && ln -sf ./magiskinit $MAGISKCORE/magiskpolicy

module_policy="$inittmp/.overlay/sepolicy.rules"
rm -rf "$module_policy"
echo "allow su * * *">"$module_policy"

# /data on Android-x86 is not always encrypted
for policy_dir in /data_mirror/adb/modules_update  /data_mirror/adb/modules /data_mirror/unencrypted/magisk; do
         for module in $(ls $policy_dir); do
              if ! [ -f "$policy_dir/$module/disable" ] && [ -f "$policy_dir/$module/sepolicy.rule" ] && [ ! -f "$inittmp/policy_loaded/$module" ]; then
                  cat  "$policy_dir/$module/sepolicy.rule" >>"$module_policy" &&  debug_log "initrd-magisk: read sepolicy.rule from $policy_dir/$module/sepolicy.rule"
                  echo "" >>"$module_policy"
                  echo -n > "$inittmp/policy_loaded/$module"
              fi
          done
done


umount -l /data_mirror

# bind mount modified sepolicy
ln -s /android/vendor /
if [ -f /android/system/vendor/etc/selinux/precompiled_sepolicy ]; then
  bind_policy /android/system/vendor/etc/selinux/precompiled_sepolicy
elif [ -f /android/sepolicy ]; then
  bind_policy /android/sepolicy
fi
}

check_magisk_and_load(){
#test magisk before inject into system
MAGISKDIR="/android/$MAGISKDIR"
ln -fs "./$magisk_name" "$MAGISKDIR/magisk"
"$MAGISKDIR/magisk" --daemon
if [ ! -z "$("$MAGISKDIR/magisk" -v)" ]; then
  echo_log "Magisk version: $("$MAGISKDIR/magisk" -v) ($("$MAGISKDIR/magisk" -V))"
  # load overlay.d from boot image
  . $MAGISKCORE/overlay.d.sh
  # inject magisk.rc into system
  cat $MAGISKCORE/magisk.rc >>"$INITRC"  && debug_log "initrd-magisk: inject magisk services into init.rc"
  # pre-init sepolicy patch for magisk and modules
  load_policy
else
   # since magisk is not available, we shoud unmount it
   debug_log "initrd-magisk: magisk is not available"
   cat $MAGISKCORE/unmount.rc >>"$INITRC"
   [ "$is_SAR" == "false" ] && rm -rf /android/magisk
fi
"$MAGISKDIR/magisk" --stop
killall -9 magiskd
}

if [ -f "/mnt/$SOURCE_OS/boot-magisk.img" ]; then
     loop_setup  "/mnt/$SOURCE_OS/boot-magisk.img"
     BOOTIMAGE="$LOOPDEV"
     debug_log "initrd-magisk: boot image = $BOOTIMAGE"
fi
[ -z "$BOOTIMAGE" ] && BOOTIMAGE=/dev/null

( # BEGIN : inject magisk

unset ABI

detect_sdk_abi

[ -z "$ABI" ] && {
echo "! Unable to detect architecture"
exit 1
}

echo_log "Architecture: $ABI - 64bit: $IS64BIT"

# load magisk from magisk.apk
magisk_name="magisk32"
if [ "$IS64BIT" == "true" ]; then
cp -af "$TMPDIR/magisk32/lib/$ABI32/"* "$MAGISKCORE"
magisk_name="magisk64"
fi
cp -af "$TMPDIR/magisk/lib/$ABI/"* "$MAGISKCORE"
for file in magisk32 magisk64 magiskinit magiskpolicy busybox magiskboot; do
    if [ ! -f "$MAGISKCORE/${file}" ]; then 
        rm -rf "$MAGISKCORE/${file}"
        cp -f "$MAGISKCORE/lib${file}.so" "$MAGISKCORE/${file}"
    fi
done



inittmp=/android/dev
mount -t tmpfs tmpfs $inittmp
mkdir -p $inittmp/.overlay/upper
mkdir -p $inittmp/.overlay/work
mkdir -p $inittmp/policy_loaded
mkdir -p $inittmp/boot-magisk
mkdir /data_mirror
mount_data_part /data_mirror
if [ -f "$MAGISKCORE/magisk.apk" ]; then
    cp "$MAGISKCORE/magisk.apk" "/data_mirror/media/0/magisk.apk"
    chmod 777 "/data_mirror/media/0/magisk.apk"
fi
datablock="$(cat /proc/mounts | grep " /data_mirror " | tail -1 | awk '{ print $1 }')"
datablock="/dev/block/$(basename "$datablock")"
OVERLAYDIR="/android/dev/boot-magisk/overlay.d"

# load magisk from boot image (boot-magisk.img)
# if boot image contains magisk, it will be used instead of magisk.apk

debug_log "initrd-magisk: parse boot image"
( cp -f "/mnt/$SOURCE_OS/boot-magisk.img" /tmp/boot.img
cd "$inittmp" && $MAGISKCORE/magiskboot unpack "/tmp/boot.img"
cd "$inittmp/boot-magisk" && cat "$inittmp/ramdisk.cpio" | cpio -iud
cp -f "$inittmp/boot-magisk/init" "$MAGISKCORE/magiskinit"
cp -f "$inittmp/boot-magisk/.backup/.magisk" "$MAGISKCORE/config"
FOUND_MAGISK=0
for item in magisk32 magisk64; do
    if [ -f "$OVERLAYDIR/sbin/$item.xz" ]; then
         FOUND_MAGISK=1
         xz -d "$OVERLAYDIR/sbin/$item.xz"
         mv "$OVERLAYDIR/sbin/$item" "$MAGISKCORE/$item" && debug_log "initrd-magisk: add ${item}"
         chmod 777 "$MAGISKCORE/$item"
    fi
done
if [ "$FOUND_MAGISK" == 0 ]; then 
    debug_log "initrd-magisk: boot image does not contain magisk";
    if [ -f "$MAGISKCORE/magisk.apk" ]; then
        echo "Load magisk temporarily from magisk.apk"
    fi
else
    debug_log "initrd-magisk: loaded magisk from boot image"
fi

 )

bootrc(){
sed -i "s|\${{SYSTEMIMAGE}}|$sysblock|g" "$MAGISKCORE/boot.rc"
sed -i "s|\${{DATAIMAGE}}|$datablock|g" "$MAGISKCORE/boot.rc"
sed -i "s|\${{BOOTIMAGE}}|$BOOTIMAGE|g" "$MAGISKCORE/boot.rc"
mkdir -p /dev/block/by-name
ln "/dev/$(basename "$sysblock")" /dev/block/by-name/system
ln "/dev/$(basename "$datablock")" /dev/block/by-name/data
ln "/dev/$(basename "$BOOTIMAGE")" /dev/block/by-name/boot
}


checkrootfs="$(mountpoint -d /android)"

MAGISKDIR=/magisk
INITRC="$inittmp/.overlay/upper/magisk.rc"

is_SAR=false

if [ "${checkrootfs%:*}" == "0" ] && mountpoint -q "/android"; then
echo_log "Android root directory is rootfs"
# rootfs, patch ramdisk
sysblock="$(cat /proc/mounts | grep " /android/system " | tail -1 | awk '{ print $1 }')"
sysblock="/dev/block/$(basename "$sysblock")"
bootrc
mount -o rw,remount /android && debug_log "initrd-magisk: remounted /android as read-write"
mkdir /android/magisk
sed -i "s|MAGISK_FILES_BASE|/magisk|g" $MAGISKCORE/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/magisk|g" $MAGISKCORE/magisk.rc
cp -a $MAGISKCORE/* /android/magisk && debug_log "initrd-magisk: copy $MAGISKCORE -> /android/magisk"
cp -a /android/init.rc "$INITRC"
bind_debug "$INITRC" /android/init.rc
cat "$MAGISKCORE/boot.rc" >>"$INITRC"
check_magisk_and_load
revert_changes(){
 debug_log "initrd-magisk: revert patches"
 rm -rf /android/magisk 
 lazy_umount /android/init.rc
 lazy_umount /android/sepolicy
 lazy_umount /android/system/vendor/etc/selinux/precompiled_sepolicy
}
elif mountpoint -q "/android"; then
is_SAR=true
echo_log "Android root directory is system-as-root"
MAGISKDIR=/system/etc/init/magisk
sysblock="$(cat /proc/mounts | grep " /android " | tail -1 | awk '{ print $1 }')"
sysblock="/dev/block/$(basename "$sysblock")"
bootrc
mkdir /android/dev/system_root
mount $sysblock /android/dev/system_root || mount -o ro $sysblock /android/dev/system_root
sys_mirror_inode="$(ls -id /android/dev/system_root | awk '{ print $1 }')"
sys_inode="$(ls -id /android | awk '{ print $1 }')"

# for user use system folder instead of system.img or system.sfs
if [ "$sys_inode" != "$sys_mirror_inode" ]; then
  mkdir /android/dev/osroot
  mount --move /android/dev/system_root /android/dev/osroot
  if [ -s "/android/dev/osroot/$SOURCE_OS/system/default.prop" ]; then
		mount --bind /android/dev/osroot/$SOURCE_OS/system /android/dev/system_root
  elif [ -z "$SOURCE_OS" -a -s /android/dev/osroot/default.prop ]; then
		mount --bind /android/dev/osroot /android/dev/system_root
  fi
fi

# prepare for second stage
chmod 750 $inittmp
lazy_umount /android/system/etc/init
mount -t overlay tmpfs -o lowerdir=/android/system/etc/init,upperdir=$inittmp/.overlay/upper,workdir=$inittmp/.overlay/work /android/system/etc/init && { 
debug_log "mount: /android/system/etc/init <- overlay"
chcon u:object_r:system_file:s0 $inittmp/.overlay/upper
chmod 755 $inittmp/.overlay/upper
chown 0.2000 $inittmp/.overlay/upper
}


sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" $MAGISKCORE/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" $MAGISKCORE/magisk.rc
cp -a $MAGISKCORE $inittmp/.overlay/upper && debug_log "initrd-magisk: copy $MAGISKCORE -> $inittmp/.overlay/upper/magisk"
cat "$MAGISKCORE/boot.rc" >>"$INITRC"
check_magisk_and_load

# fail back to magic mount if overlayfs is unavailable

if ! mount -t overlay | grep -q " /android/system/etc/init "; then
  mount -t tmpfs tmpfs -o mode=0755 /android/system/etc/init && { 
debug_log "mount: /android/system/etc/init <- tmpfs"
chcon u:object_r:system_file:s0 /android/system/etc/init
chmod 755 /android/system/etc/init
chown 0.2000 /android/system/etc/init
}

  for file in $(ls /android/dev/system_root/system/etc/init); do
    (
        sfile="/android/dev/system_root/system/etc/init/$file"
        xfile="/android/system/etc/init/$file"
        if [ -L "$sfile" ]; then
            cp "$sfile" "$xfile" && debug_log "cp_link: $xfile <- $sfile"
        elif [ -d "$sfile" ]; then
            mkdir "$xfile"
            bind_debug "$sfile" "$xfile"
        else
            echo -n >"$xfile"
            bind_debug "$sfile" "$xfile"
        fi
     ) &
  done
  sleep 0.05
  umount -l /android/system/etc/init/magisk
  umount -l /android/system/etc/init/magisk.rc
  rm -rf /android/system/etc/init/magisk
  rm -rf /android/system/etc/init/magisk.rc
  mkdir /android/system/etc/init/magisk
  bind_debug $inittmp/.overlay/upper/magisk /android/system/etc/init/magisk
  echo -n >/android/system/etc/init/magisk.rc
  bind_debug $inittmp/.overlay/upper/magisk.rc /android/system/etc/init/magisk.rc
fi



revert_changes(){
 debug_log "initrd-magisk: revert patches"
 lazy_umount /android/system/etc/init
 lazy_umount /android/sepolicy
 lazy_umount /android/system/vendor/etc/selinux/precompiled_sepolicy
}
else
    echo_log "WARNING: Android system is not mounted" 
fi


umount -l "$inittmp"

) 2>>/tmp/initrd-magisk.log # END: inject magisk

# wrapper sh command to make magisk su work properly in chroot environment
# Note: Gearlock will clear this wrapper, hard to prevent this

  [ -L "/system" ] && rm -f /system
  [ -f "/system" ] && rm -f /system
  mkdir /system 
  mount --bind /android/system /system
  mount -o ro,remount /system
  tmpfs_file /system/bin/sh
  cat <<EOF >/system/bin/sh
#!/android/system/bin/sh
name="\${0##*/}"
chroot /android "/system/bin/\$name" "\$@"
EOF
  chmod 777 /system/bin/su


 )

