#!/bin/bash
set -e  # Exit on any error

if [ "$#" -ne 0 ]; then
    echo "Usage: $0" >&2
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
[ -s bin/hopper-server ] || { echo "ERROR: bin/hopper-server is empty after extraction" >&2; exit 1; }
file bin/hopper-server | grep -q "ELF" || { echo "ERROR: bin/hopper-server is not an ELF binary" >&2; exit 1; }
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

echo "Extracting mp_com.sqlite..."
gunzip -k -c mp_com.sqlite.gz > data/mp_com.sqlite
cp mp_com.sqlite.gz.sig data

echo "Copying mp_com.dat..."
cp mp_com.dat mp_com.dat.sig data

# Extract hopper_flutter subdirectory of hopper-aim.
echo "Extracting hopper_flutter..."
tar -xzf hopper_flutter.tar.gz -C hopper-aim

# Install the NetworkManager dispatcher script that restricts the access point
# to plain WPA-PSK. It takes effect the next time the AP comes up (reboot or
# mode switch); the AP isn't restarted here, since the client applying this
# update is likely connected through it.
echo "Updating access point dispatcher script..."
DISPATCHER_SCRIPT=/etc/NetworkManager/dispatcher.d/50-cedar-ap-psk-only
if cmp -s 50-cedar-ap-psk-only $DISPATCHER_SCRIPT; then
    echo "  already up to date, skipping"
else
    sudo install -o root -g root -m 755 50-cedar-ap-psk-only $DISPATCHER_SCRIPT
    echo "  installed $DISPATCHER_SCRIPT"
fi

# Board-specific steps, in their own scripts (run with bash: the updater only
# makes unpack.sh executable).
model=$(tr -d '\0' < /proc/device-tree/model)
case "$model" in
    "Raspberry Pi"*)
        bash ./unpack_rpi.sh
        ;;
    "Radxa"*)
        bash ./unpack_radxa.sh
        ;;
    *)
        echo "ERROR: unknown board \"$model\"" >&2
        exit 1
        ;;
esac

echo "Unpack complete!"
