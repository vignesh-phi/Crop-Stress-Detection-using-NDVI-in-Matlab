# Crop Health Monitor: NDVI Estimator & Scene Classifier

An advanced, fully automated MATLAB GUI application designed for real-time agricultural and environmental analysis. This tool processes Sentinel-2 satellite imagery (or drone data) to calculate the Normalized Difference Vegetation Index (NDVI), automatically classify scene types, and visually map crop health across 5 distinct diagnostic zones.

## 📌 Overview
Whether you are analyzing a healthy farm, an arid desert, or a coastal region, this tool automatically adapts. By calculating how much near-infrared light vegetation reflects versus how much red light it absorbs, the software accurately identifies areas of environmental stress, water bodies, and thriving crops. 

## 🚀 Key Features
* **Interactive 5-Zone Analysis:** Drag a single threshold slider to dynamically update health zones in real-time.
* **Automatic Scene Detection:** The system intelligently identifies the environment (Agricultural Field, Ocean, Road/Urban, Desert) based on raw NDVI statistics.
* **Stress Hotspot Finder:** Automatically isolates, measures, and ranks isolated patches of severely stressed vegetation.
* **Comprehensive Analytics:** Compare 6 different vegetation indices, apply 5 different image filters, and view detailed Histograms and Cumulative Distribution Functions (CDF).
* **One-Click Export:** Instantly generate a CSV data report and PNG visuals of your analysis.

---

## 📥 Input Data Specifications
This application is strictly optimized for high-resolution satellite imagery, specifically Sentinel-2 data provided by the European Space Agency's **Copernicus** program. 

For the main NDVI engine to function, you must provide:
* **Format:** 16-bit `.tiff` images (Raw L1C / L2A data).
* **NIR Band:** Band 8 (Near-Infrared) — Used to capture high vegetation reflectance.
* **Red Band:** Band 4 (Red) — Used to capture chlorophyll light absorption.
*(Note: The tool also supports custom multispectral drone imagery as long as it is provided in matching 16-bit Red and NIR band formats).*

---

## 🖥️ Application Dashboard
The main interface allows users to load raw satellite bands and immediately view the RGB composite, the continuous NDVI map, and the classified health zones.

### Main Agricultural Analysis (Threshold Method)
![Real World Agricultural Land](<Real World Satellite Image of an Agricultural Land.png>)

### Sample Environments
The tool accurately handles non-agricultural environments, automatically classifying massive water bodies or dense urban areas.
* **Ocean / Water Body:** ![Sample Ocean](<Sample Ocean Image.png>)
* **Healthy Field:** ![Sample Green Field](<Sample Green Field Image.png>)

---

## 📊 Advanced Analytics & Diagnostics

### Stress Hotspot Analysis
Isolates connected patches of stressed crops, allowing users to pinpoint exact field locations requiring immediate intervention.
![Stress Hotspots](<Stress Hotspot Analysis.png>)

### Vegetation Indices Comparison
Compare the standard NDVI against EVI, SAVI, MSAVI, GNDVI, and RE-NDVI to ensure the most accurate environmental assessment.
![Indices Comparison](<Vegetation Indices Comparision.png>)

### Statistical Distribution
Detailed histogram and CDF plotting colored dynamically by the active health zones.
![Histogram and CDF](<Histogram and CDF.png>)

### Method Comparison (K-Means & Otsu)
Evaluate thresholding techniques against automated K-Means clustering and Otsu's method.
![Methods Comparison](<Methods Comparision.png>)

---

## ⚙️ How to Use

### Option 1: With Sentinel-2 Data
1. Browse and load your 16-bit **NIR Band (B08)** and **Red Band (B04)** `.tiff` files.
2. Click **"Show RGB"** to generate the standard visual composite.
3. Click **"Calculate NDVI"**.
4. Drag the threshold slider — all 5 classification zones will update in real-time.
5. Utilize the analysis buttons at the bottom for deeper diagnostics (Hotspots, Histograms, etc.).
6. Click **"Export Results"** to save your active zone data to a `.csv` and `.png`.

### Option 2: Without Data (Built-in Samples)
Click one of the 4 sample-data buttons to test the engine:
* **Agricultural Field:** Displays all 5 health zones.
* **Ocean / Water Body:** Dominantly Water class, with minor coastal stress detection.
* **Road / Urban Scene:** Stressed and Moderate classes dominate.
* **Desert / Bare Soil:** Highlights Stressed and Moderate terrain.

---

## 🔬 Technical Specifications

### Proportional Zoning Logic
Classification thresholds scale proportionally with the main Threshold value (`T`). Because the Stressed upper bound is bound to `T/2`, the stressed zone remains dynamically visible at every slider position.
* **Zone 1 (Water / Non-veg):** NDVI < 0
* **Zone 2 (Stressed):** 0 ≤ NDVI < T/2
* **Zone 3 (Moderate):** T/2 ≤ NDVI < T
* **Zone 4 (Healthy):** T ≤ NDVI < T+0.20
* **Zone 5 (Very Healthy):** NDVI ≥ T+0.20

### Scene Logic & Colormaps
* **Auto-Detection:** Ocean images process almost entirely as `NDVI < 0` (Class 1), while Roads map to `NDVI ~0-0.10` (Class 2), and Deserts map to `NDVI ~0.05-0.20` (Classes 2-3).
* **Colorimetry:** Utilizes a custom 6-class colormap (Water | Stressed | Moderate | Healthy | Very Healthy) alongside a diverging continuous NDVI colormap (Blue = negative, White = 0, Green = high).

### Filtering & Processing Parameters
* **Supported Filters:** None, Gaussian, Median, Wiener, Bilateral-like.
* **Supported Indices:** NDVI, EVI, SAVI, MSAVI, GNDVI, RE-NDVI. *(Note: Optional Green band input enables proper EVI and GNDVI calculations).*
* **Hotspot Detection:** Utilizes `bwlabel` mapping alongside a scatter severity plot based on patch area and mean NDVI.

### Required MATLAB Toolboxes
* **Image Processing Toolbox** (Core requirement)
* **Statistics and Machine Learning Toolbox** (Required for K-Means clustering and confusion matrix generation)
