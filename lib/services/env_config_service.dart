import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EnvConfigService {
  static final EnvConfigService instance = EnvConfigService._internal();
  EnvConfigService._internal();

  static const String defaultModel = 'gemini-3.5-flash-lite';
  static const String defaultSupabaseUrl =
      'https://zbigndldbjhkbilhiyej.supabase.co';
  static const String defaultSupabaseAnonKey =
      'sb_publishable_rTQBCtrqz6sC5N3_MpL2Qw_QBj01ndA';

  final Map<String, String> _envMap = {};
  bool _initialized = false;

  static const String _dartDefineApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
  );
  static const String _dartDefineModel = String.fromEnvironment(
    'GEMINI_MODEL',
  );
  static const String _dartDefineSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );
  static const String _dartDefineSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  Future<void> ensureInitialized() async {
    if (_initialized && hasGeminiApiKey && hasSupabaseConfig) return;
    _initialized = true;
    await reload();
  }

  /// Loads `.env` from bundled assets internally.
  Future<void> reload() async {
    _envMap.clear();
    try {
      rootBundle.evict('.env');
      final content = await rootBundle
          .loadString('.env', cache: false)
          .timeout(const Duration(milliseconds: 500));
      _parseEnvString(content);
    } catch (e) {
      debugPrint('Could not load .env asset: $e');
    }
  }

  void _parseEnvString(String content) {
    final lines = const LineSplitter().convert(content);
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eqIndex = line.indexOf('=');
      if (eqIndex <= 0) continue;

      final key = line.substring(0, eqIndex).trim();
      var value = line.substring(eqIndex + 1).trim();

      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        if (value.length >= 2) {
          value = value.substring(1, value.length - 1).trim();
        }
      }

      _envMap[key] = value;
    }
  }

  String get geminiApiKey {
    final envFileKey = (_envMap['GEMINI_API_KEY'] ?? '').trim();
    if (_isValidKey(envFileKey)) return envFileKey;

    if (_isValidKey(_dartDefineApiKey.trim())) {
      return _dartDefineApiKey.trim();
    }

    return '';
  }

  String get geminiModel {
    final envModel = (_envMap['GEMINI_MODEL'] ?? '').trim();
    if (envModel.isNotEmpty) return _normalizeModelName(envModel);
    if (_dartDefineModel.trim().isNotEmpty) {
      return _normalizeModelName(_dartDefineModel.trim());
    }
    return defaultModel;
  }

  String _normalizeModelName(String model) {
    final clean = model.replaceFirst(RegExp(r'^models/'), '').trim();
    if (clean == 'gemini-2.5-flash' ||
        clean == 'gemini-2.0-flash' ||
        clean == 'gemini-1.5-flash') {
      return defaultModel;
    }
    return clean.isEmpty ? defaultModel : clean;
  }

  bool get hasGeminiApiKey => geminiApiKey.isNotEmpty;

  String get supabaseUrl {
    final envUrl = (_envMap['SUPABASE_URL'] ?? '').trim();
    if (_isValidSupabaseValue(envUrl)) {
      return _normalizeSupabaseUrl(envUrl);
    }
    if (_isValidSupabaseValue(_dartDefineSupabaseUrl.trim())) {
      return _normalizeSupabaseUrl(_dartDefineSupabaseUrl.trim());
    }
    return defaultSupabaseUrl;
  }

  String _normalizeSupabaseUrl(String url) {
    return url
        .replaceAll(RegExp(r'/rest/v1/?$', caseSensitive: false), '')
        .replaceAll(RegExp(r'/+$'), '');
  }

  String get supabaseAnonKey {
    final envKey = (_envMap['SUPABASE_ANON_KEY'] ?? '').trim();
    if (_isValidSupabaseValue(envKey)) return envKey;
    if (_isValidSupabaseValue(_dartDefineSupabaseAnonKey.trim())) {
      return _dartDefineSupabaseAnonKey.trim();
    }
    return defaultSupabaseAnonKey;
  }

  bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  bool _isValidSupabaseValue(String value) {
    if (value.isEmpty) return false;
    final lower = value.toLowerCase();
    if (lower.contains('your-project-ref') ||
        lower.contains('your_supabase_anon_key')) {
      return false;
    }
    return true;
  }

  bool _isValidKey(String key) {
    if (key.isEmpty) return false;
    final lower = key.toLowerCase();
    if (lower == 'your_gemini_api_key_here' ||
        lower == 'paste_your_api_key_here') {
      return false;
    }
    return true;
  }
}
