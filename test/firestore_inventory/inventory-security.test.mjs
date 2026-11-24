import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, collection, updateDoc, runTransaction,
  query, where, serverTimestamp, Timestamp, writeBatch,
} from 'firebase/firestore';

const ownerId = 'tQt6vca2zuagZipvknBwcmSRcrc2';
const sellerId = 'canteen-seller-uid';
const otherSellerId = 'another-seller-uid';
const managerId = 'inventory-manager-uid';
const guestId = 'unapproved-uid';
const itemId = 'CHIPS001';
let environment;

function db(uid) {
  return environment.authenticatedContext(uid).firestore();
}

function seedItem() {
  return {
    sku: itemId, name: 'Potato chips', department: 'canteen',
    unit: 'packet', description: 'Sample snack', priceMinor: 5000,
    stockQty: 10, reorderPoint: 3, active: true, currency: 'PKR',
    lastMovementId: '', lastMovementType: '',
    createdBy: ownerId, createdAt: Timestamp.now(),
    updatedBy: ownerId, updatedAt: Timestamp.now(),
  };
}

async function recordSale(database, saleId, options = {}) {
  const quantity = options.quantity ?? 2;
  const unitPriceMinor = options.unitPriceMinor ?? 5000;
  const productRef = doc(database, 'inventory_items', itemId);
  const receiptRef = doc(database, 'inventory_sales', saleId);
  return runTransaction(database, async tx => {
    const before = await tx.get(productRef);
    const item = before.data();
    assert(item, 'Fixture item must exist');
    if (options.writeStock !== false) {
      tx.update(productRef, {
        stockQty: item.stockQty - quantity,
        lastMovementId: saleId, lastMovementType: 'sale',
        updatedAt: serverTimestamp(), updatedBy: sellerId,
      });
    }
    tx.set(receiptRef, {
      saleId, itemId, itemName: item.name, department: item.department,
      quantity, stockBefore: item.stockQty, unitPriceMinor,
      totalMinor: quantity * unitPriceMinor, currency: 'PKR',
      sellerUid: sellerId, paymentMethod: 'Cash',
      soldAt: serverTimestamp(),
    });
  });
}

before(async () => {
  environment = await initializeTestEnvironment({
    projectId: 'demo-suffah-inventory',
    firestore: {
      host: '127.0.0.1', port: 8080,
      rules: readFileSync('../../firestore.rules', 'utf8'),
    },
  });
});
after(async () => { if (environment) await environment.cleanup(); });
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    const admin = context.firestore();
    for (const [uid, role] of [
      [sellerId, 'canteen_seller'], [otherSellerId, 'canteen_seller'],
      [managerId, 'inventory_manager'],
    ]) {
      await setDoc(doc(admin, 'users', uid), {
        displayName: uid, email: uid + '@example.com',
        role, active: true,
      });
    }
    await setDoc(doc(admin, 'inventory_items', itemId), seedItem());
    await setDoc(doc(admin, 'inventory_purchases', 'sample-purchase'), {
      itemId, unitCostMinor: 2500, supplier: 'Test supplier',
      recordedAt: Timestamp.now(),
    });
  });
});

test('seller may read SKU/price/stock but cannot see supplier purchase cost', async () => {
  const seller = db(sellerId);
  const product = await assertSucceeds(getDoc(doc(seller, 'inventory_items', itemId)));
  assert.equal(product.data().priceMinor, 5000);
  assert.equal(product.data().stockQty, 10);
  await assertSucceeds(getDocs(collection(seller, 'inventory_items')));
  await assertFails(getDoc(doc(seller, 'inventory_purchases', 'sample-purchase')));
  await assertFails(getDoc(doc(db(guestId), 'inventory_items', itemId)));
});

