#!/bin/bash

BOARD=$(cat /boot/boot/knulli.board)

DS_PATH=/usr/share/drastic_aarch64

# Store current display (top or bottom)
DSI_OUT=$(cat /var/run/drmConn)

cd $DS_PATH

# The RG-DS needs the bottom display to be active for drastic dual screen to work
if [ "$BOARD" = "rg-ds" ] || [ "$BOARD" = "rg-ds-plus" ]; then
    knulli-resolution setOutput 1
fi

LD_PRELOAD=$DS_PATH/libhookdrastic.so $DS_PATH/drastic "$1"

if [ "$BOARD" = "rg-ds" ] || [ "$BOARD" = "rg-ds-plus" ]; then
# Restore display
    knulli-resolution setOutput $DS_PATH
fi

