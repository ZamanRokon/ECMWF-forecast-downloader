#!/bin/bash
# ============================================================
# ECMWF Open Data IFS ENS Downloader (Multi-variable)
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
shift 2  # shift to get remaining variables
VARIABLES=("$@")
CORES=$(nproc)
BASE_URL="https://storage.googleapis.com/ecmwf-open-data/${DATE}/${TIME}/ifs/0p25/enfo"

# --- Directory structure ---
MAIN_DIR="../data/ens/${DATE}_${TIME}"
INDEX_DIR="${MAIN_DIR}/index_files"
TMP_DIR="${MAIN_DIR}/tmp"
OUT_DIR="${MAIN_DIR}"

mkdir -p "$INDEX_DIR" "$TMP_DIR" "$OUT_DIR"

echo "============================================================"
echo " ECMWF Open Data IFS ENS Downloader (Multi-variable)"
echo " DATE: ${DATE} | TIME: ${TIME}"
echo " VARIABLES: ${VARIABLES[*]}"
echo " Using ${CORES} CPU cores"
echo "============================================================"

# ============================================================
# STEP 1: Download index files once
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
echo "✅ Index files ready!"
echo

# ============================================================
# STEP 2: Loop through each variable and extract
# ============================================================
for VARIABLE in "${VARIABLES[@]}"; do
  echo "============================================================"
  echo "🔍 Processing variable: ${VARIABLE}"
  echo "============================================================"

  VAR_DIR="${MAIN_DIR}/${VARIABLE}_data"
  LINK_FILE="${MAIN_DIR}/grib2_links_${VARIABLE}.txt"
  mkdir -p "$VAR_DIR"

  echo "🔗 Creating GRIB2 links for ${VARIABLE}..."
  > "$LINK_FILE"
  for STEP in $(seq 0 6 360); do
    INDEX_FILE="${INDEX_DIR}/${DATE}000000-${STEP}h-enfo-ef.index"
    if [ -s "$INDEX_FILE" ]; then
      echo "${BASE_URL}/${DATE}000000-${STEP}h-enfo-ef.grib2" >> "$LINK_FILE"
    fi
  done

  echo "📄 GRIB2 links ready."
  echo "🔍 Gathering ${VARIABLE} records..."

  VALID_FILES=$(find "$INDEX_DIR" -type f -name "*.index" -exec grep -l '"param"' {} +)
  cat $VALID_FILES | grep "\"param\": \"${VARIABLE}\"" > "${TMP_DIR}/${VARIABLE}_records_all_lines.json"

  echo "[" > "${TMP_DIR}/${VARIABLE}_records_all.json"
  sed '$!s/$/,/' "${TMP_DIR}/${VARIABLE}_records_all_lines.json" >> "${TMP_DIR}/${VARIABLE}_records_all.json"
  echo "]" >> "${TMP_DIR}/${VARIABLE}_records_all.json"

  TOTAL=$(jq length "${TMP_DIR}/${VARIABLE}_records_all.json")
  echo "✅ Found $TOTAL ${VARIABLE} records."
  echo

  echo "🚀 Extracting ${VARIABLE} ensemble slices in parallel..."
  export BASE_URL TMP_DIR VAR_DIR DATE VARIABLE
  jq -c '.[]' "${TMP_DIR}/${VARIABLE}_records_all.json" | \
    parallel -j "${CORES}" --bar '
      LINE={};
      STEP=$(echo "$LINE" | jq -r ".step")
      ENS_RAW=$(echo "$LINE" | jq -r ".number")
      if [ "$ENS_RAW" == "null" ] || [ -z "$ENS_RAW" ]; then ENS_RAW=0; fi
      ENS=$(printf "%02d" "$ENS_RAW")
      OFFSET=$(echo "$LINE" | jq -r "._offset")
      LENGTH=$(echo "$LINE" | jq -r "._length")
      END=$((OFFSET + LENGTH - 1))
      mkdir -p "${VAR_DIR}/EN${ENS}"
      OUT="${VAR_DIR}/EN${ENS}/${VARIABLE}_${STEP}h.grib2"
      GRIB_URL="${BASE_URL}/${DATE}000000-${STEP}h-enfo-ef.grib2"
      if [ -s "$OUT" ]; then exit 0; fi
      curl -s -r ${OFFSET}-${END} -o "$OUT" "$GRIB_URL"
    '

  echo "✅ Extraction complete for ${VARIABLE}"
  echo
done

# ============================================================
# STEP 3: Merge timesteps per ensemble and combine variables
# ============================================================
echo "============================================================"
echo "🌀 Merging all variables per ensemble..."
echo "============================================================"

# Export variable list as single space-separated string
VAR_STRING="${VARIABLES[*]}"
export VAR_STRING MAIN_DIR OUT_DIR DATE TIME

parallel -j "${CORES}" --bar '
  ENS={};
  TMP="${OUT_DIR}/tmp_EN${ENS}.nc"
  OUT="${OUT_DIR}/${DATE}_${TIME}_EN${ENS}.nc"

  FILE_LIST=""

  # Loop through each variable provided
  for VAR in $VAR_STRING; do
    VAR_PATH="${MAIN_DIR}/${VAR}_data/EN${ENS}"
    FILES=$(find "$VAR_PATH" -type f -name "*.grib2" | sort -V 2>/dev/null)
    if [ -n "$FILES" ]; then
      TMPVAR="${OUT_DIR}/tmp_${VAR}_EN${ENS}.nc"
      echo "🧩 Processing $VAR for EN${ENS}"
      cdo -O -f nc4 -b F32 -mergetime $FILES "$TMPVAR" 2>/dev/null || continue
      FILE_LIST="$FILE_LIST $TMPVAR"
    fi
  done

  if [ -n "$FILE_LIST" ]; then
    echo "🔗 Combining variables for EN${ENS}"
    cdo -O merge $FILE_LIST "$TMP" 2>/dev/null
    cdo -O sellonlatbox,65,110,5,40 "$TMP" "$OUT" 2>/dev/null
    rm -f $FILE_LIST "$TMP"
    echo "✅ Created ${OUT}"
  else
    echo "⚠️ No data found for EN${ENS}"
  fi
' ::: $(seq -w 0 50)

# ============================================================
# STEP 4: Cleanup temporary directories and files
# ============================================================
echo
echo "🧹 Cleaning temporary files and folders..."
for VAR in "${VARIABLES[@]}"; do
  rm -rf "${MAIN_DIR}/${VAR}_data"
  rm -f "${MAIN_DIR}/grib2_links_${VAR}.txt"
done

rm -rf "$INDEX_DIR" "$TMP_DIR"
find "$OUT_DIR" -type f -name "tmp_*" -delete 2>/dev/null || true

echo
echo "============================================================"
echo "🎯 Final combined ensemble NetCDFs:"
echo "📂 Location: ${OUT_DIR}"
echo "📄 Files: ${DATE}_${TIME}_EN[00-50].nc (variables: ${VARIABLES[*]})"
echo "============================================================"