test('seller cannot change price, stock quantity or product status directly', async () => {
  const seller = db(sellerId);
  const product = doc(seller, 'inventory_items', itemId);
  await assertFails(updateDoc(product, { priceMinor: 1 }));
  await assertFails(updateDoc(product, { stockQty: 200 }));
  await assertFails(updateDoc(product, { active: false }));
  await assertFails(setDoc(doc(seller, 'inventory_items', 'NEW001'), {
    ...seedItem(), sku: 'NEW001', createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('seller can atomically record a genuine sale at manager-set price', async () => {
  const seller = db(sellerId);
  await assertSucceeds(recordSale(seller, 'sale-legitimate'));
  const product = await getDoc(doc(seller, 'inventory_items', itemId));
  assert.equal(product.data().stockQty, 8);
  const sale = await getDoc(doc(seller, 'inventory_sales', 'sale-legitimate'));
  assert.equal(sale.data().totalMinor, 10000);
  assert.equal(sale.data().quantity, 2);
  assert.equal(sale.data().sellerUid, sellerId);
});

test('seller cannot forge cheaper prices or bypass the stock decrement', async () => {
  const seller = db(sellerId);
  await assertFails(recordSale(seller, 'sale-tampered', {unitPriceMinor: 1}));
  await assertFails(recordSale(seller, 'sale-no-stock', {writeStock: false}));
  await assertFails(recordSale(seller, 'sale-oversell', {quantity: 11}));
  const product = await getDoc(doc(seller, 'inventory_items', itemId));
  assert.equal(product.data().stockQty, 10);
});

test('seller cannot record purchases or stock adjustments', async () => {
  const seller = db(sellerId);
  await assertFails(setDoc(doc(seller, 'inventory_purchases', 'forged'), {
    purchaseId: 'forged', itemId, itemName: 'Potato chips',
    quantity: 25, stockBefore: 10, unitCostMinor: 500,
    totalCostMinor: 12500, supplier: 'Fake supplier',
    invoice: '', currency: 'PKR', recordedBy: sellerId,
    purchasedAt: serverTimestamp(), recordedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(seller, 'inventory_adjustments', 'forged'), {
    adjustmentId: 'forged', itemId, itemName: 'Potato chips',
    delta: 25, stockBefore: 10, reason: 'correction', notes: '',
    recordedBy: sellerId, recordedAt: serverTimestamp(),
  }));
});

test('owner and inventory manager can edit price but not silently alter stock', async () => {
  const manager = db(managerId);
  const product = doc(manager, 'inventory_items', itemId);
  await assertSucceeds(updateDoc(product, {
    priceMinor: 6000, updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
  await assertFails(updateDoc(product, {
    stockQty: 999, updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(manager, 'inventory_purchases', 'sample-purchase')));

  const owner = db(ownerId);
  await assertSucceeds(setDoc(doc(owner, 'inventory_items', 'PENCIL01'), {
    ...seedItem(), sku: 'PENCIL01', name: 'Pencil', department: 'stationery',
    stockQty: 0, createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  }));
});

test('manager may receive purchase stock only in a matching atomic transaction', async () => {
  const manager = db(managerId);
  const product = doc(manager, 'inventory_items', itemId);
  const invoice = doc(manager, 'inventory_purchases', 'purchase-legitimate');
  await assertSucceeds(runTransaction(manager, async tx => {
    const item = (await tx.get(product)).data();
    tx.update(product, {
      stockQty: item.stockQty + 5, lastMovementId: invoice.id,
      lastMovementType: 'purchase',
      updatedBy: managerId, updatedAt: serverTimestamp(),
    });
    tx.set(invoice, {
      purchaseId: invoice.id, itemId, itemName: item.name,
      quantity: 5, stockBefore: item.stockQty, unitCostMinor: 2500,
      totalCostMinor: 12500, supplier: 'Test supplier', invoice: 'INV-2026',
      currency: 'PKR', recordedBy: managerId,
      purchasedAt: serverTimestamp(), recordedAt: serverTimestamp(),
    });
  }));
  const after = await getDoc(product);
  assert.equal(after.data().stockQty, 15);
});

test('seller may read own sale receipts but not another seller receipts', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'inventory_sales', 'own'), {
      sellerUid: sellerId, itemId, soldAt: Timestamp.now(),
    });
    await setDoc(doc(admin, 'inventory_sales', 'other'), {
      sellerUid: otherSellerId, itemId, soldAt: Timestamp.now(),
    });
  });
  const seller = db(sellerId);
  await assertSucceeds(getDoc(doc(seller, 'inventory_sales', 'own')));
  await assertFails(getDoc(doc(seller, 'inventory_sales', 'other')));
  const mine = await assertSucceeds(getDocs(query(
    collection(seller, 'inventory_sales'), where('sellerUid', '==', sellerId))));
  assert.equal(mine.size, 1);
});


test('manager may create a product with direct opening stock and a single audited event', async () => {
  const manager = db(managerId);
  const sku = 'ST-GENBOOK001';
  const ref = doc(manager, 'inventory_items', sku);
  const opening = doc(manager, 'inventory_adjustments', 'opening-books');
  await assertSucceeds(runTransaction(manager, async tx => {
    const current = await tx.get(ref);
    assert.equal(current.exists(), false);
    tx.set(ref, {
      sku, name: 'Mathematics book', department: 'stationery',
      category: 'books', subcategory: 'textbook', customType: '',
      classLevel: 'Class 5', bookSeries: 'Oxford', subject: 'Maths',
      publisher: 'Oxford', brand: '', variant: '', expiryDate: '',
      unit: 'piece', description: '', priceMinor: 25000, stockQty: 75,
      reorderPoint: 10, active: true, archived: false,
      currency: 'PKR', lastMovementId: opening.id,
      lastMovementType: 'opening',
      createdBy: managerId, createdAt: serverTimestamp(),
      updatedBy: managerId, updatedAt: serverTimestamp(),
    });
    tx.set(opening, {
      adjustmentId: opening.id, itemId: sku, itemName: 'Mathematics book',
      delta: 75, stockBefore: 0, reason: 'opening',
      notes: 'Opening quantity entered on new product',
      recordedBy: managerId, recordedAt: serverTimestamp(),
    });
  }));
  const product = await getDoc(ref);
  assert.equal(product.data().stockQty, 75);
  const event = await getDoc(opening);
  assert.equal(event.data().reason, 'opening');
});

test('manager cannot create stock without corresponding opening balance event', async () => {
  const manager = db(managerId);
  await assertFails(setDoc(doc(manager, 'inventory_items', 'ST-BADOPEN001'), {
    ...seedItem(), sku: 'ST-BADOPEN001',
    stockQty: 50, lastMovementId: 'fake', lastMovementType: 'opening',
    createdBy: managerId, createdAt: serverTimestamp(),
    updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
});

test('manager may enter a new quantity and change book metadata with one correction event', async () => {
  const manager = db(managerId);
  const item = doc(manager, 'inventory_items', itemId);
  const event = doc(manager, 'inventory_adjustments', 'stock-correction');
  await assertSucceeds(runTransaction(manager, async tx => {
    const current = (await tx.get(item)).data();
    tx.update(item, {
      priceMinor: 7500, stockQty: 23,
      category: 'snacks', subcategory: 'chips', brand: 'School brand',
      lastMovementId: event.id, lastMovementType: 'adjustment',
      updatedBy: managerId, updatedAt: serverTimestamp(),
    });
    tx.set(event, {
      adjustmentId: event.id, itemId, itemName: current.name,
      stockBefore: current.stockQty, delta: 13, reason: 'correction',
      notes: 'Authorized user entered a new stock quantity',
      recordedBy: managerId, recordedAt: serverTimestamp(),
    });
  }));
  const after = await getDoc(item);
  assert.equal(after.data().stockQty, 23);
  assert.equal(after.data().priceMinor, 7500);
  const evt = await getDoc(event);
  assert.equal(evt.data().delta, 13);
});

test('seller cannot forge opening quantity or archive/delete a product', async () => {
  const seller = db(sellerId);
  const product = doc(seller, 'inventory_items', itemId);
  await assertFails(updateDoc(product, {
    archived: true, active: false,
    archivedBy: sellerId, archivedAt: serverTimestamp(),
    updatedBy: sellerId, updatedAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(seller, 'inventory_items', 'ST-SELLER001'), {
    ...seedItem(), sku: 'ST-SELLER001', stockQty: 30,
    lastMovementId: '', lastMovementType: '',
    createdBy: sellerId, updatedBy: sellerId,
    createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
  }));
});

test('manager delete is reversible archive; archived products cannot be sold', async () => {
  const manager = db(managerId);
  const product = doc(manager, 'inventory_items', itemId);
  await assertSucceeds(updateDoc(product, {
    archived: true, active: false,
    archivedBy: managerId, archivedAt: serverTimestamp(),
    updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
  await assertFails(recordSale(db(sellerId), 'archived-sale'));
  await assertSucceeds(updateDoc(product, {
    archived: false, active: false, archivedBy: '', archivedAt: null,
    updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
  const restored = await getDoc(product);
  assert.equal(restored.data().archived, false);
  assert.equal(restored.data().active, false);
});


async function seedStudentDirectory() {
  const owner = db(ownerId);
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'students', 'ST-2026-0005'), {
      admissionNo: 'ST-2026-0005', rollNo: '10004',
      fullName: 'Aisha Khan', classId: 'class-five',
      active: true, status: 'admitted',
      guardianPhone: 'private-number', health: {condition: 'private'},
    });
  });
  await assertSucceeds(setDoc(
    doc(owner, 'inventory_student_directory', 'ST-2026-0005'),
    {
      studentId: 'ST-2026-0005',
      fullName: 'Aisha Khan', rollNo: '10004',
      classId: 'class-five', active: true,
      updatedAt: serverTimestamp(),
    },
  ));
}

function newCartSale(saleId, sku, item, {
  orderId = 'order-2026-001',
  lineNumber = 1,
  paid = false,
  student = true,
  sellerUid = sellerId,
} = {}) {
  const total = item.priceMinor * 2;
  return {
    saleId, orderId, lineNumber,
    itemId: sku, itemName: item.name, department: item.department,
    quantity: 2, stockBefore: item.stockQty,
    unitPriceMinor: item.priceMinor, totalMinor: total, currency: 'PKR',
    sellerUid,
    customerType: student ? 'student' : 'other',
    customerId: student ? 'ST-2026-0005' : '',
    customerName: student ? 'Aisha Khan' : 'School visitor',
    customerPhone: student ? '' : '03001234567',
    customerClass: student ? 'class-five' : '',
    customerRollNo: student ? '10004' : '',
    paidMinor: paid ? total : 0,
    paymentStatus: paid ? 'paid' : 'borrowed',
    paymentMethod: paid ? 'Cash' : 'Unpaid',
    lastPaymentId: '',
    soldAt: serverTimestamp(),
  };
}

test('sellers can see limited student checkout records but never full admissions', async () => {
  await seedStudentDirectory();
  const seller = db(sellerId);
  const directory = await assertSucceeds(getDoc(
    doc(seller, 'inventory_student_directory', 'ST-2026-0005')));
  assert.deepEqual(Object.keys(directory.data()).sort(),
    ['active', 'classId', 'fullName', 'rollNo', 'studentId', 'updatedAt'].sort());
  await assertFails(getDoc(doc(seller, 'students', 'ST-2026-0005')));
  await assertFails(setDoc(
    doc(seller, 'inventory_student_directory', 'fake'), {
      studentId: 'fake', fullName: 'Fake', rollNo: '90000',
      classId: '', active: true, updatedAt: serverTimestamp(),
    }));
});

test('seller checks out a two-product borrowed cart in one atomic transaction', async () => {
  await seedStudentDirectory();
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'inventory_items', 'BOOK001'), {
      ...seedItem(), sku: 'BOOK001', name: 'English workbook',
      department: 'stationery', priceMinor: 10000, stockQty: 12,
    });
  });
  const seller = db(sellerId);
  const products = [
    doc(seller, 'inventory_items', itemId),
    doc(seller, 'inventory_items', 'BOOK001'),
  ];
  const receipts = [
    doc(seller, 'inventory_sales', 'cart-line-001'),
    doc(seller, 'inventory_sales', 'cart-line-002'),
  ];
  await assertSucceeds(runTransaction(seller, async tx => {
    const before = [];
    for (const ref of products) before.push((await tx.get(ref)).data());
    for (let i = 0; i < products.length; i++) {
      const item = before[i];
      tx.update(products[i], {
        stockQty: item.stockQty - 2,
        lastMovementId: receipts[i].id, lastMovementType: 'sale',
        updatedBy: sellerId, updatedAt: serverTimestamp(),
      });
      tx.set(receipts[i], newCartSale(
        receipts[i].id, products[i].id, item, {lineNumber: i + 1}));
    }
  }));
  assert.equal((await getDoc(products[0])).data().stockQty, 8);
  assert.equal((await getDoc(products[1])).data().stockQty, 10);
  assert.equal((await getDoc(receipts[0])).data().paidMinor, 0);
  assert.equal((await getDoc(receipts[1])).data().paymentStatus, 'borrowed');
});

test('borrowed payment is appended and only increases paid balance by collected amount', async () => {
  await seedStudentDirectory();
  const seller = db(sellerId);
  const item = doc(seller, 'inventory_items', itemId);
  const sale = doc(seller, 'inventory_sales', 'cart-credit-001');
  await assertSucceeds(runTransaction(seller, async tx => {
    const original = (await tx.get(item)).data();
    tx.update(item, {
      stockQty: original.stockQty - 2, lastMovementId: sale.id,
      lastMovementType: 'sale', updatedBy: sellerId,
      updatedAt: serverTimestamp(),
    });
    tx.set(sale, newCartSale(sale.id, itemId, original));
  }));
  await assertFails(updateDoc(sale, {
    paidMinor: 1000, paymentStatus: 'partially_paid',
    lastPaymentId: 'fake', lastPaymentAt: serverTimestamp(),
  }));
  let paidBefore = 0;
  for (const [paymentId, amount] of [['payment-part', 3000], ['payment-rest', 7000]]) {
    const payment = doc(seller, 'inventory_payments', paymentId);
    await assertSucceeds(runTransaction(seller, async tx => {
      const before = (await tx.get(sale)).data();
      assert.equal(before.paidMinor, paidBefore);
      tx.update(sale, {
        paidMinor: paidBefore + amount,
        paymentStatus: paidBefore + amount === 10000 ? 'paid' : 'partially_paid',
        lastPaymentId: paymentId,
        lastPaymentAt: serverTimestamp(),
      });
      tx.set(payment, {
        paymentId, saleId: sale.id, orderId: before.orderId,
        sellerUid: sellerId, customerId: before.customerId,
        customerName: before.customerName,
        amountMinor: amount, paidBeforeMinor: paidBefore,
        balanceAfterMinor: 10000 - paidBefore - amount,
        method: 'Cash', collectedBy: sellerId,
        collectedAt: serverTimestamp(),
      });
    }));
    paidBefore += amount;
  }
  assert.equal((await getDoc(sale)).data().paidMinor, 10000);
  assert.equal((await getDoc(sale)).data().paymentStatus, 'paid');
  assert.equal((await getDoc(item)).data().stockQty, 8);
  await assertFails(updateDoc(sale, {
    paidMinor: 11000, lastPaymentId: 'fraud',
    lastPaymentAt: serverTimestamp(),
  }));
});

test('seller cannot borrow for a forged student or without contact for other buyer', async () => {
  const seller = db(sellerId);
  const item = doc(seller, 'inventory_items', itemId);
  const sale = doc(seller, 'inventory_sales', 'fake-customer-sale');
  await assertFails(runTransaction(seller, async tx => {
    const original = (await tx.get(item)).data();
    tx.update(item, {
      stockQty: 8, lastMovementId: sale.id, lastMovementType: 'sale',
      updatedBy: sellerId, updatedAt: serverTimestamp(),
    });
    tx.set(sale, newCartSale(sale.id, itemId, original));
  }));
  const otherSale = doc(seller, 'inventory_sales', 'uncontacted-buyer');
  await assertFails(runTransaction(seller, async tx => {
    const original = (await tx.get(item)).data();
    tx.update(item, {
      stockQty: 8, lastMovementId: otherSale.id, lastMovementType: 'sale',
      updatedBy: sellerId, updatedAt: serverTimestamp(),
    });
    tx.set(otherSale, {
      ...newCartSale(otherSale.id, itemId, original, {student: false}),
      customerPhone: '',
    });
  }));
});

test('principal can read inventory analytics but cannot change seller balances', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'users', 'principal-uid'), {
      displayName: 'Principal', role: 'principal', active: true,
    });
  });
  const principal = db('principal-uid');
  await assertSucceeds(getDocs(collection(principal, 'inventory_sales')));
  await assertSucceeds(getDocs(collection(principal, 'inventory_payments')));
  await assertFails(updateDoc(
    doc(principal, 'inventory_items', itemId), {priceMinor: 1}));
});

test('owner syncs legacy admitted students without stored active/status fields', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'students', 'ST-LEGACY-1'), {
      fullName: 'Hina Khan', rollNo: '10007',
      classId: 'class-4', guardianPhone: 'PRIVATE',
    });
    await setDoc(doc(context.firestore(), 'students', 'ST-LEGACY-2'), {
      fullName: 'Zain Ali', guardianPhone: 'PRIVATE',
    });
  });
  const owner = db(ownerId);
  const seller = db(sellerId);
  await assertSucceeds(setDoc(
    doc(owner, 'inventory_student_directory', 'ST-LEGACY-1'), {
      studentId: 'ST-LEGACY-1', fullName: 'Hina Khan',
      rollNo: '10007', classId: 'class-4', active: true,
      updatedAt: serverTimestamp(),
    },
  ));
  await assertSucceeds(setDoc(
    doc(owner, 'inventory_student_directory', 'ST-LEGACY-2'), {
      studentId: 'ST-LEGACY-2', fullName: 'Zain Ali',
      rollNo: '', classId: '', active: true,
      updatedAt: serverTimestamp(),
    },
  ));
  const list = await assertSucceeds(getDocs(query(
    collection(seller, 'inventory_student_directory'),
    where('active', '==', true),
  )));
  assert.equal(list.docs.length, 2);
  assert.equal(list.docs[0].data().guardianPhone, undefined);
  await assertFails(getDoc(doc(seller, 'students', 'ST-LEGACY-1')));
  await assertFails(setDoc(
    doc(owner, 'inventory_student_directory', 'ST-LEGACY-1'), {
      studentId: 'ST-LEGACY-1', fullName: 'Hina Khan',
      rollNo: '10007', classId: 'class-4', active: true,
      guardianPhone: 'PRIVATE', updatedAt: serverTimestamp(),
    },
  ));
});

