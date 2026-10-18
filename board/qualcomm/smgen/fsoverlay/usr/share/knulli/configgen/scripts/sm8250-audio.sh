#!/bin/sh

case "$1" in
    gameStart|gameStop)
        sm8250-audio-resync
        ;;
    *)
        ;;
esac

exit 0
