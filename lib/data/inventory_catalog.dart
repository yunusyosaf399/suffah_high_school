/// School-specific product taxonomy. Owners may use "other" and the
/// custom type field for products not represented in these suggestions.
const inventoryStationeryCategories = <String, String>{
  'books': 'Books',
  'notebooks': 'Notebooks & registers',
  'writing': 'Pens, pencils & writing',
  'paper': 'Paper & sheets',
  'art': 'Art & craft',
  'geometry': 'Geometry & maths',
  'files': 'Files & organization',
  'exam': 'Examination supplies',
  'classroom': 'Classroom & teaching',
  'accessories': 'School accessories',
  'printing': 'Printing & office',
  'other': 'Other stationery',
};

const inventoryCanteenCategories = <String, String>{
  'snacks': 'Snacks',
  'drinks': 'Drinks & water',
  'bakery': 'Bakery',
  'meals': 'Meals & lunch',
  'sweets': 'Sweets & chocolate',
  'fruits': 'Fruits & healthy food',
  'dairy': 'Dairy & desserts',
  'packaged': 'Packaged foods',
  'other': 'Other canteen products',
};

const inventoryStationerySubcategories = <String, Map<String, String>>{
  'books': {
    'textbook': 'Textbook', 'workbook': 'Workbook',
    'guide': 'Guide / key', 'reading': 'Reading / story book',
    'reference': 'Reference / dictionary',
    'exam_prep': 'Exam preparation', 'religious': 'Religious / Islamic',
    'other': 'Other book',
  },
  'notebooks': {
    'single_line': 'Single-line notebook', 'double_line': 'Double-line notebook',
    'four_line': 'Four-line notebook', 'plain': 'Plain notebook',
    'graph': 'Graph notebook', 'practical': 'Practical notebook',
    'drawing': 'Drawing notebook', 'register': 'Register',
    'assignment': 'Assignment notebook', 'diary': 'School diary',
    'other': 'Other notebook',
  },
  'writing': {
    'ball_pen': 'Ball pen', 'gel_pen': 'Gel pen', 'fountain_pen': 'Fountain pen',
    'pencil': 'Pencil', 'mechanical': 'Mechanical pencil',
    'marker': 'Marker', 'whiteboard_marker': 'Whiteboard marker',
    'highlighter': 'Highlighter', 'eraser': 'Eraser',
    'sharpener': 'Sharpener', 'ink': 'Ink / refill', 'other': 'Other writing',
  },
  'paper': {
    'a4': 'A4 paper', 'a3': 'A3 paper', 'chart': 'Chart paper',
    'colored': 'Coloured paper', 'craft': 'Craft paper',
    'card': 'Card / cardstock', 'loose': 'Loose sheets',
    'graph': 'Graph paper', 'other': 'Other paper',
  },
  'art': {
    'crayons': 'Crayons', 'color_pencils': 'Coloured pencils',
    'paint': 'Paint / watercolours', 'brush': 'Paintbrush',
    'clay': 'Modelling clay', 'glue': 'Glue / adhesive',
    'scissors': 'Scissors', 'sketch': 'Sketchbook',
    'craft_kit': 'Craft kit', 'other': 'Other art supplies',
  },
  'geometry': {
    'geometry_box': 'Geometry box', 'ruler': 'Ruler / scale',
    'compass': 'Compass', 'protractor': 'Protractor',
    'set_square': 'Set square', 'calculator': 'Calculator',
    'abacus': 'Abacus', 'other': 'Other maths supplies',
  },
  'files': {
    'folder': 'Folder', 'file': 'File / binder',
    'envelope': 'Envelope', 'label': 'Labels',
    'clip': 'Paper / binder clips', 'stapler': 'Stapler',
    'staples': 'Staples', 'punch': 'Hole punch',
    'tape': 'Tape', 'other': 'Other organizational supplies',
  },
  'exam': {
    'answer_sheet': 'Answer sheet', 'test_pad': 'Test pad',
    'exam_board': 'Exam writing board', 'admit_card': 'Exam card',
    'other': 'Other exam supplies',
  },
  'classroom': {
    'whiteboard': 'Whiteboard', 'duster': 'Board duster',
    'chalk': 'Chalk', 'notice_board': 'Notice board',
    'teaching_aid': 'Teaching aid', 'other': 'Other classroom supplies',
  },
  'accessories': {
    'badge': 'School badge', 'tie': 'School tie',
    'belt': 'Belt', 'cap': 'Cap', 'socks': 'Socks',
    'id_holder': 'ID holder', 'water_bottle': 'School water bottle',
    'bag': 'School bag', 'other': 'Other accessory',
  },
  'printing': {
    'printer_paper': 'Printer paper', 'toner': 'Toner',
    'cartridge': 'Ink cartridge', 'lamination': 'Lamination sheet',
    'other': 'Other printing supplies',
  },
  'other': {'other': 'Other stationery item'},
};

