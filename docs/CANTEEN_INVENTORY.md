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
