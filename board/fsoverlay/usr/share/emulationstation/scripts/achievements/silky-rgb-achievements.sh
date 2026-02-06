#!/bin/bash

# We only want to run the script if the board has RGB capability
if ! knulli-board-capability "rgb"; then
    exit 1
fi

KEY_LED_RETRO_ACHIEVEMENTS="led.retroachievements"
EFFECT_ON=1

# Check batocera.conf for retroachievement effect setting
LED_RETRO_ACHIEVEMENTS=$(knulli-settings-get $KEY_LED_RETRO_ACHIEVEMENTS)

# Let the LED daemon run the rainbow animation if retroachievement effect is turned on
if [ $LED_RETRO_ACHIEVEMENTS -eq $EFFECT_ON ]; then
    curl -X POST -d "cheevo" localhost:1235/animation >/dev/null 2>&1
fi

exit 0
