import 'package:flutter/material.dart';

import '../data/school_errors.dart';
import '../data/staff_repository.dart';

typedef StaffRegistrationSave = Future<void> Function(
  StaffInput input, String? existingId,
);

class StaffRegistrationPage extends StatefulWidget {
  const StaffRegistrationPage({
    super.key, required this.onSave, this.initial,
  });

  final StaffRegistrationSave onSave;
  final StaffMember? initial;

  @override
  State<StaffRegistrationPage> createState() => _StaffRegistrationPageState();
}

class _StaffRegistrationPageState extends State<StaffRegistrationPage>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Name & Guardian', 'Contact', 'Address', 'Education', 'Review',
  ];
  final _formKeys = List.generate(4, (_) => GlobalKey<FormState>());
  late final TabController _tabs;
  late final Map<String, TextEditingController> _fields;
  late String _roleType;
  late DateTime _joinDate;
  DateTime? _birthDate;
  String _gender = 'Not specified';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final staff = widget.initial;
    _tabs = TabController(length: _steps.length, vsync: this)
      ..addListener(() { if (mounted) setState(() {}); });
    _roleType = staff?.roleType ?? 'teacher';
    _joinDate = DateTime.tryParse(staff?.joinDate ?? '') ?? DateTime.now();
    _birthDate = DateTime.tryParse(staff?.dateOfBirth ?? '');
    _gender = staff?.gender.isNotEmpty == true ? staff!.gender : 'Not specified';
    final values = <String, String>{
      'firstName': staff?.firstName ?? '',
      'middleName': staff?.middleName ?? '',
      'lastName': staff?.lastName ?? '',
      'guardianName': staff?.guardianName ?? '',
      'designation': staff?.designation ?? 'Teacher',
      'nationality': staff?.nationality ?? '',
      'phone': staff?.phone ?? '',
      'whatsapp': staff?.whatsapp ?? '',
      'email': staff?.email ?? '',
      'alternateEmail': staff?.alternateEmail ?? '',
      'emergencyContactName': staff?.emergencyContactName ?? '',
      'emergencyContactPhone': staff?.emergencyContactPhone ?? '',
      'presentAddress': staff?.presentAddress.isNotEmpty == true
          ? staff!.presentAddress : staff?.address ?? '',
      'permanentAddress': staff?.permanentAddress ?? '',
      'city': staff?.city ?? '',
      'postalCode': staff?.postalCode ?? '',
      'country': staff?.country ?? '',
      'highestQualification': staff?.highestQualification.isNotEmpty == true
          ? staff!.highestQualification : staff?.qualification ?? '',
      'educationDetails': staff?.educationDetails ?? '',
      'subjectSpecialization': staff?.subjectSpecialization ?? '',
      'experienceYears': staff?.experienceYears ?? '',
      'previousEmployer': staff?.previousEmployer ?? '',
    };
    _fields = {
      for (final entry in values.entries)
        entry.key: TextEditingController(text: entry.value),
    };
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final field in _fields.values) { field.dispose(); }
    super.dispose();
  }

  String _value(String key) => _fields[key]!.text.trim();

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool birth}) async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: birth
          ? _birthDate ?? DateTime(today.year - 25, today.month, today.day)
          : _joinDate,
      firstDate: DateTime(1950),
      lastDate: birth ? today : today.add(const Duration(days: 1)),
      helpText: birth ? 'Teacher date of birth' : 'Date of joining',
    );
    if (picked == null || !mounted) return;
    setState(() { if (birth) { _birthDate = picked; } else { _joinDate = picked; } });
  }

  String? _validateStep(int step) {
    _formKeys[step].currentState?.validate();
    if (step == 0) {
      if (_value('firstName').isEmpty || _value('lastName').isEmpty) {
        return 'Enter the teacher first and last name.';
      }
      if (_birthDate == null) return 'Select the teacher date of birth.';
      if (_value('guardianName').isEmpty) return 'Enter the father or guardian name.';
      if (_value('designation').isEmpty) return 'Enter the staff designation.';
    }
    if (step == 1) {
      if (_value('phone').isEmpty) return 'Enter the teacher mobile number.';
      if (_value('email').isEmpty) return 'Enter the teacher email address.';
      if (!RegExp(r'^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$')
          .hasMatch(_value('email'))) {
        return 'Enter a valid teacher email address.';
      }
      if (_value('emergencyContactPhone').isEmpty) {
        return 'Enter an emergency contact number.';
      }
    }
    if (step == 2 && _value('presentAddress').isEmpty) {
      return 'Enter the present address.';
    }
    if (step == 3 && _value('highestQualification').isEmpty) {
      return 'Enter the highest qualification.';
    }
    return null;
  }

  StaffInput _buildInput() => StaffInput(
    firstName: _value('firstName'),
    middleName: _value('middleName'),
    lastName: _value('lastName'),
    roleType: _roleType,
    designation: _value('designation'),
    phone: _value('phone'),
    email: _value('email'),
    alternateEmail: _value('alternateEmail'),
    whatsapp: _value('whatsapp'),
    joinDate: _date(_joinDate),
    dateOfBirth: _birthDate == null ? '' : _date(_birthDate!),
    gender: _gender,
    nationality: _value('nationality'),
    guardianName: _value('guardianName'),
    emergencyContactName: _value('emergencyContactName'),
    emergencyContactPhone: _value('emergencyContactPhone'),
    presentAddress: _value('presentAddress'),
    permanentAddress: _value('permanentAddress'),
    city: _value('city'),
    postalCode: _value('postalCode'),
    country: _value('country'),
    highestQualification: _value('highestQualification'),
    qualification: _value('highestQualification'),
    educationDetails: _value('educationDetails'),
    subjectSpecialization: _value('subjectSpecialization'),
    experienceYears: _value('experienceYears'),
    previousEmployer: _value('previousEmployer'),
    address: _value('presentAddress'),
  );

  Future<void> _next() async {
    if (_saving) return;
    final message = _validateStep(_tabs.index);
    if (message != null) { setState(() => _error = message); return; }
    setState(() => _error = null);
    if (_tabs.index < _steps.length - 1) _tabs.animateTo(_tabs.index + 1);
  }

  Future<void> _submit() async {
    if (_saving) return;
    for (var i = 0; i < 4; i++) {
      final message = _validateStep(i);
      if (message != null) {
        setState(() { _error = message; _tabs.animateTo(i); });
        return;
      }
    }
    final input = _buildInput();
    final validation = input.validate();
    if (validation != null) {
      setState(() { _error = validation; _tabs.animateTo(1); });
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.initial == null
            ? 'Confirm staff registration' : 'Confirm staff changes'),
        content: Text(widget.initial == null
            ? 'Submit this staff profile and reserve a permanent employee number?'
            : 'Save the reviewed staff profile? The employee number will remain unchanged.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Review again')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: Text(widget.initial == null ? 'Submit staff' : 'Save changes')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() { _saving = true; _error = null; });
    try {
      await widget.onSave(input, widget.initial?.id);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = schoolErrorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _pane(int index, List<Widget> children) => Form(
    key: _formKeys[index],
    child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Text(_steps[index], style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Text([
          'Enter the teacher identity and guardian information.',
          'Add contact details and an emergency contact.',
          'Enter present and permanent residential addresses.',
          'Record academic qualifications and teaching experience.',
        ][index], style: TextStyle(fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 18),
        ...children,
      ],
    ),
  );

  Widget _field(String key, String label, {
    bool required = false, TextInputType? keyboard, int lines = 1,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      key: Key('staff_${key}_field'),
      controller: _fields[key],
      enabled: !_saving,
      maxLines: lines,
      maxLength: lines > 1 ? 500 : 120,
      keyboardType: keyboard,
      textCapitalization: keyboard == TextInputType.emailAddress
          ? TextCapitalization.none : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: required ? '${label} *' : label,
        hintText: hint, counterText: '',
      ),
      validator: required ? (value) =>
          value == null || value.trim().isEmpty ? 'Required field' : null
          : null,
    ),
  );

  Widget _dateTile(String label, DateTime? date, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: InkWell(
          onTap: _saving ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: InputDecorator(
            decoration: const InputDecoration(
              suffixIcon: Icon(Icons.calendar_month_outlined),
            ).copyWith(labelText: label),
            child: Text(date == null ? 'Select date' : _date(date)),
          ),
        ),
      );

  Widget _namePane() => _pane(0, [
    Row(children: [
      Expanded(child: _field('firstName', 'First name', required: true)),
      const SizedBox(width: 10),
      Expanded(child: _field('middleName', 'Middle name')),
    ]),
    _field('lastName', 'Last name', required: true),
    _field('guardianName', 'Father / guardian name', required: true),
    _dateTile('Date of birth *', _birthDate, () => _pickDate(birth: true)),
    DropdownButtonFormField<String>(
      initialValue: _gender, isExpanded: true,
      decoration: const InputDecoration(labelText: 'Gender'),
      items: const ['Not specified', 'Female', 'Male', 'Other']
          .map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
      onChanged: _saving ? null : (value) {
        if (value != null) setState(() => _gender = value);
      },
    ),
    const SizedBox(height: 13),
    _field('nationality', 'Nationality'),
    DropdownButtonFormField<String>(
      initialValue: _roleType, isExpanded: true,
      decoration: const InputDecoration(labelText: 'Staff category *'),
      items: staffTypes.entries.map((entry) => DropdownMenuItem(
        value: entry.key, child: Text(entry.value))).toList(),
      onChanged: _saving ? null : (value) {
        if (value != null) setState(() => _roleType = value);
      },
    ),
    const SizedBox(height: 13),
    _field('designation', 'Designation', required: true),
  ]);

  Widget _contactPane() => _pane(1, [
    _field('phone', 'Mobile number', required: true,
      keyboard: TextInputType.phone),
    _field('whatsapp', 'WhatsApp number', keyboard: TextInputType.phone),
    _field('email', 'Email address', required: true,
      keyboard: TextInputType.emailAddress),
    _field('alternateEmail', 'Alternate email address',
      keyboard: TextInputType.emailAddress),
    _field('emergencyContactName', 'Emergency contact name'),
    _field('emergencyContactPhone', 'Emergency contact number',
      required: true, keyboard: TextInputType.phone),
    _dateTile('Date of joining *', _joinDate, () => _pickDate(birth: false)),
  ]);

  Widget _addressPane() => _pane(2, [
    _field('presentAddress', 'Present address', required: true, lines: 3),
    _field('permanentAddress', 'Permanent address', lines: 3),
    _field('city', 'City'),
    _field('postalCode', 'Postal / ZIP code'),
    _field('country', 'Country'),
  ]);

  Widget _educationPane() => _pane(3, [
    _field('highestQualification', 'Highest qualification',
      required: true, hint: 'e.g. BS Mathematics, M.Ed'),
    _field('educationDetails', 'Education details', lines: 3,
      hint: 'Degree, institution and year completed'),
    _field('subjectSpecialization', 'Teaching subject / specialization',
      hint: 'e.g. Mathematics, Physics, English'),
    _field('experienceYears', 'Teaching experience', hint: 'e.g. 5 years'),
    _field('previousEmployer', 'Previous school / employer'),
  ]);

  Widget _reviewRow(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 124, child: Text(title, style: TextStyle(
        fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant))),
      Expanded(child: Text(value.isEmpty ? '—' : value,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _reviewSection(String title, List<(String, String)> values) => Card(
    margin: const EdgeInsets.only(bottom: 11),
    child: Padding(
      padding: const EdgeInsets.all(13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800)),
        const Divider(height: 17),
        for (final value in values) _reviewRow(value.$1, value.$2),
      ]),
    ),
  );

  Widget _reviewPane() => ListView(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
    children: [
      Text('Review your information',
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      const Text('Check the details carefully before submitting.',
        style: TextStyle(fontSize: 12)),
      const SizedBox(height: 15),
      _reviewSection('Name & Guardian', [
        ('Full name', [_value('firstName'), _value('middleName'),
          _value('lastName')].where((v) => v.isNotEmpty).join(' ')),
        ('Father / guardian', _value('guardianName')),
        ('Date of birth', _birthDate == null ? '' : _date(_birthDate!)),
        ('Gender', _gender),
        ('Category', staffTypes[_roleType] ?? _roleType),
        ('Designation', _value('designation')),
      ]),
      _reviewSection('Contact', [
        ('Mobile', _value('phone')), ('WhatsApp', _value('whatsapp')),
        ('Email', _value('email')), ('Alternate email', _value('alternateEmail')),
        ('Emergency contact', _value('emergencyContactName')),
        ('Emergency phone', _value('emergencyContactPhone')),
        ('Date joined', _date(_joinDate)),
      ]),
      _reviewSection('Address', [
        ('Present', _value('presentAddress')),
        ('Permanent', _value('permanentAddress')),
        ('City', _value('city')), ('Postal code', _value('postalCode')),
        ('Country', _value('country')),
      ]),
      _reviewSection('Education', [
        ('Qualification', _value('highestQualification')),
        ('Education', _value('educationDetails')),
        ('Specialization', _value('subjectSpecialization')),
        ('Experience', _value('experienceYears')),
        ('Previous employer', _value('previousEmployer')),
      ]),
      if (widget.initial != null)
        _reviewRow('Employee ID', widget.initial!.staffNo),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Staff registration' : 'Edit staff',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(77),
          child: Column(children: [
            if (widget.initial != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                child: Row(children: [
                  Text('Employee ID: ${widget.initial!.staffNo}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text(widget.initial!.active ? 'ACTIVE' : 'ARCHIVED',
                    style: TextStyle(fontSize: 10, color: colors.primary,
                      fontWeight: FontWeight.w800)),
                ]),
              ),
            LinearProgressIndicator(
              value: (_tabs.index + 1) / _steps.length, minHeight: 3),
            TabBar(
              controller: _tabs, isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              tabs: [for (var i = 0; i < _steps.length; i++)
                Tab(text: '${i + 1}. ${_steps[i]}')],
            ),
          ]),
        ),
      ),
      body: SafeArea(child: TabBarView(
        controller: _tabs,
        children: [
          _namePane(), _contactPane(), _addressPane(),
          _educationPane(), _reviewPane(),
        ],
      )),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 12),
          child: Center(heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_error != null) ...[
                  Align(alignment: Alignment.centerLeft,
                    child: Text(_error!, style: TextStyle(
                      fontSize: 11, color: colors.error))),
                  const SizedBox(height: 8),
                ],
                Row(children: [
                  if (_tabs.index > 0) ...[
                    OutlinedButton(
                      onPressed: _saving ? null
                          : () => _tabs.animateTo(_tabs.index - 1),
                      child: const Text('Back')),
                    const SizedBox(width: 9),
                  ],
                  Expanded(child: FilledButton(
                    key: Key(_tabs.index == 4
                        ? 'submit_staff_registration'
                        : 'next_staff_registration'),
                    onPressed: _saving ? null
                        : _tabs.index == 4 ? _submit : _next,
                    child: Text(_saving ? 'Saving…'
                        : _tabs.index == 4
                            ? widget.initial == null ? 'Submit staff' : 'Save changes'
                            : 'Save & next'),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
