#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Check if pigz is available for parallel decompression.
if command -v pigz > /dev/null 2>&1; then
    GUNZIP="pigz -d -k -c"
    TAR="tar --use-compress-program=pigz -xf"
else
    GUNZIP="gunzip -k -c"
    TAR="tar -xzf"
fi

# Current working directory is the destination Cedar component.
mkdir -p bin
mkdir -p data
mkdir -p hopper-aim

# Extract hopper-server binary.
$GUNZIP hopper-server.gz > bin/hopper-server
# Set capabilities.
chmod a+x bin/hopper-server
caps="cap_sys_time,cap_dac_override,cap_chown,cap_fowner,cap_net_bind_service+ep"
sudo setcap "$caps" bin/hopper-server

# Extract data files.
cp default_database.npz data/default_database.npz
$GUNZIP merged_catalog.sqlite.gz > data/merged_catalog.sqlite
$GUNZIP mp_com.dat.gz > data/mp_com.dat

# Extract hopper_flutter subdirectory of hopper-aim.
$TAR hopper_flutter.tar.gz -C hopper-aim
