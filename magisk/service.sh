SCRIPT="$0"
MAGISKTMP=$(magisk --path) || MAGISKTMP=/sbin
set -x
exec 2>>"$MAGISKTMP/emu/record_logs.txt"
inode_data1=$(ls -id "$MAGISKTMP/.magisk/mirror/data/adb/modules" | awk '{ print $1 }')
inode_data2=$(ls -id "$MAGISKTMP/.magisk/modules" | awk '{ print $1 }')
inode_data=$(ls -id "/data/adb/modules" | awk '{ print $1 }')

if [ "$inode_data2" != "$inode_data" ]; then
  if [ "$inode_data1" == "$inode_data" ]; then
    mount --bind "$MAGISKTMP/.magisk/mirror/data/adb/modules" "$MAGISKTMP/.magisk/modules"
  fi
fi