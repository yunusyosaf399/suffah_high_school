import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../data/admission_repository.dart';
import '../data/admission_storage.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';
import 'admission_wizard_page.dart';

bool canEditAdmittedStudent(String role) =>
    role == 'owner' || role == 'principal';

/// Read-only presentation is the default for every admitted student.
/// An authenticated owner/principal can explicitly open the edit wizard.
/// Firestore rules separately enforce the same authorization server-side.
class StudentProfilePage extends StatefulWidget {
  const StudentProfilePage({
    super.key,
    required this.studentId,
    required this.role,
    required this.classes,
    this.initialRecord,
    this.onEditOverride,
  });

  final String studentId;
  final String role;
  final List<SchoolClass> classes;
  final AdmissionRecord? initialRecord;
  final Future<void> Function()? onEditOverride;

  @override
  State<StudentProfilePage> createState() => _StudentProfilePageState();
}

class _StudentProfilePageState extends State<StudentProfilePage> {
  late final AdmissionRepository _repository = AdmissionRepository();
  late final AdmissionStorage _storage = AdmissionStorage();
  String? _photoCachePath;
  Future<Uint8List>? _photoCache;
  late Future<AdmissionRecord> _recordFuture = widget.initialRecord != null
      ? Future.value(widget.initialRecord!)
      : _repository.load(widget.studentId);

  void _reload() {
    if (!mounted) return;
    setState(() => _recordFuture = _repository.load(widget.studentId));
  }

