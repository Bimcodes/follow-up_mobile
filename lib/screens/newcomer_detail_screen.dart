import 'package:flutter/material.dart';
import '../models/newcomer_record.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../services/quick_actions_service.dart';
import '../widgets/slip_form_editor.dart';

class NewcomerDetailScreen extends StatefulWidget {
  final NewcomerRecord record;

  const NewcomerDetailScreen({super.key, required this.record});

  @override
  State<NewcomerDetailScreen> createState() => _NewcomerDetailScreenState();
}

class _NewcomerDetailScreenState extends State<NewcomerDetailScreen> {
  late SlipFormDraft _draft;
  final OcrService _ocrService = OcrService();
  bool _hasUnsavedChanges = false;
  bool _isSaving = false;
  bool _isReScanning = false;

  @override
  void initState() {
    super.initState();
    _draft = SlipFormDraft.fromRecord(widget.record);
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  NewcomerRecord get _currentRecord => _draft.toRecord(
        id: widget.record.id,
        createdAt: widget.record.createdAt,
      );

  Future<void> _saveUpdates() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await DatabaseService.instance.updateRecord(_currentRecord);
      if (!mounted) return;
      setState(() {
        _hasUnsavedChanges = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Newcomer details updated!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update record: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (widget.record.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Newcomer Record?'),
        content: Text(
          'Are you sure you want to remove "${_draft.fullName.isEmpty ? 'this slip' : _draft.fullName}" from local storage?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.instance.deleteRecord(widget.record.id!);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _reRunOcr() async {
    if (_draft.imagePath == null || _isReScanning) return;
    setState(() => _isReScanning = true);
    final parsed = await _ocrService.extractSlipFromImage(_draft.imagePath!);
    if (!mounted) return;
    setState(() {
      if (parsed.fullName.isNotEmpty) _draft.fullName = parsed.fullName;
      if (parsed.phoneNumber.isNotEmpty) {
        _draft.phoneNumber = parsed.phoneNumber;
      }
      if (parsed.department.isNotEmpty) _draft.department = parsed.department;
      if (parsed.invitedBy.isNotEmpty) _draft.invitedBy = parsed.invitedBy;
      if (parsed.location.isNotEmpty) _draft.location = parsed.location;
      if (parsed.prayerPoints.isNotEmpty) {
        _draft.prayerPoints = parsed.prayerPoints;
      }
      _draft.rawOcrText = parsed.reconstructedText;
      _draft.ocrCandidates = parsed.candidateFragments;
      _draft.extractionSource = parsed.extractionSource;
      _draft.usedAiVision = parsed.usedAiVision;
      _draft.warningMessage = parsed.warningMessage;
      _isReScanning = false;
      _hasUnsavedChanges = true;
    });
  }

  Future<void> _markContactedAfterAction() async {
    if (_draft.status == FollowUpStatus.newEntry) {
      setState(() {
        _draft.status = FollowUpStatus.contacted;
        _hasUnsavedChanges = true;
      });
      await DatabaseService.instance.updateRecord(_currentRecord);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentRecord;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          current.fullName.isEmpty ? 'Slip Details' : current.fullName,
        ),
        actions: [
          IconButton(
            tooltip: 'Copy Slip Summary',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () =>
                QuickActionsService.copyRecordToClipboard(context, current),
          ),
          IconButton(
            tooltip: 'Delete Record',
            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: _isReScanning
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 14),
                  Text('Re-extracting slip with Gemini Vision AI...'),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildQuickActionsCard(context, theme, current),
                  const SizedBox(height: 16),
                  SlipFormEditor(
                    key: ValueKey('${_draft.fullName}_${_draft.extractionSource}'),
                    draft: _draft,
                    onChanged: () {
                      if (!_hasUnsavedChanges) {
                        setState(() => _hasUnsavedChanges = true);
                      }
                    },
                    onReRunOcr: _draft.imagePath != null ? _reRunOcr : null,
                  ),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
          ),
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveUpdates,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              _hasUnsavedChanges ? 'Save Updates' : 'Save & Return to List',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context,
    ThemeData theme,
    NewcomerRecord record,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.75),
            theme.colorScheme.secondaryContainer.withValues(alpha: 0.55),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bolt_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Text(
                'Quick Follow-Up Actions',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  record.status.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1B8755),
                    foregroundColor: Colors.white,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final ok = await QuickActionsService.openWhatsApp(
                      context,
                      record,
                    );
                    if (ok) await _markContactedAfterAction();
                  },
                  icon: const Icon(Icons.chat_outlined, size: 17),
                  label: const Text('WhatsApp'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final ok = await QuickActionsService.makePhoneCall(
                      context,
                      record,
                    );
                    if (ok) await _markContactedAfterAction();
                  },
                  icon: const Icon(Icons.call_outlined, size: 17),
                  label: const Text('Call'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: theme.colorScheme.surface.withValues(
                      alpha: 0.85,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final ok = await QuickActionsService.sendSms(
                      context,
                      record,
                    );
                    if (ok) await _markContactedAfterAction();
                  },
                  icon: const Icon(Icons.sms_outlined, size: 17),
                  label: const Text('SMS'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
