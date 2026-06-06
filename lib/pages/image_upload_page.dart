import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'prediction_result_page.dart';
import '../utils/yolov8_helper.dart';
import 'dart:isolate'; // Import for Isolate
import 'package:tflite_flutter/tflite_flutter.dart'; // Import Interpreter here for _isolateEntry
import 'package:flutter/services.dart'; // Required for BackgroundIsolateBinaryMessenger and RootIsolateToken

// A top-level function to run in a separate Isolate
// It must be a static or top-level function to be accessible by Isolates
Future<void> _isolateEntry(Map<String, dynamic> message) async {
  SendPort sendPort = message['sendPort'];
  String imagePath = message['imagePath'];
  int interpreterAddress = message['interpreterAddress'];
  RootIsolateToken? rootIsolateToken = message['rootIsolateToken']; // Receive the token

  // IMPORTANT: Initialize BackgroundIsolateBinaryMessenger for platform channel access
  // Pass the rootIsolateToken to ensure proper initialization
  if (rootIsolateToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  }


  try {
    // Reconstruct the Interpreter instance from the address passed by the main Isolate
    Interpreter interpreterForIsolate = Interpreter.fromAddress(interpreterAddress);

    // Create a helper instance for this Isolate.
    final helper = YOLOv8Helper();
    // Perform prediction using the interpreter instance on THIS Isolate.
    final result = await helper.performPredictionInternal(File(imagePath), interpreterForIsolate);

    // REMOVED: interpreterForIsolate.close();
    // The interpreter will be closed by the main Isolate where it was originally created.

    // Send the prediction result back to the main Isolate
    sendPort.send({
      'imagePath': result.imagePath,
      'pusCellCount': result.pusCellCount,
      'confidence': result.maxConfidence,
      'error': null,
    });
  } catch (e) {
    // Send error back to the main Isolate
    sendPort.send({
      'error': e.toString(),
    });
  }
}

class ImageUploadPage extends StatefulWidget {
  const ImageUploadPage({super.key});

  @override
  State<ImageUploadPage> createState() => _ImageUploadPageState();
}

class _ImageUploadPageState extends State<ImageUploadPage> {
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();
  late YOLOv8Helper _yolov8Helper; // Declare helper at class level
  bool _isModelLoaded = false; // To track model loading status

  @override
  void initState() {
    super.initState();
    _yolov8Helper = YOLOv8Helper(); // Initialize helper
    _loadModelOnMainIsolate(); // Load model when the page initializes
  }

  Future<void> _loadModelOnMainIsolate() async {
    try {
      await _yolov8Helper.loadModel();
      setState(() {
        _isModelLoaded = true;
      });
      debugPrint('Model pre-loaded on main Isolate successfully!');
    } catch (e) {
      debugPrint('Failed to pre-load model on main Isolate: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load AI model: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _yolov8Helper.dispose(); // Dispose the interpreter when the page is closed
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _picker.pickImage(source: source, imageQuality: 90);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  void _analyzeImage() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an image first.')),
      );
      return;
    }
    if (!_isModelLoaded) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI Model is still loading. Please wait.')),
      );
      return;
    }

    // Crucial check: Ensure interpreter is not null before passing its address
    if (_yolov8Helper.interpreterAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model not ready for analysis. Please try again.')),
      );
      return;
    }

    if (!mounted) return;

    // Show a loading dialog immediately
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(), // This will spin continuously
            SizedBox(width: 20),
            Text("Analyzing..."),
          ],
        ),
      ),
    );

    // Create a ReceivePort to get results from the Isolate
    final receivePort = ReceivePort();
    try {
      // Get the RootIsolateToken from the current (main) Isolate
      final RootIsolateToken? rootIsolateToken = ServicesBinding.rootIsolateToken;

      // Spawn a new Isolate for heavy computation
      await Isolate.spawn(
        _isolateEntry,
        {
          'sendPort': receivePort.sendPort,
          'imagePath': _selectedImage!.path,
          'interpreterAddress': _yolov8Helper.interpreterAddress!,
          'rootIsolateToken': rootIsolateToken, // Pass the token to the Isolate
        },
      );

      // Listen for the result from the Isolate
      final dynamic resultFromIsolate = await receivePort.first;

      if (!mounted) return; // Check mounted status again after async operations

      // Dismiss the loading dialog
      Navigator.of(context).pop();

      if (resultFromIsolate['error'] != null) {
        // Handle error from Isolate
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error analyzing image: ${resultFromIsolate['error']}')),
        );
      } else {
        // Navigate to the result page with data from Isolate
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PredictionResultPage(
              imagePath: resultFromIsolate['imagePath'],
              pusCellCount: resultFromIsolate['pusCellCount'],
              confidence: resultFromIsolate['confidence'],
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error spawning isolate or during analysis: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Dismiss dialog on unexpected error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e')),
        );
      }
    } finally {
      receivePort.close(); // Close the port when done
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Upload & Analyze",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue,
        elevation: 10,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          children: [
            const SizedBox(height: 80),
            // Display selected image or a placeholder
            if (_selectedImage != null)
              Image.file(_selectedImage!, height: 250, fit: BoxFit.contain)
            else
              Container(
                height: 250,
                color: Colors.grey[200],
                child: const Center(
                  child: Text(
                    'No image selected',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              ),
            const SizedBox(height: 50),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isModelLoaded ? () => _pickImage(ImageSource.gallery) : null, // Disable until model loaded
                  icon: const Icon(Icons.photo_library, color: Colors.white),
                  label: const Text(
                    "Gallery",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2575E1),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isModelLoaded ? () => _pickImage(ImageSource.camera) : null, // Disable until model loaded
                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                  label: const Text(
                    "Camera",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2575E1),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: (_selectedImage != null && _isModelLoaded) ? _analyzeImage : null, // Disable until image selected AND model loaded
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _isModelLoaded
                  ? const Text(
                "Analyze",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              )
                  : const CircularProgressIndicator(color: Colors.white), // Show loading indicator on button if model is not ready
            ),
          ],
        ),
      ),
    );
  }
}