  Future<void> _edit(AdmissionRecord record) async {
    if (!canEditAdmittedStudent(widget.role)) return;
    if (widget.onEditOverride != null) {
      await widget.onEditOverride!();
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdmissionWizardPage(
          record: record,
          classes: widget.classes,
        ),
      ),
    );
    if (mounted && changed != null) _reload();
  }

  static const _groups = <String, Map<String, String>>{
    'student': {
      'firstName': 'First name', 'middleName': 'Middle name',
      'lastName': 'Last name', 'dateOfBirth': 'Date of birth',
      'gender': 'Gender', 'nationality': 'Nationality',
      'idType': 'ID type', 'idNumber': 'Student ID / passport',
    },
    'contact': {
      'email': 'Student email', 'phone': 'Phone', 'whatsapp': 'WhatsApp',
      'street': 'Street / house', 'neighborhood': 'Neighborhood',
      'city': 'City', 'postalCode': 'Postal code', 'country': 'Country',
      'emergencyPhone': 'Emergency phone',
    },
    'guardian': {
      'firstName': 'First name', 'middleName': 'Middle name',
      'lastName': 'Last name', 'relationship': 'Relationship',
      'phone': 'Primary phone', 'whatsapp': 'WhatsApp',
      'emergencyPhone': 'Emergency phone', 'email': 'Email',
      'idNumber': 'Guardian ID', 'occupation': 'Occupation',
    },
    'academic': {
      'campus': 'Campus', 'academicYear': 'Academic year', 'term': 'Term',
      'admissionDate': 'Date of admission',
      'previousSchool': 'Previous school', 'previousGrade': 'Previous grade',
      'transcriptNotes': 'Previous results / transcript',
    },
    'health': {
      'medicalConditions': 'Medical conditions', 'allergies': 'Allergies',
      'bloodGroup': 'Blood group', 'specialNeeds': 'Learning accommodations',
    },
  };

  Widget _photo(String photoPath, String name) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    if (photoPath.isEmpty) {
      return CircleAvatar(
        radius: 35,
        child: Text(initial, style: const TextStyle(
          fontSize: 27, fontWeight: FontWeight.w700)),
      );
    }
    if (_photoCachePath != photoPath) {
      _photoCachePath = photoPath;
      _photoCache = _storage.downloadFile(photoPath);
    }
    return FutureBuilder<Uint8List>(
      future: _photoCache,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const CircleAvatar(
            radius: 35, child: Icon(Icons.person_outline, size: 34));
        }
        return CircleAvatar(
          radius: 35,
          backgroundImage: MemoryImage(snapshot.data!),
        );
      },
    );
  }

  Future<void> _openDocument(Map<String, dynamic> file) async {
    try {
      final path = (file['path'] ?? '').toString();
      if (path.isEmpty) throw StateError('This document has no storage path.');
      final type = (file['contentType'] ?? '').toString();
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
                  TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('Close')),
                ],
              ),
            ),
          ),
        );
      } else {
        await _storage.saveDocumentToDevice(file);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document saved to your device.')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))),
      );
    }
  }

  Widget _section(
    BuildContext context,
    String title,
    String section,
    Map<String, Map<String, String>> details,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final labels = _groups[section]!;
    return Card(
      margin: const EdgeInsets.only(bottom: 11),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final twoColumns = box.maxWidth >= 540;
                final cellWidth = twoColumns
                    ? (box.maxWidth - 16) / 2 : box.maxWidth;
                return Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    for (final label in labels.entries)
                      SizedBox(
                        width: cellWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label.value, style: TextStyle(
                              fontSize: 10, color: scheme.onSurfaceVariant)),
                            const SizedBox(height: 3),
                            SelectableText(
                              (details[section]?[label.key] ?? '').trim().isEmpty
                                  ? 'Not provided'
                                  : details[section]![label.key]!,
                              style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfile(BuildContext context, AdmissionRecord record) {
    final scheme = Theme.of(context).colorScheme;
    final details = record.details;
    final name = admissionFullName(details['student'] ?? {});
    final classId = details['academic']?['classId'] ?? '';
    final selected = widget.classes.where((c) => c.id == classId);
    final classLabel = selected.isEmpty ? 'Class not specified' : selected.first.label;
    final locked = record.status == 'admitted';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 930),
        child: ListView(
          key: const Key('student_profile_sections'),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _photo(record.photoPath, name),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isEmpty ? record.registrationNo : name,
                                style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 4),
                              Text(classLabel,
                                style: TextStyle(fontSize: 12,
                                    color: scheme.onSurfaceVariant)),
                              const SizedBox(height: 5),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(locked ? Icons.lock_outline : Icons.edit_note,
                                    size: 15, color: scheme.primary),
                                  const SizedBox(width: 5),
                                  Text(locked ? record.active ? 'Admitted · Details locked' : 'Archived · Details locked' : 'Draft',
                                    style: TextStyle(fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: scheme.primary)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _summaryItem(
                          'Registration', record.registrationNo)),
                        const SizedBox(width: 12),
                        Expanded(child: _summaryItem('Roll no.', record.rollNo)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      canEditAdmittedStudent(widget.role)
                          ? 'Read-only profile. Select Edit student to make authorized changes.'
                          : 'This student profile is read-only.',
                      style: TextStyle(
                        fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    if (canEditAdmittedStudent(widget.role)) ...[
                      const SizedBox(height: 11),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _edit(record),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Edit student'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            _section(context, 'Student information', 'student', details),
            _section(context, 'Contact and address', 'contact', details),
            _section(context, 'Parent / guardian', 'guardian', details),
            _section(context, 'Academic information', 'academic', details),
            _section(context, 'Health and special needs', 'health', details),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Documents', style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 9),
                    if (record.attachments.isEmpty)
                      const Text('No documents uploaded.',
                        style: TextStyle(fontSize: 12))
                    else
                      for (final file in record.attachments.entries)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined),
                          title: Text(
                            file.value['name']?.toString() ?? file.key,
                            style: const TextStyle(fontSize: 12)),
                          subtitle: Text(file.key.replaceAll('_', ' '),
                            style: const TextStyle(fontSize: 11)),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => _openDocument(file.value),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryItem(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 10)),
      const SizedBox(height: 4),
      SelectableText(value.isEmpty ? '—' : value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Student profile', style: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w700)),
      actions: [
        IconButton(
          tooltip: 'Refresh profile',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<AdmissionRecord>(
        future: _recordFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(schoolErrorMessage(snapshot.error!),
                      textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _reload,
                      child: const Text('Retry loading'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildProfile(context, snapshot.data!);
        },
      ),
    ),
  );
}
