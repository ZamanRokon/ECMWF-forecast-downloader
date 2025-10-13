#!/bin/bash
# ECMWF Forecast Downloader - Main Runner Script
# Easy-to-use interface for the downloader

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <DATE> <TIME> <VARIABLE>"
    echo "  DATE: YYYYMMDD (e.g., 20251012)"
    echo "  TIME: 00z, 06z, 12z, 18z"
    echo "  VARIABLE: tp, 2t, msl, 10u, 10v, etc."
    echo ""
    echo "Examples:"
    echo "  $0 20251012 00z tp    # Total precipitation"
    echo "  $0 20251012 12z 2t    # 2m temperature"
    echo "  $0 20251012 18z msl   # Mean sea level pressure"
}

# Check arguments
if [ "$#" -ne 3 ]; then
    usage
    exit 1
fi

DATE=$1
TIME=$2
VAR=$3

# Validate date format
if ! [[ $DATE =~ ^[0-9]{8}$ ]]; then
    echo -e "${RED}❌ Error: Date must be in YYYYMMDD format${NC}"
    exit 1
fi

# Validate time
if ! [[ $TIME =~ ^(00z|06z|12z|18z)$ ]]; then
    echo -e "${RED}❌ Error: Time must be one of: 00z, 06z, 12z, 18z${NC}"
    exit 1
fi

# Validate variable (basic check)
SUPPORTED_VARS="tp 2t msl 10u 10v tcc sp 2d"
if [[ ! " $SUPPORTED_VARS " =~ " $VAR " ]]; then
    echo -e "${YELLOW}⚠️ Warning: Variable $VAR may not be supported${NC}"
    echo -e "${YELLOW}Supported variables: $SUPPORTED_VARS${NC}"
    read -p "Continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo -e "${GREEN}🚀 Starting ECMWF Ensemble Download...${NC}"
echo "📅 Date: $DATE"
echo "⏰ Time: $TIME"
echo "📊 Variable: $VAR"
echo "======================================"

# Run the main downloader script
bash scripts/ecmwf_ens_downloader.sh "$DATE" "$TIME" "$VAR"

# Check if successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Download completed successfully!${NC}"
    echo -e "${GREEN}📁 Output: data/ens/${DATE}_${TIME}_${VAR}/${NC}"
else
    echo -e "${RED}❌ Download failed! Check logs for details.${NC}"
    exit 1
fi
