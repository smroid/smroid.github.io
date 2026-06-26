#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Current working directory is the destination Cedar component.
echo "Creating directories..."
rm -rf bin data hopper-aim
mkdir -p bin
mkdir -p data
mkdir -p hopper-aim

# Extract hopper-server binary.
echo "Extracting hopper-server binary..."
gunzip -k -c hopper-server.gz > bin/hopper-server
[ -s bin/hopper-server ] || { echo "ERROR: bin/hopper-server is empty after extraction"; exit 1; }
file bin/hopper-server | grep -q "ELF" || { echo "ERROR: bin/hopper-server is not an ELF binary"; exit 1; }
# Set capabilities.
echo "Setting permissions and capabilities on hopper-server..."
chmod a+x bin/hopper-server
caps="cap_sys_time,cap_dac_override,cap_chown,cap_fowner,cap_net_bind_service+ep"
sudo setcap "$caps" bin/hopper-server

# Extract data files, and copy their signatures for run-time verification.
echo "Copying data files..."
cp default_database.npz default_database.npz.sig data

echo "Extracting merged_catalog.sqlite..."
gunzip -k -c merged_catalog.sqlite.gz > data/merged_catalog.sqlite
cp merged_catalog.sqlite.gz.sig data

echo "Copying mp_com.dat..."
cp mp_com.dat mp_com.dat.sig data

# Extract hopper_flutter subdirectory of hopper-aim.
echo "Extracting hopper_flutter..."
tar -xzf hopper_flutter.tar.gz -C hopper-aim

# Update WiFi access point configuration if it exists.
echo "Updating WiFi access point configuration..."
if sudo nmcli con show cedar-ap > /dev/null 2>&1; then
    echo "Found existing cedar-ap connection, updating settings..."
    sudo nmcli con modify cedar-ap wifi-sec.proto rsn wifi-sec.pairwise ccmp wifi-sec.group ""
    echo "WiFi access point configuration updated"
else
    echo "cedar-ap connection not found, skipping WiFi configuration update"
fi

# Update cedar.service with restart configuration (non-fatal if this fails).
echo "Updating cedar.service systemd configuration..."
if sudo bash << 'UPDATEEOF'
SERVICE_FILE="/lib/systemd/system/cedar.service"
TEMP_FILE=$(mktemp)

awk '
    /^(Restart|RestartSec|StartLimitInterval|StartLimitBurst)=/ { next }
    /^ExecStart=/ {
        print
        print "Restart=on-failure"
        print "RestartSec=5"
        print "StartLimitInterval=60"
        print "StartLimitBurst=3"
        next
    }
    { print }
' "$SERVICE_FILE" > "$TEMP_FILE"

mv "$TEMP_FILE" "$SERVICE_FILE"
UPDATEEOF
then
    sudo systemctl daemon-reload
    echo "cedar.service updated and systemd reloaded"
else
    echo "Warning: failed to update cedar.service, continuing anyway"
fi

# Update cedar-ap-power.service: set txpower to 14 and disable power save.
echo "Updating cedar-ap-power.service to disable WiFi power save..."
if sudo bash << 'POWERSAVEEOF'
AP_POWER_SERVICE="/etc/systemd/system/cedar-ap-power.service"
if [ ! -f "$AP_POWER_SERVICE" ]; then
    echo "cedar-ap-power.service not found, skipping"
    exit 0
fi
CHANGED=0
if ! grep -q "power_save off" "$AP_POWER_SERVICE"; then
    sed -i '/iwconfig wlan0 txpower/a ExecStart=/sbin/iw dev wlan0 set power_save off' "$AP_POWER_SERVICE"
    echo "WiFi power save disable added to cedar-ap-power.service"
    CHANGED=1
fi
if ! grep -q "txpower 14" "$AP_POWER_SERVICE"; then
    sed -i 's/iwconfig wlan0 txpower [0-9]*/iwconfig wlan0 txpower 14/' "$AP_POWER_SERVICE"
    echo "WiFi txpower updated to 14 in cedar-ap-power.service"
    CHANGED=1
fi
if [ $CHANGED -eq 0 ]; then
    echo "cedar-ap-power.service already correct, skipping"
fi
if [ $CHANGED -eq 1 ]; then
    systemctl daemon-reload
fi
POWERSAVEEOF
then
    echo "WiFi power save configuration updated"
else
    echo "Warning: failed to update WiFi power save setting, continuing anyway"
fi

# Enable IMX290/IMX462 High Conversion Gain mode via kernel module parameter.
echo "Enabling IMX290/IMX462 High Conversion Gain mode..."
if ! grep -qx "options imx290 hcg_mode=1" /etc/modprobe.d/imx290.conf 2>/dev/null; then
    sudo bash -c 'cat > /etc/modprobe.d/imx290.conf <<EOF
options imx290 hcg_mode=1
EOF'
    echo "  Written /etc/modprobe.d/imx290.conf"
else
    echo "  /etc/modprobe.d/imx290.conf already correct, skipping"
fi

# Update boot partition kernel to match installed kernel package.
# apt upgrade installs new kernels to /boot on the ext4 partition but the
# bootloader reads kernel8.img from the FAT partition at /boot/firmware.
# A reboot is required for a newly copied kernel to take effect.
# (Pi 5 / BCM2712 not covered.)
echo "Checking boot partition kernel..."
NEWEST_V8=$(ls /boot/vmlinuz-*rpi-v8 2>/dev/null | sort -V | tail -1)
if [ -n "$NEWEST_V8" ]; then
    if cmp -s "$NEWEST_V8" /boot/firmware/kernel8.img; then
        echo "  kernel8.img already matches $(basename $NEWEST_V8), skipping"
    else
        echo "  Installing $(basename $NEWEST_V8) as kernel8.img (effective on next reboot)"
        sudo cp "$NEWEST_V8" /boot/firmware/kernel8.img
    fi
else
    echo "  No rpi-v8 kernel found, skipping kernel8.img update"
fi

# Mask periodic timers that are useless/harmful on a headless embedded device.
echo "Masking unnecessary periodic timers..."
for timer in apt-daily.timer apt-daily-upgrade.timer man-db.timer dpkg-db-backup.timer e2scrub_all.timer; do
    if systemctl is-enabled "$timer" 2>/dev/null | grep -q "^masked$"; then
        echo "  $timer already masked, skipping"
    else
        sudo systemctl mask "$timer"
        echo "  Masked $timer"
    fi
done

echo "Unpack complete!"
