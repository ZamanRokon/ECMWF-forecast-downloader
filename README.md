# 🌦️ ECMWF Forecast Downloader

A high-performance, bash-based pipeline for downloading ECMWF **HRES** and **Ensemble (ENS)** forecast data from the ECMWF Open Data service. Designed for fast, parallel processing and clean NetCDF output.

---

## 🌟 Features

- **Ensemble Forecasts**: Download IFS ENS data for multiple variables
- **High-Resolution Forecasts**: Access ECMWF HRES data at 0.25° resolution
- **Parallel Downloads**: Utilizes all available CPU cores for speed
- **Flexible Inputs**: Specify date, time (00z, 06z, 12z, 18z), and variable
- **NetCDF Output**: GRIB2 slices are merged and clipped to region, saved as NetCDF

---

## 🚀 Quick Start

### 📥 Download Ensemble Data

```bash
# Download ensemble total precipitation for 2025-10-12 00z
bash scripts/ecmwf_ens_downloader.sh 20251012 00z tp

# Download ensemble 2m temperature
bash scripts/ecmwf_ens_downloader.sh 20251012 00z 2t
```

### 📥 Download HRES Data

```bash
# Download high-resolution total precipitation for 2025-10-12 00z
bash scripts/ecmwf_hres_downloader.sh 20251012 00z tp

# Download high-resolution 2m temperature
bash scripts/ecmwf_hres_downloader.sh 20251012 00z 2t
```

---

## 📂 Output Structure

- Processed files are saved in:  
  `data/ens/`
  `data/hres/`

- Spatial coverage:  
  **Latitude:** 5° to 40°  
  **Longitude:** 65° to 110°
  [Note: If you want to change the coverage, change the extent in the bash scripts]
  **Variable:** `tp` (total precipitation)  
  **Unit:** meters

---

## 📄 License

This project is released under the MIT License. See the `LICENSE` file for details.

---

Let me know if you'd like to add sections for dependencies, troubleshooting, or automated scheduling.
