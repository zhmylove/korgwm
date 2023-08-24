#!/bin/sh
# made by: KorG
# vim: cc=119 et sw=4 ts=4 :

# Saver plugin for XSecureLock(1)
# Path to video file is passed via XSECURELOCK_LIST_VIDEOS_COMMAND

# Align time for saver_multiplex
perl -MTime::HiRes=time,sleep -le 'sleep(int(time / 3 + 1) * 3 - time)'

exec mpv --no-input-terminal \
    --really-quiet \
    --no-stop-screensaver \
    --wid="${XSCREENSAVER_WINDOW}" \
    --no-audio \
    --loop-file=inf \
    "${XSECURELOCK_LIST_VIDEOS_COMMAND}"
