#!/bin/bash
# ============================================================
# ECMWF Open Data IFS ENS Downloader
# ============================================================

set -euo pipefail

# Check arguments
if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
  echo "❌ Usage: bash $0 <YYYYMMDD> <TIME> <VARIABLE>"
  echo "   TIME: 00z, 06z, 12z, 18z"
  echo "   VARIABLE: tp, 2t, msl, 10u, 10v, etc."
  exit 1
fi

DATE="$1"
TIME="$2"
VARIABLE="$3"
CORES=$(nproc)
BASE_URL="https://storage.googleapis.com/ecmwf-open-data/${DATE}/${TIME}/ifs/0p25/enfo"

# Directory structure based on your main folder
MAIN_DIR="../data/ens/${DATE}_${TIME}_${VARIABLE}"
INDEX_DIR="${MAIN_DIR}/index_files"
VAR_DIR="${MAIN_DIR}/${VARIABLE}_data"
TMP_DIR="${MAIN_DIR}/tmp"
OUT_DIR="${MAIN_DIR}"
LINK_FILE="${MAIN_DIR}/grib2_links_${DATE}_${TIME}.txt"

mkdir -p "$INDEX_DIR" "$VAR_DIR" "$TMP_DIR" "$OUT_DIR"

echo "============================================================"
echo " ECMWF Open Data IFS ENS Downloader"
echo " DATE: ${DATE} | TIME: ${TIME} | VARIABLE: ${VARIABLE}"
echo " Using ${CORES} CPU cores"
echo "============================================================"

# ============================================================
# STEP 1: Parallel index download
# ============================================================
echo "📥 Downloading all index files..."
export BASE_URL DATE INDEX_DIR TIME
seq 0 6 360 | parallel -j "${CORES}" --bar '
  step={};
  url="${BASE_URL}/${DATE}000000-${step}h-enfo-ef.index";
  out="${INDEX_DIR}/${DATE}000000-${step}h-enfo-ef.index";
  if curl -s -f -L -o "$out" "$url"; then
    if grep -q "\"param\"" "$out" 2>/dev/null; then
      echo "✅ ${step}h"
    else
      echo "⚠️ Invalid (non-JSON) file for step ${step}h"
      rm -f "$out"
    fi
  else
    echo "❌ Failed to download step ${step}h"
    rm -f "$out"
  fi
'

echo "✅ Index download complete!"
echo

# ============================================================
# STEP 2: Create GRIB2 links file
# ============================================================
echo "🔗 Creating GRIB2 links list..."
> "$LINK_FILE"
for STEP in $(seq 0 6 360); do
  INDEX_FILE="${INDEX_DIR}/${DATE}000000-${STEP}h-enfo-ef.index"
  if [ -s "$INDEX_FILE" ]; then
    echo "${BASE_URL}/${DATE}000000-${STEP}h-enfo-ef.grib2" >> "$LINK_FILE"
  fi
done
echo "📄 GRIB2 links saved in: $LINK_FILE"
echo

# ============================================================
# STEP 3: Collect all valid variable records (line-based JSON fix)
# ============================================================
echo "🔍 Gathering ${VARIABLE} records (line-based parsing)..."

VALID_FILES=$(find "$INDEX_DIR" -type f -name "*.index" -exec grep -l '"param"' {} +)
if [ -z "$VALID_FILES" ]; then
  echo "❌ No valid index files found. Aborting."
  exit 1
fi

# Each line in .index is an independent JSON object — concatenate and filter
cat $VALID_FILES | grep "\"param\": \"${VARIABLE}\"" > "${TMP_DIR}/${VARIABLE}_records_all_lines.json"

# Wrap them into a proper JSON array for jq use
echo "[" > "${TMP_DIR}/${VARIABLE}_records_all.json"
sed '$!s/$/,/' "${TMP_DIR}/${VARIABLE}_records_all_lines.json" >> "${TMP_DIR}/${VARIABLE}_records_all.json"
echo "]" >> "${TMP_DIR}/${VARIABLE}_records_all.json"

