# Fees & Finance — Suffah High School

## Overview

The school finance module has eight tabs:

1. **Fee Setup:** owner-defined monthly tuition rates per class and individual monthly transport fees per student.
2. **Generate Finance:** tuition, transport, teacher salaries and recurring expense obligations for the current or immediately previous month.
3. **One-time Fees:** certificate, uniform, fines, examination, promotion, 2nd Time Tuition Fee and Other (description required).
4. **Collections:** collect full or partial payments against already generated student fee bills and record an immutable CREDIT receipt.
5. **Salary Setup:** salary structure per active teacher: basic + allowances + bonus.
6. **Pay Salary:** settle generated salary bills, display previous payments and remaining balances and record a DEBIT receipt.
7. **Expenses:** direct expenses (DEBIT immediately), recurring monthly expense setup and payment of generated recurring expense bills (DEBIT on payment).
8. **Analytics:** last-six-month debit/credit trend, monthly cash totals, outstanding bills and recent receipts.

The school overview dashboard has optional financial cards. Administrators can show/hide individual metrics or enable one-at-a-time rotation every 10 seconds; their choices are saved in Firestore. **Inventory, books, stationery, canteen and stock** are reserved for a separate future module rather than being mixed into fee collections.

**PKR is the accounting currency**, with every amount stored as an integer in paisa (minor units). There is no floating-point payment arithmetic. A ledger entry is either `credit` (money received) or `debit` (money paid).

### Core accounting rule

**Generating a fee, salary or recurring expense is NOT a credit or debit transaction.** It only creates a bill/payable with a total, paid balance of zero and outstanding amount.

- Student fee payment creates one `finance_ledger` **credit** with the receipt ID, student ID/name, class, fee category, original bill, amount paid, payment method, reference, date, time and authenticated operator.
- Salary payment creates one **debit** and advances that teacher/month's salary balance.
- Paying a generated recurring expense creates one **debit**.
- A direct expense creates one **debit** immediately.
- Partial payments leave the remaining amount due. Overpayments are rejected.

The paid-balance update and immutable receipt are in the **same Firestore transaction**. Security rules verify the update corresponds to the matching receipt; ledger entries cannot be edited/deleted by the client.

## Tuition fee setup

Open **Fees & Finance → Fee Setup → Tuition fee setup**, select a class and enter its fixed monthly tuition rate. **Only the owner** may create or edit class tuition rates; a principal may view but cannot change them.

Changing the rate affects **future generation only**. Previously generated monthly student fee bills retain their snapshot amount and cannot be retroactively overwritten.

## Transport fee setup

Open **Fee Setup → Transport fee setup**. Use the student selector to filter a class or all classes, select one, several, all shown or all students, and apply an individual fee rate. Different students may have different transport rates, even in the same class. Enter **0** to stop future generation for selected students; historical bills/payments are preserved.

Transport fees are generated only for students who have an active positive transport rate.

## Monthly generation

Open **Generate Finance**, choose current or previous month, and select any combination of:

- Tuition
- Transport
- Teacher salaries
- Recurring expenses

Click **Generate Finance**. The app reads current active students/teachers and the saved fee or salary structures and creates an individual monthly bill for each applicable person or expense plan.

Generated monthly IDs are deterministic (examples: `FEE-202611-tuition-ST-2026-0001`, `SAL-202611-EMP-2026-0001`). A second generation run checks existing bills and **does not reset amount, paid balance, or historical receipts**. Missing setup is reported and skipped.

The generation scope is limited to the current or immediately previous month, including salaries. Older backdating and future-month generation are not supported in this version.

## One-time fees

Choose a fee category, an amount, optional description (required for **Other**) and a selection of students. Apply to create **unpaid fee bills**, not credits. Later collect them from **Collections**.

Each invocation creates a new batch of bills. Verify the selection and existing charges before applying to avoid duplicate one-time fees.

## Collections and Pay Salary

