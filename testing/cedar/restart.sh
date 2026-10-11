#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Current working directory is the destination Cedar component.

# --no-block: enqueue the restart with systemd and return immediately,
# so the updater's gRPC handler can reply before cedar comes back up.
# Waiting for the full restart (~20s on Pi Zero 2 W) holds the
# finishComponentUpdate response open long enough for the client to time out.
sudo systemctl restart --no-block cedar.service
