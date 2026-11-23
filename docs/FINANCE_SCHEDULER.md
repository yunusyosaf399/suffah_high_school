# Monthly Finance Scheduler — design, activation and recovery

## Current deployment status

The Flutter scheduler configuration and the Cloud Functions v2 implementation
are committed to GitHub. **The scheduled function is not automatically deployed
by the Android GitHub Actions build**. A Firebase project on the **Blaze
billing plan** and explicit CLI deployment are required. Until this is done,
the app should show **Automatic execution not active**, and the school can
continue generating bills manually using **Generate Finance**.

**Do not enable automatic billing in production until you have tested the
emulator and deployed/published the latest reviewed Firestore security rules.**

## Functional behavior

The privileged function `generateMonthlyFinance` runs **daily at 06:10
Asia/Karachi** and checks due configurations; it does not rely on a phone
being open or online.

| Configured item | Firestore settings | Eligible records |
|---|---|---|
| Tuition | `finance_generation_settings/tuition` | Admitted/active students in active classes with an owner-defined tuition rate |
| Transport | `finance_generation_settings/transport` | Admitted/active students with an individual, active transport rate |
| Salary | `finance_generation_settings/salary` | Active teachers with a valid salary breakdown |
| Recurring expenses | One `finance_recurring_plans/{planId}` per plan | Active expense plans with automation enabled |

Each type or plan has a separate `scheduleDay` from **1 to 27** and an
`automaticEnabled` switch. Disabled items never generate automatically.
If an enabled date has passed, the worker can catch up later in the **same
month**. It does not create historical months automatically. Manual generation
still allows current and immediately previous month as before.

On first execution for a month, the worker creates **only outstanding
obligations** and stores a completion audit. It creates **no** `finance_ledger`
credits/debits; those happen only when the owner/principal collects fees,
pays salaries, or pays an expense.

IDs are deterministic and shared with manual generation:
`FEE-YYYYMM-tuition-<studentId>`,
`FEE-YYYYMM-transport-<studentId>`,
`SAL-YYYYMM-<staffId>`,
`EXP-YYYYMM-<planId>`.

The worker uses atomic Firestore document **create**, never overwrites a bill,
and treats `ALREADY_EXISTS` as an existing record. A replay/retry/manual
generation **cannot reset** `paidMinor`, `status`, or an existing bill amount.
The monthly audit is written only after all create attempts finish; failed
runs can retry on a later day, without double-charging.

### Audit and deployment indicators

- `finance_scheduler_runtime/status`: last worker heartbeat, check month/date,
  last completion status and success/failure counts.
- `finance_scheduler_runs/{YYYYMM}_{type}`: each monthly category's
  completion, created/existing/skipped counts and error state.
- Expense plan audit category format: `expense_<planId>`.
- The app displays the worker as **online** only if a heartbeat is less than
  48 hours old. Merely saving an enabled switch does not make it online.
- Rules let owner/principal **read**, but never write, audit/heartbeat documents.

## Deployment — only after Blaze is enabled

1. Open [Firebase Console billing](https://console.firebase.google.com/project/suffah-high-school/usage/details),
   review the charges and activate the Blaze plan for **suffah-high-school**.
   Set a budget alert in Google Cloud Billing; budget alerts do not impose
   a hard spending cap.
2. On a trusted development computer, clone the GitHub repository, install
   Node.js 22 and Firebase CLI and sign in with an authorized Firebase
   project administrator. Never commit service-account keys or tokens.
3. Review/publish the latest
   [firestore.rules](https://raw.githubusercontent.com/yunusyosaf399/suffah_high_school/main/firestore.rules)
   to the Firebase project. If you use CLI, verify the intended project ID:
   `firebase deploy --only firestore:rules --project suffah-high-school`.
   The owner can also publish the complete rules in Firebase Console.
4. Run the pure backend tests with `cd functions && npm install && npm test`.
   Validate against the **Firestore emulator** with representative students,
   fee setups, teacher salaries and recurring plans. Test disabled schedules,
   duplicate runs, partially paid bills, staff access controls and retries.
5. Deploy the single schedule job from the repository root:
   `firebase deploy --only functions:generateMonthlyFinance --project suffah-high-school`.
   The CLI creates the Cloud Scheduler job and secured v2 function. **This
   deployment has not been performed by ChatGPT.**
6. Check Cloud Scheduler and Cloud Functions logs after the first execution.
   Open **Fees & Finance → Generate Finance → Monthly finance scheduler**,
   refresh the worker status, choose days and enable the intended categories
   and expense plans.
7. Start with **one test category** and a low-risk test school data set.
   Verify exact bill IDs and amounts, no ledger entries, the audit record,
   then check the rest of the school after reconciling a manual run.

### Recovery

If the worker is offline or a schedule is accidentally turned off, no
financial history is deleted. Fix the backend, re-enable the setting, then let
the next daily run catch up for the current month. Alternatively use
**Generate Finance** manually; existing bill IDs are reused. Do not delete a
paid bill, bypass the payment transaction, or directly edit salary balances.

If the backend has not been deployed, **do not expect any automatic bill to
appear** just because a monthly day is saved in Firestore.

## Security and limits

The worker uses Firebase Admin SDK **only inside trusted Cloud Functions**;
it is not callable from the client and needs no public HTTP API. The Flutter
app only saves allowed schedule preferences under reviewed security rules.
The scheduler reads at most 1,000 students, 500 teachers, 1,000 rate records,
and 500 active expense plans per run. These are suitable for the planned
school scale but should be reviewed if enrollment grows. Missing or invalid
rates are skipped and tracked. One-time fees and direct expenses are never
automatically generated or paid.

Backend tests: `functions/test/scheduler.test.js`.
Flutter scheduler tests: `test/finance_monthly_scheduler_test.dart`.
