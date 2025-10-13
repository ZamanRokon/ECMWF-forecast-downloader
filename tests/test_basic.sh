#!/bin/bash
# Basic test script for ECMWF downloader
# This tests if all required tools are installed

echo "🧪 Testing ECMWF Downloader Dependencies..."

# Test if commands are available
commands=("curl" "jq" "parallel" "cdo")

for cmd in "${commands[@]}"; do
    if command -v "$cmd" &> /dev/null; then
        echo "✅ $cmd is installed"
    else
        echo "❌ $cmd is NOT installed"
    fi
done

# Test if scripts exist
scripts=("scripts/ecmwf_ens_downloader.sh" "scripts/configs/settings.conf")

for script in "${scripts[@]}"; do
    if [ -f "$script" ]; then
        echo "✅ $script exists"
    else
        echo "❌ $script is missing"
    fi
done

echo "🧪 Basic test completed!"
