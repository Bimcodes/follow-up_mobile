enum FollowUpStatus {
  newEntry('New', 'Not yet contacted'),
  contacted('Contacted', 'Reached via WhatsApp or Call'),
  visited('Visited', 'Physical follow-up completed'),
  integrated('Integrated', 'Joined a unit or regular attendance');

  final String label;
  final String description;
  const FollowUpStatus(this.label, this.description);

  static FollowUpStatus fromString(String? value) {
    return FollowUpStatus.values.firstWhere(
      (e) => e.name == value || e.label.toLowerCase() == value?.toLowerCase(),
      orElse: () => FollowUpStatus.newEntry,
    );
  }
}

class NewcomerRecord {
  final int? id;
  final String? remoteId;
  final bool isSynced;
  final String fullName;
  final String phoneNumber;
  final String department;
  final String invitedBy;
  final String location;
  final String prayerPoints;
  final String? imagePath;
  final String? rawOcrText;
  final FollowUpStatus status;
  final String notes;
  final DateTime serviceDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NewcomerRecord({
    this.id,
    this.remoteId,
    this.isSynced = false,
    required this.fullName,
    required this.phoneNumber,
    required this.department,
    required this.invitedBy,
    required this.location,
    required this.prayerPoints,
    this.imagePath,
    this.rawOcrText,
    this.status = FollowUpStatus.newEntry,
    this.notes = '',
    required this.serviceDate,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns digits only from the phone number.
  String get digitsOnlyPhone => phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');

  /// Checks whether the phone number looks like a standard 11-digit Nigerian mobile number
  /// (e.g., 080..., 090..., 070..., 081..., 091...) or 13-digit +234 number.
  bool get isPhoneComplete {
    final digits = digitsOnlyPhone;
    if (digits.isEmpty) return false;
    if (digits.startsWith('234') && digits.length == 13) return true;
    if (digits.startsWith('0') && digits.length == 11) return true;
    return false;
  }

  /// Provides a human-readable warning if the phone number looks incomplete or has OCR issues.
  String? get phoneValidationHint {
    final digits = digitsOnlyPhone;
    if (digits.isEmpty) return 'Missing phone number';
    if (digits.startsWith('0') && digits.length != 11) {
      return '${digits.length} digits (standard Nigerian numbers have 11 digits)';
    }
    if (!digits.startsWith('0') && !digits.startsWith('234')) {
      return 'Unusual prefix (${digits.length} digits)';
    }
    return null;
  }

  /// Formats phone number for WhatsApp URL (e.g. 234902709649...).
  String get whatsappPhone {
    final digits = digitsOnlyPhone;
    if (digits.startsWith('234')) return digits;
    if (digits.startsWith('0')) return '234${digits.substring(1)}';
    return '234$digits';
  }

  NewcomerRecord copyWith({
    int? id,
    String? remoteId,
    bool? isSynced,
    String? fullName,
    String? phoneNumber,
    String? department,
    String? invitedBy,
    String? location,
    String? prayerPoints,
    String? imagePath,
    String? rawOcrText,
    FollowUpStatus? status,
    String? notes,
    DateTime? serviceDate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NewcomerRecord(
      id: id ?? this.id,
      remoteId: remoteId ?? this.remoteId,
      isSynced: isSynced ?? this.isSynced,
      fullName: fullName ?? this.fullName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      department: department ?? this.department,
      invitedBy: invitedBy ?? this.invitedBy,
      location: location ?? this.location,
      prayerPoints: prayerPoints ?? this.prayerPoints,
      imagePath: imagePath ?? this.imagePath,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      serviceDate: serviceDate ?? this.serviceDate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      if (id != null) 'id': id,
      'remote_id': remoteId,
      'is_synced': isSynced ? 1 : 0,
      'full_name': fullName.trim(),
      'phone_number': phoneNumber.trim(),
      'department': department.trim(),
      'invited_by': invitedBy.trim(),
      'location': location.trim(),
      'prayer_points': prayerPoints.trim(),
      'image_path': imagePath,
      'raw_ocr_text': rawOcrText,
      'status': status.name,
      'notes': notes.trim(),
      'service_date': serviceDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Payload sent to Supabase (extracted text data only, no slip image file/path).
  Map<String, Object?> toSupabasePayload() {
    return {
      if (id != null) 'local_id': id,
      'full_name': fullName.trim(),
      'phone_number': phoneNumber.trim(),
      'department': department.trim(),
      'invited_by': invitedBy.trim(),
      'location': location.trim(),
      'prayer_points': prayerPoints.trim(),
      'raw_ocr_text': rawOcrText,
      'status': status.name,
      'notes': notes.trim(),
      'service_date': serviceDate.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  factory NewcomerRecord.fromMap(Map<String, Object?> map) {
    final rawSynced = map['is_synced'];
    final synced = rawSynced == 1 || rawSynced == true;
    return NewcomerRecord(
      id: map['id'] as int?,
      remoteId: map['remote_id'] as String?,
      isSynced: synced,
      fullName: (map['full_name'] as String?) ?? '',
      phoneNumber: (map['phone_number'] as String?) ?? '',
      department: (map['department'] as String?) ?? '',
      invitedBy: (map['invited_by'] as String?) ?? '',
      location: (map['location'] as String?) ?? '',
      prayerPoints: (map['prayer_points'] as String?) ?? '',
      imagePath: map['image_path'] as String?,
      rawOcrText: map['raw_ocr_text'] as String?,
      status: FollowUpStatus.fromString(map['status'] as String?),
      notes: (map['notes'] as String?) ?? '',
      serviceDate: DateTime.tryParse((map['service_date'] as String?) ?? '') ??
          DateTime.now(),
      createdAt: DateTime.tryParse((map['created_at'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((map['updated_at'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}
