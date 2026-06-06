import 'dart:io';
import 'package:flutter/material.dart';

class PredictionResultPage extends StatelessWidget {
  final String imagePath;
  final int pusCellCount;
  final double confidence;

  const PredictionResultPage({
    super.key,
    required this.imagePath,
    required this.pusCellCount,
    required this.confidence,
  });

  @override
  Widget build(BuildContext context) {
    // Determine infection status based on pus cell count
    final bool infected = pusCellCount > 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Prediction Result',
          style: TextStyle(
            color: Colors.white, // Keeping consistency with blue title
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true, // Center the title for better aesthetics
        backgroundColor: Colors.blue, // Clean white background
        elevation: 10, // Added shadow
        shape: const RoundedRectangleBorder( // Added rounded corners at the bottom
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(20), // Adjust radius as desired
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white), // Blue back arrow for consistency
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Display the predicted image.
            Image.file(
              File(imagePath),
              height: 300,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),

            Text(
              "🧪 Pus Cells Detected: $pusCellCount",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),

            Text(
              "🎯 Confidence: ${(confidence * 100).toStringAsFixed(2)}%",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              '-----------------------------------------------------------------',
            ),
            // Displaying the threshold condition explicitly with specific bolding
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 20,
                  color: infected ? Colors.red : Colors.green,
                ),
                children: <TextSpan>[
                  TextSpan(
                    text: infected
                        ? "🔴 No of pus cells > 3 :: "
                        : "🟢 No of pus cells <= 3 :: ",
                  ),
                  TextSpan(
                    text: infected ? "Infected" : "Not Infected",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
