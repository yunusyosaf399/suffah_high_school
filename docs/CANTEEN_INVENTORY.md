## Purchase costs & department Analytics (November 2026)

### New product and purchase history

- **Canteen Sales → Stock** and **Stationery & Books → Stock** now require
  a **Purchase price (PKR)** as well as the **Selling price (PKR)**.
  Only the owner and inventory managers can access the purchase price.
- The sellable `inventory_items` document contains only the selling price,
  stock and catalog metadata. Confidential purchase cost lives in the
  separately protected `inventory_costs/{sku}` document. Sellers cannot
  read or write this collection (enforced by `firestore.rules`).
- A new product with quantity greater than zero writes the existing
  opening-stock audit adjustment AND a valued **Opening stock** purchase
  receipt to `inventory_purchases` atomically. No second stock increment
  occurs. This makes initial quantity and its unit cost visible in the
  owner's **Purchases** history.
- Subsequent purchases via **Receive stock** record the actual supplier,
  unit purchase price, quantity and time and update the current unit cost.
  Editing a product can change its owner-managed purchase cost but does
  not fabricate a historical purchase receipt.

### Analytics (owner / inventory manager)

Each department has its own **Analytics** tab and an independent trend
chart (sales, purchases and estimated gross profit). The filter offers:

- **Monthly**: choose year and month; graph by day
- **Yearly**: choose year; graph by month
- **All**: all available stored history, graph by month

Metrics: **Items available now** (live stock units, independent of date),
**Total items sold**, **Total purchases** (valued opening stock plus stock
purchase receipts), **Total profit (estimated)**, and **Sales value**.

Gross profit is estimated as sales revenue minus units sold times the
*current* confidential item purchase cost, not expenses or cash collected.
It can differ from historical invoice-level margin after cost changes.
If a sold product does not have a known purchase price, the profit card
shows a dash rather than inventing a complete total. When safety limits
(500 items/cost records or 2,500 sales/purchases) are reached, the screen
warns that historic values may be partial.

**Existing products** created before cost tracking have no automatically
known historic purchase price. Open **Edit product** and enter its true
purchase price. Older opening stock does not automatically become a
fictitious purchase or expenditure.

**Deployment:** Publish the entire updated `firestore.rules` file
before using the new forms or analytics. A source-code merge does not
publish live Firestore security rules.

---

## Separate Canteen and Stationery sales (November 2026)

**Owner dashboard** now has independent **Canteen Sales** and **Stationery &
Books** cards. Seller/inventory-manager accounts open a two-card shop home.
Each section shows only products, purchases and receipts for its department;
both still use the same secured stock and sales audit collections.

### Fast canteen checkout (during school break)

- Owner/inventory manager creates canteen products, prices, quantities and
  purchases in **Canteen Sales → Stock**. Sellers can only view inventory,
  add to cart, or sell.
- Seller opens **Canteen Sales → Sell**, taps **Sell now** on a product
  for a single-unit checkout, or **Add to cart** for multiple products.
- The checkout shows just quantity, total, **Student / Teacher / Other**
  customer category, and payment method (Cash by default). No name,
  registration, student lookup, guardian information or phone is requested.
- **Complete paid sale** performs an atomic server-price stock decrement and
  receipt creation. Canteen fast checkout does not offer borrowed credit:
  unnamed customers must never be assigned recoverable debt.
- Receipts appear in the **Canteen Sales → Sales/My sales** tab, separated
  from stationery sales. Cash received is included in existing sales
  analytics under the Canteen department.

### Detailed stationery checkout (unchanged)

- Open **Stationery & Books → Sell**, add books/notebooks/supplies to cart.
- Choose an individual student from the protected directory, or a named
  non-student customer. Select **Paid** or **Borrowed** as before.
- Outstanding credit remains under **Stationery & Books → Borrowed**.
  All inventory permissions, purchase logs, prices and repayments still
  follow the existing secure transaction rules.
