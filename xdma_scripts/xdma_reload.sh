#!/bin/bash

DIRNAME="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

cd "$DIRNAME/xdma"

# Remove old install
echo -e "\n[INFO] Cleaning old install..."
[[ -n $(lsmod | grep xdma) ]] && rmmod -v xdma
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