const inventoryCanteenSubcategories = <String, Map<String, String>>{
  'snacks': {
    'chips': 'Chips', 'biscuits': 'Biscuits',
    'wafers': 'Wafers', 'nimko': 'Nimko',
    'popcorn': 'Popcorn', 'nuts': 'Nuts',
    'other': 'Other snack',
  },
  'drinks': {
    'water': 'Bottled water', 'juice': 'Juice',
    'milk': 'Milk drink', 'soft_drink': 'Soft drink',
    'lassi': 'Lassi', 'tea': 'Tea',
    'other': 'Other drink',
  },
  'bakery': {
    'bun': 'Bun', 'bread': 'Bread',
    'cake': 'Cake', 'pastry': 'Pastry',
    'patties': 'Patties', 'samosa': 'Samosa',
    'roll': 'Roll', 'other': 'Other bakery item',
  },
  'meals': {
    'sandwich': 'Sandwich', 'burger': 'Burger',
    'wrap': 'Wrap', 'rice': 'Rice / biryani',
    'noodles': 'Noodles', 'lunch_box': 'Lunch box',
    'other': 'Other meal',
  },
  'sweets': {
    'chocolate': 'Chocolate', 'candy': 'Candy',
    'toffee': 'Toffee', 'lollipop': 'Lollipop',
    'other': 'Other sweet',
  },
  'fruits': {
    'apple': 'Apple', 'banana': 'Banana',
    'orange': 'Orange', 'dates': 'Dates',
    'fruit_cup': 'Fruit cup', 'other': 'Other fruit / healthy food',
  },
  'dairy': {
    'yogurt': 'Yogurt', 'ice_cream': 'Ice cream',
    'custard': 'Custard', 'cheese': 'Cheese',
    'other': 'Other dairy / dessert',
  },
  'packaged': {
    'cereal': 'Cereal bar', 'instant': 'Instant snack',
    'juice_box': 'Juice box', 'cracker': 'Crackers',
    'other': 'Other packaged food',
  },
  'other': {'other': 'Other canteen item'},
};

const inventorySchoolClasses = <String>[
  'Playgroup', 'Nursery', 'KG / Prep',
  'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5',
  'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10',
  'Class 11', 'Class 12', 'O Level', 'A Level', 'Other',
];

Map<String, String> inventoryCategoriesFor(String department) =>
    department == 'stationery'
      ? inventoryStationeryCategories : inventoryCanteenCategories;

Map<String, String> inventorySubcategoriesFor(
    String department, String category) {
  final catalog = department == 'stationery'
      ? inventoryStationerySubcategories : inventoryCanteenSubcategories;
  return catalog[category] ?? const {'other': 'Other'};
}

String inventoryCategoryLabel(String department, String category) =>
    inventoryCategoriesFor(department)[category] ?? 'Other';

String inventorySubcategoryLabel(
    String department, String category, String subcategory) =>
    inventorySubcategoriesFor(department, category)[subcategory] ?? 'Other';