- The protected student directory sync is needed only for **Stationery**;
  Canteen can sell immediately without student synchronization.

**Deployment:** The new anonymous-category canteen receipt format requires
publishing the updated repository `firestore.rules` in Firebase Console.
Older APKs do not provide the new quick checkout.

---

## Sales cart, customer credit and analytics (November 2026)

### Stationery seller checkout

1. Open **Stationery & Books → Sell**. Tap **Add to cart** for each
   product. Tap the **Cart** button, then change quantities with + / -.
   A single checkout accepts up to six distinct products and up to 100 units
   per product. The transaction re-reads each unit price and current stock
   from Firestore and commits *all* stock changes and sale lines atomically.
2. Under **Customer details**, choose:
   - **Student:** Search by name, student registration ID, roll number or
     class. The directory contains **only** registration ID, name, roll
     number and class; sellers cannot read admission, health, photo,
     guardians or contact documents.
   - **Other:** Enter customer name, and optionally a contact number;
     the number becomes mandatory for borrowed purchases.
3. Under **Payment**, choose **Paid** (and payment method) or **Borrowed**.
   **Paid** counts toward collected cash immediately. **Borrowed** removes
   stock but creates a receivable for the named customer and does not count
   as received cash.
4. Tap **Complete paid sale** or **Save borrowed sale** once.
   Every cart line receives an immutable sale record with the same order ID.
   The checkout uses no seller-supplied unit price.

### Borrowed balances and payment collection

- **Sales / My sales** groups recent sale lines by receipt, with customer,
  item quantities, total, paid amount and outstanding balance.
- **Borrowed** uses a separate server query, so older open credit sales are
  still collectible even when they fall outside recent sales. For sellers,
  it shows only their own borrowed sales; owners/managers can see all.
- Tap **Collect payment**, enter full or partial amount and method. A
  Firestore transaction allocates the collection across the order's
  outstanding lines. Each allocation writes an append-only
  `inventory_payments` event and updates only that receipt's payment
  balance/status. A later collection never reduces stock again.
- Fully paid lines disappear from the Borrowed query; the original sales
  remain in the Sales history. The form rejects amounts above the current
  outstanding balance. After reading server data, transaction retries
  prevent duplicate or lost payments.
- Sales created in older APK versions are interpreted as **paid** for
  backward-compatible historical reporting; they are not treated as debt.

### Student directory synchronization

The **owner** should open **Stationery & Books → Sell → Sync students for
checkout** after first deploying the updated Firestore rules. This
backfills the previously admitted students into
`inventory_student_directory`, excluding guardian/contact/health details.
Future admitted-student edits sync the directory automatically as a
best-effort follow-up without putting admission saves at risk.

### Finance → Analytics

The Finance **Analytics** tab has a separate **Canteen & Stationery sales
analytics** section: past six calendar months of sales and actual cash
collections, open credit balances, average order, quantities, canteen vs
stationery revenue, top products and month-by-month bars. These are **not**
mixed into tuition-fee or salary accounting.

Reporting queries are capped at the most recent 1,500 sale lines and
1,500 payment records; if a cap is reached the screen warns that totals
may be incomplete. Outstanding balances cover available receipt history,
not an unlimited all-time audited balance sheet.

### Firebase deployment requirements

1. Publish the **complete** repository `firestore.rules` in Firebase.
2. Create the composite index for `inventory_sales` with fields
   `sellerUid ASC` and `paymentStatus ASC` (Collection scope). The
   `firestore.indexes.json` file contains the required definition.

   **Important:** This repository did not previously track Firebase composite
   indexes. Firebase CLI index deployments can propose deletion of manually
   created indexes that aren't represented in the local file. **Before**
   running `firebase deploy --only firestore:indexes`, review and merge
   all existing indexes from the live Firebase project into the file, then
   review any deletion prompts carefully. Alternatively, create just this
   one index manually in the Firebase Console without disturbing others.

   Publish rules separately when needed:

   ```bash
   firebase deploy --only firestore:rules
   ```

   The new composite index must finish building before seller-specific
   Borrowed queries become available.
