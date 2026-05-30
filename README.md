# 💊 Prescription Reader

Prescription Reader is a Flutter-based mobile application that helps users read and interpret handwritten medical prescriptions. The app allows users to capture a prescription using their camera or upload an existing image from their gallery, then uses Optical Character Recognition (OCR) to extract text from the prescription.

## 🚀 Features

- 📷 Capture prescription images using the device camera
- 🖼️ Upload prescription images from the gallery
- 🔍 Extract text using Google ML Kit OCR
- 🌙 Modern dark-themed UI
- ⚡ Fast on-device text recognition
- 📱 Built with Flutter for cross-platform support

## 🛠️ Tech Stack

- Flutter
- Dart
- Google ML Kit Text Recognition
- Image Picker

## 📂 Project Structure

```
lib/
 └── main.dart

android/
ios/
linux/
macos/
web/
windows/
```

## ⚙️ Installation

### Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/prescription_reader.git
cd prescription_reader
```

### Install dependencies

```bash
flutter pub get
```

### Run the application

```bash
flutter run
```

## 📦 Dependencies

```yaml
image_picker:
google_mlkit_text_recognition:
```

## 📸 How It Works

1. Open the app.
2. Tap **Take Photo** to capture a prescription.
3. Or tap **Upload Photo** to select an image from the gallery.
4. OCR processes the image.
5. Extracted text is displayed inside the application.

## 🔮 Future Improvements

- AI-powered medicine name correction
- Medicine database integration
- Dosage detection
- Prescription interpretation using LLMs
- Medicine information lookup
- Confidence score for detected medicines
- Cloud-based AI processing for improved accuracy
- Export results as PDF

## 🎯 Project Goal

Doctor handwriting is often difficult to understand. This project aims to bridge that gap by combining OCR, AI, and medicine databases to help users identify medicines more accurately and understand prescriptions with greater confidence.

## 🤝 Contributing

Contributions, issues, and feature requests are welcome.

## 📜 License

This project is licensed under the MIT License.

---

Made with ❤️ using Flutter
