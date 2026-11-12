import 'package:flutter_test/flutter_test.dart';
import 'package:klc_attendance_extractor/main.dart';
import 'package:klc_attendance_extractor/models/newcomer_record.dart';
import 'package:klc_attendance_extractor/services/slip_parser.dart';

void main() {
  group('Kingdom Life Chapel (OAU) SlipParser Tests', () {
    test('Extracts all 6 fields from sample Newcomer\'s Slip text', () {
      const sampleText = '''
KINGDOM LIFE
CHAPEL (OAU)
NEWCOMER'S SLIP
Name (Full): Ojedokun Iyanuloluwa
Phone No (Whatsapp): 0902709649
Department: Public Administration
How were you invited: Ige Tobiloba
Location/Address: Angola
Prayer Points: Grace to grow deeper in God
''';

      final parsed = SlipParser.parseFromRawText(sampleText);

      expect(parsed.fullName, 'Ojedokun Iyanuloluwa');
      expect(parsed.phoneNumber, '0902709649');
      expect(parsed.department, 'Public Administration');
      expect(parsed.invitedBy, 'Ige Tobiloba');
      expect(parsed.location, 'Angola');
      expect(parsed.prayerPoints, 'Grace to grow deeper in God');
    });

    test(
      'Reconstructs horizontal rows from spatially separated ML Kit OCR boxes',
      () {
        // Simulates ML Kit detecting printed labels on the left and handwriting on the right
        final boxes = <OcrLineBox>[
          const OcrLineBox(
            text: 'KINGDOM LIFE CHAPEL (OAU)',
            left: 220,
            top: 40,
            right: 520,
            bottom: 70,
          ),
          // Handwritten values detected in a separate block order from labels:
          const OcrLineBox(
            text: 'Ojedokun Iyanuloluwa',
            left: 310,
            top: 152,
            right: 680,
            bottom: 182,
          ),
          const OcrLineBox(
            text: '0902709649',
            left: 380,
            top: 212,
            right: 620,
            bottom: 240,
          ),
          const OcrLineBox(
            text: 'Public Administration',
            left: 300,
            top: 271,
            right: 650,
            bottom: 300,
          ),
          const OcrLineBox(
            text: 'Ige Tobiloba',
            left: 350,
            top: 332,
            right: 590,
            bottom: 360,
          ),
          const OcrLineBox(
            text: 'Angola',
            left: 330,
            top: 391,
            right: 490,
            bottom: 420,
          ),
          const OcrLineBox(
            text: 'Grace to grow deeper in God',
            left: 290,
            top: 452,
            right: 760,
            bottom: 482,
          ),
          // Printed labels on the left:
          const OcrLineBox(
            text: 'Name (Full):',
            left: 80,
            top: 150,
            right: 280,
            bottom: 180,
          ),
          const OcrLineBox(
            text: 'Phone No (Whatsapp):',
            left: 80,
            top: 210,
            right: 350,
            bottom: 240,
          ),
          const OcrLineBox(
            text: 'Department:',
            left: 80,
            top: 270,
            right: 270,
            bottom: 300,
          ),
          const OcrLineBox(
            text: 'How were you invited:',
            left: 80,
            top: 330,
            right: 330,
            bottom: 360,
          ),
          const OcrLineBox(
            text: 'Location/Address:',
            left: 80,
            top: 390,
            right: 300,
            bottom: 420,
          ),
          const OcrLineBox(
            text: 'Prayer Points:',
            left: 80,
            top: 450,
            right: 260,
            bottom: 480,
          ),
        ];

        final parsed = SlipParser.parseFromBoxes(boxes);

        expect(parsed.fullName, 'Ojedokun Iyanuloluwa');
        expect(parsed.phoneNumber, '0902709649');
        expect(parsed.department, 'Public Administration');
        expect(parsed.invitedBy, 'Ige Tobiloba');
        expect(parsed.location, 'Angola');
        expect(parsed.prayerPoints, 'Grace to grow deeper in God');
      },
    );

    test('Validates Nigerian phone number length and WhatsApp formatting', () {
      final now = DateTime.now();
      final incompleteRecord = NewcomerRecord(
        fullName: 'Ojedokun Iyanuloluwa',
        phoneNumber: '0902709649', // 10 digits on the slip
        department: 'Public Administration',
        invitedBy: 'Ige Tobiloba',
        location: 'Angola',
        prayerPoints: 'Grace to grow deeper in God',
        serviceDate: now,
        createdAt: now,
        updatedAt: now,
      );

      expect(incompleteRecord.isPhoneComplete, isFalse);
      expect(incompleteRecord.phoneValidationHint, contains('10 digits'));

      final completeRecord = incompleteRecord.copyWith(
        phoneNumber: '09027096490',
      );
      expect(completeRecord.isPhoneComplete, isTrue);
      expect(completeRecord.phoneValidationHint, isNull);
      expect(completeRecord.whatsappPhone, '2349027096490');
    });
  });

  testWidgets('HomeScreen displays extracted sample slip record offline', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KlcNewcomersApp());
    await tester.pumpAndSettle();

    expect(find.text('Kingdom Life Chapel (OAU)'), findsOneWidget);
    expect(find.text('Ojedokun Iyanuloluwa'), findsOneWidget);
    expect(find.text('Dept: Public Administration'), findsOneWidget);
    expect(find.text('Invited by: Ige Tobiloba'), findsOneWidget);
  });
}