3. In the owner app, tap **Sync students for checkout**, then verify a
   named student credit checkout and a small partial/full collection.
4. Review role-based security tests and ensure the old client cannot
   create a credit sale without a customer/receipt. **Do not** grant
   sellers access to the full `students` collection.


# Canteen and Stationery — Controlled Inventory

## Permission model

**Only the owner can grant or revoke accounts.** The Owner → Users form
can create:
- **Canteen seller** (`canteen_seller`): read item names, SKU, current
  selling prices and quantities; record a sale at the server-stored price;
  view only their own sale receipts. They cannot add/edit items, edit prices,
  receive supplier purchases, change stock, view supplier purchase costs,
  adjust inventory or access school finances.
- **Inventory manager** (`inventory_manager`): an explicitly owner-approved
  account that can add/edit products and selling prices, receive stock,
  record damaged/expired/wasted items and stock corrections, and view
  purchases and all sale receipts. Cannot create additional users or
  access student data, payroll or school fees.
- **Owner**: has all inventory manager permissions and can create/suspend
  seller and manager accounts.
Other roles (principal, accountant, teacher, clerk, parent) cannot access this
module by default.

**The permissions must be enforced by the deployed `firestore.rules`, not
only by hiding buttons.** The app code alone is insufficient.

## Inventory records (Firestore)

| Collection | Purpose | Seller access |
| --- | --- | --- |
| `inventory_items/{SKU}` | Canteen/stationery, name, unit, selling price (integer paisa), quantity, low-stock threshold, active flag | Read only; linked stock decrement on sale only |
| `inventory_sales/{saleId}` | Immutable, timestamped single-item sale, units, snapshot price, total PKR, seller UID, payment method, stock-before | Create transaction; read own sales |
| `inventory_purchases/{purchaseId}` | Immutable supplier receipt, invoice, purchase cost, units, purchase and recording time | None |
| `inventory_adjustments/{adjustmentId}` | Immutable audited quantity correction with reason and signed delta | None |

Stock can be entered directly at item creation (including zero). A positive
opening balance creates a linked, immutable opening adjustment. The owner or
inventory manager can also record a **purchase/receive stock** operation. A sale
decreases stock using a Firestore transaction that re-reads the current item.
Security rules cross-check the sale and the corresponding item update
**after** the atomic transaction. The current seller cannot submit a cheaper
price, create a sale without the associated stock decrement, directly change
a stock count, or oversell. Purchases and adjustments similarly require
a matching item update and cannot be erased.

Selling prices are stored as integer paisa (e.g. Rs 85.50 = 8550).
Purchases and sales store timestamps with server-generated timestamps, not
the phone clock. `recordedBy` and `sellerUid` retain accountability.
No documents can be deleted; price or stock changes are never applied
retroactively to historical sales.

The seller sees prices and quantities but **not supplier costs**. Supplier
information is in separate manager-only purchase documents.

## Simplified product registration (2026 update)

Only an **owner or an owner-created inventory manager** can register, edit or
delete a product. The form has no manually entered SKU and no separate
"receive stock" step for the first stock balance.

- **Department:** Canteen or Stationery
- **Category and subcategory:** Department-specific dropdowns, with an **Other**
  option and free-text specification
- **Books:** Textbook, workbook, guide, story or reference books, select
  Playgroup–Class 12/O Level/A Level; optionally specify book series,
  subject and publisher
- **Notebooks:** Single-line, double-line, four-line, plain, graph, drawing,
  practical, registers and diaries; optionally enter pages/size; book series
  is not required
- **Other stationery:** Writing tools, paper, art and craft, geometry,
  examination materials, classroom tools, files, school accessories,
  printing/office supplies
