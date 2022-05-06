( # MAGISK SCRIPT
. /bin/utils.sh
. /bin/info.sh
set -

( # BEGIN : inject magisk

lazy_umount(){
    umount -l "$1" && debug_log "initrd-magisk unmount: $1"
}

if [ ! -z "$DEBUG" ]; then
    SELOGFILE=/tmp/magiskpolicy.txt
else
    SELOGFILE=/dev/null
fi

unset ABI

detect_sdk_abi

[ -z "$ABI" ] && {
echo "! Unable to detect architecture"
exit 1
}

echo_log "Architecture: $ABI - 64bit: $IS64BIT"

magisk_name="magisk32"

if [ "$IS64BIT" == "true" ]; then
cp -af "$TMPDIR/magisk32/lib/$ABI32/"* "$MAGISKCORE"
magisk_name="magisk64"
fi

cp -af "$TMPDIR/magisk/lib/$ABI/"* "$MAGISKCORE"

for file in magisk32 magisk64 magiskinit magiskpolicy busybox magiskboot; do
rm -rf "$MAGISKCORE/${file}"
cp "$MAGISKCORE/lib${file}.so" "$MAGISKCORE/${file}"
done



inittmp=/android/dev
mount -t tmpfs tmpfs $inittmp
mkdir -p $inittmp/.overlay/upper
mkdir -p $inittmp/.overlay/work
mkdir -p $inittmp/policy_loaded

checkrootfs="$(mountpoint -d /android)"

MAGISKDIR=/android/magisk

if [ "${checkrootfs%:*}" == "0" ] && mountpoint -q "/android"; then
echo_log "Android root directory is rootfs"
# rootfs, patch ramdisk
mount -o rw,remount /android && debug_log "initrd-magisk: remounted /android as read-write"
mkdir /android/magisk
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/magisk.rc
cp -a /magisk/* /android/magisk && debug_log "initrd-magisk: copy /magisk -> /android/magisk"
[ ! -f "/magisk/init.rc" ] && cat /android/init.rc >/magisk/init.rc
[ -f "/magisk/init.rc" ] && cat /magisk/init.rc >/android/init.rc
cat /magisk/magisk.rc >>/android/init.rc && debug_log "initrd-magisk: inject magisk services into init.rc"
revert_changes(){
 debug_log "initrd-magisk: revert patches"
 cat /magisk/init.rc >/android/init.rc && debug_log "initrd-magisk restore: /android/init.rc"
 rm -rf /android/magisk 
 lazy_umount /android/sepolicy
 lazy_umount /android/system/vendor/etc/selinux/precompiled_sepolicy
}
elif mountpoint -q "/android"; then
echo_log "Android root directory is system-as-root"
sysblock="$(mount | grep " /android " | tail -1 | awk '{ print $1 }')"
mkdir /android/dev/system_root
mount $sysblock /android/dev/system_root || mount -o ro $sysblock /android/dev/system_root
# prepare for second stage
chmod 750 $inittmp
lazy_umount /android/system/etc/init
mount -t overlay tmpfs -o lowerdir=/android/system/etc/init,upperdir=$inittmp/.overlay/upper,workdir=$inittmp/.overlay/work /android/system/etc/init && { 
debug_log "mount: /android/system/etc/init <- overlay"
chcon u:object_r:system_file:s0 $inittmp/.overlay/upper
chmod 755 $inittmp/.overlay/upper
chown 0.2000 $inittmp/.overlay/upper
}


sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/magisk.rc
cp -a /magisk $inittmp/.overlay/upper && debug_log "initrd-magisk: copy /magisk -> $inittmp/.overlay/upper/magisk"
cp /magisk/magisk.rc $inittmp/.overlay/upper/magisk.rc  && debug_log "initrd-magisk: inject magisk services into init.rc"
MAGISKDIR=/android/system/etc/init/magisk

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
            mount --bind "$sfile" "$xfile" && debug_log "mnt_bind: $xfile <- $sfile"
        else
            echo -n >"$xfile"
            mount --bind "$sfile" "$xfile" && debug_log "mnt_bind: $xfile <- $sfile"
        fi
     ) &
  done
  sleep 0.05
  umount -l /android/system/etc/init/magisk
  umount -l /android/system/etc/init/magisk.rc
  rm -rf /android/system/etc/init/magisk
  rm -rf /android/system/etc/init/magisk.rc
  mkdir /android/system/etc/init/magisk
  mount --bind $inittmp/.overlay/upper/magisk /android/system/etc/init/magisk && debug_log "mnt_bind: /android/system/etc/init/magisk <- $inittmp/.overlay/upper/magisk"
  echo -n >/android/system/etc/init/magisk.rc
  mount --bind $inittmp/.overlay/upper/magisk.rc /android/system/etc/init/magisk.rc && debug_log "mnt_bind: /android/system/etc/init/magisk.rc <- $inittmp/.overlay/upper/magisk.rc"
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


if mountpoint -q "/android"; then
# pre-init sepolicy patch


mkdir -p /data
mount_data_part /data
[ ! -f "/magisk/magiskpolicy" ] && ln -sf ./magiskinit /magisk/magiskpolicy

module_policy="$inittmp/.overlay/sepolicy.rules"
rm -rf "$module_policy"
echo "allow su * * *">"$module_policy"

# /data on Android-x86 is not always encrypted
for policy_dir in /data/adb/modules_update  /data/adb/modules /data/unencrypted/magisk; do
         for module in $(ls $policy_dir); do
              if ! [ -f "$policy_dir/$module/disable" ] && [ -f "$policy_dir/$module/sepolicy.rule" ] && [ ! -f "$inittmp/policy_loaded/$module" ]; then
                  cat  "$policy_dir/$module/sepolicy.rule" >>"$module_policy" &&  debug_log "initrd-magisk: read sepolicy.rule from $policy_dir/$module/sepolicy.rule"
                  echo "" >>"$module_policy"
                  echo -n > "$inittmp/policy_loaded/$module"
              fi
          done
done

bind_policy(){
policy="$1"
umount -l "$1"
(
/magisk/magiskpolicy --load "$policy" --save "$inittmp/.overlay/policy" --magisk "allow * magisk_file lnk_file *" 2>>/tmp/magiskpolicy.txt && debug_log "magiskpolicy: inject magisk built-in rules"
/magisk/magiskpolicy --load "$inittmp/.overlay/policy" --save "$inittmp/.overlay/policy" --apply "$module_policy" 2>>/tmp/magiskpolicy.txt && debug_log "magiskpolicy: inject magisk modules sepolicy.rule"
) 2>>$SELOGFILE
mount --bind $inittmp/.overlay/policy "$policy" && debug_log "mnt_bind: $policy <- $inittmp/.overlay/policy"
}

umount -l /data

# bind mount modified sepolicy

rm -rf /tmp/magiskpolicy.txt
[ ! -z "$DEBUG" ] && {
    cp -af "$module_policy" /tmp/magiskpolicy.txt
    echo "
---------------------------------">>/tmp/magiskpolicy.txt
    }

if [ -f /android/system/vendor/etc/selinux/precompiled_sepolicy ]; then
  bind_policy /android/system/vendor/etc/selinux/precompiled_sepolicy
elif [ -f /android/sepolicy ]; then
  bind_policy /android/sepolicy
fi
umount -l $inittmp

#test magisk

ln -fs "./$magisk_name" "$MAGISKDIR/magisk"
"$MAGISKDIR/magisk" --daemon
if [ -z "$("$MAGISKDIR/magisk" -v)" ]; then
  echo_log "WARING: Failed to inject Magisk into system"
  revert_changes
else
  echo_log "Magisk version: $("$MAGISKDIR/magisk" -v) ($("$MAGISKDIR/magisk" -V))"
fi
"$MAGISKDIR/magisk" --stop
killall -9 magiskd

sleep 0.2
fi

) 2>>/tmp/initrd-magisk.log # END: inject magisk

( # after
get_src
gzip -f /tmp/initrd-magisk.log
gzip -f /tmp/magiskpolicy.txt
cp /tmp/log /tmp/ex_log
gzip -f /tmp/ex_log
if [ ! -z "$SOURCE_OS" ]; then
    mkdir "/mnt/$SOURCE_OS/logcat"
    [ -d "/mnt/$SOURCE_OS/logcat" ] && {
        cp /tmp/initrd-magisk.log.gz "/mnt/$SOURCE_OS/logcat/initrd-magisk.txt.gz"
        cp /tmp/magiskpolicy.txt.gz "/mnt/$SOURCE_OS/logcat/magiskpolicy.txt.gz"
        cp /tmp/ex_log.gz "/mnt/$SOURCE_OS/logcat/debug_log.txt.gz"
    }
fi
) )

