import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, collection, updateDoc, runTransaction,
  query, where, collectionGroup, serverTimestamp, Timestamp, writeBatch, arrayUnion,
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

test('confidential unit purchase cost is visible only to owner and managers', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'inventory_costs', itemId), {
      sku: itemId, department: 'canteen', unitCostMinor: 3200,
      currency: 'PKR', createdBy: managerId, createdAt: Timestamp.now(),
      updatedBy: managerId, updatedAt: Timestamp.now(),
    });
  });
  const seller = db(sellerId);
  const publicProduct = await assertSucceeds(
    getDoc(doc(seller, 'inventory_items', itemId)));
  assert.equal(publicProduct.data().unitCostMinor, undefined);
  await assertFails(getDoc(doc(seller, 'inventory_costs', itemId)));
  await assertFails(getDocs(collection(seller, 'inventory_costs')));
  await assertFails(getDoc(doc(db(guestId), 'inventory_costs', itemId)));
  const manager = db(managerId);
  const privateCost = await assertSucceeds(
    getDoc(doc(manager, 'inventory_costs', itemId)));
  assert.equal(privateCost.data().unitCostMinor, 3200);
  await assertFails(updateDoc(doc(seller, 'inventory_costs', itemId), {
    unitCostMinor: 1,
  }));
});

test('new canteen stock records private unit cost plus valued opening purchase atomically', async () => {
  const manager = db(managerId);
  const sku = 'CN-NEWVALUED01';
  const product = doc(manager, 'inventory_items', sku);
  const cost = doc(manager, 'inventory_costs', sku);
  const opening = doc(manager, 'inventory_adjustments', 'open-valued-new');
  const purchase = doc(manager, 'inventory_purchases', 'purchase-valued-new');
  await assertSucceeds(runTransaction(manager, async tx => {
    const existing = await tx.get(product);
    assert.equal(existing.exists(), false);
    const existingCost = await tx.get(cost);
    assert.equal(existingCost.exists(), false);
    tx.set(cost, {
      sku, department: 'canteen', unitCostMinor: 4000, currency: 'PKR',
      createdBy: managerId, createdAt: serverTimestamp(),
      updatedBy: managerId, updatedAt: serverTimestamp(),
    });
    tx.set(product, {
      ...seedItem(), sku, name: 'New juice',
      priceMinor: 7000, stockQty: 20,
      lastMovementId: opening.id, lastMovementType: 'opening',
      createdBy: managerId, createdAt: serverTimestamp(),
      updatedBy: managerId, updatedAt: serverTimestamp(),
    });
    tx.set(opening, {
      adjustmentId: opening.id, itemId: sku, itemName: 'New juice',
      delta: 20, stockBefore: 0, reason: 'opening',
      notes: 'Opening quantity entered on new product',
      recordedBy: managerId, recordedAt: serverTimestamp(),
    });
    tx.set(purchase, {
      purchaseId: purchase.id, itemId: sku, itemName: 'New juice',
      quantity: 20, stockBefore: 0, unitCostMinor: 4000,
      totalCostMinor: 80000, supplier: 'Opening stock',
      invoice: '', source: 'opening', currency: 'PKR',
      recordedBy: managerId, purchasedAt: serverTimestamp(),
      recordedAt: serverTimestamp(),
    });
  }));
  assert.equal((await getDoc(product)).data().stockQty, 20);
  assert.equal((await getDoc(cost)).data().unitCostMinor, 4000);
  assert.equal((await getDoc(purchase)).data().totalCostMinor, 80000);
  await assertFails(getDoc(doc(db(sellerId), 'inventory_purchases',
    'purchase-valued-new')));
  await assertFails(getDoc(doc(db(sellerId), 'inventory_costs', sku)));
});