- **Canteen:** Snacks, drinks, bakery, meals, sweets, fruits, dairy,
  packaged goods and Other; optionally enter brand, flavour, pack size
  and best-before date
- **Stock quantity:** Enter the **whole-number quantity directly** when
  adding or editing a product, e.g. 100. The owner can still use separate
  Receive Stock for later supplier purchases
- **Selling price:** Rupees, stored in integer paisa; low-stock threshold,
  unit and description remain available
- **Automatic item code:** Unique `ST-...` or `CN-...` generated on save.
  Codes are never reused after deletion

**Opening stock is auditable:** A non-zero initial quantity writes an
immutable `inventory_adjustments` opening record in the same Firestore
transaction as the product. A subsequent direct quantity edit records a
`correction` event in the same transaction as the item's metadata.
If a sale changed the stock while the owner was editing, saving rejects
stale numbers and asks the owner to reopen the item.

**Delete is reversible:** The owner/manager's Delete button archives the
product, marks it inactive and hides it from active sales and Stock.
A Show deleted products switch displays archived items with Restore.
Historical sales, purchases and stock records are never physically removed
and existing product codes never become available for reuse.

**Seller permissions are unchanged:** The seller can still see active
product names, selling prices, stock quantities and record sales at the
server-stored price. Sellers cannot add products, delete/restore,
change categories, adjust stock or set selling prices.

## Owner workflow

1. Build the new Android APK from the inventory feature branch.
2. **Before real inventory use**, publish the complete updated
   [Firestore rules](https://github.com/yunusyosaf399/suffah_high_school/blob/feature/canteen-stationery-inventory/firestore.rules)
   in [Firebase Console → Firestore Rules](https://console.firebase.google.com/project/suffah-high-school/firestore/rules).
   Publishing rules is a separate manual step; GitHub Actions do not deploy them.
3. Owner → Users → Create user account → choose **Canteen seller** or
   **Inventory manager**. Supply name and email and privately share the
   temporary password. Seller privileges are not self-assigned.
4. Owner/manager → **Inventory & Canteen → Stock → Add product**.
   Choose Canteen or Stationery, a subcategory, and fill out the relevant details.
   The SKU is generated automatically. Enter starting stock as a number.
5. To replenish stock later, tap **Receive stock** and record quantity,
   supplier and invoice details; later direct stock corrections are also audited.
6. Canteen seller signs in and opens **Sell**, chooses an item, enters
   quantity and payment method, confirms **Record sale**.
   They cannot enter the price. The stock count decreases immediately.
7. The seller checks **My sales** (up to 60 recent receipts). Owner/manager
   checks **Purchases** and **Sales**, low-stock warnings and stock ledger
   adjustments for expired/damaged/wasted goods.

## Important boundaries

This is the first **single-product point of sale**: each recorded sale
receives its own immutable receipt. Multi-item baskets, integrated cash
register/till closing, returns/refunds, supplier account balances,
inventory valuation by cost layers, barcode scanners, automatic purchasing
and receipt printing are *not yet implemented*. Purchases have automatic
server-recorded timestamps; separate historical invoice dates are not
yet editable. Lists show recent 60 transaction records, not full
accounting exports.

Canteen cash sales are kept in a **separate inventory sales collection**;
they are not automatically posted to the tuition/transport/salary ledger.
This avoids double counting until a formal school revenue integration
and reconciliation workflow is built. Do not treat the module as audited
accounting software.

## Verification

GitHub workflow `Inventory Security - Firestore Rules` uses the Firestore
emulator to check owner/manager access, seller read-only catalogue, seller
purchase-cost restrictions, legitimate sales, price manipulation,
direct stock edits and over-selling. Android Flutter tests verify visible
role-specific screens.

After publishing the rules, test with a **separate seller account** before
real operations. Make sure seller direct Firestore price writes return
permission-denied and no stock goes negative. If the Firebase Console still
has old rules, new inventory operations will be blocked regardless of
successful APK compilation.
