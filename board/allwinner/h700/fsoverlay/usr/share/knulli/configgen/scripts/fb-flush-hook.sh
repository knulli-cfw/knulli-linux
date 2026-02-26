#!/bin/sh

if [ "$1" != "gameStart" ] && [ "$1" != "gameStop" ]; then
    exit 0
fi

fb-flush

exit 0
