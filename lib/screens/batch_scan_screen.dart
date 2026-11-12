import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/database_service.dart';
import '../services/ocr_service.dart';
import '../widgets/slip_form_editor.dart';

enum InitialScanAction { none, camera, multiGallery, sampleSlip, manual }

class BatchScanScreen extends StatefulWidget {
  final InitialScanAction initialAction;

  const BatchScanScreen({
    super.key,
    this.initialAction = InitialScanAction.none,
  });

  @override
  State<BatchScanScreen> createState() => _BatchScanScreenState();
}

class _BatchScanScreenState extends State<BatchScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final OcrService _ocrService = OcrService();

  final List<SlipFormDraft> _draftQueue = [];
  int _selectedIndex = 0;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runInitialAction();
    });
  }

  Future<void> _runInitialAction() async {
    switch (widget.initialAction) {
      case InitialScanAction.camera:
        await _captureFromCamera();
        break;
      case InitialScanAction.multiGallery:
        await _pickMultiFromGallery();
        break;
      case InitialScanAction.sampleSlip:
        await _loadBundledSampleSlip();
        break;
      case InitialScanAction.manual:
        _addManualBlankSlip();
        break;
      case InitialScanAction.none:
        break;
    }
  }

  @override
  void dispose() {
    _ocrService.dispose();
    super.dispose();
  }

  Future<void> _captureFromCamera({bool continuousBatch = false}) async {
    try {
      do {
        final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 92,
        );
        if (photo == null) break;

        await _enqueueAndExtractImage(photo.path);

        if (!continuousBatch || !mounted) break;

        final takeAnother = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Slip Added to Batch'),
            content: Text(
              '${_draftQueue.length} slip(s) queued. Would you like to snap another slip now or review the batch?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Review Batch'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Snap Next Slip'),
              ),
            ],
          ),
        );
        if (takeAnother != true) break;
      } while (mounted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera unavailable: $e')),
        );
      }
    }
  }

  Future<void> _pickMultiFromGallery() async {
    try {
      final List<XFile> files = await _picker.pickMultiImage(imageQuality: 92);
      if (files.isEmpty) return;

      for (final file in files) {
        await _enqueueAndExtractImage(file.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick images: $e')),
        );
      }
    }
  }

  Future<void> _loadBundledSampleSlip() async {
    final samplePath = await _ocrService.ensureSampleSlipFile();
    await _enqueueAndExtractImage(samplePath, isBundledSample: true);
  }

  void _addManualBlankSlip() {
    setState(() {
      _draftQueue.add(SlipFormDraft());
      _selectedIndex = _draftQueue.length - 1;
    });
  }

  Future<void> _enqueueAndExtractImage(
    String rawPath, {
    bool isBundledSample = false,
  }) async {
    final persistedPath = isBundledSample
        ? rawPath
        : await _ocrService.persistSlipImage(rawPath);

    final draft = SlipFormDraft(
      imagePath: persistedPath,
      isProcessingOcr: true,
    );

    setState(() {
      _draftQueue.add(draft);
      _selectedIndex = _draftQueue.length - 1;
    });

    await _runOcrForDraft(draft, isBundledSample: isBundledSample);
  }

  Future<void> _runOcrForDraft(
    SlipFormDraft draft, {
    bool isBundledSample = false,
  }) async {
    if (draft.imagePath == null) return;
    setState(() {
      draft.isProcessingOcr = true;
    });

    final parsed = await _ocrService.extractSlipFromImage(
      draft.imagePath!,
      isBundledSample: isBundledSample,
    );

    if (!mounted) return;
    setState(() {
      draft.fullName = parsed.fullName;
      draft.phoneNumber = parsed.phoneNumber;
      draft.department = parsed.department;
      draft.invitedBy = parsed.invitedBy;
      draft.location = parsed.location;
      draft.prayerPoints = parsed.prayerPoints;
      draft.rawOcrText = parsed.reconstructedText;
      draft.ocrCandidates = parsed.candidateFragments;
      draft.extractionSource = parsed.extractionSource;
      draft.usedAiVision = parsed.usedAiVision;
      draft.warningMessage = parsed.warningMessage;
      draft.isProcessingOcr = false;
    });
  }

  void _removeCurrentDraft() {
    if (_draftQueue.isEmpty) return;
    setState(() {
      _draftQueue.removeAt(_selectedIndex);
      if (_selectedIndex >= _draftQueue.length && _draftQueue.isNotEmpty) {
        _selectedIndex = _draftQueue.length - 1;
      }
    });
  }

  Future<void> _saveCurrentSlipAndAdvance() async {
    if (_draftQueue.isEmpty || _isSaving) return;
    final current = _draftQueue[_selectedIndex];
    if (current.fullName.trim().isEmpty && current.phoneNumber.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter at least a Name or Phone Number.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await DatabaseService.instance.insertRecord(current.toRecord());
      if (!mounted) return;
      setState(() {
        _draftQueue.removeAt(_selectedIndex);
        if (_selectedIndex >= _draftQueue.length && _draftQueue.isNotEmpty) {
          _selectedIndex = _draftQueue.length - 1;
        }
        _isSaving = false;
      });

      if (_draftQueue.isEmpty) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Slip saved! ${_draftQueue.length} remaining in batch.',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving slip: $e')),
        );
      }
    }
  }

  Future<void> _saveEntireBatch() async {
    if (_draftQueue.isEmpty || _isSaving) return;
    final validDrafts = _draftQueue
        .where(
          (d) =>
              d.fullName.trim().isNotEmpty ||
              d.phoneNumber.trim().isNotEmpty ||
              d.department.trim().isNotEmpty,
        )
        .toList();

    if (validDrafts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No filled slips to save. Please check the fields.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final records = validDrafts.map((d) => d.toRecord()).toList();
      await DatabaseService.instance.insertBatch(records);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving batch: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _draftQueue.isEmpty
              ? 'Scan Newcomer\'s Slips'
              : 'Review Slip ${_selectedIndex + 1} of ${_draftQueue.length}',
        ),
        actions: [
          IconButton(
            tooltip: 'Batch Camera Scan',
            icon: const Icon(Icons.add_a_photo_outlined),
            onPressed: () => _captureFromCamera(continuousBatch: true),
          ),
          IconButton(
            tooltip: 'Add Multiple from Gallery',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: _pickMultiFromGallery,
          ),
          if (_draftQueue.isNotEmpty)
            IconButton(
              tooltip: 'Discard Current Slip',
              icon: const Icon(Icons.delete_outline),
              onPressed: _removeCurrentDraft,
            ),
        ],
      ),
      body: _draftQueue.isEmpty
          ? _buildEmptyScanLauncher(theme)
          : Column(
              children: [
                if (_draftQueue.length > 1) _buildBatchQueueStrip(theme),
                Expanded(
                  child: _draftQueue[_selectedIndex].isProcessingOcr
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Extracting handwritten slip with Gemini Vision AI...',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Reading Kingdom Life Chapel (OAU) Newcomer\'s Slip fields',
                                style: TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          child: SlipFormEditor(
                            key: ObjectKey(_draftQueue[_selectedIndex]),
                            draft: _draftQueue[_selectedIndex],
                            onChanged: () => setState(() {}),
                            onReRunOcr: () => _runOcrForDraft(
                              _draftQueue[_selectedIndex],
                            ),
                          ),
                        ),
                ),
              ],
            ),
      bottomNavigationBar: _draftQueue.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: Row(
                  children: [
                    if (_draftQueue.length > 1) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isSaving ? null : _saveEntireBatch,
                          icon: const Icon(Icons.done_all, size: 18),
                          label: Text('Save All (${_draftQueue.length})'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed:
                            _isSaving ? null : _saveCurrentSlipAndAdvance,
                        icon: Icon(
                          _draftQueue.length > 1
                              ? Icons.arrow_forward
                              : Icons.save_outlined,
                        ),
                        label: Text(
                          _draftQueue.length > 1
                              ? 'Save & Next Slip'
                              : 'Save to Local List',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildBatchQueueStrip(ThemeData theme) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _draftQueue.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final item = _draftQueue[index];
          final isSelected = index == _selectedIndex;
          final title = item.fullName.trim().isNotEmpty
              ? item.fullName.trim()
              : 'Slip #${index + 1}';

          return InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _selectedIndex = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outlineVariant,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.imagePath != null &&
                      File(item.imagePath!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(
                        File(item.imagePath!),
                        width: 40,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 40,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.description_outlined, size: 20),
                    ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.isProcessingOcr
                              ? 'Extracting...'
                              : (item.phoneNumber.isNotEmpty
                                    ? item.phoneNumber
                                    : 'Tap to review'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyScanLauncher(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.5,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 48,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI Handwriting Extraction',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Scan one or multiple Kingdom Life Chapel (OAU) Newcomer\'s Slips using Gemini Vision AI, review the extracted fields, and save them to your local database.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _captureFromCamera(continuousBatch: true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Batch Scan with Camera'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _pickMultiFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Select Multiple Slips from Gallery'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _loadBundledSampleSlip,
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Extract Uploaded Sample Slip'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _addManualBlankSlip,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Enter Slip Manually Without Photo'),
            ),
          ],
        ),
      ),
    );
  }
}
