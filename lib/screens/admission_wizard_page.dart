import 'dart:async';

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

/// A six-tab admission wizard with horizontal page swipes and Cloud Firestore
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
  late final AdmissionStorage _storage = AdmissionStorage();
  final _attachments = <String, Map<String, dynamic>>{};
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
      if (!mounted || _busy || _closing) return;
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
    await _performSave();
    if (!mounted || _dirty) return;
    if (_tabs.index < _steps.length - 1) {
      _tabs.animateTo(_tabs.index + 1);
    }
  }

  Future<void> _performSave({bool complete = false}) async {
    if (_busy) return;
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
    await _performSave(complete: true);
  }

  Future<void> _saveAndClose() async {
    if (_busy || _closing) return;
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
            fontWeight: FontWeight.w800,
          )),
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint, style: TextStyle(fontSize: 11, color: color.onSurfaceVariant)),
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

  Widget _pane(String section, List<Widget> children) => ListView(
    key: PageStorageKey<String>('admission_$section'),
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 34),
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 710),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    ],
  );

  Widget _studentPane() => _pane('student', [
    _heading('Student personal details',
      hint: 'Names should match official identification. Middle name is optional.'),
    _field('student', 'firstName', 'First name', required: true),
    _field('student', 'middleName', 'Middle name (optional)'),
    _field('student', 'lastName', 'Last name', required: true),
    _date('student', 'dateOfBirth', 'Date of birth *', birth: true),
    _choice('student', 'gender', 'Gender',
      ['Not specified', 'Male', 'Female', 'Other']),
    _field('student', 'nationality', 'Nationality'),
    _choice('student', 'idType', 'ID document type',
      ['Not specified', 'National ID', 'B-Form', 'Iqama', 'Passport', 'Other']),
    _field('student', 'idNumber', 'Student ID / passport number', maxLength: 40),
    const SizedBox(height: 4),
    const Text('A passport-style profile photo can be added under Documents.',
      style: TextStyle(fontSize: 11)),
  ]);

  Widget _contactPane() => _pane('contact', [
    _heading('Contact and residential address',
      hint: 'Student contact details are optional. Guardian contacts are recorded in the next step.'),
    _field('contact', 'email', 'Student email',
      type: TextInputType.emailAddress),
    _field('contact', 'phone', 'Student phone', type: TextInputType.phone),
    _field('contact', 'whatsapp', 'Student WhatsApp', type: TextInputType.phone),
    _field('contact', 'street', 'Street / house / building', maxLength: 180),
    _field('contact', 'neighborhood', 'Neighborhood / area'),
    _field('contact', 'city', 'City'),
    _field('contact', 'postalCode', 'Postal code', maxLength: 16),
    _field('contact', 'country', 'Country'),
    _field('contact', 'emergencyPhone', 'Additional emergency phone',
      type: TextInputType.phone),
  ]);

  Widget _guardianPane() => _pane('guardian', [
    _heading('Parent or guardian',
      hint: 'The same parent account will later be able to link multiple children.'),
    _field('guardian', 'firstName', 'First name', required: true),
    _field('guardian', 'middleName', 'Middle name (optional)'),
    _field('guardian', 'lastName', 'Last name', required: true),
    _choice('guardian', 'relationship', 'Relationship',
      ['Father', 'Mother', 'Brother', 'Sister', 'Grandparent',
       'Legal guardian', 'Uncle', 'Aunt', 'Other']),
    _field('guardian', 'phone', 'Primary phone', required: true,
      type: TextInputType.phone),
    _field('guardian', 'whatsapp', 'WhatsApp number', type: TextInputType.phone),
    _field('guardian', 'emergencyPhone', 'Emergency phone', type: TextInputType.phone),
    _field('guardian', 'email', 'Guardian email', type: TextInputType.emailAddress),
    _field('guardian', 'idNumber', 'Guardian ID / passport number',
      maxLength: 40),
    _field('guardian', 'occupation', 'Occupation (optional)'),
  ]);

  Widget _academicPane() => _pane('academic', [
    _heading('Registration and academic details',
      hint: 'Numbers are reserved automatically and cannot be edited.'),
    _readOnly('Registration number', widget.record.registrationNo),
    _readOnly('Roll number (5 digits)', widget.record.rollNo),
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
    _readOnly(
      'Section',
      widget.classes.where((c) =>
        c.id == _value('academic', 'classId')).map((c) => c.section)
          .firstOrNull ?? 'Select a class',
    ),
    _field('academic', 'campus', 'Campus', required: true),
    _field('academic', 'academicYear', 'Academic year',
      hint: 'e.g. 2026–2027'),
    _choice('academic', 'term', 'Term',
      ['Annual', 'Term 1', 'Term 2', 'Term 3']),
    _date('academic', 'admissionDate', 'Date of admission'),
    _field('academic', 'previousSchool', 'Previous school / institution'),
    _field('academic', 'previousGrade', 'Previous grade / class'),
    _field('academic', 'transcriptNotes', 'Previous results / transcripts',
      lines: 3, maxLength: 500),
  ]);

  Widget _healthPane() => _pane('health', [
    _heading('Health and special educational needs',
      hint: 'All fields are optional. Only collect what the school needs for student safety.'),
    _field('health', 'medicalConditions', 'Medical conditions',
      lines: 3, maxLength: 500),
    _field('health', 'allergies', 'Allergies / medication alerts',
      lines: 3, maxLength: 500),
    _choice('health', 'bloodGroup', 'Blood group',
      ['Not specified', 'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-']),
    _field('health', 'specialNeeds', 'Learning needs / accommodations',
      lines: 3, maxLength: 500),
  ]);

  Future<void> _uploadPhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _storage.uploadProfilePhoto(widget.record.registrationNo);
      if (path == null) return;
      _photoPath = path;
      _revision++;
      await _persist();
      _showMessage('Student photo uploaded successfully.');
    } catch (error) {
      _showMessage('Photo upload unavailable: ${schoolErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadDocument(String type) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await _storage.uploadDocument(
        widget.record.registrationNo, type);
      if (file == null) return;
      _attachments[type] = file;
      _revision++;
      await _persist();
      _showMessage('Document uploaded successfully.');
    } catch (error) {
      _showMessage('Upload unavailable: ${schoolErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _documentsPane() {
    const kinds = {
      'birth_certificate': 'Birth certificate',
      'student_id': 'Student ID / B-Form',
      'guardian_id': 'Parent / guardian ID',
      'previous_transcript': 'Previous results / transcript',
      'transfer_certificate': 'Transfer certificate',
      'other': 'Other document',
    };
    final colors = Theme.of(context).colorScheme;
    return _pane('documents', [
      _heading('Photos and supporting documents',
        hint: 'Optional. Save admission drafts even when document storage is not enabled.'),
      Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.account_circle_outlined, size: 36,
                color: colors.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Passport-style photo',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_photoPath.isEmpty
                      ? 'Not uploaded • WebP, maximum 100 KB'
                      : 'Photo uploaded',
                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                ],
              )),
              TextButton(onPressed: _busy ? null : _uploadPhoto,
                child: Text(_photoPath.isEmpty ? 'Upload' : 'Replace')),
            ],
          ),
        ),
      ),
      for (final entry in kinds.entries)
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Icon(_attachments.containsKey(entry.key)
                ? Icons.check_circle_outline_rounded
                : Icons.description_outlined, color: colors.primary),
            title: Text(entry.value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _attachments[entry.key]?['name']?.toString()
                  ?? 'PDF or image • maximum 5 MB',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
            trailing: TextButton(
              onPressed: _busy ? null : () => _uploadDocument(entry.key),
              child: Text(_attachments.containsKey(entry.key)
                  ? 'Replace' : 'Upload'),
            ),
          ),
        ),
      const SizedBox(height: 13),
      Text(
        'Cloud Storage requires Firebase Blaze billing and the school’s '
        'Storage access rules. If uploads are unavailable, finish the '
        'admission now and attach documents later.',
        style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return PopScope(
      canPop: _closing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_saveAndClose());
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: 'Save draft and close',
            icon: const Icon(Icons.close_rounded),
            onPressed: _busy ? null : _saveAndClose,
          ),
          title: Text(widget.record.isDraft ? 'New admission' : 'Student record',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          actions: [
            TextButton(
              onPressed: _busy ? null : _saveAndClose,
              child: const Text('Save draft'),
            ),
            const SizedBox(width: 6),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(107),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 9),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Reg: ${widget.record.registrationNo}',
                          style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800)),
                      ),
                      Text('Roll: ${widget.record.rollNo}',
                        style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
                      const SizedBox(width: 10),
                      Text(widget.record.isDraft ? 'DRAFT' : 'ADMITTED',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: color.primary)),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: (_tabs.index + 1) / _steps.length,
                  minHeight: 3,
                ),
                TabBar(
                  controller: _tabs,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: const TextStyle(fontSize: 12),
                  tabs: [
                    for (var i = 0; i < _steps.length; i++)
                      Tab(text: '${i + 1}. ${_steps[i]}'),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            controller: _tabs,
            children: [
              _studentPane(),
              _contactPane(),
              _guardianPane(),
              _academicPane(),
              _healthPane(),
              _documentsPane(),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Row(
                  children: [
                    if (_tabs.index > 0) ...[
                      OutlinedButton(
                        onPressed: _busy
                            ? null : () => _tabs.animateTo(_tabs.index - 1),
                        child: const Text('Back'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _saveAndClose,
                        icon: const Icon(Icons.save_outlined, size: 18),
                        label: Text(_busy ? 'Saving…' : 'Save draft'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null
                            : _tabs.index == _steps.length - 1 ? _finish : _next,
                        child: Text(_tabs.index == _steps.length - 1
                            ? 'Complete' : 'Save & next'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
