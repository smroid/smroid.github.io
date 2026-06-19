#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Current working directory is the destination Updater component.
# Run in background: systemctl restart kills this process, so we must not wait
# for it to return. Note that future versions of updater.rs won't be invoking
# restart.sh when updating itself.
sudo systemctl restart updater.service &
