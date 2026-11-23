import 'package:flutter_test/flutter_test.dart';
import 'package:suffah_high_school/data/inventory_catalog.dart';
import 'package:suffah_high_school/data/inventory_product_service.dart';
import 'package:suffah_high_school/data/inventory_repository.dart';

void main() {
  test('Stationery includes book, notebook, school supplies, other categories', () {
    expect(inventoryStationeryCategories.keys,
      containsAll(['books', 'notebooks', 'writing', 'paper', 'art',
        'geometry', 'files', 'exam', 'classroom', 'accessories', 'printing', 'other']));
    expect(inventorySubcategoriesFor('stationery', 'books').containsKey('textbook'), isTrue);
    expect(inventorySubcategoriesFor('stationery', 'notebooks').containsKey('graph'), isTrue);
    expect(inventorySchoolClasses, containsAll(['Nursery', 'Class 1', 'Class 10', 'Class 12']));
  });

  test('Canteen includes food, drinks and Other product category', () {
    expect(inventoryCanteenCategories.keys,
      containsAll(['snacks', 'drinks', 'bakery', 'meals', 'sweets',
        'fruits', 'dairy', 'packaged', 'other']));
    expect(inventorySubcategoriesFor('canteen', 'drinks').containsKey('water'), isTrue);
  });

  test('Direct numeric opening stock and book series are valid', () {
    const input = InventoryProductInput(
      name: 'Mathematics Class 5', department: 'stationery',
      category: 'books', subcategory: 'textbook',
      classLevel: 'Class 5', bookSeries: 'Oxford Primary Maths',
      quantity: 150, priceMinor: 85000, reorderPoint: 10,
    );
    expect(input.validate, returnsNormally);
    expect(input.quantity, 150);
    expect(input.metadata['bookSeries'], 'Oxford Primary Maths');
    expect(inventoryRupees(input.priceMinor), 'Rs 850.00');
  });

  test('Notebook registration does not need a series or class', () {
    const input = InventoryProductInput(
      name: 'Single line notebook', department: 'stationery',
      category: 'notebooks', subcategory: 'single_line',
      variant: '100 pages', quantity: 100,
      priceMinor: 15000, reorderPoint: 5,
    );
    expect(input.validate, returnsNormally);
    expect(input.bookSeries, isEmpty);
  });

  test('Books must select a class, Other must have an explanation', () {
    const noClass = InventoryProductInput(
      name: 'English reader', department: 'stationery',
      category: 'books', subcategory: 'reading',
      quantity: 5, priceMinor: 15000, reorderPoint: 2,
    );
    expect(noClass.validate, throwsArgumentError);
    const unknown = InventoryProductInput(
      name: 'Special school item', department: 'stationery',
      category: 'other', subcategory: 'other',
      quantity: 10, priceMinor: 5000, reorderPoint: 2,
    );
    expect(unknown.validate, throwsArgumentError);
  });

  test('Invalid quantities and prices are not saved', () {
    const negative = InventoryProductInput(
      name: 'Bottle of water', department: 'canteen',
      category: 'drinks', subcategory: 'water',
      quantity: -1, priceMinor: 10000, reorderPoint: 5,
    );
    const free = InventoryProductInput(
      name: 'Bottle of water', department: 'canteen',
      category: 'drinks', subcategory: 'water',
      quantity: 20, priceMinor: 0, reorderPoint: 5,
    );
    expect(negative.validate, throwsArgumentError);
    expect(free.validate, throwsArgumentError);
  });

  test('Archived items cannot be sold', () {
    const item = InventoryItem(
      id: 'ST-ARCHIVE', name: 'Old book', department: 'stationery',
      unit: 'piece', priceMinor: 50000, stockQty: 100,
      reorderPoint: 5, active: true, archived: true, description: '',
    );
    expect(item.canSell, isFalse);
  });
}
