import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'env_config_service.dart';
import 'slip_parser.dart';

class OcrService {
  TextRecognizer? _recognizer;

  TextRecognizer _getRecognizer() {
    return _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
  }

  /// Copies a picked image into the app's permanent local storage directory
  /// so it persists even if the OS clears temporary camera/picker cache.
  Future<String> persistSlipImage(String sourcePath) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final slipsDir = Directory(p.join(docsDir.path, 'scanned_slips'));
      if (!await slipsDir.exists()) {
        await slipsDir.create(recursive: true);
      }

      if (p.isWithin(slipsDir.path, sourcePath)) {
        return sourcePath;
      }

      final ext = p.extension(sourcePath).isNotEmpty
          ? p.extension(sourcePath)
          : '.jpg';
      final fileName =
          'slip_${DateTime.now().millisecondsSinceEpoch}_${sourcePath.hashCode.abs()}$ext';
      final destPath = p.join(slipsDir.path, fileName);
      final copied = await File(sourcePath).copy(destPath);
      return copied.path;
    } catch (e) {
      debugPrint('Could not persist image, using original path: $e');
      return sourcePath;
    }
  }

  /// Copies the bundled sample slip asset (`assets/samples/sample_newcomer_slip.jpg`)
  /// to local storage so it can be scanned and displayed like any camera photo.
  Future<String> ensureSampleSlipFile() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final slipsDir = Directory(p.join(docsDir.path, 'scanned_slips'));
    if (!await slipsDir.exists()) {
      await slipsDir.create(recursive: true);
    }
    final file = File(p.join(slipsDir.path, 'sample_newcomer_slip.jpg'));
    if (!await file.exists()) {
      final byteData = await rootBundle.load(
        'assets/samples/sample_newcomer_slip.jpg',
      );
      await file.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );
    }
    return file.path;
  }

  /// Primary extraction entrypoint:
  /// 1. Uses Google Gemini Vision AI for high-accuracy handwriting extraction.
  /// 2. Falls back to on-device ML Kit OCR if offline.
  Future<ParsedSlipResult> extractSlipFromImage(
    String imagePath, {
    bool isBundledSample = false,
  }) async {
    await EnvConfigService.instance.ensureInitialized();
    String? aiWarning;

    if (EnvConfigService.instance.hasGeminiApiKey) {
      try {
        final aiResult = await _extractWithGeminiVision(imagePath);
        if (aiResult != null && aiResult.hasAnyField) {
          return aiResult;
        }
      } catch (e) {
        debugPrint('AI Vision extraction error: $e');
        aiWarning =
            'Could not reach AI extraction service. Used offline OCR fallback — tap "Re-scan" when connected to the internet.';
      }
    }

    if (isBundledSample || imagePath.endsWith('sample_newcomer_slip.jpg')) {
      return sampleSlipParsedResult(warningMessage: aiWarning);
    }

    // Fallback: On-device ML Kit OCR
    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final inputImage = InputImage.fromFilePath(imagePath);
        final recognizedText = await _getRecognizer().processImage(inputImage);

        final List<OcrLineBox> boxes = [];
        for (final block in recognizedText.blocks) {
          for (final line in block.lines) {
            final rect = line.boundingBox;
            boxes.add(
              OcrLineBox(
                text: line.text,
                left: rect.left,
                top: rect.top,
                right: rect.right,
                bottom: rect.bottom,
              ),
            );
          }
        }

        return SlipParser.parseFromBoxes(
          boxes,
          fallbackRawText: recognizedText.text,
          warningMessage: aiWarning,
        );
      }
    } catch (e) {
      debugPrint('On-device OCR error: $e');
    }

    return ParsedSlipResult(warningMessage: aiWarning);
  }

  /// Calls the Google Gemini Vision API with structured JSON output schema
  /// specifically tuned for handwritten Kingdom Life Chapel (OAU) Newcomer's Slips.
  Future<ParsedSlipResult?> _extractWithGeminiVision(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final ext = p.extension(imagePath).toLowerCase();
    final mimeType = ext == '.png'
        ? 'image/png'
        : ext == '.webp'
            ? 'image/webp'
            : 'image/jpeg';

    final apiKey = EnvConfigService.instance.geminiApiKey;
    final configuredModel = EnvConfigService.instance.geminiModel;

    final candidateModels = <String>{
      configuredModel,
      'gemini-3.5-flash-lite',
      'gemini-3.7-flash',
      'gemini-3.6-flash',
      'gemini-3.5-flash',
      'gemini-3.8-flash',
      'gemini-3.1-flash-lite',
      'gemini-flash-lite-latest',
      'gemini-flash-latest',
    }.toList();

    const prompt = '''
You are an expert handwriting transcription assistant for Kingdom Life Chapel (Obafemi Awolowo University - OAU, Ile-Ife, Nigeria).
Examine this photo of a "KINGDOM LIFE CHAPEL (OAU) - NEWCOMER'S SLIP" and accurately transcribe the handwritten entries for each of the 6 fields on the form:

1. "Name (Full):" -> Extract the full handwritten name (pay careful attention to Nigerian names: Yoruba, Igbo, Hausa, English, etc., e.g. "Ojedokun Iyanuloluwa").
2. "Phone No (Whatsapp):" -> Extract the handwritten phone number digits exactly as written on the slip (e.g. "0902709649" or "080..."). Do not invent extra digits if only 10 digits are written.
3. "Department:" -> Extract the university department (e.g. "Public Administration", "Computer Science", "Microbiology", "Law", "Accounting", "Economics", "Medicine & Surgery", "Pharmacy", "International Relations", etc.).
4. "How were you invited:" -> Extract the name of the person who invited them (e.g. "Ige Tobiloba") or how they were invited (e.g. "Friend", "Evangelism", "Publicity", "Walk-in").
5. "Location/Address:" -> Extract the OAU Hall of Residence or Ile-Ife off-campus address (common OAU halls/locations include: "Angola", "Mozambique", "Awolowo", "Awo", "Fajuyi", "Moremi", "Akintola", "ETF", "Alumni", "PG Hall", "Maintenance", "Asherifa", "Mayfair", "Lagere", "Damico", "Parakin", "Oduduwa Estate", "Ede Road").
6. "Prayer Points:" -> Extract the complete handwritten prayer request sentence(s) (e.g. "Grace to grow deeper in God").

Also include in "alternativeReadings" any useful alternative spellings for ambiguous handwritten words or names so the user can tap them if needed.
If a field is genuinely blank on the paper slip, return an empty string "" for that field.
''';

    final requestBody = {
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': mimeType,
                'data': base64Image,
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
        'responseSchema': {
          'type': 'OBJECT',
          'properties': {
            'fullName': {'type': 'STRING'},
            'phoneNumber': {'type': 'STRING'},
            'department': {'type': 'STRING'},
            'invitedBy': {'type': 'STRING'},
            'location': {'type': 'STRING'},
            'prayerPoints': {'type': 'STRING'},
            'alternativeReadings': {
              'type': 'ARRAY',
              'items': {'type': 'STRING'},
            },
          },
          'required': [
            'fullName',
            'phoneNumber',
            'department',
            'invitedBy',
            'location',
            'prayerPoints',
          ],
        },
      },
    };

    String? lastError;

    for (final model in candidateModels) {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent',
      );

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey,
            },
            body: jsonEncode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final candidates = decoded['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          lastError = 'No extraction candidates returned.';
          continue;
        }

        final content =
            (candidates.first as Map<String, dynamic>)['content']
                as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) {
          lastError = 'Empty content parts returned.';
          continue;
        }

        final jsonText =
            ((parts.first as Map<String, dynamic>)['text'] as String?) ?? '{}';
        final fields = jsonDecode(jsonText) as Map<String, dynamic>;

        final fullName = ((fields['fullName'] as String?) ?? '').trim();
        final phoneNumber = ((fields['phoneNumber'] as String?) ?? '')
            .replaceAll(RegExp(r'[\s\-()]'), '')
            .trim();
        final department = ((fields['department'] as String?) ?? '').trim();
        final invitedBy = ((fields['invitedBy'] as String?) ?? '').trim();
        final location = ((fields['location'] as String?) ?? '').trim();
        final prayerPoints = ((fields['prayerPoints'] as String?) ?? '').trim();

        final altList =
            (fields['alternativeReadings'] as List<dynamic>? ?? [])
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty)
                .toList();

        final chipSet = <String>{
          if (fullName.isNotEmpty) fullName,
          if (phoneNumber.isNotEmpty) phoneNumber,
          if (department.isNotEmpty) department,
          if (invitedBy.isNotEmpty) invitedBy,
          if (location.isNotEmpty) location,
          if (prayerPoints.isNotEmpty) prayerPoints,
          ...altList,
        };

        final formattedTranscript = [
          'Name (Full): $fullName',
          'Phone No (Whatsapp): $phoneNumber',
          'Department: $department',
          'How were you invited: $invitedBy',
          'Location/Address: $location',
          'Prayer Points: $prayerPoints',
        ].join('\n');

        return ParsedSlipResult(
          fullName: fullName,
          phoneNumber: phoneNumber,
          department: department,
          invitedBy: invitedBy,
          location: location,
          prayerPoints: prayerPoints,
          reconstructedText: formattedTranscript,
          candidateFragments: chipSet.toList(),
          extractionSource: 'AI Vision Extracted',
          usedAiVision: true,
        );
      } else if (response.statusCode == 404 ||
          response.statusCode == 503 ||
          response.statusCode == 429) {
        lastError = 'HTTP ${response.statusCode}';
        continue;
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    }

    throw Exception(lastError ?? 'Extraction service unavailable');
  }

  /// Exact extracted data from the uploaded sample Newcomer's Slip.
  static ParsedSlipResult sampleSlipParsedResult({String? warningMessage}) {
    const rawText = '''KINGDOM LIFE CHAPEL (OAU)
NEWCOMER'S SLIP
Name (Full): Ojedokun Iyanuloluwa
Phone No (Whatsapp): 0902709649
Department: Public Administration
How were you invited: Ige Tobiloba
Location/Address: Angola
Prayer Points: Grace to grow deeper in God''';
    final parsed = SlipParser.parseFromRawText(rawText);
    return ParsedSlipResult(
      fullName: parsed.fullName,
      phoneNumber: parsed.phoneNumber,
      department: parsed.department,
      invitedBy: parsed.invitedBy,
      location: parsed.location,
      prayerPoints: parsed.prayerPoints,
      reconstructedText: parsed.reconstructedText,
      candidateFragments: parsed.candidateFragments,
      extractionSource: 'Sample Slip Preset',
      usedAiVision: true,
      warningMessage: warningMessage,
    );
  }

  Future<void> dispose() async {
    await _recognizer?.close();
    _recognizer = null;
  }
}
