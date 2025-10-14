# ECMWF Forecast Downloader

A high-performance bash-based pipeline for downloading ECMWF HRES and Ensemble forecast data from ECMWF Open Data service.

## 🌟 Features

- **Ensemble Forecasts**: Download IFS ENS data for multiple variables
- **HRES Forecasts**: Download high-resolution forecast data  
- **Parallel Processing**: Utilizes multiple CPU cores for fast downloads
- **Flexible Configuration**: Customizable date, time, and variable parameters
- **NetCDF Output**: Converted and clipped data in NetCDF format

## 🚀 Quick Start

### Download Ensemble Data
```bash
# Download ensemble total precipitation for 2025-10-12 00z
bash scripts/ecmwf_ens_downloader.sh 20251012 00z tp

# Download ensemble 2m temperature
bash scripts/ecmwf_ens_downloader.sh 20251012 00z 2t

### Download HRES Data
```bash
# Download ensemble total precipitation for 2025-10-12 00z
bash scripts/ecmwf_hres_downloader.sh 20251012 00z tp

# Download ensemble 2m temperature
bash scripts/ecmwf_hres_downloader.sh 20251012 00z 2t
