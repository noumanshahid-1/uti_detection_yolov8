import 'package:flutter_test/flutter_test.dart';
import 'package:uti_detection/main.dart'; // Import your main app file

void main() {
  testWidgets('Welcome page displays correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const UTIApp()); // Use UTIApp instead of MyApp

    // Verify that the "Welcome" text is present.
    expect(find.text('Welcome'), findsOneWidget);

    // Verify that the "Get Started" button is present.
    expect(find.text('Get Started'), findsOneWidget);
  });
}