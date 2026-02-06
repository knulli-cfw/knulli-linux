#!/bin/sh

EMU="yabasanshiro"
[ "$3" = "$EMU" ] || exit 0

STEP=5

get_vol() {
    knulli-audio getSystemVolume 2>/dev/null
}

set_vol() {
    knulli-audio setSystemVolume "$1" >/dev/null 2>&1
}

set_boost() {
    /usr/bin/knulli-settings-set audio.volume.boost "$1" >/dev/null 2>&1
}

round_to_step() {
    v="$1"
    step="$2"
    printf "%s" $(( ((v + (step / 2)) / step) * step ))
}

clamp_0_max() {
    v="$1"
    max="$2"
    [ "$v" -lt 0 ] && v=0
    [ "$v" -gt "$max" ] && v="$max"
    printf "%s" "$v"
}

case "$1" in
    gameStart)
        vol="$(get_vol)"
        set_boost 200

        new_vol=$(( vol * 2 ))
        new_vol="$(round_to_step "$new_vol" "$STEP")"
        new_vol="$(clamp_0_max "$new_vol" 200)"

        set_vol "$new_vol"
        ;;

    gameStop)
        vol="$(get_vol)"
        new_vol=$(( (vol + 1) / 2 ))
        new_vol="$(round_to_step "$new_vol" "$STEP")"
        new_vol="$(clamp_0_max "$new_vol" 100)"

        set_vol "$new_vol"
        set_boost 100
        ;;

    *)
        exit 0
        ;;
esac

exit 0
