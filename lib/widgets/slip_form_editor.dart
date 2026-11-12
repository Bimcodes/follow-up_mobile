import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/newcomer_record.dart';

class SlipFormDraft {
  String fullName;
  String phoneNumber;
  String department;
  String invitedBy;
  String location;
  String prayerPoints;
  String? imagePath;
  String? rawOcrText;
  List<String> ocrCandidates;
  String extractionSource;
  bool usedAiVision;
  String? warningMessage;
  FollowUpStatus status;
  String notes;
  DateTime serviceDate;
  bool isProcessingOcr;

  SlipFormDraft({
    this.fullName = '',
    this.phoneNumber = '',
    this.department = '',
    this.invitedBy = '',
    this.location = '',
    this.prayerPoints = '',
    this.imagePath,
    this.rawOcrText,
    this.ocrCandidates = const [],
    this.extractionSource = '',
    this.usedAiVision = false,
    this.warningMessage,
    this.status = FollowUpStatus.newEntry,
    this.notes = '',
    DateTime? serviceDate,
    this.isProcessingOcr = false,
  }) : serviceDate = serviceDate ?? DateTime.now();

  factory SlipFormDraft.fromRecord(NewcomerRecord record) {
    return SlipFormDraft(
      fullName: record.fullName,
      phoneNumber: record.phoneNumber,
      department: record.department,
      invitedBy: record.invitedBy,
      location: record.location,
      prayerPoints: record.prayerPoints,
      imagePath: record.imagePath,
      rawOcrText: record.rawOcrText,
      ocrCandidates: (record.rawOcrText ?? '')
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      status: record.status,
      notes: record.notes,
      serviceDate: record.serviceDate,
    );
  }

  NewcomerRecord toRecord({int? id, DateTime? createdAt}) {
    final now = DateTime.now();
    return NewcomerRecord(
      id: id,
      fullName: fullName.trim(),
      phoneNumber: phoneNumber.trim(),
      department: department.trim(),
      invitedBy: invitedBy.trim(),
      location: location.trim(),
      prayerPoints: prayerPoints.trim(),
      imagePath: imagePath,
      rawOcrText: rawOcrText,
      status: status,
      notes: notes.trim(),
      serviceDate: serviceDate,
      createdAt: createdAt ?? now,
      updatedAt: now,
    );
  }
}

class SlipFormEditor extends StatefulWidget {
  final SlipFormDraft draft;
  final VoidCallback? onChanged;
  final VoidCallback? onReRunOcr;

  const SlipFormEditor({
    super.key,
    required this.draft,
    this.onChanged,
    this.onReRunOcr,
  });

  @override
  State<SlipFormEditor> createState() => _SlipFormEditorState();
}

