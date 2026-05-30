import 'package:flutter_test/flutter_test.dart';
import 'package:prescription_reader/main.dart';

void main() {
  testWidgets('app renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const PrescriptionApp());
    expect(find.text('Prescription Reader'), findsOneWidget);
  });
}