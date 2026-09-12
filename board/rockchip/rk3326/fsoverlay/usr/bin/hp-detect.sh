#!/bin/bash
#
# Headphone jack -> audio routing for rk3326.
#
# The jack line is claimed by the sound card (hp-det-gpio, with an IRQ), so it
# cannot be exported through /sys/class/gpio.  The previous version of this
# script tried, got no gpioNN directory, read an empty value every time and so
# never switched anything at all -- which is why the speaker was silent.  The
# multicodecs driver publishes the jack as an ALSA input device instead; watch
# that.
#
# Two things have to move on every change, and knulli-audio does both:
#
#   Playback Path        the route inside the rk817 (per board)
#   spk switch/hp switch the amp-enable GPIOs (spk-con-gpio / hp-con-gpio).
#                        Nothing else drives them: rockchip_multicodecs only
#                        powers them from a DAPM widget, and rk817_codec
#                        registers no widgets for a route to ever reach one.

POLL_INTERVAL=0.5

find_jack() {
    for d in /sys/class/input/event*; do
        [ -r "${d}/device/name" ] || continue
        case "$(cat "${d}/device/name")" in
            *Headset*|*Headphone*) echo "/dev/input/${d##*/}"; return 0 ;;
        esac
    done
    return 1
}

JACK=$(find_jack)
if [ -z "$JACK" ]; then
    echo "hp-detect: no headset jack input device; leaving audio routing alone"
    exit 0
fi
echo "hp-detect: watching $JACK"

switch_audio() {
    # knulli-audio owns the per-board route and amp-switch map.
    if [ "$1" = "1" ]; then
        echo "Headphone inserted"
        /usr/bin/knulli-audio set headphone >/dev/null 2>&1
    else
        echo "Headphone removed"
        /usr/bin/knulli-audio set speakers >/dev/null 2>&1
    fi
}

LAST_STATE=""
while true; do
    # evtest --query exits 10 when the switch is set, 0 when it is not.
    evtest --query "$JACK" EV_SW SW_HEADPHONE_INSERT >/dev/null 2>&1
    [ "$?" -eq 10 ] && STATE=1 || STATE=0

    if [ "$STATE" != "$LAST_STATE" ]; then
        LAST_STATE="$STATE"
        switch_audio "$STATE"
    fi
    sleep $POLL_INTERVAL
done
