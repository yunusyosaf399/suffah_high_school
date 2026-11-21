import 'dart:async';

import 'package:flutter/material.dart';
import '../data/school_repository.dart';
import '../data/school_errors.dart';

class ClassesPage extends StatefulWidget {
  const ClassesPage({super.key, this.classesStream});

  final Stream<List<SchoolClass>>? classesStream;

  @override
  State<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends State<ClassesPage> {
  late final SchoolRepository _repository = SchoolRepository();
  late Stream<List<SchoolClass>> _stream =
      widget.classesStream ?? _repository.watchClasses();
  Timer? _loadTimer;
  bool _loadingTooLong = false;

  @override
  void initState() {
    super.initState();
    _armLoadTimer();
  }

  void _armLoadTimer() {
    _loadTimer?.cancel();
    _loadTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) setState(() => _loadingTooLong = true);
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _loadingTooLong = false;
      _stream = widget.classesStream ?? _repository.watchClasses();
    });
    _armLoadTimer();
  }

  Future<void> _verifyConnection() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Checking Firebase connection…')),
    );
    try {
      await _repository.verifyFirestoreConnection();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(content: Text('Firestore is reachable. Try saving a class.')),
      );
      _refresh();
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(schoolErrorMessage(error)),
        ),
      );
    }
  }

  Future<void> _addClass() async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _CreateClassDialog(
        onSave: ({required String name, required String section}) =>
            _repository.createClass(name: name, section: section),
      ),
    );
    if (mounted && saved == true) {
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class added successfully.')),
      );
    }
  }

  Future<void> _setActive(SchoolClass schoolClass, bool active) async {
    try {
      await _repository.setClassActive(schoolClass.id, active);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active ? 'Class reactivated.' : 'Class archived.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(schoolErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes & sections', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Test Firebase connection',
            onPressed: _verifyConnection,
            icon: const Icon(Icons.cloud_outlined),
          ),
          IconButton(
            tooltip: 'Reload classes',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Manage class sections',
                          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _addClass,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add class'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: StreamBuilder<List<SchoolClass>>(
                      stream: _stream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          _loadTimer?.cancel();
                          return _ClassState(
                            icon: Icons.cloud_off_outlined,
                            title: 'Classes could not load',
                            subtitle: schoolErrorMessage(snapshot.error!),
                            action: OutlinedButton.icon(
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry loading classes'),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return _ClassState(
                            icon: _loadingTooLong
                                ? Icons.wifi_off_outlined
                                : Icons.hourglass_top_outlined,
                            title: _loadingTooLong
                                ? 'Firestore has not responded'
                                : 'Loading classes',
                            subtitle: _loadingTooLong
                                ? 'Check mobile data or Wi-Fi, or use the cloud icon above to test Firebase. You can still tap Add class.'
                                : 'Your classes will appear here. Add class is available above.',
                            action: _loadingTooLong
                                ? OutlinedButton.icon(
                                    onPressed: _refresh,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                  )
                                : null,
                          );
                        }
                        _loadTimer?.cancel();
                        final classes = snapshot.data!;
                        if (classes.isEmpty) {
                          return _ClassState(
                            icon: Icons.school_outlined,
                            title: 'No classes yet',
                            subtitle: 'Add your first class to start admitting students.',
                            action: FilledButton.icon(
                              onPressed: _addClass,
                              icon: const Icon(Icons.add),
                              label: const Text('Create class'),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: classes.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = classes[index];
                            return Card(
                              margin: EdgeInsets.zero,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: colors.primaryContainer,
                                    foregroundColor: colors.onPrimaryContainer,
                                    child: const Icon(Icons.school_outlined, size: 20),
                                  ),
                                  title: Text(item.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    item.active ? 'Active • Available for admissions' : 'Archived • Not available for new admissions',
                                    style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
                                  ),
                                  trailing: PopupMenuButton<bool>(
                                    tooltip: 'Class options',
                                    onSelected: (active) => _setActive(item, active),
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: !item.active,
                                        child: Text(item.active ? 'Archive class' : 'Reactivate class'),
                                      ),
                                    ],
                                    icon: const Icon(Icons.more_vert),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassState extends StatelessWidget {
  const _ClassState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: color)),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}

class _CreateClassDialog extends StatefulWidget {
  const _CreateClassDialog({required this.onSave});
  final Future<void> Function({required String name, required String section})
      onSave;

  @override
  State<_CreateClassDialog> createState() => _CreateClassDialogState();
}

class _CreateClassDialogState extends State<_CreateClassDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _section = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _section.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget
          .onSave(name: _name.text, section: _section.text)
          .timeout(const Duration(seconds: 25));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = schoolErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Add a class', style: TextStyle(fontSize: 18)),
      content: SizedBox(
        width: 340,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'Class name',
                  hintText: 'e.g. Grade 5',
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Class name is required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _section,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                decoration: const InputDecoration(
                  labelText: 'Section (optional)',
                  hintText: 'e.g. A',
                ),
                onFieldSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save class')),
      ],
    );
  }
}
