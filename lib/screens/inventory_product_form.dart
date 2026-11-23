import 'package:flutter/material.dart';

import '../data/inventory_catalog.dart';
import '../data/inventory_product_service.dart';
import '../data/inventory_repository.dart';
import '../data/school_errors.dart';

/// Full-page form prevents keyboard and dropdown overflow on small phones.
/// Product codes are generated at save time by Firestore; the user never
/// needs to type or reserve an identifier.
class InventoryProductForm extends StatefulWidget {
  const InventoryProductForm({super.key, this.item, this.service});
  final InventoryItem? item;
  final InventoryProductService? service;

  @override
  State<InventoryProductForm> createState() => _InventoryProductFormState();
}

class _InventoryProductFormState extends State<InventoryProductForm> {
  late final InventoryProductService _service =
      widget.service ?? InventoryProductService();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _threshold;
  late final TextEditingController _customType;
  late final TextEditingController _bookSeries;
  late final TextEditingController _subject;
  late final TextEditingController _publisher;
  late final TextEditingController _brand;
  late final TextEditingController _variant;
  late final TextEditingController _expiry;
  late final TextEditingController _description;
  late String _department;
  late String _category;
  late String _subcategory;
  late String _classLevel;
  late String _unit;
  late bool _active;
  bool _saving = false;
  String? _error;