Search the student fee bills by student, class, category/subcategory, or select a generated salary payable. Open **Collect**/**Pay**, enter amount (defaults to the outstanding balance), payment method, optional bank reference and notes. The app shows the remaining balance immediately.

After confirming, a unique receipt ID is generated; date/time and operator are recorded automatically. The ledger is append-only, and the associated bill stays open until fully paid.

**No refunds, reversals, discounts, late-fee policy, or bank reconciliation are implemented yet.** Do not edit Firestore to reverse a posted payment; a supervised reversal workflow and audit approval should be designed first.

## Expenses

The expense category/subcategory catalog includes utilities (WiFi, electricity, water), hospitality/hotel, stationery (ink, copy paper, printers, toner), lab equipment, examination materials, transport fuel and maintenance, tailoring, building rent, general maintenance, teacher mobile packages, second-time tuition paid to teachers, and Other.

- **Record direct expense**: creates a debit immediately.
- **Monthly expense setup**: creates a recurring plan. Use **Generate Finance** to create the monthly payable, then **Pay** when actual money is spent.

Recurring plans have a preferred day (1–27); they can be stopped without deleting historical expenses.

## Monthly automation: configured, not deployed

Owners and principals can enable automatic tuition, transport, salary and recurring expense generation in **Generate Finance → Monthly schedule preferences**. Select day 1–27 for fees and salaries. Each expense plan supplies its own day. Existing preferences stay disabled until switched on.

The Firebase job checks once daily in Pakistan time. It processes enabled categories due in the current month, so enabling after the chosen day generates bills on the next run. A completed category is not rerun that month. Manual generation is still available for adding missing records or handling earlier months. Existing bill IDs, balances and ledger entries are preserved.

To enable the online scheduler on a Firebase project with Blaze billing, deploy `firestore:rules` and `functions:generateMonthlyFinance` from this checkout. The job runs at 02:00 Asia/Karachi. Review its Cloud Logging entries for failed or completed runs.

## Firestore storage

| Collection | Purpose |
|---|---|
| `finance_tuition_rates/{classId}` | Fixed monthly tuition per class; owner-only changes |
| `finance_transport_rates/{studentId}` | Personal monthly transport amount |
| `finance_salary_rates/{staffId}` | Teacher basic, allowance, bonus and total |
| `finance_recurring_plans/{planId}` | Monthly bill plans and their generation days |
| `finance_generation_settings/{category}` | Opt-in and generation day for each automatic bill type |
| `finance_fee_bills/{billId}` | Unpaid/partial/paid student obligations |
| `finance_salary_bills/{billId}` | Monthly teacher salary obligations |
| `finance_recurring_bills/{billId}` | Generated monthly expense obligations |
| `finance_ledger/{entryId}` | Immutable credit/debit cash movements and receipts |
| `finance_dashboard_preferences/{userId}` | Private dashboard preferences for each administrator |

Old `payroll_records` remain protected and read-only, retained for a future migration. They are **not** automatically imported into the new ledger; no historical balances are invented.

### Security and go-live

The new Firestore Rules are committed in [firestore.rules](../firestore.rules), but an APK **cannot publish them**. To enable finance, open [Firestore Rules Console](https://console.firebase.google.com/project/suffah-high-school/firestore/rules), replace the editor content with the **complete latest** [raw rules file](https://raw.githubusercontent.com/yunusyosaf399/suffah_high_school/main/firestore.rules) and click **Publish**.

Owner and active principal accounts may access the finance module. **Only the owner can edit tuition rates.** Teachers, students, parents, and inactive accounts cannot access this ledger, salary data, or other people's financial details.

**Before entering real financial data**, verify deployed rules with the Firestore Emulator; test double-generation, partial payment, concurrent collectors, tampered receipts, staff access denial, owner-only tuition editing, and recovery/backup procedures. Financial reports currently read a bounded six-month window: large historical datasets will eventually require server-side aggregated reporting. There is no certified accounting audit or tax reporting yet.

## Acceptance test

1. Set tuition for Grade 1-A; set a different transport amount for two students. Verify a principal cannot edit tuition.
2. Generate tuition + transport for current month. Confirm bills appear with paid=0 and the Credit/Debit ledger remains unchanged.
3. Generate again; confirm **existing** count and unchanged bills.
4. Add an Examination Fee for one student; verify it appears only as an unpaid one-time bill.
5. Collect a partial fee, verify the credit receipt, amount, date/time, operator, and remaining balance. Attempt to overpay; verify rejection.
6. Configure teacher salary, generate this or previous month, partially pay and verify debit receipt and remaining salary.
7. Record stationery or fuel as a direct expense; verify a debit receipt.
8. Create a monthly Building Rent plan, generate its bill, pay it, and verify debit is created only after payment.
9. Open Analytics and School Overview; choose visible metrics and enable 10-second rotation.
10. Sign in as teacher or unapproved account and verify finance data is denied.
