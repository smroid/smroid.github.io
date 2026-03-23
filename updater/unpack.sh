#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Current working directory is the destination Updater component.
mkdir -p bin
mkdir -p data

# Extract cedar-updater binary.
gunzip -k -c cedar-updater.gz > bin/cedar-updater
chmod a+x bin/cedar-updater

# Extract/emplace data files.
cp public_key.pem data/public_key.pem

# Update updater.service with restart configuration (non-fatal if this fails).
echo "Updating updater.service systemd configuration..."
if sudo bash << 'UPDATEEOF'
SERVICE_FILE="/lib/systemd/system/updater.service"
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
    echo "updater.service updated and systemd reloaded"
else
    echo "Warning: failed to update updater.service, continuing anyway"
fi
