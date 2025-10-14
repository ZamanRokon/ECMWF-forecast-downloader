#!/bin/bash
# ============================================================
# ECMWF Open Data IFS HRES Downloader (Deterministic)
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
BASE_URL="https://storage.googleapis.com/ecmwf-open-data/${DATE}/${TIME}/ifs/0p25/oper"

# Directory structure
MAIN_DIR="../data/hres/${DATE}_${TIME}_${VARIABLE}"
INDEX_DIR="${MAIN_DIR}/index_files"
VAR_DIR="${MAIN_DIR}/${VARIABLE}_data"
TMP_DIR="${MAIN_DIR}/tmp"
OUT_DIR="${MAIN_DIR}"
LINK_FILE="${MAIN_DIR}/grib2_links_${DATE}_${TIME}.txt"

mkdir -p "$INDEX_DIR" "$VAR_DIR" "$TMP_DIR" "$OUT_DIR"

echo "============================================================"
echo " ECMWF Open Data IFS HRES Downloader"
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
  url="${BASE_URL}/${DATE}000000-${step}h-oper-fc.index";
  out="${INDEX_DIR}/${DATE}000000-${step}h-oper-fc.index";
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
  INDEX_FILE="${INDEX_DIR}/${DATE}000000-${STEP}h-oper-fc.index"
  if [ -s "$INDEX_FILE" ]; then
    echo "${BASE_URL}/${DATE}000000-${STEP}h-oper-fc.grib2" >> "$LINK_FILE"
  fi
done
echo "📄 GRIB2 links saved in: $LINK_FILE"
echo

# ============================================================
# STEP 3: Collect valid variable records
# ============================================================
echo "🔍 Gathering ${VARIABLE} records..."

VALID_FILES=$(find "$INDEX_DIR" -type f -name "*.index" -exec grep -l '"param"' {} +)
if [ -z "$VALID_FILES" ]; then
  echo "❌ No valid index files found. Aborting."
  exit 1
fi

cat $VALID_FILES | grep "\"param\": \"${VARIABLE}\"" > "${TMP_DIR}/${VARIABLE}_records_all_lines.json"

echo "[" > "${TMP_DIR}/${VARIABLE}_records_all.json"
sed '$!s/$/,/' "${TMP_DIR}/${VARIABLE}_records_all_lines.json" >> "${TMP_DIR}/${VARIABLE}_records_all.json"
echo "]" >> "${TMP_DIR}/${VARIABLE}_records_all.json"

TOTAL=$(jq length "${TMP_DIR}/${VARIABLE}_records_all.json")
echo "✅ Found $TOTAL ${VARIABLE} records across all indices"
echo

# ============================================================
# STEP 4: Extract variable records
# ============================================================
echo "🚀 Extracting ${VARIABLE} GRIB slices..."
export BASE_URL TMP_DIR VAR_DIR DATE VARIABLE

jq -c '.[]' "${TMP_DIR}/${VARIABLE}_records_all.json" | \
  parallel -j "${CORES}" --bar '
    LINE={};
    STEP=$(echo "$LINE" | jq -r ".step")
    OFFSET=$(echo "$LINE" | jq -r "._offset")
    LENGTH=$(echo "$LINE" | jq -r "._length")
    END=$((OFFSET + LENGTH - 1))

    mkdir -p "${VAR_DIR}"
    OUT="${VAR_DIR}/${VARIABLE}_${STEP}h.grib2"
    GRIB_URL="${BASE_URL}/${DATE}000000-${STEP}h-oper-fc.grib2"

    if [ -s "$OUT" ]; then
      echo "⏩ Skipping ${STEP}h (already exists)"
      exit 0
    fi

    echo "⬇️  Downloading ${VARIABLE} step ${STEP}h"
    if curl -s -r ${OFFSET}-${END} -o "$OUT" "$GRIB_URL"; then
      echo "✅ ${STEP}h"
    else
      echo "❌ Failed ${STEP}h"
      rm -f "$OUT"
    fi
'

echo "✅ All ${VARIABLE} GRIB slices extracted!"
echo

# ============================================================
# STEP 5: Merge timesteps + clip (single deterministic run)
# ============================================================
echo "🌀 Merging & clipping ${VARIABLE} ..."
export VAR_DIR OUT_DIR DATE TIME VARIABLE

FILES=$(find "${VAR_DIR}" -type f -name "*.grib2" | sort -V)
OUT="${OUT_DIR}/${DATE}_${TIME}_${VARIABLE}.nc"
TMP="${OUT_DIR}/tmp_${VARIABLE}.nc"

if [ -n "$FILES" ]; then
  if cdo -O -f nc4 -b F32 -mergetime $FILES "$TMP" 2>/dev/null; then
    if cdo -O sellonlatbox,65,110,5,40 "$TMP" "$OUT" 2>/dev/null; then
      rm -f "$TMP"
      echo "✅ Merged and clipped → $OUT"
    else
      echo "❌ Clipping failed"
      rm -f "$TMP"
    fi
  else
    echo "❌ Merge failed"
  fi
else
  echo "⚠️ No GRIB files found!"
fi

# Cleanup
rm -r "$INDEX_DIR" "$VAR_DIR" "$TMP_DIR"
rm -f "$LINK_FILE"

echo
echo "============================================================"
echo "🎯 Final NetCDF file:"
echo " ${OUT}"
echo "============================================================"
