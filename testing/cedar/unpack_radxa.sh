#!/bin/bash
set -e  # Exit on any error

# Radxa ZERO 3 steps of unpack.sh, run by it from the destination Cedar
# component directory. Items here will typically patch prior Hopper
# installations.

# Install the current camera detection script.
# TODO: remove once the October 2026 Radxa zygote SD cards are used up: units
# made from them have a camera detection script and unit lacking these fixes.
echo "Updating camera detection script..."
DETECT_SCRIPT=/usr/local/bin/detect-camera.py
if cmp -s detect-camera-radxa.py $DETECT_SCRIPT; then
    echo "  already up to date, skipping"
else
    sudo install -m 755 detect-camera-radxa.py $DETECT_SCRIPT
    echo "  installed $DETECT_SCRIPT"
fi

# Camera detection runs once per boot: its unit stays active once run, so
# restarting cedar.service (which Wants= it) doesn't re-run it mid-session.
# TODO: remove once the October 2026 Radxa zygote SD cards are used up.
echo "Updating camera-detection.service..."
UNIT=/etc/systemd/system/camera-detection.service
if [ ! -f $UNIT ]; then
    echo "  not found, skipping"
elif grep -q "^RemainAfterExit=yes" $UNIT; then
    echo "  already up to date, skipping"
else
    sudo sed -i 's/^Type=oneshot$/Type=oneshot\nRemainAfterExit=yes/' $UNIT
    if grep -q "^RemainAfterExit=yes" $UNIT; then
        sudo systemctl daemon-reload
        echo "  added RemainAfterExit=yes"
    else
        echo "Warning: could not update $UNIT, continuing anyway"
    fi
fi