  static const _units = [
    'piece', 'packet', 'pack', 'box', 'bottle', 'cup',
    'plate', 'ream', 'set', 'kg', 'gram', 'dozen',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _department = item?.department ?? 'stationery';
    _category = item?.category ?? 'other';
    if (!inventoryCategoriesFor(_department).containsKey(_category)) {
      _category = 'other';
    }
    _subcategory = item?.subcategory ?? 'other';
    if (!inventorySubcategoriesFor(_department, _category)
        .containsKey(_subcategory)) {
      _subcategory = 'other';
    }
    _classLevel = inventorySchoolClasses.contains(item?.classLevel)
        ? item!.classLevel : 'Class 1';
    _unit = _units.contains(item?.unit) ? item!.unit : 'piece';
    _active = item?.active ?? true;
    _name = TextEditingController(text: item?.name ?? '');
    _quantity = TextEditingController(text: item?.stockQty.toString() ?? '');
    _price = TextEditingController(text: item == null ? ''
        : (item.priceMinor / 100).toStringAsFixed(2));
    _threshold = TextEditingController(
      text: item?.reorderPoint.toString() ?? '5');
    _customType = TextEditingController(text: item?.customType ?? '');
    _bookSeries = TextEditingController(text: item?.bookSeries ?? '');
    _subject = TextEditingController(text: item?.subject ?? '');
    _publisher = TextEditingController(text: item?.publisher ?? '');
    _brand = TextEditingController(text: item?.brand ?? '');
    _variant = TextEditingController(text: item?.variant ?? '');
    _expiry = TextEditingController(text: item?.expiryDate ?? '');
    _description = TextEditingController(text: item?.description ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name, _quantity, _price, _threshold, _customType, _bookSeries,
      _subject, _publisher, _brand, _variant, _expiry, _description,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    int maxLength = 100,
    TextInputType? keyboard,
    bool required = false,
    int maxLines = 1,
    String? hint,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: key,
      controller: controller, maxLength: maxLength,
      maxLines: maxLines, keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label, helperText: hint, border: const OutlineInputBorder(),
        counterText: '',
      ),
      validator: required
          ? (value) => value == null || value.trim().isEmpty
              ? 'This field is required' : null
          : null,
    ),
  );

  Widget _selector({
    required String label,
    required String value,
    required Map<String, String> options,
    required ValueChanged<String> onChanged,
    Key? key,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: DropdownButtonFormField<String>(
      // Reset dropdown internal state when parent category changes.
      key: ValueKey('${key ?? label}|$_department|$_category|$_subcategory'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label, border: const OutlineInputBorder()),
      items: [for (final option in options.entries)
        DropdownMenuItem<String>(
          value: option.key,
          child: Text(option.value, overflow: TextOverflow.ellipsis),
        )],
      onChanged: _saving ? null : (value) {
        if (value != null) onChanged(value);
      },
    ),
  );

  Future<void> _chooseExpiry() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_expiry.text);
    final chosen = await showDatePicker(
      context: context,
      initialDate: current ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (chosen != null) {
      _expiry.text = '${chosen.year.toString().padLeft(4, '0')}-'
          '${chosen.month.toString().padLeft(2, '0')}-'
          '${chosen.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    final quantity = int.tryParse(_quantity.text.trim());
    final point = int.tryParse(_threshold.text.trim());
    if (quantity == null || point == null) {
      setState(() => _error = 'Enter whole numbers for quantity and low stock alert.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      final input = InventoryProductInput(
        name: _name.text, department: _department,
        category: _category, subcategory: _subcategory,
        quantity: quantity, priceMinor: inventoryMoneyMinor(_price.text),
        reorderPoint: point, unit: _unit,
        customType: (_category == 'other' || _subcategory == 'other')
            ? _customType.text : '',
        classLevel: _department == 'stationery' && _category == 'books'
            ? _classLevel : '',
        bookSeries: _department == 'stationery' && _category == 'books'
            ? _bookSeries.text : '',
        subject: _department == 'stationery' && _category == 'books'
            ? _subject.text : '',
        publisher: _department == 'stationery' && _category == 'books'
            ? _publisher.text : '',
        brand: _brand.text, variant: _variant.text,
        expiryDate: _department == 'canteen' ? _expiry.text : '',
        description: _description.text, active: _active,
      );
      final item = widget.item;
      if (item == null) {
        await _service.create(input);
      } else {
        await _service.save(item, input);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = schoolErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoryOptions = inventoryCategoriesFor(_department);
    final subcategoryOptions = inventorySubcategoriesFor(_department, _category);
    final isBook = _department == 'stationery' && _category == 'books';
    final isNotebook = _department == 'stationery' && _category == 'notebooks';
    final isCanteen = _department == 'canteen';
    final custom = _category == 'other' || _subcategory == 'other';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'Add product' : 'Edit product'),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('Product details', style: Theme.of(context)
                  .textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 7),
              Text(widget.item == null
                  ? 'Item code is generated automatically when you save.'
                  : 'Item code: ${widget.item!.id}',
                style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 18),
              _selector(
                label: 'Department', value: _department,
                options: inventoryDepartments,
                onChanged: (value) => setState(() {
                  _department = value;
                  _category = 'other';
                  _subcategory = 'other';
                  _customType.clear();
                  _unit = value == 'canteen' ? 'packet' : 'piece';
                }),
              ),
              _selector(
                key: const Key('inventory_category'),
                label: isCanteen ? 'Canteen category' : 'Stationery category',
                value: _category, options: categoryOptions,
                onChanged: (value) => setState(() {
                  _category = value;
                  _subcategory = inventorySubcategoriesFor(
                      _department, value).keys.first;
                  _customType.clear();
                }),
              ),
              _selector(
                key: const Key('inventory_subcategory'),
                label: 'Subcategory / product type',
                value: _subcategory, options: subcategoryOptions,
                onChanged: (value) => setState(() {
                  _subcategory = value; _customType.clear();
                }),
              ),
              if (custom)
                _field(
                  controller: _customType, label: 'Specify other category / item *',
                  required: true, maxLength: 80,
                ),
              _field(
                key: const Key('inventory_product_name'),
                controller: _name, label: 'Product name *', required: true,
              ),
              _field(
                key: const Key('inventory_stock_quantity'),
                controller: _quantity,
                label: 'Stock quantity (number) *', required: true,
                keyboard: TextInputType.number, maxLength: 9,
                hint: 'Enter the current number of products (e.g. 100)',
              ),
              if (isBook) ...[
                _selector(
                  key: const Key('inventory_book_class'),
                  label: 'Class / grade *', value: _classLevel,
                  options: {for (final level in inventorySchoolClasses)
                    level: level},
                  onChanged: (value) => setState(() => _classLevel = value),
                ),
                _field(
                  key: const Key('inventory_book_series'),
                  controller: _bookSeries,
                  label: 'Book series name (optional)',
                  hint: 'e.g. Oxford, Punjab Textbook Board',
                ),
                _field(controller: _subject, label: 'Subject (optional)',
                  maxLength: 80),
                _field(controller: _publisher,
                  label: 'Publisher / edition (optional)'),
              ],
              if (isNotebook)
                _field(controller: _variant,
                  label: 'Notebook size / pages (optional)',
                  hint: 'e.g. 100 pages, A4, ruled'),
              if (!isBook && !isNotebook)
                _field(controller: _variant,
                  label: isCanteen ? 'Flavour / pack size (optional)'
                      : 'Size / colour / variant (optional)', maxLength: 80),
              _field(controller: _brand,
                label: isCanteen ? 'Brand / manufacturer (optional)'
                  : 'Brand (optional)'),
              if (isCanteen) ...[
                _field(controller: _expiry,
                  label: 'Best before (optional)', maxLength: 10,
                  hint: 'YYYY-MM-DD'),
                Align(alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _chooseExpiry,
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: const Text('Choose expiry date'),
                  )),
                const SizedBox(height: 10),
              ],
              Text('Pricing and stock', style: Theme.of(context)
                .textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),

              _field(
                controller: _price, label: 'Selling price (PKR) *',
                required: true,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              _selector(
                label: 'Stock unit', value: _unit,
                options: {for (final unit in _units) unit: unit},
                onChanged: (value) => setState(() => _unit = value),
              ),
              _field(
                controller: _threshold, label: 'Low stock alert at',
                keyboard: TextInputType.number, maxLength: 9,
              ),
              _field(controller: _description,
                label: 'Other details / description (optional)',
                maxLength: 250, maxLines: 3),
              if (widget.item != null)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available to sell'),
                  value: _active,
                  onChanged: _saving ? null : (value) =>
                      setState(() => _active = value),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 12),
                child: Text('Stock quantity is saved directly and its changes '
                    'are recorded in the audit history. Sellers cannot change '
                    'prices or quantities.',
                  style: Theme.of(context).textTheme.bodySmall),
              ),
              if (_error != null) ...[
                Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 10),
              ],
              FilledButton.icon(
                key: const Key('inventory_save_product'),
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : 'Save product'),
              ),
              const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
