# 💊 Medicine Reader — AI-Powered Prescription Reader

Medicine Reader is a Flutter mobile application that helps users read and interpret handwritten medical prescriptions. It combines on-device OCR with AI interpretation and a local medicine database to identify medicines, dosages, and instructions from prescription photos.

---

## 🚀 Features

- 📷 Capture prescription images using the device camera
- 🖼️ Upload prescription images from the gallery
- ✂️ Interactive crop tool to focus on the prescription area
- 🔍 On-device OCR using Google ML Kit (Latin script)
- 🧠 AI interpretation powered by Google Gemini (2.0 Flash with fallback models)
- 💊 Local fuzzy medicine matching against 100+ common Indian medicines
- 🗄️ SQLite database with 2.5 lakh (250,000) Indian medicines for validation
- 📊 Image quality scoring (blur + brightness detection)
- 🖼️ Image preprocessing pipeline: CLAHE + integral-image Sauvola binarisation
- 🌙 Modern dark-themed UI with animated states
- ⚡ On-device text recognition (no OCR data leaves the phone)
- 📱 Built with Flutter for cross-platform support

---

## 🛠️ Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter / Dart |
| OCR | Google ML Kit Text Recognition |
| AI Interpretation | Google Gemini API (gemini-2.0-flash with fallback) |
| Local DB | SQLite via sqflite (2.5 lakh medicines) |
| In-memory fuzzy DB | Custom Levenshtein/prefix matching |
| Image preprocessing | CLAHE + Sauvola binarisation (Dart isolate) |
| Image picking & cropping | image\_picker + image\_cropper |
| HTTP | http package |
| Env config | flutter\_dotenv |

---

## 📂 Project Structure

```
lib/
├── main.dart                          # App entry point & full UI
├── models/
│   ├── medicine.dart                  # Medicine model (SQLite row)
│   ├── ocr_result.dart                # OCR output model (blocks + quality score)
│   └── prescription_result.dart       # Structured AI interpretation result
└── services/
    ├── ocr_service.dart               # Orchestrates preprocessing → OCR → AI
    ├── image_preprocessor.dart        # CLAHE + Sauvola binarisation pipeline
    ├── ai_interpretation_service.dart # Gemini API client + local fallback
    └── medicine_database.dart         # In-memory fuzzy DB + SQLite DB service

assets/
└── db/
    └── medicines.db                   # 2.5 lakh Indian medicines (SQLite)

android/
ios/
```

---

## ⚙️ Installation

### Prerequisites

- Flutter SDK ≥ 3.44.0
- Dart SDK ^3.12.0
- A Google Gemini API key ([get one here](https://aistudio.google.com/app/apikey))

### Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/prescription_reader.git
cd prescription_reader
```

### Configure environment

Create a `.env` file in the project root:

```env
GEMINI_API_KEY=your_gemini_api_key_here
```

> The `.env` file is declared as a Flutter asset and loaded at startup via `flutter_dotenv`.

### Install dependencies

```bash
flutter pub get
```

### Run the application

```bash
flutter run
```

---

## 📦 Key Dependencies

```yaml
google_mlkit_text_recognition: ^0.13.0  # On-device OCR
image_picker: ^1.2.2                    # Camera & gallery access
image_cropper: ^8.0.2                   # Interactive crop UI
sqflite: ^2.3.3                        # SQLite for medicine DB
http: ^1.6.0                           # Gemini API calls
flutter_dotenv: ^5.1.0                 # .env config
path_provider: ^2.1.2                  # App directory paths
```

---

## 📸 How It Works

### Layer 1 — OCR Pipeline

1. User captures or uploads a prescription image.
2. The image cropper lets the user isolate the prescription area.
3. **Image preprocessing** runs in a Dart isolate:
   - Decodes and downscales to max 1200px
   - Computes blur score (Laplacian variance) and brightness score
   - Applies CLAHE (tile-based adaptive histogram equalisation with clip limiting)
   - Applies integral-image Sauvola binarisation (O(1) per pixel)
   - Outputs a BMP file for ML Kit
4. **Google ML Kit** performs Latin-script OCR and returns text blocks with confidence scores.
5. Blocks are sorted top-to-bottom, left-to-right and joined into raw text.

### Layer 2 — AI Interpretation

1. Raw OCR text is pre-processed (abbreviation expansion, noise removal).
2. A **local fuzzy pass** scans each token against 100+ common Indian medicine entries using Levenshtein distance + prefix matching.
3. A structured prompt is sent to **Google Gemini** with OCR text and local hints.
4. The AI response is parsed and each medicine is **validated against the 250,000-medicine SQLite database** for name correction and confidence boosting.
5. If all Gemini models are rate-limited, the app falls back to local DB results only.

### Gemini Model Fallback Chain

```
gemini-2.0-flash → gemini-1.5-flash → gemini-1.5-flash-latest → gemini-1.5-flash-8b
```

Each model retries up to 3× on HTTP 429 with exponential backoff before moving to the next.

---

## 🎨 UI Overview

The app uses a dark theme throughout with these main sections:

- **App bar** — App name, processing quality pill, and "Made by MD SADIQUE" credit
- **Image preview** — Shows the cropped prescription or an animated placeholder
- **Action buttons** — Camera and Gallery buttons
- **Processing card** — Animated step-by-step status during processing
- **AI Interpretation card** — Expandable medicine cards showing name, dosage, frequency, duration, confidence, and OCR corrections
- **Raw OCR text card** — Expandable view of all extracted text with processing time
- **Text blocks debug view** — Expandable list of individual OCR blocks with per-block confidence

---

## 🔮 Future Improvements

- Devanagari script support (requires separately downloaded ML Kit model)
- Medicine interaction checker
- Dosage safety validation
- Export results as PDF
- Prescription history
- Offline-only mode without Gemini
- Confidence score calibration
- Support for printed (typed) prescriptions

---

## 📋 Permissions

| Permission | Platform | Reason |
|---|---|---|
| CAMERA | Android / iOS | Capture prescription photos |
| READ\_MEDIA\_IMAGES | Android 13+ | Gallery access |
| READ\_EXTERNAL\_STORAGE | Android ≤ 12 | Gallery access |
| INTERNET | Android / iOS | Gemini API calls |

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome. Please open an issue first to discuss what you would like to change.

---

## 📜 License

This project is licensed under the MIT License.

---

*Made with ❤️ using Flutter by **MD SADIQUE***
