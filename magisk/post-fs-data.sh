SCRIPT="$0"
MAGISKTMP=$(magisk --path) || MAGISKTMP=/sbin
set -x
exec 2>>"$MAGISKTMP/emu/record_logs.txt"
( #fix mount data mirror
function cmdline() { 
	awk -F"${1}=" '{print $2}' < /proc/cmdline | cut -d' ' -f1 2> /dev/null
}

SRC="$(cmdline SRC)"
BIPATH="$(cmdline BOOT_IMAGE)"
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
fi )