#!/bin/bash
# ============================================================
# ECMWF Open Data IFS HRES Downloader
# ============================================================

set -euo pipefail

# --- Check arguments ---
if [ "$#" -lt 3 ]; then
  echo "❌ Usage: bash $0 <YYYYMMDD> <TIME> <VAR1> [VAR2 VAR3 ...]"
  echo "   Example: bash $0 20251019 00z tp 2t msl"
  exit 1
fi

DATE="$1"
TIME="$2"
shift 2  # remaining are variables
VARIABLES=("$@")
CORES=$(nproc)
BASE_URL="https://storage.googleapis.com/ecmwf-open-data/${DATE}/${TIME}/ifs/0p25/oper"

# --- Directories ---
MAIN_DIR="../data/hres/${DATE}_${TIME}"
INDEX_DIR="${MAIN_DIR}/index_files"
TMP_DIR="${MAIN_DIR}/tmp"
OUT_DIR="${MAIN_DIR}"

mkdir -p "$INDEX_DIR" "$TMP_DIR" "$OUT_DIR"

echo "============================================================"
echo " ECMWF Open Data IFS HRES Downloader (Multi-variable)"
echo " DATE: ${DATE} | TIME: ${TIME}"
echo " VARIABLES: ${VARIABLES[*]}"
echo " Using ${CORES} CPU cores"
echo "============================================================"

# ============================================================
# STEP 1: Download index files once
# ============================================================
echo "📥 Downloading index files..."
export BASE_URL DATE INDEX_DIR TIME
seq 0 6 360 | parallel -j "${CORES}" --bar '
  step={};
  url="${BASE_URL}/${DATE}000000-${step}h-oper-fc.index";
  out="${INDEX_DIR}/${DATE}000000-${step}h-oper-fc.index";
  if curl -s -f -L -o "$out" "$url"; then
    grep -q "\"param\"" "$out" && echo "✅ ${step}h" || { echo "⚠️ Invalid ${step}h"; rm -f "$out"; }
  else
    echo "❌ Failed ${step}h"
    rm -f "$out"
  fi
'
echo "✅ Index files ready."
echo

# ============================================================
# STEP 2: Extract each variable
# ============================================================
for VARIABLE in "${VARIABLES[@]}"; do
  echo "============================================================"
  echo "🔍 Processing variable: ${VARIABLE}"
  echo "============================================================"

  VAR_DIR="${MAIN_DIR}/${VARIABLE}_data"
  LINK_FILE="${MAIN_DIR}/grib2_links_${VARIABLE}.txt"
  mkdir -p "$VAR_DIR"

  echo "🔗 Building GRIB2 links for ${VARIABLE}..."
  > "$LINK_FILE"
  for STEP in $(seq 0 6 360); do
    INDEX_FILE="${INDEX_DIR}/${DATE}000000-${STEP}h-oper-fc.index"
    [ -s "$INDEX_FILE" ] && echo "${BASE_URL}/${DATE}000000-${STEP}h-oper-fc.grib2" >> "$LINK_FILE"
  done

  VALID_FILES=$(find "$INDEX_DIR" -type f -name "*.index" -exec grep -l '"param"' {} +)
  cat $VALID_FILES | grep "\"param\": \"${VARIABLE}\"" > "${TMP_DIR}/${VARIABLE}_records_all_lines.json"

  echo "[" > "${TMP_DIR}/${VARIABLE}_records_all.json"
  sed '$!s/$/,/' "${TMP_DIR}/${VARIABLE}_records_all_lines.json" >> "${TMP_DIR}/${VARIABLE}_records_all.json"
  echo "]" >> "${TMP_DIR}/${VARIABLE}_records_all.json"

  TOTAL=$(jq length "${TMP_DIR}/${VARIABLE}_records_all.json")
  echo "✅ Found $TOTAL ${VARIABLE} records."
  echo

  echo "🚀 Extracting ${VARIABLE} slices..."
  export BASE_URL TMP_DIR VAR_DIR DATE VARIABLE TIME
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

      if [ -z "$GRIB_URL" ]; then
        echo "❌ ERROR: Empty GRIB_URL for step ${STEP}"
        exit 1
      fi

      if [ -s "$OUT" ]; then
        echo "⏩ Skipping ${STEP}h (already exists)"
        exit 0
      fi

      echo "⬇️  Downloading ${VARIABLE} step ${STEP}h from ${GRIB_URL}"
      if curl -s -r ${OFFSET}-${END} -o "$OUT" "$GRIB_URL"; then
        echo "✅ ${STEP}h"
      else
        echo "❌ Failed ${STEP}h"
        rm -f "$OUT"
      fi
  '

  echo "✅ Extraction complete for ${VARIABLE}"
  echo
done

# ============================================================
# STEP 3: Merge timesteps per variable, then combine all vars
# ============================================================
echo "============================================================"
echo "🌀 Merging variables into single NetCDF..."
echo "============================================================"

VAR_STRING="${VARIABLES[*]}"
export VAR_STRING MAIN_DIR OUT_DIR DATE TIME

TMP_MAIN="${OUT_DIR}/tmp_allvars.nc"
OUT="${OUT_DIR}/${DATE}_${TIME}_HRES.nc"

FILE_LIST=""
for VAR in $VAR_STRING; do
  VAR_PATH="${MAIN_DIR}/${VAR}_data"
  FILES=$(find "$VAR_PATH" -type f -name "*.grib2" | sort -V 2>/dev/null)
  if [ -n "$FILES" ]; then
    TMPVAR="${OUT_DIR}/tmp_${VAR}.nc"
    echo "🧩 Merging $VAR ..."
    cdo -O -f nc4 -b F32 -mergetime $FILES "$TMPVAR" 2>/dev/null || continue
    FILE_LIST="$FILE_LIST $TMPVAR"
  fi
done

if [ -n "$FILE_LIST" ]; then
  echo "🔗 Combining all variables..."
  cdo -O merge $FILE_LIST "$TMP_MAIN" 2>/dev/null
  cdo -O sellonlatbox,65,110,5,40 "$TMP_MAIN" "$OUT" 2>/dev/null
  rm -f $FILE_LIST "$TMP_MAIN"
  echo "✅ Created final merged file → $OUT"
else
  echo "⚠️ No valid data to merge!"
fi

# ============================================================
# STEP 4: Cleanup (keep only final .nc)
# ============================================================
echo
echo "🧹 Cleaning temporary folders and files..."
for VAR in "${VARIABLES[@]}"; do
  rm -rf "${MAIN_DIR}/${VAR}_data" "${MAIN_DIR}/grib2_links_${VAR}.txt"
done

rm -rf "$INDEX_DIR" "$TMP_DIR"
find "$OUT_DIR" -type f -name "tmp_*" -delete 2>/dev/null || true

echo
echo "============================================================"
echo "🎯 Final HRES NetCDF file:"
echo "📂 Location: ${OUT_DIR}"
echo "📄 File: ${OUT}"
echo "============================================================"
