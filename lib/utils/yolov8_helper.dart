import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

// Define a class to hold the prediction result
class PredictionResult {
  final String imagePath;
  final int pusCellCount;
  final double maxConfidence;

  PredictionResult({
    required this.imagePath,
    required this.pusCellCount,
    required this.maxConfidence,
  });
}

// Data structure to hold a single detection for NMS
class Detection {
  final Rect boundingBox;
  final double confidence;
  final int classId;

  Detection(this.boundingBox, this.confidence, this.classId);
}

class YOLOv8Helper {
  Interpreter? _interpreter; // This interpreter will be loaded on the main Isolate

  // IMPORTANT: These shapes MUST match your TFLite model's input/output exactly.
  final int inputSize = 1280;
  final List<int> outputShape = [1, 5, 33600];

  // Constructor for main Isolate (for initial model loading)
  YOLOv8Helper();

  // Public getter to expose the interpreter's native address
  // This is used to pass the interpreter to background isolates.
  int? get interpreterAddress => _interpreter?.address;


  Future<void> loadModel() async {
    try {
      // Model loading via fromAsset MUST happen on the main Isolate
      _interpreter = await Interpreter.fromAsset('assets/models/best_float16.tflite');
      debugPrint('Model loaded successfully on main Isolate!');
    } catch (e) {
      debugPrint('Error loading model on main Isolate: $e');
      throw Exception('Failed to load model: $e');
    }
  }

  // This method now contains the core prediction logic and can be called
  // by either the main isolate (via predict()) or a background isolate.
  // It takes an Interpreter instance as a parameter.
  Future<PredictionResult> performPredictionInternal(File imageFile, Interpreter interpreterInstance) async {
    List<Rect> detectedBoundingBoxes = []; // Local to this method for clarity of NMS flow

    img_lib.Image? originalImage = img_lib.decodeImage(imageFile.readAsBytesSync());
    if (originalImage == null) {
      throw Exception("Could not decode image.");
    }

    final double originalWidth = originalImage.width.toDouble();
    final double originalHeight = originalImage.height.toDouble();

    img_lib.Image resizedImage = img_lib.copyResize(originalImage, width: inputSize, height: inputSize);

    var inputBytes = Float32List(1 * inputSize * inputSize * 3);
    var buffer = Float32List.view(inputBytes.buffer);
    int pixelIndex = 0;
    for (int y = 0; y < inputSize; y++) {
      for (int x = 0; x < inputSize; x++) {
        final pixel = resizedImage.getPixel(x, y);
        buffer[pixelIndex++] = pixel.r / 255.0;
        buffer[pixelIndex++] = pixel.g / 255.0;
        buffer[pixelIndex++] = pixel.b / 255.0;
      }
    }

    List<Object> inputTensor = [inputBytes.reshape([1, inputSize, inputSize, 3])];

    var outputTensor = List.filled(
        outputShape[0] * outputShape[1] * outputShape[2], 0.0)
        .reshape(outputShape);

    Map<int, Object> outputs = {
      0: outputTensor,
    };

    try {
      interpreterInstance.runForMultipleInputs(inputTensor, outputs); // Use the provided interpreter instance
      debugPrint('Inference completed in Isolate!');
    } catch (e) {
      debugPrint('Error during interpreter run in Isolate: $e');
      throw Exception('Failed to run inference: $e');
    }

    int pusCellCount = 0;
    double maxOverallConfidence = 0.0;
    List<Detection> allDetections = [];

    final List<List<double>> rawOutput = (outputs[0]! as List<dynamic>)[0].cast<List<double>>();

    for (int i = 0; i < rawOutput[0].length; i++) {
      double xCenterNormalized = rawOutput[0][i];
      double yCenterNormalized = rawOutput[1][i];
      double widthNormalized = rawOutput[2][i];
      double heightNormalized = rawOutput[3][i];
      double confidence = rawOutput[4][i];

      if (confidence > 0.3) {
        double xCenterPx = xCenterNormalized * inputSize;
        double yCenterPx = yCenterNormalized * inputSize;
        double widthPx = widthNormalized * inputSize;
        double heightPx = heightNormalized * inputSize;

        double x1Px = xCenterPx - (widthPx / 2);
        double y1Px = yCenterPx - (heightPx / 2);
        double x2Px = xCenterPx + (widthPx / 2);
        double y2Px = yCenterPx + (heightPx / 2);

        double scaleX = originalWidth / inputSize;
        double scaleY = originalHeight / inputSize;

        Rect scaledBBox = Rect.fromLTRB(
          x1Px * scaleX,
          y1Px * scaleY,
          x2Px * scaleX,
          y2Px * scaleY,
        );

        allDetections.add(Detection(scaledBBox, confidence, 0));
      }
    }

    List<Detection> finalDetections = applyNMS(allDetections, iouThreshold: 0.45);

    for (var detection in finalDetections) {
      pusCellCount++;
      if (detection.confidence > maxOverallConfidence) {
        maxOverallConfidence = detection.confidence;
      }
      detectedBoundingBoxes.add(detection.boundingBox);
    }

    img_lib.Image imageWithBoxes = img_lib.copyResize(originalImage, width: originalImage.width, height: originalImage.height);

    for (Rect bbox in detectedBoundingBoxes) {
      img_lib.drawRect(
        imageWithBoxes,
        x1: bbox.left.toInt(),
        y1: bbox.top.toInt(),
        x2: bbox.right.toInt(),
        y2: bbox.bottom.toInt(),
        color: img_lib.ColorRgb8(255, 0, 0),
        thickness: 3,
      );
    }

    final String tempPath = (await getTemporaryDirectory()).path;
    final String predictedImagePath = '$tempPath/predicted_image_${DateTime.now().millisecondsSinceEpoch}.png';
    File(predictedImagePath).writeAsBytesSync(img_lib.encodePng(imageWithBoxes));

    return PredictionResult(
      imagePath: predictedImagePath,
      pusCellCount: pusCellCount,
      maxConfidence: maxOverallConfidence,
    );
  }

  // Dispose of the interpreter on the main Isolate
  void dispose() {
    _interpreter?.close();
    _interpreter = null; // Ensure it's null after closing
  }

  // --- NMS Helper Functions ---

  double calculateIoU(Rect box1, Rect box2) {
    double xA = math.max(box1.left, box2.left);
    double yA = math.max(box1.top, box2.top);
    double xB = math.min(box1.right, box2.right);
    double yB = math.min(box1.bottom, box2.bottom);

    double intersectionWidth = xB - xA;
    double intersectionHeight = yB - yA;

    if (intersectionWidth <= 0 || intersectionHeight <= 0) return 0.0;

    double intersectionArea = intersectionWidth * intersectionHeight;

    double box1Area = box1.width * box1.height;
    double box2Area = box2.width * box2.height;
    double unionArea = box1Area + box2Area - intersectionArea;

    return intersectionArea / unionArea;
  }

  List<Detection> applyNMS(List<Detection> detections, {required double iouThreshold}) {
    if (detections.isEmpty) return [];

    detections.sort((a, b) => b.confidence.compareTo(a.confidence));

    List<Detection> finalDetections = [];
    List<bool> suppressed = List.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final currentDetection = detections[i];
      finalDetections.add(currentDetection);

      for (int j = i + 1; j < detections.length; j++) {
        if (suppressed[j]) continue;

        double iou = calculateIoU(currentDetection.boundingBox, detections[j].boundingBox);

        if (iou > iouThreshold) {
          suppressed[j] = true;
        }
      }
    }
    return finalDetections;
  }
}
