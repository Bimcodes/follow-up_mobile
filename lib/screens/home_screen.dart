import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/newcomer_record.dart';
import '../services/database_service.dart';
import '../services/env_config_service.dart';
import '../services/quick_actions_service.dart';
import '../services/supabase_sync_service.dart';

import 'batch_scan_screen.dart';
import 'newcomer_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<NewcomerRecord> _allRecords = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  FollowUpStatus? _selectedStatusFilter;
  String? _selectedLocationFilter;

  @override
  void initState() {
    super.initState();
    _loadRecords(autoSync: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRecords({bool autoSync = false}) async {
    setState(() => _isLoading = true);
    await EnvConfigService.instance.ensureInitialized();
    var records = await DatabaseService.instance.getAllRecords();
    if (!mounted) return;
    setState(() {
      _allRecords = records;
      _isLoading = false;
    });

    if (autoSync &&
        SupabaseSyncService.instance.isConfigured &&
        records.any((r) => !r.isSynced)) {
      await _syncToCloud(silent: true);
    }
  }

  Future<void> _syncToCloud({bool silent = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    final result = await DatabaseService.instance.syncPendingRecords();
    final refreshed = await DatabaseService.instance.getAllRecords();
    if (!mounted) return;
    setState(() {
      _allRecords = refreshed;
      _isSyncing = false;
    });

    if (!silent) {
      final msg = result.errorMessage ??
          (result.syncedCount > 0
              ? 'Synced ${result.syncedCount} record(s) to Admin Dashboard!'
              : 'All ${refreshed.length} record(s) are already synced to Supabase.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  List<String> get _availableLocations {
    final set = <String>{};
    for (final r in _allRecords) {
      final loc = r.location.trim();
      if (loc.isNotEmpty) set.add(loc);
    }
    return set.toList()..sort();
  }

  List<NewcomerRecord> get _filteredRecords {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _allRecords.where((r) {
      if (_selectedStatusFilter != null && r.status != _selectedStatusFilter) {
        return false;
      }
      if (_selectedLocationFilter != null &&
          r.location.trim().toLowerCase() !=
              _selectedLocationFilter!.toLowerCase()) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.fullName.toLowerCase().contains(q) ||
          r.phoneNumber.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q) ||
          r.invitedBy.toLowerCase().contains(q) ||
          r.location.toLowerCase().contains(q) ||
          r.prayerPoints.toLowerCase().contains(q) ||
          r.notes.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openScanner(InitialScanAction action) async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchScanScreen(initialAction: action),
      ),
    );
    if (added == true) {
      await _loadRecords();
    }
  }

  Future<void> _openRecordDetail(NewcomerRecord record) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NewcomerDetailScreen(record: record),
      ),
    );
    if (changed == true) {
      await _loadRecords();
    }
  }

  Future<void> _cycleOrSelectStatus(NewcomerRecord record) async {
    final selected = await showModalBottomSheet<FollowUpStatus>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Update Follow-Up Status for ${record.fullName}',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            ...FollowUpStatus.values.map((status) {
              final isCurrent = record.status == status;
              return ListTile(
                leading: Icon(
                  isCurrent
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: isCurrent
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(
                  status.label,
                  style: TextStyle(
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Text(status.description),
                onTap: () => Navigator.pop(ctx, status),
              );
            }),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected != null && selected != record.status) {
      await DatabaseService.instance.updateRecord(
        record.copyWith(status: selected),
      );
      await _loadRecords();
    }
  }

  Future<void> _showExportSheet() async {
    final recordsToExport = _filteredRecords;
    if (recordsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No records to export.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Export ${recordsToExport.length} Newcomer Record(s)',
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Share as a CSV spreadsheet (Excel/Google Sheets compatible) or copy formatted list to clipboard.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    await DatabaseService.instance.exportAndShareCsv(
                      recordsToExport,
                    );
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('CSV export failed: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.table_view_outlined),
                label: const Text('Export & Share CSV (Excel)'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final csv = DatabaseService.instance.generateCsvContent(
                    recordsToExport,
                  );
                  await Clipboard.setData(ClipboardData(text: csv));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied CSV data to clipboard!'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy CSV to Clipboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showScanOptionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Add / Extract Newcomer\'s Slips',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.primaryContainer,
                  child: const Icon(Icons.camera_alt_outlined),
                ),
                title: const Text('Camera Scan (Single or Batch)'),
                subtitle: const Text(
                  'Snap one or multiple paper slips in a row offline',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScanner(InitialScanAction.camera);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.secondaryContainer,
                  child: const Icon(Icons.photo_library_outlined),
                ),
                title: const Text('Pick Multiple Slips from Gallery'),
                subtitle: const Text(
                  'Select multiple photos to extract & review in a batch',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScanner(InitialScanAction.multiGallery);
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(ctx).colorScheme.tertiaryContainer,
                  child: const Icon(Icons.fact_check_outlined),
                ),
                title: const Text('Extract Uploaded Sample Slip'),
                subtitle: const Text(
                  'Test OCR extraction with the sample KLC OAU slip',
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScanner(InitialScanAction.sampleSlip);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.edit_note_outlined),
                ),
                title: const Text('Manual Entry'),
                subtitle: const Text('Type newcomer details directly'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openScanner(InitialScanAction.manual);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredRecords;
    final newCount =
        _allRecords.where((r) => r.status == FollowUpStatus.newEntry).length;
    final followedUpCount = _allRecords.length - newCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kingdom Life Chapel (OAU)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 13,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  'Newcomer\'s Slip Extractor & Manager',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: SupabaseSyncService.instance.isConfigured
                ? 'Sync Extracted Data to Admin Dashboard'
                : 'Supabase Sync (Configure SUPABASE_URL in .env)',
            onPressed: _isSyncing ? null : () => _syncToCloud(silent: false),
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Badge(
                    isLabelVisible: _allRecords.any((r) => !r.isSynced),
                    label: Text(
                      '${_allRecords.where((r) => !r.isSynced).length}',
                    ),
                    child: Icon(
                      _allRecords.isNotEmpty &&
                              _allRecords.every((r) => r.isSynced)
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_upload_outlined,
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Export CSV / Share',
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: _showExportSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSummaryStrip(theme, _allRecords.length, newCount, followedUpCount),
          _buildSearchAndFilters(theme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildEmptyState(theme)
                    : RefreshIndicator(
                        onRefresh: _loadRecords,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _buildNewcomerCard(
                              context,
                              theme,
                              filtered[index],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showScanOptionsSheet,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan Slip(s)'),
      ),
    );
  }

  Widget _buildSummaryStrip(
    ThemeData theme,
    int total,
    int pendingCount,
    int followedUpCount,
  ) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          _buildStatMetric(
            theme,
            label: 'Total Slips',
            value: total.toString(),
            icon: Icons.people_alt_outlined,
            color: theme.colorScheme.primary,
          ),
          _buildVerticalDivider(theme),
          _buildStatMetric(
            theme,
            label: 'New / To Contact',
            value: pendingCount.toString(),
            icon: Icons.fiber_new_outlined,
            color: Colors.amber.shade900,
          ),
          _buildVerticalDivider(theme),
          _buildStatMetric(
            theme,
            label: 'Followed Up',
            value: followedUpCount.toString(),
            icon: Icons.verified_outlined,
            color: Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerticalDivider(ThemeData theme) {
    return Container(
      height: 28,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: theme.colorScheme.outlineVariant,
    );
  }

  Widget _buildSearchAndFilters(ThemeData theme) {
    final locations = _availableLocations;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText:
                  'Search name, phone, department, location, inviter...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                    )
                  : null,
              isDense: true,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.45,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('All'),
                  selected: _selectedStatusFilter == null &&
                      _selectedLocationFilter == null,
                  onSelected: (_) => setState(() {
                    _selectedStatusFilter = null;
                    _selectedLocationFilter = null;
                  }),
                ),
                const SizedBox(width: 6),
                ...FollowUpStatus.values.map((status) {
                  final selected = _selectedStatusFilter == status;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text(status.label),
                      selected: selected,
                      onSelected: (val) => setState(() {
                        _selectedStatusFilter = val ? status : null;
                      }),
                    ),
                  );
                }),
                if (locations.isNotEmpty) ...[
                  const VerticalDivider(width: 12),
                  ...locations.map((loc) {
                    final selected = _selectedLocationFilter == loc;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.place_outlined, size: 14),
                        label: Text(loc),
                        selected: selected,
                        onSelected: (val) => setState(() {
                          _selectedLocationFilter = val ? loc : null;
                        }),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewcomerCard(
    BuildContext context,
    ThemeData theme,
    NewcomerRecord record,
  ) {
    final statusColor = _statusColor(record.status, theme);
    final phoneHint = record.phoneValidationHint;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openRecordDetail(record),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSlipAvatar(theme, record),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                record.fullName.isEmpty
                                    ? 'Unnamed Newcomer'
                                    : record.fullName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _cycleOrSelectStatus(record),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      record.status.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.expand_more,
                                      size: 13,
                                      color: statusColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.phone_iphone_outlined,
                              size: 15,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            SelectableText(
                              record.phoneNumber.isEmpty
                                  ? 'No phone'
                                  : record.phoneNumber,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (phoneHint != null) ...[
                              const SizedBox(width: 6),
                              Tooltip(
                                message: phoneHint,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.18,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.warning_amber_rounded,
                                        size: 13,
                                        color: Colors.orange.shade900,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${record.digitsOnlyPhone.length}d',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.orange.shade900,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (record.department.isNotEmpty)
                    _buildMetadataBadge(
                      theme,
                      icon: Icons.school_outlined,
                      label: 'Dept: ${record.department}',
                    ),
                  if (record.location.isNotEmpty)
                    _buildMetadataBadge(
                      theme,
                      icon: Icons.location_on_outlined,
                      label: record.location,
                    ),
                  if (record.invitedBy.isNotEmpty)
                    _buildMetadataBadge(
                      theme,
                      icon: Icons.handshake_outlined,
                      label: 'Invited by: ${record.invitedBy}',
                    ),
                ],
              ),
              if (record.prayerPoints.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.45,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.volunteer_activism_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Prayer Points: ${record.prayerPoints}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    DateFormat('MMM d, yyyy').format(record.serviceDate),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: record.isSynced
                        ? 'Synced to Admin Dashboard'
                        : 'Pending Cloud Sync',
                    child: Icon(
                      record.isSynced
                          ? Icons.cloud_done_outlined
                          : Icons.cloud_queue_outlined,
                      size: 14,
                      color: record.isSynced
                          ? Colors.green.shade700
                          : theme.colorScheme.outline,
                    ),
                  ),
                  const Spacer(),
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'WhatsApp Message',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(
                        0xFF1B8755,
                      ).withValues(alpha: 0.14),
                      foregroundColor: const Color(0xFF1B8755),
                    ),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    onPressed: () =>
                        QuickActionsService.openWhatsApp(context, record),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Call Phone',
                    icon: const Icon(Icons.call_outlined, size: 18),
                    onPressed: () =>
                        QuickActionsService.makePhoneCall(context, record),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Copy Details',
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    onPressed: () => QuickActionsService.copyRecordToClipboard(
                      context,
                      record,
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _openRecordDetail(record),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlipAvatar(ThemeData theme, NewcomerRecord record) {
    final hasFile =
        record.imagePath != null && File(record.imagePath!).existsSync();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48,
        height: 54,
        child: hasFile
            ? Image.file(File(record.imagePath!), fit: BoxFit.cover)
            : Image.asset(
                'assets/samples/sample_newcomer_slip.jpg',
                fit: BoxFit.cover,
              ),
      ),
    );
  }

  Widget _buildMetadataBadge(
    ThemeData theme, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(FollowUpStatus status, ThemeData theme) {
    switch (status) {
      case FollowUpStatus.newEntry:
        return Colors.amber.shade900;
      case FollowUpStatus.contacted:
        return Colors.blue.shade700;
      case FollowUpStatus.visited:
        return Colors.purple.shade700;
      case FollowUpStatus.integrated:
        return Colors.green.shade700;
    }
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 56,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'No Matching Newcomer Slips',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Scan Slip(s)" below to extract a Newcomer\'s Slip using offline OCR or clear your active search filters.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
