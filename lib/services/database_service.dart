import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import '../models/newcomer_record.dart';
import 'ocr_service.dart';
import 'supabase_sync_service.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  Database? _db;
  final List<NewcomerRecord> _fallbackMemoryStore = [];
  bool _useMemoryFallback = false;

  Future<Database?> get database async {
    if (_useMemoryFallback) return null;
    if (_db != null) return _db;
    try {
      _db = await _initDatabase();
      return _db;
    } catch (e) {
      debugPrint('SQLite unavailable on this host, using memory store: $e');
      _useMemoryFallback = true;
      await _seedMemoryFallbackIfEmpty();
      return null;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, 'klc_newcomers.db');

    String? sampleImagePath;
    try {
      sampleImagePath = await OcrService().ensureSampleSlipFile();
    } catch (_) {}

    return openDatabase(
      fullPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE newcomers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            remote_id TEXT,
            is_synced INTEGER NOT NULL DEFAULT 0,
            full_name TEXT NOT NULL,
            phone_number TEXT NOT NULL,
            department TEXT NOT NULL,
            invited_by TEXT NOT NULL,
            location TEXT NOT NULL,
            prayer_points TEXT NOT NULL,
            image_path TEXT,
            raw_ocr_text TEXT,
            status TEXT NOT NULL,
            notes TEXT NOT NULL,
            service_date TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');

        await db.execute(
          'CREATE INDEX idx_newcomers_name ON newcomers(full_name)',
        );
        await db.execute(
          'CREATE INDEX idx_newcomers_status ON newcomers(status)',
        );

        final now = DateTime.now();
        final sampleParsed = OcrService.sampleSlipParsedResult();
        final initialRecord = NewcomerRecord(
          fullName: sampleParsed.fullName,
          phoneNumber: sampleParsed.phoneNumber,
          department: sampleParsed.department,
          invitedBy: sampleParsed.invitedBy,
          location: sampleParsed.location,
          prayerPoints: sampleParsed.prayerPoints,
          imagePath: sampleImagePath,
          rawOcrText: sampleParsed.reconstructedText,
          status: FollowUpStatus.newEntry,
          notes:
              'Extracted from uploaded Kingdom Life Chapel (OAU) Newcomer\'s Slip.',
          serviceDate: now,
          createdAt: now,
          updatedAt: now,
        );

        await db.insert('newcomers', initialRecord.toMap());
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          try {
            await db.execute('ALTER TABLE newcomers ADD COLUMN remote_id TEXT');
          } catch (_) {}
          try {
            await db.execute(
              'ALTER TABLE newcomers ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
      },
    );
  }

  Future<void> _seedMemoryFallbackIfEmpty() async {
    if (_fallbackMemoryStore.isNotEmpty) return;
    final now = DateTime.now();
    final sampleParsed = OcrService.sampleSlipParsedResult();
    _fallbackMemoryStore.add(
      NewcomerRecord(
        id: 1,
        fullName: sampleParsed.fullName,
        phoneNumber: sampleParsed.phoneNumber,
        department: sampleParsed.department,
        invitedBy: sampleParsed.invitedBy,
        location: sampleParsed.location,
        prayerPoints: sampleParsed.prayerPoints,
        rawOcrText: sampleParsed.reconstructedText,
        status: FollowUpStatus.newEntry,
        notes:
            'Extracted from uploaded Kingdom Life Chapel (OAU) Newcomer\'s Slip.',
        serviceDate: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<List<NewcomerRecord>> getAllRecords() async {
    final db = await database;
    if (db == null) {
      await _seedMemoryFallbackIfEmpty();
      final sorted = List<NewcomerRecord>.from(_fallbackMemoryStore)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return sorted;
    }

    final rows = await db.query('newcomers', orderBy: 'created_at DESC');
    return rows.map(NewcomerRecord.fromMap).toList();
  }

  Future<NewcomerRecord> insertRecord(NewcomerRecord record) async {
    final db = await database;
    NewcomerRecord savedLocal;
    if (db == null) {
      final nextId = _fallbackMemoryStore.isEmpty
          ? 1
          : (_fallbackMemoryStore
                      .map((e) => e.id ?? 0)
                      .reduce((a, b) => a > b ? a : b) +
                  1);
      savedLocal = record.copyWith(id: nextId, isSynced: false);
      _fallbackMemoryStore.insert(0, savedLocal);
    } else {
      final id = await db.insert(
        'newcomers',
        record.copyWith(isSynced: false).toMap(),
      );
      savedLocal = record.copyWith(id: id, isSynced: false);
    }

    // Push extracted text data to Supabase if configured
    return _trySyncSingleRecord(savedLocal);
  }

  Future<List<NewcomerRecord>> insertBatch(List<NewcomerRecord> records) async {
    final List<NewcomerRecord> inserted = [];
    for (final rec in records) {
      inserted.add(await insertRecord(rec));
    }
    return inserted;
  }

  Future<void> updateRecord(NewcomerRecord record) async {
    if (record.id == null) return;
    final updated = record.copyWith(
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    final db = await database;
    if (db == null) {
      final idx = _fallbackMemoryStore.indexWhere((e) => e.id == record.id);
      if (idx != -1) {
        _fallbackMemoryStore[idx] = updated;
      }
    } else {
      await db.update(
        'newcomers',
        updated.toMap(),
        where: 'id = ?',
        whereArgs: [record.id],
      );
    }

    await _trySyncSingleRecord(updated);
  }

  Future<void> deleteRecord(int id) async {
    final db = await database;
    String? remoteId;
    if (db == null) {
      final existing = _fallbackMemoryStore.where((e) => e.id == id);
      if (existing.isNotEmpty) remoteId = existing.first.remoteId;
      _fallbackMemoryStore.removeWhere((e) => e.id == id);
    } else {
      final rows = await db.query(
        'newcomers',
        columns: ['remote_id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isNotEmpty) {
        remoteId = rows.first['remote_id'] as String?;
      }
      await db.delete('newcomers', where: 'id = ?', whereArgs: [id]);
    }
    if (remoteId != null) {
      await SupabaseSyncService.instance.deleteRemoteRecord(remoteId);
    }
  }

  Future<NewcomerRecord> _trySyncSingleRecord(NewcomerRecord record) async {
    await SupabaseSyncService.instance.ensureReady();
    if (!SupabaseSyncService.instance.isConfigured) return record;
    final remoteId = await SupabaseSyncService.instance.pushRecord(record);
    if (remoteId == null) return record;

    final syncedRecord = record.copyWith(remoteId: remoteId, isSynced: true);
    final db = await database;
    if (db == null) {
      final idx = _fallbackMemoryStore.indexWhere((e) => e.id == record.id);
      if (idx != -1) {
        _fallbackMemoryStore[idx] = syncedRecord;
      }
    } else if (record.id != null) {
      await db.update(
        'newcomers',
        {'remote_id': remoteId, 'is_synced': 1},
        where: 'id = ?',
        whereArgs: [record.id],
      );
    }
    return syncedRecord;
  }

  /// Syncs all local records where `is_synced == false` to Supabase.
  Future<SupabaseSyncResult> syncPendingRecords() async {
    await SupabaseSyncService.instance.ensureReady();
    if (!SupabaseSyncService.instance.isConfigured) {
      return const SupabaseSyncResult(
        syncedCount: 0,
        failedCount: 0,
        errorMessage:
            'Supabase is not configured in .env (SUPABASE_URL / SUPABASE_ANON_KEY).',
      );
    }

    final all = await getAllRecords();
    final pending = all.where((r) => !r.isSynced).toList();
    if (pending.isEmpty) {
      return const SupabaseSyncResult(syncedCount: 0, failedCount: 0);
    }

    int syncedCount = 0;
    int failedCount = 0;

    for (final rec in pending) {
      final updated = await _trySyncSingleRecord(rec);
      if (updated.isSynced) {
        syncedCount++;
      } else {
        failedCount++;
      }
    }

    return SupabaseSyncResult(
      syncedCount: syncedCount,
      failedCount: failedCount,
      errorMessage: failedCount > 0
          ? 'Could not sync $failedCount record(s). Check internet or Supabase table setup.'
          : null,
    );
  }

  /// Generates CSV content for the given newcomer records.
  String generateCsvContent(List<NewcomerRecord> records) {
    final dateFmt = DateFormat('yyyy-MM-dd');
    final buffer = StringBuffer();
    buffer.writeln(
      'S/N,Full Name,Phone No (WhatsApp),Department,How Were You Invited,Location/Address,Prayer Points,Follow-Up Status,Notes,Service Date',
    );

    for (int i = 0; i < records.length; i++) {
      final r = records[i];
      buffer.writeln(
        [
          (i + 1).toString(),
          _escapeCsv(r.fullName),
          _escapeCsv(r.phoneNumber),
          _escapeCsv(r.department),
          _escapeCsv(r.invitedBy),
          _escapeCsv(r.location),
          _escapeCsv(r.prayerPoints),
          _escapeCsv(r.status.label),
          _escapeCsv(r.notes),
          _escapeCsv(dateFmt.format(r.serviceDate)),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// Writes records to a `.csv` file in the temporary directory and opens the share dialog.
  Future<String> exportAndShareCsv(List<NewcomerRecord> records) async {
    final csv = generateCsvContent(records);
    final dir = await getTemporaryDirectory();
    final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final file = File(p.join(dir.path, 'klc_newcomers_$timestamp.csv'));
    await file.writeAsString(csv, flush: true);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Kingdom Life Chapel (OAU) — Newcomers List',
        text:
            'Kingdom Life Chapel (OAU) Newcomers Export (${records.length} records)',
      ),
    );
    return file.path;
  }

  String _escapeCsv(String value) {
    final normalized = value.replaceAll('\r\n', ' ').replaceAll('\n', ' ');
    if (normalized.contains(',') ||
        normalized.contains('"') ||
        normalized.contains('\n')) {
      return '"${normalized.replaceAll('"', '""')}"';
    }
    return normalized;
  }
}
