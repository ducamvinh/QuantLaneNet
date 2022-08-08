#!/bin/bash

DIRNAME=$(pwd -P)

if ! [[ $DIRNAME =~ dma_ip_drivers\/XDMA\/linux-kernel$ ]] ; then
    echo -e "[ERROR] This script needs to be run in <path>/dma_ip_drivers/XDMA/linux-kernel"
    exit 1
fi

cd "$DIRNAME/xdma"

# Remove old install
echo -e "\n[INFO] Cleaning old install..."
[[ -n $(lsmod | grep xdma) ]] && rmmod xdma
make clean

# Install driver
echo -e "\n[INFO] Building kernel modules and install..."
make install

# Rebuild tools
echo -e "\n[INFO] Building tools..."
cd "$DIRNAME/tools"
make clean
make

# Load driver
echo -e "\n[INFO] Loading driver..."
cd "$DIRNAME/tests"
source ./load_driver.sh
