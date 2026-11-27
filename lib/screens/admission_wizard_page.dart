import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/admission_repository.dart';
import '../data/admission_storage.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';

typedef AdmissionSaveOverride = Future<void> Function(
  Map<String, Map<String, String>> details,
  int step,
  bool complete,
);

/// A seven-tab admission wizard with horizontal page swipes and Cloud Firestore
/// drafts. Inputs are owned by the page, not individual tabs, so swipes never
/// discard entered values.
class AdmissionWizardPage extends StatefulWidget {
  const AdmissionWizardPage({
    super.key,
    required this.record,
    required this.classes,
    this.saveOverride,
  });

  final AdmissionRecord record;
  final List<SchoolClass> classes;

  /// Injected only by widget tests; live app always uses AdmissionRepository.
  final AdmissionSaveOverride? saveOverride;

  @override
  State<AdmissionWizardPage> createState() => _AdmissionWizardPageState();
}

class _AdmissionWizardPageState extends State<AdmissionWizardPage>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Student',
    'Contact',
    'Guardian',
    'Academic',
    'Health',
    'Documents',
    'Review',
  ];

  static const _accent = Color(0xFF7138D0);
  static const _background = Color(0xFFF6F4FB);
  static const _tint = Color(0xFFF1EBFC);
  static const _stepIcons = [
    Icons.person_outline_rounded, Icons.contact_phone_outlined,
    Icons.family_restroom_outlined, Icons.school_outlined,
    Icons.health_and_safety_outlined, Icons.folder_open_outlined,
    Icons.fact_check_outlined,
  ];

  static const _fields = [
    'student.firstName', 'student.middleName', 'student.lastName',
    'student.dateOfBirth', 'student.gender', 'student.nationality',
    'student.idType', 'student.idNumber',
    'contact.email', 'contact.phone', 'contact.whatsapp',
    'contact.city', 'contact.neighborhood', 'contact.street',
    'contact.postalCode', 'contact.country', 'contact.emergencyPhone',
    'guardian.firstName', 'guardian.middleName', 'guardian.lastName',
    'guardian.relationship', 'guardian.email', 'guardian.phone',
    'guardian.whatsapp', 'guardian.idNumber', 'guardian.occupation',
    'guardian.emergencyPhone',
    'academic.classId', 'academic.campus', 'academic.academicYear',
    'academic.term', 'academic.admissionDate', 'academic.previousSchool',
    'academic.previousGrade', 'academic.transcriptNotes',
    'health.medicalConditions', 'health.allergies', 'health.bloodGroup',
    'health.specialNeeds',
  ];

  final _inputs = <String, TextEditingController>{};
  late final AdmissionRepository _repository = AdmissionRepository();
  final _attachments = <String, Map<String, dynamic>>{};
  late final AdmissionStorage _storage = AdmissionStorage();
  final Set<String> _filesToDelete = <String>{};
  Uint8List? _localPhotoPreview;
  Future<Uint8List>? _remotePhotoPreview;
  bool _uploading = false;
  late final TabController _tabs;
  Future<void> _saveQueue = Future<void>.value();
  Timer? _debounce;
  bool _busy = false;
  bool _dirty = false;
  bool _closing = false;
  int _revision = 0;
  String _photoPath = '';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    for (final key in _fields) {
      final parts = key.split('.');
      final oldValue = widget.record.details[parts[0]]?[parts[1]] ?? '';
      String value = oldValue;
      if (value.isEmpty && key == 'academic.campus') value = 'Main';
      if (value.isEmpty && key == 'academic.academicYear') {
        value = '${today.year}–${today.year + 1}';
      }
      if (value.isEmpty && key == 'academic.admissionDate') {
        value = _dateString(today);
      }
      if (value.isEmpty && key == 'student.gender') value = 'Not specified';
      if (value.isEmpty && key == 'student.idType') value = 'Not specified';
      if (value.isEmpty && key == 'guardian.relationship') value = 'Father';
      if (value.isEmpty && key == 'academic.term') value = 'Annual';
      if (value.isEmpty && key == 'health.bloodGroup') value = 'Not specified';
      _inputs[key] = TextEditingController(text: value)..addListener(_edited);
    }
    _photoPath = widget.record.photoPath;
    _attachments.addAll(widget.record.attachments);
    _tabs = TabController(
      length: _steps.length,
      vsync: this,
      initialIndex: widget.record.step.clamp(0, _steps.length - 1),
    );
    _tabs.addListener(() {
      if (!mounted) return;
      setState(() {});
      _scheduleSave();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    for (final controller in _inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited() {
    _revision++;
    if (!_dirty && mounted) setState(() => _dirty = true);
    _scheduleSave();
  }

  void _scheduleSave() {
    if (widget.saveOverride != null) return; // tests remain deterministic
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () {
      if (!mounted || _busy || _uploading || _closing || !widget.record.isDraft) return;
      unawaited(_persist().catchError((Object error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Autosave: ${schoolErrorMessage(error)}')),
          );
        }
      }));
    });
  }

  TextEditingController _controller(String section, String key) =>
      _inputs['$section.$key']!;

  String _value(String section, String key) =>
      _controller(section, key).text.trim();

  void _assign(String section, String key, String value) {
    _controller(section, key).text = value;
  }

  Map<String, Map<String, String>> _collect() {
    final data = <String, Map<String, String>>{};
    for (final entry in _inputs.entries) {
      final parts = entry.key.split('.');
      data.putIfAbsent(parts[0], () => {})[parts[1]] = entry.value.text.trim();
    }
    return data;
  }

  Future<void> _persist({bool complete = false}) {
    final captured = _collect();
    final step = _tabs.index;
    final revision = _revision;
    final files = <String, Map<String, dynamic>>{
      for (final entry in _attachments.entries)
        entry.key: Map<String, dynamic>.from(entry.value),
    };
    final photo = _photoPath;

    final next = _saveQueue.then((_) async {
      if (widget.saveOverride != null) {
        await widget.saveOverride!(captured, step, complete);
      } else {
        await _repository.save(
          admission: widget.record,
          details: captured,
          currentStep: step,
          complete: complete,
          attachments: files,
          photoPath: photo,
        );
      }
    }).timeout(const Duration(seconds: 25));

    _saveQueue = next.catchError((Object _) {});
    return next.then((_) {
      if (mounted && revision == _revision) {
        setState(() => _dirty = false);
      }
    });
  }


  static const _documentLabels = <String, String>{
    'birth_certificate': 'Birth certificate',
    'transfer_certificate': 'Transfer certificate',
    'previous_school_certificate': 'Previous-school certificate',
    'medical_report': 'Medical certificate',
    'other': 'Other document',
  };

  void _mediaChanged() {
    _revision++;
    setState(() => _dirty = true);
  }

  void _queueDeletion(String path) {
    if (AdmissionStorage.isR2Path(path)) _filesToDelete.add(path);
  }

  /// Persist the new metadata BEFORE deleting replaced objects. The Worker
  /// also checks current Firestore references to prevent accidental removal.
  Future<void> _saveMediaChange() async {
    _debounce?.cancel();
    await _persist();
    for (final path in _filesToDelete.toList()) {
      try {
        await _storage.deleteFile(path);
        _filesToDelete.remove(path);
      } catch (_) {
        // Metadata is already saved. An orphan can be cleaned up later.
      }
    }
  }

  Future<void> _uploadPhoto() async {
    if (_busy || _uploading) return;
    setState(() => _uploading = true);
    try {
      final photo = await _storage.uploadProfilePhoto(widget.record.id);
      if (photo == null || !mounted) return;
      _queueDeletion(_photoPath);
      _photoPath = photo.path;
      _localPhotoPreview = photo.bytes;
      _remotePhotoPreview = null;
      _mediaChanged();
      await _saveMediaChange();
      _showMessage('Student photo saved securely.');
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_photoPath.isEmpty || _busy || _uploading) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove student photo?'),
        content: const Text('The photo will be removed from this student profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uploading = true);
    try {
      _queueDeletion(_photoPath);
      _photoPath = '';
      _localPhotoPreview = null;
      _remotePhotoPreview = null;
      _mediaChanged();
      await _saveMediaChange();
      _showMessage('Student photo removed.');
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _uploadDocument() async {
    if (_busy || _uploading) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Select document type'),
        children: [
          for (final entry in _documentLabels.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(entry.value),
              ),
            ),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await _storage.uploadDocument(widget.record.id, kind);
      if (uploaded == null || !mounted) return;
      final key = kind == 'other'
          ? 'other_' + DateTime.now().microsecondsSinceEpoch.toString()
          : kind;
      final previous = _attachments[key]?['path']?.toString() ?? '';
      _queueDeletion(previous);
      _attachments[key] = uploaded;
      _mediaChanged();
      await _saveMediaChange();
      _showMessage('Document uploaded and saved.');
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeDocument(String key) async {
    if (_busy || _uploading || !_attachments.containsKey(key)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this document?'),
        content: const Text('It will no longer be linked to the student profile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _uploading = true);
    try {
      _queueDeletion(_attachments[key]?['path']?.toString() ?? '');
      _attachments.remove(key);
      _mediaChanged();
      await _saveMediaChange();
      _showMessage('Document removed.');
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _viewDocument(Map<String, dynamic> file) async {
    if (_uploading) return;
    final path = file['path']?.toString() ?? '';
    if (path.isEmpty) return;
    setState(() => _uploading = true);
    try {
      final type = file['contentType']?.toString() ?? '';
      if (type.startsWith('image/')) {
        final bytes = await _storage.downloadFile(path);
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 440),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        final saved = await _storage.saveDocumentToDevice(file);
        if (saved) _showMessage('Document saved to the selected device location.');
      }
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Widget _photoThumbnail() {
    if (_photoPath.isEmpty) {
      return const CircleAvatar(radius: 37, backgroundColor: _tint, foregroundColor: _accent, child: Icon(Icons.person_outline, size: 35));
    }
    if (_localPhotoPreview != null) {
      return CircleAvatar(radius: 33,
        backgroundImage: MemoryImage(_localPhotoPreview!));
    }
    _remotePhotoPreview ??= _storage.downloadFile(_photoPath);
    return FutureBuilder<Uint8List>(
      future: _remotePhotoPreview,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircleAvatar(radius: 33,
            child: Icon(Icons.person_outline, size: 31));
        }
        return CircleAvatar(radius: 33,
          backgroundImage: MemoryImage(snapshot.data!));
      },
    );
  }

  Widget _photoPanel() => Card(
    margin: EdgeInsets.zero,
    color: _tint,
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Profile photo', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 9),
          Row(children: [
            _photoThumbnail(),
            const SizedBox(width: 14),
            Expanded(child: Text(
              _photoPath.isEmpty
                ? 'No photo selected. JPEG and PNG photos are compressed to WebP, maximum 100 KB.'
                : 'Photo securely attached to this student.',
              style: const TextStyle(fontSize: 11),
            )),
          ]),
          const SizedBox(height: 10),
          if (!AdmissionStorage.isConfigured)
            const Text('R2 upload is not configured in this APK.',
              style: TextStyle(fontSize: 11)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: _busy || _uploading || !AdmissionStorage.isConfigured
                  ? null : _uploadPhoto,
              icon: const Icon(Icons.add_a_photo_outlined, size: 18),
              label: Text(_photoPath.isEmpty ? 'Upload photo' : 'Replace photo'),
            ),
            if (_photoPath.isNotEmpty)
              TextButton.icon(
                onPressed: _busy || _uploading ? null : _removePhoto,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remove'),
              ),
          ]),
        ],
      ),
    ),
  );

  Widget _documentsPanel() => Card(
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Certificates and documents', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Birth, transfer, previous-school and medical certificates. PDF or image; maximum 5 MB each.',
            style: TextStyle(fontSize: 11)),
          const SizedBox(height: 8),
          if (_attachments.isEmpty)
            const Text('No documents uploaded.', style: TextStyle(fontSize: 12))
          else
            for (final entry in _attachments.entries)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(entry.value['name']?.toString() ?? 'Document',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_documentLabels[entry.value['kind']] ??
                    entry.key.replaceAll('_', ' ')),
                onTap: _uploading ? null : () => _viewDocument(entry.value),
                trailing: IconButton(
                  tooltip: 'Remove document',
                  onPressed: _uploading || _busy
                      ? null : () => _removeDocument(entry.key),
                  icon: const Icon(Icons.delete_outline),
                ),
              ),
          const SizedBox(height: 9),
          OutlinedButton.icon(
            onPressed: _busy || _uploading || !AdmissionStorage.isConfigured
                ? null : _uploadDocument,
            icon: const Icon(Icons.upload_file_outlined),
            label: Text(_uploading ? 'Uploading…' : 'Upload document'),
          ),
        ],
      ),
    ),
  );

  String? _requiredStepMessage(int step) {
    final data = _collect();
    String value(String section, String key) =>
        (data[section]?[key] ?? '').trim();
    if (step == 0) {
      if (value('student', 'firstName').isEmpty ||
          value('student', 'lastName').isEmpty) {
        return 'Enter the student’s first and last name.';
      }
      if (value('student', 'dateOfBirth').isEmpty) {
        return 'Select the student’s date of birth.';
      }
    }
    if (step == 2) {
      if (value('guardian', 'firstName').isEmpty ||
          value('guardian', 'lastName').isEmpty ||
          value('guardian', 'phone').isEmpty) {
        return 'Guardian first name, last name and phone are required.';
      }
    }
    if (step == 3) {
      if (value('academic', 'classId').isEmpty) return 'Choose a class and section.';
      if (value('academic', 'campus').isEmpty) return 'Enter the campus.';
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 5)),
    );
  }

  Future<void> _next() async {
    final error = _requiredStepMessage(_tabs.index);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (widget.record.isDraft) {
      await _performSave();
      if (!mounted || _dirty) return;
    }
    if (_tabs.index < _steps.length - 1) {
      _tabs.animateTo(_tabs.index + 1);
    }
  }

  Future<void> _performSave({bool complete = false}) async {
    if (_busy || _uploading) return;
    _debounce?.cancel();
    setState(() => _busy = true);
    try {
      await _persist(complete: complete);
      if (complete) {
        if (!mounted) return;
        setState(() => _closing = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop(true);
        });
      }
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish() async {
    if (_tabs.index != _steps.length - 1) {
      _tabs.animateTo(_steps.length - 1);
      return;
    }
    final validation = admissionValidationMessage(_collect());
    if (validation != null) {
      _showMessage(validation);
      if (_value('student', 'firstName').isEmpty ||
          _value('student', 'lastName').isEmpty ||
          _value('student', 'dateOfBirth').isEmpty) {
        _tabs.animateTo(0);
      } else if (_value('guardian', 'phone').isEmpty ||
          _value('guardian', 'firstName').isEmpty ||
          _value('guardian', 'lastName').isEmpty) {
        _tabs.animateTo(2);
      } else {
        _tabs.animateTo(3);
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.record.isDraft
            ? 'Confirm student admission'
            : 'Confirm student changes'),
        content: Text(widget.record.isDraft
            ? 'Review the information and admit this student? The record will be locked for everyone except the owner and principal.'
            : 'Save the reviewed changes to this admitted student record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.record.isDraft ? 'Apply admission' : 'Save changes'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _performSave(complete: true);
    }
  }

  Future<void> _saveAndClose() async {
    if (_busy || _uploading || _closing) return;
    _debounce?.cancel();
    setState(() => _busy = true);
    try {
      await _persist();
      if (!mounted) return;
      setState(() => _closing = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(false);
      });
    } catch (error) {
      _showMessage(schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _dateString(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate(String section, String name, {bool birth = false}) async {
    final current = DateTime.tryParse(_value(section, name));
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? (birth ? DateTime(today.year - 6, 1, 1) : today),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: birth ? 'Student date of birth' : 'Date of admission',
    );
    if (picked != null) _assign(section, name, _dateString(picked));
  }

  Widget _heading(String text, {String? hint}) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800, fontSize: 21,
          )),
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint, style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _field(
    String section,
    String key,
    String label, {
    bool required = false,
    TextInputType? type,
    int lines = 1,
    int maxLength = 100,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      controller: _controller(section, key),
      textCapitalization: type == TextInputType.emailAddress ||
              type == TextInputType.phone
          ? TextCapitalization.none : TextCapitalization.words,
      keyboardType: type,
      minLines: lines,
      maxLines: lines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: '$label${required ? " *" : ""}',
        hintText: hint,
        counterText: '',
      ),
    ),
  );

  Widget _choice(
    String section,
    String key,
    String label,
    List<String> options,
  ) {
    final chosen = _value(section, key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        value: options.contains(chosen) ? chosen : options.first,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: options.map((value) =>
            DropdownMenuItem(value: value, child: Text(value))).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _assign(section, key, value));
        },
      ),
    );
  }

  Widget _date(String section, String key, String label, {bool birth = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextFormField(
          readOnly: true,
          controller: _controller(section, key),
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: const Icon(Icons.calendar_month_outlined, size: 20),
          ),
          onTap: () => _pickDate(section, key, birth: birth),
        ),
      );

  Widget _readOnly(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    ),
  );

  // The existing input widgets and controllers remain the source of truth.
  // Only their arrangement changes with the available workspace width.
  Widget _fieldGrid(List<Widget> fields, {int columns = 2}) =>
    LayoutBuilder(builder: (context, limits) {
      final count = limits.maxWidth >= 840 ? columns :
          limits.maxWidth >= 500 ? 2 : 1;
      final width = (limits.maxWidth - (count - 1) * 16) / count;
      return Wrap(spacing: 16, runSpacing: 3, children: [
        for (final field in fields) SizedBox(width: width, child: field),
      ]);
    });

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(top: 9, bottom: 15),
    child: Row(children: [
      Container(width: 4, height: 18,
        decoration: BoxDecoration(color: _accent, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 9),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
    ]),
  );

  Widget _pane(String section, List<Widget> children) => ListView(
    key: PageStorageKey<String>('admission_$section'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Card(
            margin: EdgeInsets.zero, elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18),
              side: const BorderSide(color: Color(0xFFE5DFF1))),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _studentPane() => _pane('student', [
    _heading('Student personal details',
      hint: 'Names should match official identification. Fields marked * are required.'),
    const Divider(height: 24),
    LayoutBuilder(builder: (context, limits) {
      final photo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _photoPanel(),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _busy || _uploading ? null : () => _tabs.animateTo(5),
          icon: const Icon(Icons.upload_file_outlined, size: 18),
          label: const Text('Upload certificates & documents', textAlign: TextAlign.center),
        ),
      ]);
      final details = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _sectionTitle('Personal information'),
        _fieldGrid([
          _field('student', 'firstName', 'First name', required: true),
          _field('student', 'middleName', 'Middle name (optional)'),
          _field('student', 'lastName', 'Last name', required: true),
          _date('student', 'dateOfBirth', 'Date of birth *', birth: true),
          _choice('student', 'gender', 'Gender',
            ['Not specified', 'Male', 'Female', 'Other']),
          _field('student', 'nationality', 'Nationality'),
        ]),
        const Divider(height: 24),
        _sectionTitle('Identification'),
        _fieldGrid([
          _choice('student', 'idType', 'ID document type',
            ['Not specified', 'National ID', 'B-Form', 'Iqama', 'Passport', 'Other']),
          _field('student', 'idNumber', 'Student ID / passport number', maxLength: 40),
        ]),
      ]);
      if (limits.maxWidth >= 800) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: details), const SizedBox(width: 24),
          SizedBox(width: 250, child: photo),
        ]);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        photo, const SizedBox(height: 18), details,
      ]);
    }),
    const SizedBox(height: 4),
    const Text('Photo and certificates can also be managed in the Documents tab.',
      style: TextStyle(fontSize: 12)),
  ]);

  Widget _contactPane() => _pane('contact', [
    _heading('Contact and residential address',
      hint: 'Student contact details are optional. Guardian contacts are recorded in the next step.'),
    const Divider(height: 24),
    _sectionTitle('Contact information'),
    _fieldGrid([
      _field('contact', 'email', 'Student email', type: TextInputType.emailAddress),
      _field('contact', 'phone', 'Student phone', type: TextInputType.phone),
      _field('contact', 'whatsapp', 'Student WhatsApp', type: TextInputType.phone),
      _field('contact', 'emergencyPhone', 'Additional emergency phone', type: TextInputType.phone),
    ]),
    const Divider(height: 24),
    _sectionTitle('Residential address'),
    _field('contact', 'street', 'Street / house / building', maxLength: 180),
    _fieldGrid([
      _field('contact', 'neighborhood', 'Neighborhood / area'),
      _field('contact', 'city', 'City'),
      _field('contact', 'postalCode', 'Postal code', maxLength: 16),
      _field('contact', 'country', 'Country'),
    ]),
  ]);

  Widget _guardianPane() => _pane('guardian', [
    _heading('Parent or guardian',
      hint: 'The same parent account will later be able to link multiple children.'),
    const Divider(height: 24),
    _sectionTitle('Guardian information'),
    _fieldGrid([
      _field('guardian', 'firstName', 'First name', required: true),
      _field('guardian', 'middleName', 'Middle name (optional)'),
      _field('guardian', 'lastName', 'Last name', required: true),
      _choice('guardian', 'relationship', 'Relationship',
        ['Father', 'Mother', 'Brother', 'Sister', 'Grandparent',
         'Legal guardian', 'Uncle', 'Aunt', 'Other']),
      _field('guardian', 'idNumber', 'Guardian ID / passport number', maxLength: 40),
      _field('guardian', 'occupation', 'Occupation (optional)'),
    ]),
    const Divider(height: 24),
    _sectionTitle('Guardian contact'),
    _fieldGrid([
      _field('guardian', 'phone', 'Primary phone', required: true, type: TextInputType.phone),
      _field('guardian', 'whatsapp', 'WhatsApp number', type: TextInputType.phone),
      _field('guardian', 'emergencyPhone', 'Emergency phone', type: TextInputType.phone),
      _field('guardian', 'email', 'Guardian email', type: TextInputType.emailAddress),
    ]),
  ]);

  Widget _academicPane() => _pane('academic', [
    _heading('Registration and academic details',
      hint: 'Numbers are reserved automatically and cannot be edited.'),
    const Divider(height: 24),
    _sectionTitle('Registration'),
    _fieldGrid([
      _readOnly('Registration number', widget.record.registrationNo),
      _readOnly('Roll number (5 digits)', widget.record.rollNo),
    ]),
    _sectionTitle('Class placement'),
    _fieldGrid([
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: DropdownButtonFormField<String>(
          value: widget.classes.any((c) => c.id == _value('academic', 'classId'))
              ? _value('academic', 'classId') : '',
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class and section *'),
          items: [
            const DropdownMenuItem(value: '', child: Text('Select class / section')),
            ...widget.classes.map((c) =>
              DropdownMenuItem(value: c.id, child: Text(c.label))),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _assign('academic', 'classId', value));
          },
        ),
      ),
      _readOnly('Section', widget.classes.where((c) =>
        c.id == _value('academic', 'classId')).map((c) => c.section)
          .firstOrNull ?? 'Select a class'),
      _field('academic', 'campus', 'Campus', required: true),
      _field('academic', 'academicYear', 'Academic year', hint: 'e.g. 2026–2027'),
      _choice('academic', 'term', 'Term', ['Annual', 'Term 1', 'Term 2', 'Term 3']),
      _date('academic', 'admissionDate', 'Date of admission'),
    ]),
    const Divider(height: 24),
    _sectionTitle('Previous education'),
    _fieldGrid([
      _field('academic', 'previousSchool', 'Previous school / institution'),
      _field('academic', 'previousGrade', 'Previous grade / class'),
    ]),
    _field('academic', 'transcriptNotes', 'Previous results / transcripts', lines: 3, maxLength: 500),
  ]);

  Widget _healthPane() => _pane('health', [
    _heading('Health and special educational needs',
      hint: 'All fields are optional. Only collect what the school needs for student safety.'),
    const Divider(height: 24),
    _sectionTitle('Medical information'),
    _fieldGrid([
      _field('health', 'medicalConditions', 'Medical conditions', lines: 3, maxLength: 500),
      _field('health', 'allergies', 'Allergies / medication alerts', lines: 3, maxLength: 500),
      _choice('health', 'bloodGroup', 'Blood group',
        ['Not specified', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']),
    ]),
    _sectionTitle('Learning support'),
    _field('health', 'specialNeeds', 'Learning needs / accommodations', lines: 3, maxLength: 500),
  ]);

  static const _reviewLabels = <String, Map<String, String>>{
    'student': {
      'firstName': 'First name', 'middleName': 'Middle name',
      'lastName': 'Last name', 'dateOfBirth': 'Date of birth',
      'gender': 'Gender', 'nationality': 'Nationality',
      'idType': 'ID type', 'idNumber': 'Student ID number',
    },
    'contact': {
      'email': 'Student email', 'phone': 'Student phone',
      'whatsapp': 'Student WhatsApp', 'street': 'Street',
      'neighborhood': 'Neighborhood', 'city': 'City',
      'postalCode': 'Postal code', 'country': 'Country',
      'emergencyPhone': 'Emergency contact',
    },
    'guardian': {
      'firstName': 'First name', 'middleName': 'Middle name',
      'lastName': 'Last name', 'relationship': 'Relationship',
      'phone': 'Primary phone', 'whatsapp': 'WhatsApp',
      'emergencyPhone': 'Emergency phone', 'email': 'Email',
      'idNumber': 'Guardian ID number', 'occupation': 'Occupation',
    },
    'academic': {
      'campus': 'Campus', 'academicYear': 'Academic year',
      'term': 'Term', 'admissionDate': 'Admission date',
      'previousSchool': 'Previous school', 'previousGrade': 'Previous grade',
      'transcriptNotes': 'Previous results',
    },
    'health': {
      'medicalConditions': 'Medical conditions', 'allergies': 'Allergies',
      'bloodGroup': 'Blood group', 'specialNeeds': 'Special needs',
    },
  };

  Widget _documentsPane() => _pane('documents', [
    _heading('Student photos and documents',
      hint: 'Upload files during admission, or add and replace them when editing an existing student.'),
    _photoPanel(),
    _documentsPanel(),
    const Padding(
      padding: EdgeInsets.all(12),
      child: Text('Uploads are private and accessible only to authorized school accounts.'),
    ),
  ]);

  Widget _reviewPane() {
    final colors = Theme.of(context).colorScheme;
    final data = _collect();
    final classId = _value('academic', 'classId');
    final schoolClass = widget.classes.where((c) => c.id == classId);
    final className = schoolClass.isEmpty ? 'Not selected' : schoolClass.first.label;

    Widget section(String heading, String sectionName) {
      final labels = _reviewLabels[sectionName]!;
      final rows = labels.entries.where(
        (entry) => (data[sectionName]?[entry.key] ?? '').trim().isNotEmpty,
      ).toList();
      return Card(
        margin: const EdgeInsets.only(bottom: 11),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 9),
              if (rows.isEmpty)
                const Text('No information entered.',
                  style: TextStyle(fontSize: 11))
              else
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 9),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 128, child: Text(
                          row.value, style: TextStyle(
                            fontSize: 11, color: colors.onSurfaceVariant))),
                        Expanded(child: Text(data[sectionName]![row.key]!,
                          style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
            ],
          ),
        ),
      );
    }

    final validation = admissionValidationMessage(data);
    return _pane('review', [
      _heading('Review admission',
        hint: 'Check everything carefully before applying. Only the owner and principal can edit an admitted record.'),
      if (validation != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('Still required: $validation',
              style: TextStyle(fontSize: 12, color: colors.error)),
          ),
        ),
      _readOnly('Registration number', widget.record.registrationNo),
      _readOnly('Roll number', widget.record.rollNo),
      _readOnly('Class and section', className),
      section('Student personal details', 'student'),
      section('Contact and address', 'contact'),
      section('Parent or guardian', 'guardian'),
      section('Academic information', 'academic'),
      section('Health and special needs', 'health'),
      _photoPanel(),
      _documentsPanel(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final step = _tabs.index;
    final disabled = _busy || _uploading || _closing;
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_saveAndClose());
      },
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Save draft and close',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: disabled ? null : _saveAndClose,
          ),
          title: Text(widget.record.isDraft ? 'Add student' : 'Student record',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          actions: [
            TextButton.icon(
              onPressed: disabled ? null : _saveAndClose,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: Text(widget.record.isDraft ? 'Save draft' : 'Save changes'),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Center(child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Card(
                  margin: EdgeInsets.zero, elevation: 0,
                  child: Padding(padding: const EdgeInsets.all(13), child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(spacing: 16, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                        Text('Reg: ${widget.record.registrationNo}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('Roll: ${widget.record.rollNo}', style: TextStyle(color: color.onSurfaceVariant)),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(color: _tint, borderRadius: BorderRadius.circular(20)),
                          child: Text(widget.record.isDraft ? 'DRAFT' : 'ADMITTED',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: _accent))),
                        Text(_busy ? 'Saving…' : _dirty ? 'Unsaved changes' : 'Step ${step + 1} of ${_steps.length}',
                          style: TextStyle(fontSize: 11, color: color.onSurfaceVariant)),
                      ]),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(value: (step + 1) / _steps.length,
                        color: _accent, backgroundColor: _tint, minHeight: 5,
                        borderRadius: BorderRadius.circular(8)),
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, limits) {
                        final wide = limits.maxWidth >= 720;
                        return TabBar(
                          controller: _tabs,
                          isScrollable: !wide,
                          tabAlignment: wide ? TabAlignment.fill : TabAlignment.start,
                          labelColor: _accent,
                          unselectedLabelColor: color.onSurfaceVariant,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 10),
                          indicatorColor: _accent,
                          dividerColor: Colors.transparent,
                          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          unselectedLabelStyle: const TextStyle(fontSize: 12),
                          tabs: [
                            for (var i = 0; i < _steps.length; i++)
                              Tab(icon: Icon(_stepIcons[i], size: 21),
                                text: '${i + 1}. ${_steps[i]}'),
                          ],
                        );
                      }),
                    ],
                  )),
                ),
              )),
            ),
            Expanded(child: TabBarView(
              controller: _tabs,
              children: [
                _studentPane(), _contactPane(), _guardianPane(), _academicPane(),
                _healthPane(), _documentsPane(), _reviewPane(),
              ],
            )),
          ]),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: color.surface,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Center(heightFactor: 1, child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: LayoutBuilder(builder: (context, limits) {
                  final wide = limits.maxWidth >= 600;
                  return Row(children: [
                    if (step > 0) ...[
                      if (wide) OutlinedButton.icon(
                        onPressed: disabled ? null : () => _tabs.animateTo(step - 1),
                        icon: const Icon(Icons.arrow_back, size: 17), label: const Text('Back'))
                      else IconButton(tooltip: 'Back',
                        onPressed: disabled ? null : () => _tabs.animateTo(step - 1),
                        icon: const Icon(Icons.arrow_back)),
                      const SizedBox(width: 8),
                    ],
                    if (wide) ...[
                      Text('Step ${step + 1} of ${_steps.length}', style: TextStyle(color: color.onSurfaceVariant)),
                      const Spacer(),
                    ],
                    Flexible(flex: wide ? 0 : 1, fit: FlexFit.tight, child: OutlinedButton(
                      onPressed: disabled ? null : _saveAndClose,
                      child: Text(_busy ? 'Saving…' : widget.record.isDraft ? 'Save draft' : 'Save changes'),
                    )),
                    const SizedBox(width: 10),
                    Flexible(flex: wide ? 0 : 1, fit: FlexFit.tight, child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
                        minimumSize: const Size(100, 46)),
                      onPressed: disabled ? null : step == _steps.length - 1 ? _finish : _next,
                      child: Text(step == _steps.length - 1
                        ? widget.record.isDraft ? 'Review & admit' : 'Save reviewed changes'
                        : widget.record.isDraft ? 'Save & next' : 'Next', textAlign: TextAlign.center),
                    )),
                  ]);
                }),
              )),
            ),
          ),
        ),
      ),
    );
  }
}
