#!/bin/bash
set -e  # Exit on any error.

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi


# Current working directory is the destination Cedar component.

sudo systemctl restart cedar.service
