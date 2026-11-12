class OcrLineBox {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLineBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  double get width => (right - left).abs();
  double get height => (bottom - top).abs();
  double get centerY => (top + bottom) / 2.0;
  double get centerX => (left + right) / 2.0;
}

class ParsedSlipResult {
  final String fullName;
  final String phoneNumber;
  final String department;
  final String invitedBy;
  final String location;
  final String prayerPoints;
  final String reconstructedText;
  final List<String> candidateFragments;
  final String extractionSource;
  final bool usedAiVision;
  final String? warningMessage;

  const ParsedSlipResult({
    this.fullName = '',
    this.phoneNumber = '',
    this.department = '',
    this.invitedBy = '',
    this.location = '',
    this.prayerPoints = '',
    this.reconstructedText = '',
    this.candidateFragments = const [],
    this.extractionSource = 'On-Device OCR',
    this.usedAiVision = false,
    this.warningMessage,
  });

  bool get hasAnyField =>
      fullName.isNotEmpty ||
      phoneNumber.isNotEmpty ||
      department.isNotEmpty ||
      invitedBy.isNotEmpty ||
      location.isNotEmpty ||
      prayerPoints.isNotEmpty;
}

enum _SlipField {
  fullName,
  phoneNumber,
  department,
  invitedBy,
  location,
  prayerPoints,
}

class SlipParser {
  static final RegExp _headerNoiseRegex = RegExp(
    r'''^(?:kingdom\s*life|chapel\s*\(?oau\)?|newcomer['’`s]*\s*slip|kingdom\s*life\s*chapel.*)$''',
    caseSensitive: false,
  );

