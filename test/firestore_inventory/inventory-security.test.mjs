import { readFileSync } from 'node:fs';
import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment, assertFails, assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, getDocs, collection, updateDoc, runTransaction,
  query, where, serverTimestamp, Timestamp,
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
