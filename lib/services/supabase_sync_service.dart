import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/newcomer_record.dart';
import 'env_config_service.dart';

class SupabaseSyncResult {
  final int syncedCount;
  final int failedCount;
  final String? errorMessage;

  const SupabaseSyncResult({
    required this.syncedCount,
    required this.failedCount,
    this.errorMessage,
  });

  bool get isSuccess => failedCount == 0 && errorMessage == null;
}

/// Syncs extracted NewcomerRecord text data (no slip images) to Supabase via PostgREST.
class SupabaseSyncService {
  static final SupabaseSyncService instance = SupabaseSyncService._internal();
  SupabaseSyncService._internal();

  bool get isConfigured => EnvConfigService.instance.hasSupabaseConfig;

  Future<void> ensureReady() async {
    await EnvConfigService.instance.ensureInitialized();
  }

  Map<String, String> _buildHeaders({bool returnRepresentation = true}) {
    final anonKey = EnvConfigService.instance.supabaseAnonKey;
    final isJwt = anonKey.startsWith('eyJ');
    return {
      'apikey': anonKey,
      if (isJwt) 'Authorization': 'Bearer $anonKey',
      'Content-Type': 'application/json',
      if (returnRepresentation) 'Prefer': 'return=representation',
    };
  }

  /// Pushes a single record to Supabase.
  /// If [record.remoteId] is present, updates the existing row; otherwise inserts a new row.
  /// Returns the remote UUID (`id`) on success, or `null` if offline / unconfigured / failed.
  Future<String?> pushRecord(NewcomerRecord record) async {
    await EnvConfigService.instance.ensureInitialized();
    if (!isConfigured) return null;

    final baseUrl = EnvConfigService.instance.supabaseUrl;
    final payload = record.toSupabasePayload();

    try {
      if (record.remoteId != null && record.remoteId!.isNotEmpty) {
        final uri = Uri.parse(
          '$baseUrl/rest/v1/newcomers?id=eq.${Uri.encodeComponent(record.remoteId!)}',
        );
        final response = await http
            .patch(
              uri,
              headers: _buildHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is List && decoded.isNotEmpty) {
            return (decoded.first['id'] as String?) ?? record.remoteId;
          }
          return record.remoteId;
        }
        debugPrint(
          'Supabase PATCH failed (${response.statusCode}): ${response.body}',
        );
        return null;
      } else {
        final uri = Uri.parse('$baseUrl/rest/v1/newcomers');
        final response = await http
            .post(
              uri,
              headers: _buildHeaders(),
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          final decoded = jsonDecode(response.body);
          if (decoded is List && decoded.isNotEmpty) {
            return decoded.first['id'] as String?;
          }
          if (decoded is Map<String, dynamic>) {
            return decoded['id'] as String?;
          }
        }
        debugPrint(
          'Supabase POST failed (${response.statusCode}): ${response.body}',
        );
        return null;
      }
    } catch (e) {
      debugPrint('Supabase sync error: $e');
      return null;
    }
  }

  /// Deletes a record from Supabase if it was previously synced.
  Future<bool> deleteRemoteRecord(String? remoteId) async {
    if (remoteId == null || remoteId.isEmpty) return true;
    await EnvConfigService.instance.ensureInitialized();
    if (!isConfigured) return false;

    final baseUrl = EnvConfigService.instance.supabaseUrl;
    try {
      final uri = Uri.parse(
        '$baseUrl/rest/v1/newcomers?id=eq.${Uri.encodeComponent(remoteId)}',
      );
      final response = await http
          .delete(
            uri,
            headers: _buildHeaders(returnRepresentation: false),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('Supabase delete error: $e');
      return false;
    }
  }
}
