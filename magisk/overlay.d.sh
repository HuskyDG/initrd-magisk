mkdir /android/dev/overlay.d
mount --bind /overlay.d /android/dev/overlay.d
umount -l /overlay.d
OVERLAYDIR=/android/dev/overlay.d

replace(){
local TARGET="$1"
local DEST="$2"

if [ -d "$TARGET" ]; then
        [ -L "$DEST/$TARGET" ] && return 0
        for a in `ls "$TARGET"`; do
            ( replace "$TARGET/$a" "$DEST" ) &
        done
else
        case "$TARGET" in
            *.rc)
                # inject custom rc script
                debug_log "initrd-magisk: overlay.d: rc_script add $TARGET"
                echo -e "\n$(cat "$TARGET" | sed "s|\${MAGISKTMP}|$MAGISKTMP|g")" >>"$INITRC"
                ;;
            *)
                [ -L "$DEST/$TARGET" ] && return 0
                [ -e "$DEST/$TARGET" ] || return 0
                debug_log "initrd-magisk: overlay.d: replace $DEST/$TARGET"
                mount --bind "$TARGET" "$DEST/$TARGET"
                ;;
        esac
fi
}

cd "$OVERLAYDIR"

for item in `ls $OVERLAYDIR`; do
    case "$item" in
        "system")
            # ignore
            ;;
        "vendor")
            # ignore
            ;;
        "data")
            # ignore
            ;;
        "product")
            # ignore
            ;;
        "system_ext")
            # ignore
            ;;
         "init.rc")
            # ignore
            ;;
         "init")
            # ignore
            ;;
         "sepolicy")
            # ignore
            ;;
         "sbin")
            mkdir "/android/$MAGISKDIR/sbin"
            cp -af "$OVERLAYDIR/sbin/"* "/android/$MAGISKDIR/sbin"
            ;;
        *)
            # replace existing files in root directory
            replace "$item" "/android"
            ;;
    esac
done
