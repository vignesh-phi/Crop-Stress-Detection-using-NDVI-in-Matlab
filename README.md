# Crop-Stress-Detection-using-NDVI-in-Matlab

An advanced, automated MATLAB GUI tool designed for drone and Sentinel-2 satellite imagery analysis. This application calculates the Normalized Difference Vegetation Index (NDVI) to classify and monitor crop health, vegetation vigor, and agricultural environmental stress.

## 🚀 Features
* **Multi-Source Support:** Compatible with drone imagery and Sentinel-2 satellite bands (Red and NIR `.tiff` files).
* **Automatic Scene Classification:** Supports analysis for diverse environments including farmland, ocean, roads, and deserts.
* **5-Zone Health Analysis:** Classifies vegetation into 5 distinct zones ranging from water/non-vegetation to highly healthy crops.
* **Automated Reporting:** Generates downloadable visual maps, classification charts, and CSV health summaries.

## 📊 Visual Reports & GUI Outputs

### 1. Crop Health Map
This output maps the geographic layout of the field, highlighting variations in vegetation density and potential stress areas.
![Crop Health Map](crop_health_report_map.png)

### 2. Classification Distribution Chart
A breakdown chart showing the exact percentage distribution of soil, water, stressed crops, and healthy crop zones across the analyzed area.
![Classification Report](crop_health_report_classification.png)

## 🛠️ How to Run
1. Open MATLAB (or MATLAB Online).
2. Download the `CropHealthMonitor.m` script and your Sentinel-2 raw `.tiff` input bands to your working directory.
3. Run the script by typing `CropHealthMonitor` in the Command Window.
4. Use the interactive GUI to load your bands, adjust NDVI thresholds, and export your crop health data.
