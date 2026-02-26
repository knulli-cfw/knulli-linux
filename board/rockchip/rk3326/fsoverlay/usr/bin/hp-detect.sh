#!/bin/bash

GPIO=86
GPIO_PATH="/sys/class/gpio/gpio${GPIO}"
POLL_INTERVAL=0.5

# Export GPIO if needed
if [ ! -d "$GPIO_PATH" ]; then
    echo $GPIO > /sys/class/gpio/export
    echo in > "${GPIO_PATH}/direction"
    # Enable edge detection if supported
    echo both > "${GPIO_PATH}/edge" 2>/dev/null
fi

LAST_STATE=""

switch_audio() {
    if [ "$1" = "1" ]; then
        echo "Headphone inserted"
        amixer -c 0 set 'Playback Path' 'HP'
    else
        echo "Headphone removed"
        amixer -c 0 set 'Playback Path' 'SPK'
    fi
}

echo "Using polling on GPIO $GPIO (interval: ${POLL_INTERVAL}s)"
while true; do
    STATE=$(cat "${GPIO_PATH}/value")
    if [ "$STATE" != "$LAST_STATE" ]; then
        LAST_STATE="$STATE"
        switch_audio "$STATE"
    fi
    sleep $POLL_INTERVAL
done

