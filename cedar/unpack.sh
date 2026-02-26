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
    sudo nmcli con modify cedar-ap wifi-sec.proto rsn
    sudo nmcli con modify cedar-ap wifi-sec.pairwise ccmp
    sudo nmcli con modify cedar-ap -wifi-sec.group
    echo "WiFi access point configuration updated"
else
    echo "cedar-ap connection not found, skipping WiFi configuration update"
fi

echo "Unpack complete!"
