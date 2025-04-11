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
