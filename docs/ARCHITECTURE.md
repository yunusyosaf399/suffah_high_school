# Suffah High School — Offline-first architecture (v1)

## Current implementation
- Supabase (SUPA MODEL SCHOOL): 18 application tables, RLS, one Auth owner, one private WebP-only photo bucket, two cron jobs.
- GitHub Flutter starter: UI and sync software are **not yet developed**.
- The applied SQL migrations are in `supabase/migrations/` with versions matching the remote project.

## What lives where
| Records | Primary location | Notes |
|---|---|---|
| Students, staff, class history, teaching assignments | Supabase + authorized local cache | Shared durable facts |
| Final grades, exams, short notices/homework | Supabase + authorized local cache | Small structured data |
| Fees, payments, expense/canteen summaries | Supabase + authorized local cache | Immutable ledger entries; money in integer PKR paisa |
| Recent staff and student attendance | Supabase for 30+ days | Never delete before desktop acknowledgment |
| Full 30-year attendance history | Encrypted desktop SQLite + independent backup | Authoritative long-term archive |
| Student photos | Private `student-photos` Supabase Storage bucket | WebP, exactly one object key `<student-uuid>.webp`, max 102400 bytes |
| Student documents, scans, medical files | Encrypted user-selected desktop folder | Never upload |
| PDF reports, ID cards, result cards, certificates, question bank files | Local encrypted folder | Generated locally from cached records |
| Per-sale canteen data, UI cache, outbound queue | Encrypted local SQLite | Aggregate durable transactions when required |

## Tables and feature groups
- Users: `app_users` with owner/admin/teacher/accountant/clerk roles.
- School master: `school_settings`, `academic_years`, `classes`, `subjects`.
- Admissions, promotions, staff: `students`, `student_enrollments`, `staff`, `teacher_assignments`.
- Exams and result cards: `assessments`, `assessment_marks`.
- Time table, syllabus, diary, notices, homework, simple tasks, date sheets, communications: `school_content` (short text only).
- Equipment and library: `school_assets`.
- Fee plans (monthly and one-time): `fee_rates`. Tuition, transport, books, uniform, promotion, certificates, examinations, fines and discounts use codes in `finance_entries`.
- Expenses: **one** `finance_entries` table covers salary, building rent, internet, medical, stationery, lab, examination, fuel/vehicle maintenance, tailor, general maintenance, canteen stock, payments to principal/tutors, and other categories. No separate table per expense.
- Attendance: `student_attendance`, `staff_attendance`, `attendance_archive_receipts`.
- Print templates and downloads: produced from cached data, not stored as blobs in Postgres.
- WhatsApp alerts, notifications and parent portal are **future integrations**, not currently implemented.

## Attendance retention — critical protocol
1. Teacher marks attendance on mobile/desktop; offline edits enter an encrypted local queue.
2. On reconnect, client uploads idempotent rows to Supabase.
3. Desktop downloads and verifies the **complete** date snapshot. It commits records in its encrypted SQLite archive and verifies an **independent encrypted backup**.
4. Only then an owner/admin uploads date-specific `attendance_archive_receipts` containing archive checksum and device label.
5. Daily Supabase Cron (02:15 UTC) deletes attendance where date is **more than 30 days old AND** the archive receipt is newer than or equal to the row's `updated_at`.
6. Later changes require a fresh desktop archive acknowledgment. Without verified backup, leave rows online even after day 30.
7. The old archive is **not recoverable from Supabase** after cleanup; local encrypted backups are essential.

## Login and sync — implementation contract
- First login must be online via Supabase Auth. Download only rows permitted by RLS and save to **per-user encrypted SQLite**.
- Returning users immediately see the cached subset, even if the network is unavailable; an online session refreshes it incrementally.
- For offline unlock, use a local PIN/biometrics + secure OS-keystore-held encryption secret, not a cached password. Enforce an offline grace window and lock old caches after revocation.
- Client creates UUIDs before syncing new records; retry uses the same UUID.
- Keep outbound `pending_operations` and `sync_cursors`. Updates carry the `updated_at` originally read; any mismatch becomes a conflict for reconciliation, not a silent overwrite.
- Use `updated_at` + stable ID for incremental pagination and `deleted_at` tombstones for soft-delete entities. Small catalog tables can be fetched in full.
- Never expose the Supabase secret/service-role key in Flutter clients.
- Finance entries are append-only and corrected with reversal entries; never overwrite paid receipts.
- During photo upload, convert/resize to WebP, validate **actual bytes <= 102400**, and keep only the student's fixed object key. No PDF uploads.

## Desktop document storage
- Flutter desktop must show a native folder chooser, store the chosen root in secured app settings, and use randomly generated relative paths.
- Encrypt documents with authenticated encryption (such as AES-256-GCM) and keep keys in OS keychain/secure storage. Folder permissions **alone** are insufficient.
- Use SQLCipher or an equally encrypted SQLite solution. Plain SQLite is **not** encrypted merely because a schema file exists.
- For WAL-mode SQLite use the Online Backup API or equivalent safe checkpoint procedure when backing up.
- At least two independent encrypted backups and periodic restore tests are necessary for a 30-year retention target.
- Apply privacy rules for student records, printers, exported files and staff access.

## Delivery phases
1. Flutter Supabase authentication and owner UI, encrypted local database, selected document folder.
2. Student admission, grades/classes/staff, photo compression and storage rules.
3. Two-way offline sync, teacher class assignments, attendance and archival acknowledgment.
4. Fee assessments, receipt printing, finance reporting, assessment results, print templates.
5. Communications, notifications, parent portal (if desired), school reports and maintenance tools.

**Note:** This is a practical baseline. Before importing real records, test offline conflict resolution, backups/restores, authorization, account deactivation, printed exports and finance reconciliation. Thirty-year operability cannot be guaranteed by one cloud provider or a single local disk.