test('owner can commit a five-student safe directory backfill atomically', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    for (let i = 0; i < 5; i++) {
      await setDoc(doc(context.firestore(), 'students', 'ST-BATCH-' + i), {
        fullName: 'Student ' + i, rollNo: '1000' + i,
        classId: 'class-5', active: true, status: 'admitted',
      });
    }
  });
  const owner = db(ownerId);
  const batch = writeBatch(owner);
  for (let i = 0; i < 5; i++) {
    batch.set(doc(owner, 'inventory_student_directory', 'ST-BATCH-' + i), {
      studentId: 'ST-BATCH-' + i, fullName: 'Student ' + i,
      rollNo: '1000' + i, classId: 'class-5', active: true,
      updatedAt: serverTimestamp(),
    });
  }
  await assertSucceeds(batch.commit());
  for (let i = 0; i < 5; i++) {
    const docSnap = await assertSucceeds(getDoc(doc(
      db(sellerId), 'inventory_student_directory', 'ST-BATCH-' + i)));
    assert.equal(docSnap.data().fullName, 'Student ' + i);
  }
});

test('canteen seller records paid Student Teacher and Other quick sales with no identity lookup', async () => {
  const seller = db(sellerId);
  for (const customerType of ['student', 'teacher', 'other']) {
    const saleId = 'quick-' + customerType;
    const product = doc(seller, 'inventory_items', itemId);
    const receipt = doc(seller, 'inventory_sales', saleId);
    const label = customerType[0].toUpperCase() + customerType.slice(1);
    await assertSucceeds(runTransaction(seller, async tx => {
      const stock = (await tx.get(product)).data();
      tx.update(product, {
        stockQty: stock.stockQty - 1,
        lastMovementId: saleId, lastMovementType: 'sale',
        updatedBy: sellerId, updatedAt: serverTimestamp(),
      });
      tx.set(receipt, {
        saleId, orderId: 'order-quick-' + customerType, lineNumber: 1,
        itemId, itemName: stock.name, department: 'canteen',
        quantity: 1, stockBefore: stock.stockQty,
        unitPriceMinor: stock.priceMinor, totalMinor: stock.priceMinor,
        currency: 'PKR', sellerUid: sellerId, paymentMethod: 'Cash',
        customerType, customerId: '', customerName: label,
        customerPhone: '', customerClass: '', customerRollNo: '',
        paidMinor: stock.priceMinor, paymentStatus: 'paid',
        lastPaymentId: '', soldAt: serverTimestamp(),
      });
    }));
    const recorded = await getDoc(receipt);
    assert.equal(recorded.data().customerType, customerType);
    assert.equal(recorded.data().customerId, '');
    assert.equal(recorded.data().customerName, label);
  }
  assert.equal((await getDoc(doc(seller, 'inventory_items', itemId)))
    .data().stockQty, 7);
});

