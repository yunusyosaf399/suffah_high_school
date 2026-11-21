import 'dart:async';

import 'package:flutter/material.dart';
import '../data/school_errors.dart';
import '../data/school_repository.dart';

/// No nested Expanded/Center chains: always render the toolbar and action bar.
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
    _armTimer();
  }

  void _armTimer() {
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

  void _reload() {
    setState(() {
      _loadingTooLong = false;
      _stream = widget.classesStream ?? _repository.watchClasses();
    });
    _armTimer();
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
      _reload();
    } catch (error) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 8), content: Text(schoolErrorMessage(error))),
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
      _reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class added successfully.')),
      );
    }
  }

  Future<void> _setActive(SchoolClass schoolClass, bool active) async {
    try {
      await _repository.setClassActive(schoolClass.id, active);
      if (!mounted) return;
      _reload();
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
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes & sections',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            tooltip: 'Test Firebase connection',
            onPressed: _verifyConnection,
            icon: const Icon(Icons.cloud_outlined),
          ),
          IconButton(
            tooltip: 'Reload classes',
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _addClass,
                  icon: const Icon(Icons.add, size: 19),
                  label: const Text('Add class'),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: CustomScrollView(
              key: const Key('classes_scroll_view'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Academic setup', style: Theme.of(context)
                            .textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text('Create class sections before admitting students.',
                          style: TextStyle(fontSize: 12, color: color.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
                StreamBuilder<List<SchoolClass>>(
                  stream: _stream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      _loadTimer?.cancel();
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ModuleMessage(
                          icon: Icons.wifi_off_outlined,
                          title: 'Classes could not load',
                          detail: schoolErrorMessage(snapshot.error!),
                          buttonLabel: 'Retry loading',
                          onPressed: _reload,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ModuleMessage(
                          icon: Icons.hourglass_top_outlined,
                          title: _loadingTooLong ? 'Firestore has not responded' : 'Loading classes',
                          detail: _loadingTooLong
                              ? 'Check your connection or test Firebase with the cloud icon. Add class remains available below.'
                              : 'Your classes will appear here. You can also add a class now.',
                          buttonLabel: _loadingTooLong ? 'Retry loading' : null,
                          onPressed: _loadingTooLong ? _reload : null,
                        ),
                      );
                    }
                    _loadTimer?.cancel();
                    final classes = snapshot.data!;
                    if (classes.isEmpty) {
                      return const SliverFillRemaining(
                        hasScrollBody: false,
                        child: _ModuleMessage(
                          icon: Icons.school_outlined,
                          title: 'No classes yet',
                          detail: 'Tap Add class below to create your first section.',
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      sliver: SliverList.builder(
                        itemCount: classes.length,
                        itemBuilder: (context, index) {
                          final item = classes[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Card(
                              margin: EdgeInsets.zero,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: color.primaryContainer,
                                  foregroundColor: color.onPrimaryContainer,
                                  child: const Icon(Icons.school_outlined, size: 20),
                                ),
                                title: Text(item.label,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                subtitle: Text(item.active ? 'Active class' : 'Archived class',
                                  style: TextStyle(fontSize: 11, color: color.onSurfaceVariant)),
                                trailing: PopupMenuButton<bool>(
                                  tooltip: 'Class options',
                                  onSelected: (active) => _setActive(item, active),
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: !item.active,
                                      child: Text(item.active ? 'Archive class' : 'Reactivate class'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModuleMessage extends StatelessWidget {
  const _ModuleMessage({
    required this.icon,
    required this.title,
    required this.detail,
    this.buttonLabel,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String? buttonLabel;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 330),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 44),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text(detail, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: color)),
              if (buttonLabel != null && onPressed != null) ...[
                const SizedBox(height: 17),
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.refresh),
                  label: Text(buttonLabel!),
                ),
              ],
            ],
          ),
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