TOTAL=$(jq length "${TMP_DIR}/${VARIABLE}_records_all.json")
echo "✅ Found $TOTAL ${VARIABLE} records across all indices"
echo

# ============================================================
# STEP 4: Parallel GRIB extraction (fast + smart skip)
# ============================================================
echo "🚀 Extracting ${VARIABLE} slices in parallel..."
export BASE_URL TMP_DIR VAR_DIR DATE VARIABLE

jq -c '.[]' "${TMP_DIR}/${VARIABLE}_records_all.json" | \
  parallel -j "${CORES}" --bar '
    LINE={};
    STEP=$(echo "$LINE" | jq -r ".step")
    ENS_RAW=$(echo "$LINE" | jq -r ".number")

    # Handle control forecast (missing number)
    if [ "$ENS_RAW" == "null" ] || [ -z "$ENS_RAW" ]; then
      ENS_RAW=0
    fi

    # Zero-pad ensemble number to 2 digits
    ENS=$(printf "%02d" "$ENS_RAW")

    OFFSET=$(echo "$LINE" | jq -r "._offset")
    LENGTH=$(echo "$LINE" | jq -r "._length")
    END=$((OFFSET + LENGTH - 1))

    mkdir -p "${VAR_DIR}/EN${ENS}"
    OUT="${VAR_DIR}/EN${ENS}/${VARIABLE}_${STEP}h.grib2"
    GRIB_URL="${BASE_URL}/${DATE}000000-${STEP}h-enfo-ef.grib2"

    # Skip if file already exists and not empty
    if [ -s "$OUT" ]; then
      echo "⏩ Skipping EN${ENS} step ${STEP}h (already exists)"
      exit 0
    fi

    echo "⬇️  Downloading EN${ENS} step ${STEP}h"
    if curl -s -r ${OFFSET}-${END} -o "$OUT" "$GRIB_URL"; then
      echo "✅ EN${ENS} step ${STEP}h"
    else
      echo "❌ Failed EN${ENS} step ${STEP}h"
      rm -f "$OUT"
    fi
'

echo "✅ All ${VARIABLE} ensemble GRIBs extracted (skipped existing files)!"
echo

# ============================================================
# STEP 5: Merge timesteps ensemble-wise + clip
# ============================================================
echo "🌀 Merging & clipping per ensemble..."
export VAR_DIR OUT_DIR DATE VARIABLE

parallel -j "${CORES}" --bar '
  ENS={};
  FILES=$(find "${VAR_DIR}/EN${ENS}" -type f -name "*.grib2" | sort -V)
  if [ -n "$FILES" ]; then
    TMP="${OUT_DIR}/tmp_EN${ENS}.nc"
    OUT="${OUT_DIR}/${DATE}_${TIME}_${VARIABLE}_EN${ENS}.nc"

    # Skip merge if already exists
    if [ -s "$OUT" ]; then
      echo "⏩ Skipping EN${ENS} (already merged)"
      exit 0
    fi

    echo "🧩 Merging EN${ENS} ..."
    if cdo -O -f nc4 -b F32 -mergetime $FILES "$TMP" 2>/dev/null; then
      if cdo -O sellonlatbox,65,110,5,40 "$TMP" "$OUT" 2>/dev/null; then
        rm -f "$TMP"
        echo "✅ EN${ENS}"
      else
        echo "❌ Clipping failed for EN${ENS}"
        rm -f "$TMP"
      fi
    else
      echo "❌ Merge failed for EN${ENS}"
      rm -f "$TMP"
    fi
  else
    echo "⚠️ No files found for EN${ENS}"
  fi
' ::: $(seq -w 0 50)

rm -r "$INDEX_DIR" "$VAR_DIR" "$TMP_DIR" "$OUT_DIR"
rm -f "$LINK_FILE"

echo
echo "============================================================"
echo "🎯 Final ensemble NetCDF files at: $OUT_DIR"
echo " Files: ${DATE}_${TIME}_${VARIABLE}_EN[00-50].nc"
echo "============================================================"
