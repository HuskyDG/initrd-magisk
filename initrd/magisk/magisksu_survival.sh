MAGISKTMP=${{MAGISKTMP}}
export PATH="$MAGISKTMP:$PATH"

# prevent /system/bin/su from removing

if mount | grep -q " /system/bin " && [ -f "/system/bin/magisk" ]; then
    [ -L /system/bin/su ] || umount -l /system/bin/su
    rm -rf /system/bin/su
    ln -fs ./magisk /system/bin/su
    mount -o ro,remount /system/bin
fi

# mount all drives
( for blkdisk in /dev/block/[hmnsvx][dmrv][0-9a-z]*; do
        if [ -b "$blkdisk" ]; then
            BLOCKNAME="${blkdisk##*/}"
            CHECKBLOCK="$(mountpoint -x "/dev/block/$BLOCKNAME")"
            blk_major="${CHECKBLOCK%:*}"
            blk_minor="${CHECKBLOCK: ${#blk_major}+1}"
            mknod -m 666 "$MAGISKTMP/.magisk/block/$BLOCKNAME" b "$blk_major" "$blk_minor"
            mkdir -p "$MAGISKTMP/.magisk/mirror/$BLOCKNAME"
            mount.fuse "$MAGISKTMP/.magisk/block/$BLOCKNAME" "$MAGISKTMP/.magisk/mirror/$BLOCKNAME"
            mountpoint -q "$MAGISKTMP/.magisk/mirror/$BLOCKNAME" || mount "$MAGISKTMP/.magisk/block/$BLOCKNAME" "$MAGISKTMP/.magisk/mirror/$BLOCKNAME"
            mountpoint -q "$MAGISKTMP/.magisk/mirror/$BLOCKNAME" || mount -o ro "$MAGISKTMP/.magisk/block/$BLOCKNAME" "$MAGISKTMP/.magisk/mirror/$BLOCKNAME"
            mount -o ro,remount "$MAGISKTMP/.magisk/mirror/$BLOCKNAME"
        fi
done
# remove empty directory
rmdir $MAGISKTMP/.magisk/mirror/* 
) &