class _SlipFormEditorState extends State<SlipFormEditor> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _deptCtrl;
  late TextEditingController _invitedByCtrl;
  late TextEditingController _locationCtrl;
  late TextEditingController _prayerCtrl;
  late TextEditingController _notesCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _phoneFocus = FocusNode();
  final FocusNode _deptFocus = FocusNode();
  final FocusNode _invitedByFocus = FocusNode();
  final FocusNode _locationFocus = FocusNode();
  final FocusNode _prayerFocus = FocusNode();

  String _activeFieldLabel = 'Name (Full)';
  TextEditingController? _activeController;
  bool _showRawOcrPanel = false;

  static const List<String> _oauLocations = [
    'Angola',
    'Mozambique',
    'Awolowo (Awo)',
    'Fajuyi',
    'Moremi',
    'Akintola',
    'ETF',
    'Alumni',
    'PG Hall',
    'Maintenance',
    'Asherifa',
    'Mayfair',
    'Lagere',
    'Damico',
    'Parakin',
  ];

  @override
  void initState() {
    super.initState();
    _initControllers();
    _setupFocusTrackers();
  }

  @override
  void didUpdateWidget(covariant SlipFormEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      _syncControllersFromDraft();
    }
  }

  void _initControllers() {
    _nameCtrl = TextEditingController(text: widget.draft.fullName);
    _phoneCtrl = TextEditingController(text: widget.draft.phoneNumber);
    _deptCtrl = TextEditingController(text: widget.draft.department);
    _invitedByCtrl = TextEditingController(text: widget.draft.invitedBy);
    _locationCtrl = TextEditingController(text: widget.draft.location);
    _prayerCtrl = TextEditingController(text: widget.draft.prayerPoints);
    _notesCtrl = TextEditingController(text: widget.draft.notes);
    _activeController = _nameCtrl;
  }

  void _syncControllersFromDraft() {
    if (_nameCtrl.text != widget.draft.fullName) {
      _nameCtrl.text = widget.draft.fullName;
    }
    if (_phoneCtrl.text != widget.draft.phoneNumber) {
      _phoneCtrl.text = widget.draft.phoneNumber;
    }
    if (_deptCtrl.text != widget.draft.department) {
      _deptCtrl.text = widget.draft.department;
    }
    if (_invitedByCtrl.text != widget.draft.invitedBy) {
      _invitedByCtrl.text = widget.draft.invitedBy;
    }
    if (_locationCtrl.text != widget.draft.location) {
      _locationCtrl.text = widget.draft.location;
    }
    if (_prayerCtrl.text != widget.draft.prayerPoints) {
      _prayerCtrl.text = widget.draft.prayerPoints;
    }
    if (_notesCtrl.text != widget.draft.notes) {
      _notesCtrl.text = widget.draft.notes;
    }
  }

  void _setupFocusTrackers() {
    void bindFocus(
      FocusNode node,
      TextEditingController ctrl,
      String fieldName,
    ) {
      node.addListener(() {
        if (node.hasFocus && mounted) {
          setState(() {
            _activeController = ctrl;
            _activeFieldLabel = fieldName;
          });
        }
      });
    }

    bindFocus(_nameFocus, _nameCtrl, 'Name (Full)');
    bindFocus(_phoneFocus, _phoneCtrl, 'Phone No (WhatsApp)');
    bindFocus(_deptFocus, _deptCtrl, 'Department');
    bindFocus(_invitedByFocus, _invitedByCtrl, 'How were you invited');
    bindFocus(_locationFocus, _locationCtrl, 'Location/Address');
    bindFocus(_prayerFocus, _prayerCtrl, 'Prayer Points');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _deptCtrl.dispose();
    _invitedByCtrl.dispose();
    _locationCtrl.dispose();
    _prayerCtrl.dispose();
    _notesCtrl.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _deptFocus.dispose();
    _invitedByFocus.dispose();
    _locationFocus.dispose();
    _prayerFocus.dispose();
    super.dispose();
  }

  void _notifyDraftUpdated() {
    widget.draft.fullName = _nameCtrl.text;
    widget.draft.phoneNumber = _phoneCtrl.text;
    widget.draft.department = _deptCtrl.text;
    widget.draft.invitedBy = _invitedByCtrl.text;
    widget.draft.location = _locationCtrl.text;
    widget.draft.prayerPoints = _prayerCtrl.text;
    widget.draft.notes = _notesCtrl.text;
    setState(() {});
    widget.onChanged?.call();
  }

  void _insertCandidateIntoActiveField(String text, {bool append = false}) {
    final target = _activeController ?? _nameCtrl;
    if (append && target.text.trim().isNotEmpty) {
      target.text = '${target.text.trim()} $text';
    } else {
      target.text = text;
    }
    target.selection = TextSelection.fromPosition(
      TextPosition(offset: target.text.length),
    );
    _notifyDraftUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tempRecord = widget.draft.toRecord();
    final phoneHint = tempRecord.phoneValidationHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.draft.warningMessage != null) ...[
          _buildWarningBanner(context, theme, widget.draft.warningMessage!),
          const SizedBox(height: 12),
        ],
        if (widget.draft.imagePath != null) ...[
          _buildSlipImagePreview(context, widget.draft.imagePath!),
          const SizedBox(height: 12),
        ],
        if (widget.draft.ocrCandidates.isNotEmpty) ...[
          _buildOcrChipsBar(theme),
          const SizedBox(height: 14),
        ],
        _buildTextField(
          controller: _nameCtrl,
          focusNode: _nameFocus,
          label: 'Name (Full)',
          hint: 'e.g. Ojedokun Iyanuloluwa',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _phoneCtrl,
          focusNode: _phoneFocus,
          label: 'Phone No (WhatsApp)',
          hint: 'e.g. 09027096490',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          suffix: tempRecord.isPhoneComplete
              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
              : const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
        ),
        if (phoneHint != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Colors.orange.shade800,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    phoneHint,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _buildTextField(
          controller: _deptCtrl,
          focusNode: _deptFocus,
          label: 'Department',
          hint: 'e.g. Public Administration',
          icon: Icons.school_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _invitedByCtrl,
          focusNode: _invitedByFocus,
          label: 'How were you invited',
          hint: 'e.g. Ige Tobiloba',
          icon: Icons.handshake_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _locationCtrl,
          focusNode: _locationFocus,
          label: 'Location / Address',
          hint: 'e.g. Angola',
          icon: Icons.location_on_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _oauLocations.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final loc = _oauLocations[index];
              final isSelected =
                  _locationCtrl.text.trim().toLowerCase() == loc.toLowerCase();
              return ActionChip(
                visualDensity: VisualDensity.compact,
                backgroundColor: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                label: Text(
                  loc,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                onPressed: () {
                  _locationCtrl.text = loc;
                  _notifyDraftUpdated();
                },
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _prayerCtrl,
          focusNode: _prayerFocus,
          label: 'Prayer Points',
          hint: 'e.g. Grace to grow deeper in God',
          icon: Icons.volunteer_activism_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Follow-Up & Service Metadata',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: FollowUpStatus.values.map((status) {
            final selected = widget.draft.status == status;
            return ChoiceChip(
              label: Text(status.label),
              selected: selected,
              onSelected: (_) {
                setState(() {
                  widget.draft.status = status;
                });
                widget.onChanged?.call();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: widget.draft.serviceDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2035),
            );
            if (picked != null) {
              setState(() {
                widget.draft.serviceDate = picked;
              });
              widget.onChanged?.call();
            }
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Service Date',
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            child: Text(
              DateFormat('EEEE, MMM d, yyyy').format(widget.draft.serviceDate),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildTextField(
          controller: _notesCtrl,
          label: 'Follow-Up Notes (Optional)',
          hint: 'Add call feedback, hostel room number, or unit interest...',
          icon: Icons.notes_outlined,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
    );
  }

  Widget _buildWarningBanner(
    BuildContext context,
    ThemeData theme,
    String warning,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 19,
            color: Colors.amber.shade900,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              warning,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.amber.shade900,
              ),
            ),
          ),
          if (widget.onReRunOcr != null)
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: widget.onReRunOcr,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
        ],
      ),
    );
  }

  Widget _buildSlipImagePreview(BuildContext context, String imagePath) {
    final file = File(imagePath);
    final exists = file.existsSync();
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.6,
            ),
            child: Row(
              children: [
                Icon(
                  widget.draft.usedAiVision
                      ? Icons.auto_awesome
                      : Icons.image_search_outlined,
                  size: 18,
                  color: widget.draft.usedAiVision
                      ? Colors.green.shade700
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.draft.extractionSource.isNotEmpty
                        ? widget.draft.extractionSource
                        : 'Scanned Slip Photo (Pinch to zoom)',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: widget.draft.usedAiVision
                          ? Colors.green.shade800
                          : null,
                    ),
                  ),
                ),
                if (widget.onReRunOcr != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: widget.onReRunOcr,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                    label: const Text('Re-scan AI'),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Full screen view',
                  icon: const Icon(Icons.fullscreen, size: 20),
                  onPressed: () => _showFullScreenImage(context, imagePath),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 210,
            child: Container(
              color: Colors.black87,
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.5,
                child: exists
                    ? Image.file(file, fit: BoxFit.contain)
                    : Image.asset(
                        'assets/samples/sample_newcomer_slip.jpg',
                        fit: BoxFit.contain,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrChipsBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_fix_high_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Tap a detected phrase to fill "$_activeFieldLabel" (long-press to append):',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if ((widget.draft.rawOcrText ?? '').isNotEmpty)
                InkWell(
                  onTap: () => setState(() {
                    _showRawOcrPanel = !_showRawOcrPanel;
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      _showRawOcrPanel ? 'Hide Transcript' : 'Transcript',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.draft.ocrCandidates.map((fragment) {
              return GestureDetector(
                onLongPress: () =>
                    _insertCandidateIntoActiveField(fragment, append: true),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(fragment, style: const TextStyle(fontSize: 12)),
                  onPressed: () =>
                      _insertCandidateIntoActiveField(fragment, append: false),
                ),
              );
            }).toList(),
          ),
          if (_showRawOcrPanel && (widget.draft.rawOcrText ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.draft.rawOcrText!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    FocusNode? focusNode,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    int maxLines = 1,
    Widget? suffix,
  }) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      maxLines: maxLines,
      onChanged: (_) => _notifyDraftUpdated(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffix,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imagePath) {
    final file = File(imagePath);
    final exists = file.existsSync();
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6.0,
                child: exists
                    ? Image.file(file)
                    : Image.asset('assets/samples/sample_newcomer_slip.jpg'),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