  static final Map<_SlipField, RegExp> _labelPrefixMatchers = {
    _SlipField.fullName: RegExp(
      r'^\s*(?:name\s*\(?\s*full\s*\)?|full\s*name|name)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
    _SlipField.phoneNumber: RegExp(
      r'^\s*(?:phone\s*(?:no|number)?\s*\(?\s*whats\s*app\s*\)?|phone\s*(?:no|number)?|whats\s*app)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
    _SlipField.department: RegExp(
      r'^\s*(?:department|dept\.?)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
    _SlipField.invitedBy: RegExp(
      r'^\s*(?:how\s*were\s*you\s*invited|invited\s*by|who\s*invited\s*you|how\s*were\s*you)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
    _SlipField.location: RegExp(
      r'^\s*(?:location\s*[\/\\|]?\s*address|location|address)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
    _SlipField.prayerPoints: RegExp(
      r'^\s*(?:prayer\s*points?|prayer\s*requests?|prayer)\s*[:;\-._]*\s*(.*)$',
      caseSensitive: false,
    ),
  };

  /// Reconstructs horizontal rows from spatial OCR bounding boxes and extracts
  /// the 6 Kingdom Life Chapel (OAU) Newcomer's Slip fields.
  static ParsedSlipResult parseFromBoxes(
    List<OcrLineBox> boxes, {
    String? fallbackRawText,
    String? warningMessage,
  }) {
    final nonEmptyBoxes =
        boxes.where((b) => b.text.trim().isNotEmpty).toList();
    if (nonEmptyBoxes.isEmpty) {
      return parseFromRawText(
        fallbackRawText ?? '',
        warningMessage: warningMessage,
      );
    }

    final heights =
        nonEmptyBoxes.map((b) => b.height).where((h) => h > 0).toList()..sort();
    final double avgHeight =
        heights.isEmpty ? 28.0 : heights[heights.length ~/ 2];
    final double rowThreshold = avgHeight * 0.68;

    final sortedByY = List<OcrLineBox>.from(nonEmptyBoxes)
      ..sort((a, b) => a.centerY.compareTo(b.centerY));

    final List<List<OcrLineBox>> rowClusters = [];
    for (final box in sortedByY) {
      if (rowClusters.isEmpty) {
        rowClusters.add([box]);
        continue;
      }
      final currentCluster = rowClusters.last;
      final clusterMeanY =
          currentCluster.map((e) => e.centerY).reduce((a, b) => a + b) /
              currentCluster.length;
      if ((box.centerY - clusterMeanY).abs() <= rowThreshold) {
        currentCluster.add(box);
      } else {
        rowClusters.add([box]);
      }
    }

    final List<String> horizontalLines = [];
    for (final cluster in rowClusters) {
      cluster.sort((a, b) => a.left.compareTo(b.left));
      final merged = cluster.map((b) => b.text.trim()).join(' ');
      if (merged.isNotEmpty) {
        horizontalLines.add(merged);
      }
    }

    final reconstructed = horizontalLines.join('\n');
    return parseFromRawText(reconstructed, warningMessage: warningMessage);
  }

  /// Parses newline-separated text from a Newcomer's Slip into structured fields.
  static ParsedSlipResult parseFromRawText(
    String rawText, {
    String? warningMessage,
  }) {
    if (rawText.trim().isEmpty) {
      return ParsedSlipResult(warningMessage: warningMessage);
    }

    final rawLines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => _cleanCommonArtifacts(l))
        .where((l) => l.isNotEmpty)
        .toList();

    final Map<_SlipField, String> extracted = {};
    final List<String> unmatchedFragments = [];
    _SlipField? pendingEmptyField;

    for (int i = 0; i < rawLines.length; i++) {
      final line = rawLines[i];
      if (_isHeaderNoise(line)) {
        continue;
      }

      _SlipField? matchedField;
      String? remainder;

      for (final entry in _labelPrefixMatchers.entries) {
        final match = entry.value.firstMatch(line);
        if (match != null) {
          matchedField = entry.key;
          remainder = (match.group(1) ?? '').trim();
          break;
        }
      }

      if (matchedField != null) {
        final cleanedRemainder = _stripLeadingPunctuation(remainder ?? '');
        if (cleanedRemainder.isNotEmpty) {
          extracted[matchedField] = cleanedRemainder;
          pendingEmptyField = null;
          unmatchedFragments.add(cleanedRemainder);
        } else {
          pendingEmptyField = matchedField;
        }
      } else {
        final embedded = _tryExtractEmbeddedLabel(line);
        if (embedded != null) {
          final field = embedded.$1;
          final value = _stripLeadingPunctuation(embedded.$2);
          if (value.isNotEmpty) {
            extracted[field] = value;
            unmatchedFragments.add(value);
          }
          pendingEmptyField = null;
          continue;
        }

        if (pendingEmptyField != null &&
            (extracted[pendingEmptyField] == null ||
                extracted[pendingEmptyField]!.isEmpty)) {
          extracted[pendingEmptyField] = line;
          unmatchedFragments.add(line);
          pendingEmptyField = null;
        } else if (pendingEmptyField == _SlipField.prayerPoints ||
            (extracted.containsKey(_SlipField.prayerPoints) &&
                i == rawLines.length - 1 &&
                !_looksLikePhone(line))) {
          final existing = extracted[_SlipField.prayerPoints] ?? '';
          extracted[_SlipField.prayerPoints] =
              existing.isEmpty ? line : '$existing $line';
          unmatchedFragments.add(line);
        } else {
          unmatchedFragments.add(line);
        }
      }
    }

    String phone = _normalizePhone(extracted[_SlipField.phoneNumber] ?? '');
    if (phone.isEmpty) {
      for (final fragment in unmatchedFragments) {
        final candidate = _extractPhoneFromText(fragment);
        if (candidate.isNotEmpty) {
          phone = candidate;
          break;
        }
      }
    }

    final seen = <String>{};
    final chips = <String>[];
    for (final item in unmatchedFragments) {
      final trimmed = item.trim();
      if (trimmed.length >= 2 &&
          !_isHeaderNoise(trimmed) &&
          seen.add(trimmed.toLowerCase())) {
        chips.add(trimmed);
      }
    }

    return ParsedSlipResult(
      fullName: extracted[_SlipField.fullName] ?? '',
      phoneNumber: phone,
      department: extracted[_SlipField.department] ?? '',
      invitedBy: extracted[_SlipField.invitedBy] ?? '',
      location: extracted[_SlipField.location] ?? '',
      prayerPoints: extracted[_SlipField.prayerPoints] ?? '',
      reconstructedText: rawLines.join('\n'),
      candidateFragments: chips,
      extractionSource: 'On-Device ML Kit Fallback',
      usedAiVision: false,
      warningMessage: warningMessage,
    );
  }

  static bool _isHeaderNoise(String line) {
    final cleaned = line.trim();
    if (_headerNoiseRegex.hasMatch(cleaned)) return true;
    final lower = cleaned.toLowerCase();
    if (lower == 'kingdom life' ||
        lower == 'chapel (oau)' ||
        lower == "newcomer's slip" ||
        lower == 'newcomers slip') {
      return true;
    }
    return false;
  }

  static String _cleanCommonArtifacts(String input) {
    return input
        .replaceAll(RegExp(r'_{2,}'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _stripLeadingPunctuation(String input) {
    return input.replaceFirst(RegExp(r'^[:;\-._\s]+'), '').trim();
  }

  static (_SlipField, String)? _tryExtractEmbeddedLabel(String line) {
    final Map<_SlipField, RegExp> embeddedPatterns = {
      _SlipField.fullName: RegExp(
        r'(?:name\s*\(?\s*full\s*\)?)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
      _SlipField.phoneNumber: RegExp(
        r'(?:phone\s*no\s*\(?\s*whats\s*app\s*\)?|whats\s*app)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
      _SlipField.department: RegExp(
        r'(?:department)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
      _SlipField.invitedBy: RegExp(
        r'(?:how\s*were\s*you\s*invited|invited\s*by)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
      _SlipField.location: RegExp(
        r'(?:location\s*[\/\\|]?\s*address)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
      _SlipField.prayerPoints: RegExp(
        r'(?:prayer\s*points?)\s*[:;\-._]+\s*(.+)$',
        caseSensitive: false,
      ),
    };

    for (final entry in embeddedPatterns.entries) {
      final match = entry.value.firstMatch(line);
      if (match != null) {
        return (entry.key, match.group(1)?.trim() ?? '');
      }
    }
    return null;
  }

  static bool _looksLikePhone(String input) {
    return _extractPhoneFromText(input).isNotEmpty;
  }

  static String _normalizePhone(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final extracted = _extractPhoneFromText(trimmed);
    if (extracted.isNotEmpty) return extracted;
    return trimmed;
  }

  static String _extractPhoneFromText(String text) {
    final normalized = text
        .replaceAll(RegExp(r'[OoQD]'), '0')
        .replaceAll(RegExp(r'[Il|!]'), '1')
        .replaceAll(RegExp(r'[Ss]'), '5')
        .replaceAll(RegExp(r'[Bb]'), '8')
        .replaceAll(RegExp(r'[\s\-().]'), '');

    final ngMatch = RegExp(r'(?:\+?234|0)[789][01]\d{7,8}').firstMatch(
      normalized,
    );
    if (ngMatch != null) {
      return ngMatch.group(0)!;
    }

    final genericMatch = RegExp(r'\+?\d{9,13}').firstMatch(normalized);
    if (genericMatch != null) {
      return genericMatch.group(0)!;
    }
    return '';
  }
}
