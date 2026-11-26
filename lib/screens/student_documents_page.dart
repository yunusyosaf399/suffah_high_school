import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/admission_storage.dart';
import '../data/school_errors.dart';
import '../data/student_documents_repository.dart';

class StudentDocumentsPage extends StatefulWidget {
  const StudentDocumentsPage({super.key, required this.role, this.folderLoader});
  final String role;
  final Future<List<StudentDocumentFolder>> Function()? folderLoader;

  @override
  State<StudentDocumentsPage> createState() => _StudentDocumentsPageState();
}

class _StudentDocumentsPageState extends State<StudentDocumentsPage> {
  late final StudentDocumentsRepository _repository = StudentDocumentsRepository();
  late final AdmissionStorage _storage = AdmissionStorage();
  late Future<List<StudentDocumentFolder>> _folders = _load();
  String _query = '';
  String _classFilter = '';
  bool _withFilesOnly = false;
  bool _busy = false;

  Future<List<StudentDocumentFolder>> _load() =>
      widget.folderLoader?.call() ?? _repository.loadFolders();

  void _refresh() => setState(() => _folders = _load());

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirm(String title, String detail, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title), content: Text(detail),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true),
                child: Text(action)),
          ],
        ),
      ) ?? false;

  Future<void> _cleanup(String path) async {
    if (!AdmissionStorage.isR2Path(path)) return;
    try {
      await _storage.deleteFile(path);
    } catch (_) {
      _message('Student record updated, but old file cleanup failed.');
    }
  }

  Future<void> _upload(StudentDocumentFolder folder) async {
    if (_busy || !canManageStudentDocuments(widget.role)) return;
    final kind = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choose document type'),
        children: [
          for (final entry in studentDocumentKinds.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry.key),
              child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(entry.value)),
            ),
        ],
      ),
    );
    if (!mounted || kind == null || _busy) return;
    final key = kind == 'other' ? 'other_${DateTime.now().microsecondsSinceEpoch}' : kind;
    final previous = folder.attachments[key];
    if (previous != null && !await _confirm('Replace document?',
        'Replace the existing ${studentDocumentKinds[kind]} for ${folder.name}?', 'Replace')) return;
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final file = await _storage.uploadDocument(folder.id, kind);
      if (file == null) return;
      final oldPath = previous?['path']?.toString() ?? '';
      await _repository.changeAttachment(studentId: folder.id, key: key,
          expectedPath: oldPath, replacement: file);
      _message('Document saved for ${folder.name}.');
      if (mounted) _refresh();
      if (oldPath != file['path']) await _cleanup(oldPath);
    } catch (error) {
      _message(schoolErrorMessage(error));
      // Do not delete an uploaded object when the commit outcome is uncertain.
      if (mounted) _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(StudentDocumentFolder folder, String key,
      Map<String, dynamic> file) async {
    if (_busy || !canManageStudentDocuments(widget.role)) return;
    final name = file['name']?.toString() ?? 'this document';
    if (!await _confirm('Remove document?',
        'Remove $name from ${folder.name}’s folder? This cannot be undone.', 'Remove')) return;
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    try {
      final path = file['path']?.toString() ?? '';
      await _repository.changeAttachment(studentId: folder.id, key: key,
          expectedPath: path, replacement: null);
      _message('Document removed.');
      if (mounted) _refresh();
      await _cleanup(path);
    } catch (error) {
      _message(schoolErrorMessage(error));
      if (mounted) _refresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _preview(StudentDocumentFolder folder, Map<String, dynamic> file) {
    if (_busy) return;
    final path = file['path']?.toString() ?? '';
    if (path.isEmpty) {
      _message('This document has no storage path.');
      return;
    }
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => _DocumentPreview(
        student: folder, file: file, storage: _storage,
      ),
    ));
  }

  Widget _fileTile(StudentDocumentFolder folder, String key,
      Map<String, dynamic> file, {bool photo = false}) {
    final name = file['name']?.toString() ?? 'Document';
    final type = file['contentType']?.toString() ?? '';
    final image = photo || type.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(name);
    final bytes = file['bytes'];
    final label = photo ? 'Profile photo' : StudentDocumentFolder.documentKindLabel(key, file);
    return ListTile(
      leading: Icon(image ? Icons.image_outlined : Icons.picture_as_pdf_outlined,
          color: Theme.of(context).colorScheme.primary),
      title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(bytes is num ? '$label • ${(bytes / 1024).toStringAsFixed(1)} KB' : label),
      onTap: _busy ? null : () => _preview(folder, file),
      trailing: photo
          ? const Icon(Icons.chevron_right)
          : IconButton(tooltip: 'Remove document',
              onPressed: _busy ? null : () => _remove(folder, key, file),
              icon: const Icon(Icons.delete_outline)),
    );
  }

  Widget _folder(StudentDocumentFolder folder) {
    final subtitle = [
      folder.registrationNo,
      if (folder.rollNo.isNotEmpty) 'Roll ${folder.rollNo}',
      if (folder.classLabel.isNotEmpty) folder.classLabel,
      if (folder.status == 'draft') 'Draft' else if (!folder.active) 'Archived',
      '${folder.fileCount} files',
    ].join(' • ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('documents-folder-${folder.id}'),
        leading: const Icon(Icons.folder_rounded, size: 36, color: Color(0xFFD89B30)),
        title: Text(folder.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        children: [
          if (folder.fileCount == 0)
            const Padding(padding: EdgeInsets.all(16), child: Text('No files uploaded.')),
          if (folder.photoPath.isNotEmpty)
            _fileTile(folder, 'photo', {
              'name': 'Profile photo.webp', 'path': folder.photoPath,
              'contentType': 'image/webp',
            }, photo: true),
          for (final entry in folder.attachments.entries)
            _fileTile(folder, entry.key, entry.value),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: OutlinedButton.icon(
                onPressed: _busy || !AdmissionStorage.isConfigured
                    ? null : () => _upload(folder),
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Upload document'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!canManageStudentDocuments(widget.role)) {
      return Scaffold(appBar: AppBar(title: const Text('Documents')),
        body: const Center(child: Text('Only the owner or principal can manage student documents.')));
    }
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Documents'),
        actions: [IconButton(tooltip: 'Refresh folders',
          onPressed: _busy ? null : _refresh, icon: const Icon(Icons.refresh))]),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: FutureBuilder<List<StudentDocumentFolder>>(
              future: _folders,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(schoolErrorMessage(snapshot.error!), textAlign: TextAlign.center),
                      TextButton(onPressed: _refresh, child: const Text('Retry')),
                    ]),
                  ));
                }
                final all = snapshot.data ?? const <StudentDocumentFolder>[];
                final classes = all.map((f) => f.classLabel)
                    .where((v) => v.isNotEmpty).toSet().toList()..sort();
                final visible = all.where((f) => f.matches(_query) &&
                    (_classFilter.isEmpty || !classes.contains(_classFilter) || f.classLabel == _classFilter) &&
                    (!_withFilesOnly || f.fileCount > 0)).toList();
                final count = all.fold<int>(0, (sum, f) => sum + f.fileCount);
                return Column(children: [
                  if (_busy) const LinearProgressIndicator(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Student document library', style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('${all.length} student folders • $count files',
                          style: TextStyle(color: colors.onSurfaceVariant)),
                      if (!AdmissionStorage.isConfigured && widget.folderLoader == null)
                        const Padding(padding: EdgeInsets.only(top: 8),
                          child: Text('File storage is not configured in this build. Set R2_WORKER_URL to preview or upload files.')),
                      const SizedBox(height: 14),
                      TextField(
                        key: const Key('documents_search'),
                        onChanged: (value) => setState(() => _query = value),
                        decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
                          hintText: 'Search student, admission no. or file'),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: classes.contains(_classFilter) ? _classFilter : '',
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Class'),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('All classes')),
                          for (final name in classes)
                            DropdownMenuItem(value: name, child: Text(name, overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) => setState(() => _classFilter = value ?? ''),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Only folders with files'),
                        value: _withFilesOnly,
                        onChanged: (value) => setState(() => _withFilesOnly = value),
                      ),
                    ]),
                  ),
                  Expanded(child: visible.isEmpty
                      ? Center(child: Text(all.isEmpty ? 'No student records yet.' : 'No matching folders.'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                          itemCount: visible.length,
                          itemBuilder: (context, index) => _folder(visible[index]),
                        )),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentPreview extends StatefulWidget {
  const _DocumentPreview({required this.student, required this.file, required this.storage});
  final StudentDocumentFolder student;
  final Map<String, dynamic> file;
  final AdmissionStorage storage;

  @override
  State<_DocumentPreview> createState() => _DocumentPreviewState();
}

class _DocumentPreviewState extends State<_DocumentPreview> {
  late Future<Uint8List> _bytes = _download();
  bool _saving = false;

  Future<Uint8List> _download() =>
      widget.storage.downloadFile(widget.file['path'].toString());

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.storage.saveDocumentToDevice(widget.file);
      if (mounted && saved) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Document saved to your device.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(schoolErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.file['name']?.toString() ?? 'Document';
    final type = widget.file['contentType']?.toString() ?? '';
    final pdf = type == 'application/pdf' || name.toLowerCase().endsWith('.pdf');
    final image = type.startsWith('image/') ||
        RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(name);
    return Scaffold(
      appBar: AppBar(title: const Text('Document preview'),
        actions: [IconButton(tooltip: 'Save to device', onPressed: _saving ? null : _save,
          icon: const Icon(Icons.download_outlined))]),
      body: SafeArea(child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 4),
              Text('${widget.student.name} • ${widget.student.registrationNo}'),
              if (widget.student.classLabel.isNotEmpty) Text(widget.student.classLabel),
            ]),
          ),
          const Divider(height: 1),
          Expanded(child: FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return Center(child: Padding(padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(snapshot.hasError ? schoolErrorMessage(snapshot.error!) : 'No file data.'),
                    TextButton(onPressed: () => setState(() => _bytes = _download()),
                        child: const Text('Retry preview')),
                  ])));
              }
              final bytes = snapshot.data!;
              if (pdf) return PdfViewer.data(bytes, sourceName: 'student-document');
              if (image) return InteractiveViewer(
                minScale: 0.5, maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Text('This image could not be opened.'))),
              );
              return const Center(child: Text('Preview is unavailable for this file type. Use Save to device.'));
            },
          )),
        ],
      )),
    );
  }
}
