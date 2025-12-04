#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0"
    exit 1
fi

# Current working directory is the destination Cedar component.
mkdir -p bin
mkdir -p data
mkdir -p hopper-aim

# Extract hopper-server binary.
gunzip -k -c hopper-server.gz > bin/hopper-server
# Set capabilities.
chmod a+x bin/hopper-server
caps="cap_sys_time,cap_dac_override,cap_chown,cap_fowner,cap_net_bind_service+ep"
sudo setcap "$caps" bin/hopper-server

# Extract data files, and copy their signatures for run-time verification.
cp default_database.npz default_database.npz.sig data

gunzip -k -c merged_catalog.sqlite.gz > data/merged_catalog.sqlite
cp merged_catalog.sqlite.gz.sig data

cp mp_com.dat mp_com.dat.sig data

# Extract hopper_flutter subdirectory of hopper-aim.
tar -xzf hopper_flutter.tar.gz -C hopper-aim
