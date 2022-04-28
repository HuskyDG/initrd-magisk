. /bin/utils.sh
. /bin/info.sh

detect_sdk_abi

echo "Architecture: $ABI - 64bit: $IS64BIT"

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

if [ "${checkrootfs%:*}" == "0" ]; then
echo "Android root directory is rootfs"
# rootfs, patch ramdisk
mount -o rw,remount /android
mkdir /android/magisk
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/magisk.rc
cp -a /magisk/* /android/magisk
[ ! -f "/magisk/init.rc" ] && cat /android/init.rc >/magisk/init.rc
[ -f "/magisk/init.rc" ] && cat /magisk/init.rc >/android/init.rc
cat /magisk/magisk.rc >>/android/init.rc
revert_changes(){
 cat /magisk/init.rc >/android/init.rc
 rm -rf /android/magisk
 umount -l /android/sepolicy
 umount -l /android/system/vendor/etc/selinux/precompiled_sepolicy
}
else
echo "Android root directory is system-as-root"
sysblock="$(mount | grep " /android " | tail -1 | awk '{ print $1 }')"
mkdir /android/dev/system_root
mount $sysblock /android/dev/system_root || mount -o ro $sysblock /android/dev/system_root
# prepare for second stage
chmod 750 $inittmp
umount -l /android/system/etc/init
mount -t overlay tmpfs -o lowerdir=/android/system/etc/init,upperdir=$inittmp/.overlay/upper,workdir=$inittmp/.overlay/work /android/system/etc/init


sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/magisk.rc
cp -a /magisk $inittmp/.overlay/upper
cp /magisk/magisk.rc $inittmp/.overlay/upper/magisk.rc

# fail back to magic mount if overlayfs is unavailable

if ! mount -t overlay | grep -q " /android/system/etc/init "; then
  mount -t tmpfs tmpfs -o mode=0755 /android/system/etc/init
  for file in $(ls /android/dev/system_root/system/etc/init); do
    (
        sfile="/android/dev/system_root/system/etc/init/$file"
        xfile="/android/system/etc/init/$file"
        if [ -L "$sfile" ]; then
            cp "$sfile" "$xfile"
        elif [ -d "$sfile" ]; then
            mkdir "$xfile"
            mount --bind "$sfile" "$xfile"
        else
            echo -n >"$xfile"
            mount --bind "$sfile" "$xfile"
        fi
     ) &
  done
  sleep 0.05
  umount -l /android/system/etc/init/magisk
  umount -l /android/system/etc/init/magisk.rc
  rm -rf /android/system/etc/init/magisk
  rm -rf /android/system/etc/init/magisk.rc
  mkdir /android/system/etc/init/magisk
  mount --bind $inittmp/.overlay/upper/magisk /android/system/etc/init/magisk
  echo -n >/android/system/etc/init/magisk.rc
  mount --bind $inittmp/.overlay/upper/magisk.rc /android/system/etc/init/magisk.rc
fi

revert_changes(){
 umount -l /android/system/etc/init
 umount -l /android/sepolicy
 umount -l /android/system/vendor/etc/selinux/precompiled_sepolicy
}


fi



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
                  cat  "$policy_dir/$module/sepolicy.rule" >>"$module_policy"
                  echo "" >>"$module_policy"
                  echo -n > "$inittmp/policy_loaded/$module"
              fi
          done
done

bind_policy(){
policy="$1"
umount -l "$1"
/magisk/magiskpolicy --load "$policy" --save "$inittmp/.overlay/policy" --magisk "allow * magisk_file lnk_file *"
/magisk/magiskpolicy --load "$inittmp/.overlay/policy" --save "$inittmp/.overlay/policy" --apply "$module_policy"
mount --bind $inittmp/.overlay/policy "$policy"
}

umount -l /data

# bind mount modified sepolicy

if [ -f /android/system/vendor/etc/selinux/precompiled_sepolicy ]; then
  bind_policy /android/system/vendor/etc/selinux/precompiled_sepolicy
elif [ -f /android/sepolicy ]; then
  bind_policy /android/sepolicy
fi
umount -l $inittmp

cp -af /magisk/magisk32 /sbin/magisk32
cp -af /magisk/magisk64 /sbin/magisk64
ln -fs "./$magisk_name" /sbin/magisk
/sbin/magisk --daemon
if [ -z "$(/sbin/magisk -v)" ]; then
  echo "[!] Failed to load Magisk"
  revert_changes
else
  echo "Magisk version: $(/sbin/magisk -v) ($(/sbin/magisk -V))"
fi
/sbin/magisk --stop
killall -9 magiskd
rm -rf /sbin/magisk /sbin/magisk32 /sbin/magisk64

sleep 0.2