inittmp=/android/dev
mount -t tmpfs tmpfs $inittmp
mkdir -p $inittmp/.overlay/upper
mkdir -p $inittmp/.overlay/work

if mount -t tmpfs | grep -q " /android " || mount -t rootfs | grep -q " /android "; then
# rootfs, patch ramdisk
mount -o rw,remount /android
mkdir /android/magisk
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/magisk|g" /magisk/magisk.rc
cp -a /magisk/* /android/magisk
[ ! -f "/magisk/init.rc" ] && cat /init.rc >/magisk/init.rc
[ -f "/magisk/init.rc" ] && cat /magisk/init.rc >/init.rc
cat /magisk/magisk.rc >>/android/init.rc
else
sysblock="$(mount | grep " /android " | tail -1 | awk '{ print $1 }')"
mkdir /system_root
mount $sysblock /system_root
# prepare for second stage
chmod 750 $inittmp
mount -t overlay tmpfs -o lowerdir=/android/system/etc/init,upperdir=$inittmp/.overlay/upper,workdir=$inittmp/.overlay/work /android/system/etc/init
sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/overlay.sh
sed -i "s|MAGISK_FILES_BASE|/system/etc/init/magisk|g" /magisk/magisk.rc
cp -a /magisk $inittmp/.overlay/upper
cp /magisk/magisk.rc $inittmp/.overlay/upper/magisk.rc
fi
[ ! -d "/magisk/magiskpolicy" ] && ln -sf ./magiskinit /magisk/magiskpolicy

bind_policy(){
policy="$1"
/magisk/magiskpolicy --load "$policy" --save $inittmp/.overlay/policy --magisk "allow * magisk_file lnk_file *"
mount --bind $inittmp/.overlay/policy "$policy"
}


if [ -f /android/system/vendor/etc/selinux/precompiled_sepolicy ]; then
  bind_policy /android/system/vendor/etc/selinux/precompiled_sepolicy
elif [ -f /android/sepolicy ]; then
  bind_policy /android/sepolicy
fi
umount -l $inittmp
