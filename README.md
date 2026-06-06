# UTI Detection YOLOv8

Portfolio-ready Flutter app for urinary tract infection screening from microscopy-style images. The app accepts an image, runs an on-device YOLOv8 TensorFlow Lite detector, counts detected pus cells, and reports whether the sample crosses the infection threshold.

## Preview

| Welcome | Image Upload | Prediction Result |
| --- | --- | --- |
| ![UTI detection welcome screen](screenshots/Screenshot_20250618_062415.png) | ![UTI detection upload screen](screenshots/Screenshot_20250618_062544.png) | ![UTI detection result screen](screenshots/Screenshot_20250618_062615.png) |

## Project Highlights

- Built a complete Flutter flow for image selection, preview, YOLOv8 inference, and diagnosis output.
- Integrated local TensorFlow Lite inference so analysis runs on device without a remote API.
- Used YOLO-style object detection to identify pus cells and draw prediction boxes on the analyzed image.
- Applied non-maximum suppression to reduce duplicate detections before producing the final count.
- Converted detection count into a simple infection status using the app threshold of more than 3 pus cells.
- Kept the repository clean by excluding generated build artifacts and the trained model file.

## Tech Stack

- Flutter and Dart
- YOLOv8 model exported to TensorFlow Lite
- `tflite_flutter` for local model inference
- `image_picker` for gallery/camera input
- `image` for preprocessing and drawing bounding boxes
- Dart isolates for keeping heavy prediction work off the UI thread

## Repository Structure

- `lib/pages/` - welcome, upload, and prediction result screens
- `lib/utils/yolov8_helper.dart` - model loading, preprocessing, inference, NMS, and annotated output generation
- `assets/classes.txt` - detection class labels
- `assets/images/uti.png` - application visual asset
- `assets/models/best_float16.tflite` - local model file, excluded from Git because of size
- `screenshots/` - portfolio screenshots used in this README

## Run Locally

1. Install Flutter and confirm the environment with `flutter doctor`.
2. Install dependencies with `flutter pub get`.
3. Place the trained YOLOv8 TensorFlow Lite model at `assets/models/best_float16.tflite`.
4. Start the app with `flutter run`.

## Model Note

The trained `.tflite` model is about 21.7 MB, so it is intentionally excluded from the repository. Restore it locally at `assets/models/best_float16.tflite` before running inference.

## Diagnosis Note

The app uses detected pus-cell count as a screening signal: more than 3 detected pus cells is shown as infected, while 3 or fewer is shown as not infected. This project is intended as a software prototype, not a replacement for clinical diagnosis.