test('manager can update cost without changing public selling price', async () => {
  const manager = db(managerId);
  const cost = doc(manager, 'inventory_costs', itemId);
  await assertSucceeds(setDoc(cost, {
    sku: itemId, department: 'canteen', unitCostMinor: 2500,
    currency: 'PKR', createdBy: managerId, createdAt: serverTimestamp(),
    updatedBy: managerId, updatedAt: serverTimestamp(),
  }));
  await assertSucceeds(updateDoc(cost, {
    unitCostMinor: 2750, updatedBy: managerId,
    updatedAt: serverTimestamp(),
  }));
  assert.equal((await getDoc(cost)).data().unitCostMinor, 2750);
  assert.equal((await getDoc(doc(manager, 'inventory_items', itemId)))
    .data().priceMinor, 5000);
  await assertFails(updateDoc(cost, {createdBy: sellerId}));
  await assertFails(updateDoc(cost, {unitCostMinor: -1}));
});


function termPaper({examiner,cycleId='2026_first',category='First Term',classId='C1',staffId='T1',assignmentId='A1',subject='Math',date='2026-01-02'}) {
  return {cycleId,sessionId:'session',kind:'term',category,title:subject,assignmentId,staffId,classId,subject,
    maxMarks:100,active:true,resultStatus:'draft',createdBy:examiner,
    startDate:'2026-01-01',endDate:'2026-01-30',examDate:date,
    paperType:'Theory',durationMinutes:60,startMinute:540,endMinute:600,
    endAt:Timestamp.fromDate(new Date('2026-01-02T05:00:00Z')),
    expectedStudentIds:['S1','S2'],rosterSnapshot:{S1:{fullName:'Student 1',rollNo:'1'},S2:{fullName:'Student 2',rollNo:'2'}},
    markedStudentIds:[]};
}
function termRecord(examiner,ids,slots,{year=2026,category='First Term',planned=['C1'],classId='C1'}={}) {
  return {academicYear:year,category,title:category,status:'active',startDate:'2026-01-01',endDate:'2026-01-30',
    excludedDates:{},skipSunday:false,plannedClassIds:planned,classIds:[classId],paperIds:ids,
    releasedPaperIds:[],slots,lastClassId:classId,createdBy:examiner,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
}
async function publishTerm(database,examiner,id,papers,{category='First Term',planned=['C1']}={}) {
  const batch=writeBatch(database);
  const ids=Object.keys(papers);
  const classId=papers[ids[0]].classId;
  const slots=Object.fromEntries(ids.map(p=>[classId+'__'+papers[p].examDate,p]));
  batch.set(doc(database,'exam_term_control','current'),{cycleId:id,updatedAt:serverTimestamp()});
  batch.set(doc(database,'exam_term_cycles',id),termRecord(examiner,ids,slots,{category,planned,classId}));
  for(const [key,data] of Object.entries(papers)) batch.set(doc(database,'examinations',key),data);
  return batch.commit();
}
async function recordExamMark(database,teacher,examId,studentId,score) {
  const batch=writeBatch(database);
  batch.set(doc(database,'examinations',examId,'marks',studentId),{examId,studentId,classId:'C1',teacherUid:teacher,score});
  const paper=doc(database,'examinations',examId);
  // Use arrayUnion as the real app does.
  batch.update(paper,{markedStudentIds:arrayUnion(studentId),lastMarkedStudentId:studentId,updatedAt:serverTimestamp()});
  return batch.commit();
}
async function releaseExam(database,cycleId,examId) {
  const batch=writeBatch(database);
  batch.update(doc(database,'examinations',examId),{resultStatus:'released',updatedAt:serverTimestamp()});
  batch.update(doc(database,'exam_term_cycles',cycleId),{releasedPaperIds:arrayUnion(examId),lastPaperId:examId,updatedAt:serverTimestamp()});
  return batch.commit();
}
async function closeExam(database,id,uid) {
  return updateDoc(doc(database,'exam_term_cycles',id),{status:'closed',closedBy:uid,closedAt:serverTimestamp(),updatedAt:serverTimestamp()});
}
test('annual exam locks, complete marks, release and closure are enforced', async () => {
  const examiner='examiner-uid',teacher='exam-teacher-uid';
  await environment.withSecurityRulesDisabled(async context => {
    const admin=context.firestore();
    await setDoc(doc(admin,'users',examiner),{role:'principal',active:true});
    await setDoc(doc(admin,'users',teacher),{role:'teacher',active:true,staffId:'T1'});
    await setDoc(doc(admin,'staff','T1'),{active:true,roleType:'teacher'});
    await setDoc(doc(admin,'classes','C1'),{active:true});
    await setDoc(doc(admin,'classes','C1','subjects','math'),{active:true,name:'Math'});
    await setDoc(doc(admin,'teacher_assignments','A1'),{active:true,staffId:'T1',classId:'C1',subject:'Math',subjectId:'math'});
    await setDoc(doc(admin,'teacher_class_links','T1__C1'),{active:true,staffId:'T1',classId:'C1'});
    for(const id of ['S1','S2','S3']) await setDoc(doc(admin,'class_rosters','C1','students',id),{active:true,classId:'C1',fullName:id});
    await setDoc(doc(admin,'students','S1'),{fullName:'Student',guardianPhone:'private'});
  });
  const manager=db(examiner), tutor=db(teacher), fields=termPaper({examiner});
  await assertFails(setDoc(doc(manager,'examinations','direct'),fields));
  await assertSucceeds(publishTerm(manager,examiner,'2026_first',{E1:fields}));
  const middle=termPaper({examiner,cycleId:'2026_mid',category:'Mid Term'});
  await assertFails(publishTerm(manager,examiner,'2026_mid',{E2:middle},{category:'Mid Term'}));
  await assertFails(closeExam(manager,'2026_first',examiner));
  await assertFails(updateDoc(doc(manager,'exam_term_cycles','2026_first'),{releasedPaperIds:['E1'],lastPaperId:'E1',updatedAt:serverTimestamp()}));
  await assertSucceeds(getDocs(query(collection(tutor,'examinations'),where('staffId','==','T1'),where('active','==',true))));
  await environment.withSecurityRulesDisabled(async context=>{
    await setDoc(doc(context.firestore(),'users','review-examiner'),{role:'examiner',active:true});
  });
  const review=db('review-examiner');
  await assertFails(getDoc(doc(review,'students','S1')));
  await assertFails(getDoc(doc(review,'staff','T1')));
  await assertFails(getDoc(doc(review,'inventory_purchases','sample-purchase')));
  await assertFails(publishTerm(review,'review-examiner','2026_mid',{E3:{...middle,createdBy:'review-examiner'}},{category:'Mid Term'}));
  await assertFails(setDoc(doc(tutor,'examinations','formal'),{...fields,createdBy:teacher}));
  const classTest={...fields,kind:'test',category:'Monthly Test',createdBy:teacher};
  delete classTest.cycleId;
  await assertSucceeds(setDoc(doc(tutor,'examinations','test'),classTest));
  const work={kind:'assignment',title:'Exercise',active:true,teacherUid:examiner,assignmentId:'A1',staffId:'T1',classId:'C1',subject:'Math'};
  await assertSucceeds(setDoc(doc(manager,'classwork','W1'),work));
  await assertFails(setDoc(doc(manager,'classwork','H1'),{...work,kind:'homework'}));
  await assertSucceeds(setDoc(doc(tutor,'classwork','H2'),{...work,kind:'homework',teacherUid:teacher}));
  const submission={resultStatus:'submitted',submittedBy:teacher,submittedAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(updateDoc(doc(tutor,'examinations','E1'),submission));
  await assertFails(recordExamMark(tutor,teacher,'E1','S3',80));
  await assertSucceeds(recordExamMark(tutor,teacher,'E1','S1',80));
  await assertFails(updateDoc(doc(tutor,'examinations','E1'),{markedStudentIds:['S1','S2'],lastMarkedStudentId:'S2',updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(tutor,'examinations','E1'),submission));
  await assertSucceeds(recordExamMark(tutor,teacher,'E1','S2',70));
  await assertSucceeds(updateDoc(doc(tutor,'examinations','E1'),submission));
  await assertFails(recordExamMark(tutor,teacher,'E1','S1',90));
  await assertFails(updateDoc(doc(manager,'examinations','E1'),{resultStatus:'released',updatedAt:serverTimestamp()}));
  await assertSucceeds(releaseExam(manager,'2026_first','E1'));
  await assertSucceeds(closeExam(manager,'2026_first',examiner));
  await assertFails(updateDoc(doc(manager,'examinations','E1'),{resultStatus:'draft',updatedAt:serverTimestamp()}));
  await assertSucceeds(publishTerm(manager,examiner,'2026_mid',{E2:middle},{category:'Mid Term'}));
  await assertFails(publishTerm(manager,examiner,'2026_first',{duplicate:fields}));
});

test('term supports 15 distinct papers in one class and appends a second class', async () => {
  const examiner='schedule-examiner';
  await environment.withSecurityRulesDisabled(async context => {
    const admin=context.firestore();
    await setDoc(doc(admin,'users',examiner),{role:'principal',active:true});
    for(let i=0;i<16;i++) {
      await setDoc(doc(admin,'teacher_assignments','multi-'+i),{active:true,staffId:'teacher-'+i,classId:i===15?'C2':'C1',subject:'Subject '+i});
    }
  });
  const database=db(examiner), papers={};
  for(let i=0;i<15;i++) papers['paper-'+i]=termPaper({examiner,cycleId:'2026_mid',category:'Mid Term',
    staffId:'teacher-'+i,assignmentId:'multi-'+i,subject:'Subject '+i,date:'2026-01-'+String(i+1).padStart(2,'0')});
  await assertSucceeds(publishTerm(database,examiner,'2026_mid',papers,{category:'Mid Term',planned:['C1','C2']}));
  const second=termPaper({examiner,cycleId:'2026_mid',category:'Mid Term',classId:'C2',staffId:'teacher-15',
    assignmentId:'multi-15',subject:'Subject 15',date:'2026-01-02'});
  const batch=writeBatch(database);
  batch.set(doc(database,'examinations','second'),second);
  batch.update(doc(database,'exam_term_cycles','2026_mid'),{classIds:arrayUnion('C2'),paperIds:arrayUnion('second'),
    'slots.C2__2026-01-02':'second',lastClassId:'C2',updatedAt:serverTimestamp()});
  await assertSucceeds(batch.commit());
  await assertFails(closeExam(database,'2026_mid',examiner));
});

test('holiday exclusion and paper reschedule preserve slots and audit reason', async () => {
  const examiner='holiday-examiner';
  await environment.withSecurityRulesDisabled(async context=>{
    const admin=context.firestore();
    await setDoc(doc(admin,'users',examiner),{role:'principal',active:true});
    await setDoc(doc(admin,'teacher_assignments','A1'),{active:true,staffId:'T1',classId:'C1',subject:'Math'});
    await setDoc(doc(admin,'teacher_assignments','A2'),{active:true,staffId:'T2',classId:'C1',subject:'English'});
  });
  const database=db(examiner);
  await assertSucceeds(publishTerm(database,examiner,'2026_first',{
    E1:termPaper({examiner}),E2:termPaper({examiner,staffId:'T2',assignmentId:'A2',subject:'English',date:'2026-01-03'})}));
  const cycle=doc(database,'exam_term_cycles','2026_first'),paper=doc(database,'examinations','E1');
  await assertSucceeds(updateDoc(cycle,{excludedDates:{'2090-01-04':'School closure'},updatedAt:serverTimestamp()}));
  async function move(date,slots) {
    const batch=writeBatch(database);
    batch.update(paper,{examDate:date,endDate:date,startMinute:600,endMinute:660,durationMinutes:60,
      endAt:Timestamp.fromDate(new Date('2090-01-06T06:00:00Z')),rescheduleReason:'School closure',
      rescheduleHistory:[{previousDate:'2026-01-02',newDate:date,reason:'School closure'}],updatedAt:serverTimestamp()});
    batch.update(cycle,{slots,endDate:date,lastPaperId:'E1',updatedAt:serverTimestamp()});
    return batch.commit();
  }
  await assertFails(move('2090-01-04',{'C1__2090-01-04':'E1','C1__2026-01-03':'E2'}));
  await assertSucceeds(move('2090-01-06',{'C1__2090-01-06':'E1','C1__2026-01-03':'E2'}));
});

test('owner can suspend, configure parent links and remove accounts; principal and parent cannot alter them',async()=>{
  const parent='guardian-one', principal='principal-one';
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    await setDoc(doc(a,'users',parent),{active:true,role:'parent',linkedStudentIds:['S1']});
    await setDoc(doc(a,'users',principal),{active:true,role:'principal'});
    await setDoc(doc(a,'students','S1'),{fullName:'Student'});
    await setDoc(doc(a,'examinations','private-exam'),{active:true,rosterSnapshot:{S1:{fullName:'Student'},S2:{fullName:'Other'}}});
  });
  const own=db(ownerId),p=db(parent),admin=db(principal);
  const target=database=>doc(database,'users',parent);
  const patch={permissions:{parent_fees:false},linkedStudentIds:['S1'],updatedAt:serverTimestamp()};
  await assertFails(updateDoc(target(p),patch));
  await assertFails(updateDoc(target(admin),patch));
  await assertSucceeds(updateDoc(target(own),patch));
  await assertFails(updateDoc(target(own),{permissions:{teacher_payroll:true},updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(p,'students','S1')));
  await assertFails(getDoc(doc(p,'examinations','private-exam')));
  await assertSucceeds(updateDoc(target(own),{active:false,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(target(own),{active:true,updatedAt:serverTimestamp()}));
  await assertSucceeds(updateDoc(target(own),{active:false,removed:true,removedAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(target(own),{active:true,updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(target(own),{removed:false,updatedAt:serverTimestamp()}));
});
test('disabled teacher capabilities deny direct Firestore reads and writes',async()=>{
  const teacher='restricted-teacher';
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    await setDoc(doc(a,'users',teacher),{active:true,role:'teacher',staffId:'T1',permissions:{teacher_profile:false,teacher_academics:false,teacher_classwork:false}});
    await setDoc(doc(a,'staff','T1'),{active:true,roleType:'teacher'});
    await setDoc(doc(a,'classes','C1'),{active:true});
    await setDoc(doc(a,'teacher_assignments','A1'),{active:true,staffId:'T1',classId:'C1',subject:'Math'});
    await setDoc(doc(a,'examinations','E1'),{active:true,staffId:'T1',classId:'C1',subject:'Math'});
    await setDoc(doc(a,'classwork','W1'),{active:true,staffId:'T1',classId:'C1',subject:'Math'});
  });
  const tutor=db(teacher);
  await assertFails(getDoc(doc(tutor,'staff','T1')));
  await assertFails(getDoc(doc(tutor,'examinations','E1')));
  await assertFails(getDoc(doc(tutor,'classwork','W1')));
  await assertFails(setDoc(doc(tutor,'classwork','W2'),{kind:'homework',teacherUid:teacher,active:true,title:'Homework',staffId:'T1',assignmentId:'A1',classId:'C1',subject:'Math'}));
});

test('teacher direct profile, contract and payroll reads stay scoped and read-only',async()=>{
  const teacher='portal-teacher',other='portal-other';
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    await setDoc(doc(a,'users',teacher),{active:true,role:'teacher',staffId:'T1'});
    await setDoc(doc(a,'users',other),{active:true,role:'teacher',staffId:'T2'});
    for(const id of ['T1','T2']){
      await setDoc(doc(a,'staff',id),{active:true,roleType:'teacher'});
      await setDoc(doc(a,'staff_contracts',id),{type:'Full time'});
      await setDoc(doc(a,'finance_salary_rates',id),{staffId:id,amountMinor:10000});
      await setDoc(doc(a,'finance_salary_bills','bill-'+id),{staffId:id,amountMinor:10000,paidMinor:0});
    }
  });
  const tutor=db(teacher),own=db(ownerId);
  for(const collectionName of ['staff','staff_contracts','finance_salary_rates']){
    await assertSucceeds(getDoc(doc(tutor,collectionName,'T1')));
    await assertFails(getDoc(doc(tutor,collectionName,'T2')));
    await assertFails(updateDoc(doc(tutor,collectionName,'T1'),{amountMinor:999999}));
  }
  await assertSucceeds(getDocs(query(collection(tutor,'finance_salary_bills'),where('staffId','==','T1'))));
  await assertFails(getDocs(collection(tutor,'finance_salary_bills')));
  await assertFails(getDoc(doc(tutor,'finance_salary_bills','bill-T2')));
  await assertFails(updateDoc(doc(tutor,'finance_salary_bills','bill-T1'),{paidMinor:10000}));
  await assertSucceeds(updateDoc(doc(own,'users',teacher),{permissions:{teacher_payroll:false,teacher_profile:false},updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(tutor,'finance_salary_rates','T1')));
  await assertFails(getDocs(query(collection(tutor,'finance_salary_bills'),where('staffId','==','T1'))));
  await assertFails(getDoc(doc(tutor,'staff_contracts','T1')));
});
test('private conversations permit own messages and school replies but block impersonation and cross-account access',async()=>{
  const teacher='msg-teacher',other='msg-other',principal='msg-principal';
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    for(const [uid,role] of [[teacher,'teacher'],[other,'teacher'],[principal,'principal']])
      await setDoc(doc(a,'users',uid),{active:true,role,displayName:uid});
  });
  const tutor=db(teacher),admin=db(principal),stranger=db(other),own=db(ownerId);
  async function send(database,target,sender,fromSchool,id){
    const batch=writeBatch(database);
    batch.set(doc(database,'portal_threads',target),{uid:target,name:target,role:'teacher',updatedAt:serverTimestamp()},{merge:true});
    batch.set(doc(database,'portal_threads',target,'messages',id),{text:'Hello',senderUid:sender,fromSchool,createdAt:serverTimestamp()});
    return batch.commit();
  }
  await assertSucceeds(send(tutor,teacher,teacher,false,'first'));
  await assertFails(send(tutor,teacher,teacher,true,'forged'));
  await assertFails(send(stranger,teacher,other,false,'cross'));
  await assertFails(getDocs(collection(stranger,'portal_threads',teacher,'messages')));
  await assertFails(getDocs(collection(tutor,'portal_threads')));
  await assertSucceeds(getDocs(collection(admin,'portal_threads')));
  await assertSucceeds(send(admin,teacher,principal,true,'reply'));
  await assertSucceeds(getDocs(collection(tutor,'portal_threads',teacher,'messages')));
  await assertFails(updateDoc(doc(tutor,'portal_threads',teacher,'messages','first'),{text:'edited'}));
  await assertSucceeds(updateDoc(doc(own,'users',teacher),{permissions:{messages:false},updatedAt:serverTimestamp()}));
  await assertFails(getDocs(collection(tutor,'portal_threads',teacher,'messages')));
  await assertFails(send(tutor,teacher,teacher,false,'blocked'));
});

test('new parent account and guardian emails are saved atomically by owner only',async()=>{
  const guardian='new-parent-profile', child='parent-child-new';
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    await setDoc(doc(a,'students',child),{admissionNo:child,rollNo:'12345',status:'admitted',active:true,
      guardianName:'Guardian',details:{guardian:{firstName:'Guardian',email:'old@example.com'},student:{firstName:'Child'}}});
    await setDoc(doc(a,'users','parent-creator-principal'),{active:true,role:'principal'});
  });
  const own=db(ownerId), principal=db('parent-creator-principal');
  const profile={role:'parent',displayName:'Guardian',email:'new@example.com',active:true,
    linkedStudentIds:[child],createdBy:ownerId,createdAt:serverTimestamp(),updatedAt:serverTimestamp()};
  await assertFails(setDoc(doc(own,'users','empty-parent'),{...profile,linkedStudentIds:[]}));
  await assertFails(setDoc(doc(own,'users','duplicate-child-parent'),{...profile,linkedStudentIds:[child,child]}));
  async function create(database){
    const batch=writeBatch(database);
    batch.set(doc(database,'users',guardian),profile);
    batch.update(doc(database,'students',child),{'details.guardian.email':'new@example.com',updatedAt:serverTimestamp()});
    return batch.commit();
  }
  await assertFails(create(principal));
  assert.equal((await getDoc(doc(own,'students',child))).data().details.guardian.email,'old@example.com');
  await assertSucceeds(create(own));
  assert.deepEqual((await getDoc(doc(own,'users',guardian))).data().linkedStudentIds,[child]);
  assert.equal((await getDoc(doc(own,'students',child))).data().details.guardian.email,'new@example.com');
  assert.equal((await getDoc(doc(own,'students',child))).data().details.student.firstName,'Child');
  await assertFails(updateDoc(doc(db(guardian),'students',child),{'details.guardian.email':'tampered@example.com'}));
});

test('parent portal reads only linked child views, live fees, attendance and released marks',async()=>{
  const uid='portal-parent', child='PC1', other='PC2', klass='PC-A', otherClass='PC-B';
  const file='student-documents/PC1/other/one.pdf';
  const attachments={one:{path:file,name:'One',contentType:'application/pdf'}};
  const paper={classId:klass,title:'Math',subject:'Math',active:true,resultStatus:'draft',maxMarks:100,examDate:'2026-12-01'};
  await environment.withSecurityRulesDisabled(async ctx=>{
    const a=ctx.firestore();
    await setDoc(doc(a,'users',uid),{role:'parent',active:true,linkedStudentIds:[child]});
    for(const [id,c] of [[child,klass],[other,otherClass]]){
      await setDoc(doc(a,'students',id),{status:'admitted',classId:c,fullName:id,photoPath:'',attachments:id===child?attachments:{}});
      await setDoc(doc(a,'parent_children',id),{fullName:id,classId:c});
      await setDoc(doc(a,'parent_profiles',id),{fullName:id,classId:c});
      await setDoc(doc(a,'parent_documents',id),{photoPath:'',attachments:id===child?attachments:{}});
      await setDoc(doc(a,'finance_fee_bills',id),{studentId:id,amountMinor:1000,paidMinor:0});
      await setDoc(doc(a,'parent_attendance',id,'days','day'),{studentId:id,classId:c,date:'2026-11-01',status:'present'});
      await setDoc(doc(a,'class_rosters',c,'students',id),{studentId:id,classId:c,active:true});
    }
    await setDoc(doc(a,'examinations','PE1'),{...paper,rosterSnapshot:{PC1:{fullName:'Child'},PC2:{fullName:'Other'}}});
    await setDoc(doc(a,'examinations','PE1','marks',child),{studentId:child,score:70});
    await setDoc(doc(a,'examinations','PE1','marks',other),{studentId:other,score:99});
    await setDoc(doc(a,'parent_class_schedules',klass,'papers','PE1'),paper);
  });
  const parent=db(uid), own=db(ownerId);
  await assertSucceeds(getDoc(doc(parent,'parent_children',child)));
  await assertSucceeds(getDoc(doc(parent,'parent_profiles',child)));
  await assertSucceeds(getDoc(doc(parent,'parent_documents',child)));
  await assertFails(getDoc(doc(parent,'students',child)));
  await assertFails(getDoc(doc(parent,'parent_profiles',other)));
  await assertFails(getDocs(collection(parent,'parent_profiles')));
  await assertFails(updateDoc(doc(parent,'parent_profiles',child),{fullName:'Changed'}));
  await assertSucceeds(getDocs(query(collection(parent,'finance_fee_bills'),where('studentId','==',child))));
  await assertFails(getDocs(collection(parent,'finance_fee_bills')));
  await assertFails(getDocs(query(collection(parent,'finance_fee_bills'),where('studentId','==',other))));
  await assertSucceeds(getDocs(collection(parent,'parent_attendance',child,'days')));
  await assertFails(getDocs(collection(parent,'parent_attendance',other,'days')));
  await assertFails(getDocs(query(collectionGroup(parent,'marks'),where('studentId','==',child))));
  await assertSucceeds(getDocs(query(collectionGroup(own,'marks'),where('studentId','==',child))));
  const grant=c=>doc(parent,'parent_class_grants',uid,'classes',c);
  await assertFails(getDocs(collection(parent,'parent_class_schedules',klass,'papers')));
  await assertFails(setDoc(grant(otherClass),{studentId:child}));
  await assertFails(setDoc(grant(otherClass),{studentId:other}));
  await assertSucceeds(setDoc(grant(klass),{studentId:child}));
  await assertSucceeds(getDocs(collection(parent,'parent_class_schedules',klass,'papers')));
  await assertFails(getDoc(doc(parent,'examinations','PE1')));
  await assertFails(getDoc(doc(parent,'examinations','PE1','marks',child)));
  await environment.withSecurityRulesDisabled(async ctx=>{
    await updateDoc(doc(ctx.firestore(),'examinations','PE1'),{resultStatus:'released'});
  });
  await assertSucceeds(getDoc(doc(parent,'examinations','PE1','marks',child)));
  await assertFails(getDoc(doc(parent,'examinations','PE1','marks',other)));
  await assertFails(getDocs(collection(parent,'examinations','PE1','marks')));
  await assertFails(setDoc(doc(parent,'parent_class_schedules',klass,'papers','PE1'),paper));
  await assertSucceeds(setDoc(doc(own,'parent_class_schedules',klass,'papers','PE1'),{...paper,resultStatus:'released'}));
  await assertFails(setDoc(doc(own,'parent_class_schedules',klass,'papers','PE1'),{...paper,resultStatus:'released',rosterSnapshot:{PC2:'Other'}}));
  // Removing the attachment revokes the stale parent view immediately.
  await assertSucceeds(updateDoc(doc(own,'students',child),{attachments:{}}));
  await assertFails(getDoc(doc(parent,'parent_documents',child)));
  await assertSucceeds(updateDoc(doc(own,'users',uid),{permissions:{parent_fees:false,parent_exams:false},updatedAt:serverTimestamp()}));
  await assertFails(getDocs(query(collection(parent,'finance_fee_bills'),where('studentId','==',child))));
  await assertFails(getDocs(collection(parent,'parent_class_schedules',klass,'papers')));
  await assertFails(getDoc(doc(parent,'examinations','PE1','marks',child)));
  await assertSucceeds(updateDoc(doc(own,'users',uid),{active:false,updatedAt:serverTimestamp()}));
  await assertFails(getDoc(doc(parent,'parent_profiles',child)));
  await assertFails(getDocs(collection(parent,'parent_attendance',child,'days')));
});

 test('owner can export nested records, other accounts cannot enumerate collection groups', async () => {
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(),'parent_classwork_history','child-a','items','work-a'),{title:'Private'});
    await setDoc(doc(context.firestore(),'portal_threads','parent-a','messages','message-a'),{text:'Private'});
  });
  for(const name of ['items','messages']){
    await assertSucceeds(getDocs(collectionGroup(db(ownerId),name)));
    await assertFails(getDocs(collectionGroup(db(sellerId),name)));
    await assertFails(getDocs(collectionGroup(db(guestId),name)));
  }
 });