test('quick checkout cannot borrow or impersonate identified students and cannot sell stationery', async () => {
  const seller = db(sellerId);
  async function attempt({customerType = 'student', name = 'Student',
    paid = true, department = 'canteen', customerId = ''}) {
    const itemRef = doc(seller, 'inventory_items',
      department === 'canteen' ? itemId : 'BOOKFAST');
    const receiptRef = doc(seller, 'inventory_sales',
      'negative-' + Math.random().toString(36).slice(2));
    return runTransaction(seller, async tx => {
      const snap = await tx.get(itemRef);
      const item = snap.data();
      tx.update(itemRef, {
        stockQty: item.stockQty - 1, lastMovementId: receiptRef.id,
        lastMovementType: 'sale', updatedBy: sellerId,
        updatedAt: serverTimestamp(),
      });
      tx.set(receiptRef, {
        saleId: receiptRef.id, orderId: 'order-negative-case', lineNumber: 1,
        itemId: itemRef.id, itemName: item.name, department,
        quantity: 1, stockBefore: item.stockQty,
        unitPriceMinor: item.priceMinor, totalMinor: item.priceMinor,
        currency: 'PKR', sellerUid: sellerId,
        paymentMethod: paid ? 'Cash' : 'Unpaid',
        customerType, customerId, customerName: name,
        customerPhone: '', customerClass: '', customerRollNo: '',
        paidMinor: paid ? item.priceMinor : 0,
        paymentStatus: paid ? 'paid' : 'borrowed',
        lastPaymentId: '', soldAt: serverTimestamp(),
      });
    });
  }
  await environment.withSecurityRulesDisabled(async context => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'inventory_items', 'BOOKFAST'), {
      ...seedItem(), sku: 'BOOKFAST', name: 'Exercise book',
      department: 'stationery',
    });
  });
  await assertFails(attempt({paid: false}));
  await assertFails(attempt({department: 'stationery'}));
  await assertFails(attempt({name: 'Fake student'}));
  await assertFails(attempt({customerId: 'ST-FAKE'}));
  await assertFails(attempt({customerType: 'teacher', name: 'Fake teacher'}));
  // Failed transactions do not write stock decrements.
  assert.equal((await getDoc(doc(seller, 'inventory_items', itemId)))
    .data().stockQty, 10);
  assert.equal((await getDoc(doc(seller, 'inventory_items', 'BOOKFAST')))
    .data().stockQty, 10);
});
