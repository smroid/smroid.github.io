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

# Commit the root filesystem's journal at the default 5 s, not Armbian's
# commit=120. Takes effect at the next boot.
# TODO: remove once the October 2026 Radxa zygote SD cards are used up.
echo "Updating root filesystem commit interval..."
if grep -q "commit=" /etc/fstab; then
    sudo sed -i -E 's/,commit=[0-9]+//' /etc/fstab
    echo "  removed commit= from /etc/fstab"
else
    echo "  already up to date, skipping"
fi

# Journal the root filesystem in ordered mode, not Armbian's writeback mode,
# in which a power cut can leave recently written files full of zeros. A
# default mount option, so safe to change while mounted; takes effect at the
# next boot.
# TODO: remove once the October 2026 Radxa zygote SD cards are used up.
echo "Updating root filesystem data mode..."
ROOT_DEV=$(findmnt -n -o SOURCE /)
if sudo dumpe2fs -h $ROOT_DEV 2>/dev/null | grep -q journal_data_writeback; then
    sudo tune2fs -o ^journal_data_writeback $ROOT_DEV > /dev/null
    echo "  cleared journal_data_writeback on $ROOT_DEV"
else
    echo "  already up to date, skipping"
fi

# Stop Armbian rewriting armbianEnv.txt at every boot: U-Boot reads it without
# replaying the filesystem's journal, so a power cut soon after a rewrite can
# leave the unit unable to boot. Takes effect at the next boot.
# TODO: remove once the October 2026 Radxa zygote SD cards are used up.
echo "Updating armbian-hardware-optimization..."
AHO=/usr/lib/armbian/armbian-hardware-optimization
if [ ! -f $AHO ]; then
    echo "  not found, skipping"
elif grep -qE "^\s*add_usb_storage_quirks &$" $AHO; then
    sudo sed -i -E 's/^(\s*)add_usb_storage_quirks &$/\1: # add_usb_storage_quirks: disabled for Hopper/' $AHO
    if grep -qE "^\s*add_usb_storage_quirks &$" $AHO; then
        echo "Warning: could not update $AHO, continuing anyway"
    else
        echo "  disabled its rewrite of armbianEnv.txt"
    fi
else
    echo "  already up to date, skipping"
fi
