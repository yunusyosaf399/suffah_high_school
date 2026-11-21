# Suffah High School — 3-month delivery plan

**Target:** client-ready school management app by approximately 21 February 2027.
**Starting point:** 21 November 2026. School: about 400 students, scalable to 800+.
**Platform focus:** Flutter Android first, adaptable layouts for Windows and iOS; desktop releases require separate platform setup and verification.
**Backend:** Firebase Authentication and Cloud Firestore now; Cloud Storage and Cloud Messaging in later milestones after billing setup.
**Operation:** online-first; no offline data-edit queue in MVP.
**Accounts:** owner, principal, accountant, teachers, and parents; each parent account may access multiple children.

## Priorities and proposed 12-week roadmap

| Weeks | Priority | Done means |
|---|---|---|
| 1–2 | Academic setup, classes, admissions, student search/edit, staff | Real records can be created, edited and archived in Firestore. |
| 3–4 | Teacher assignments and daily student/staff attendance | Attendance entered, corrected and reported by class/date. |
| 5–6 | Fees, discounts, dues, receipts, expenses, summary reports | Billing and payment records reconcile and print/export accurately. |
| 7–8 | Subjects, exams, marks, result cards, printable reports | Grades and result cards can be entered, verified and exported. |
| 9–10 | Parent profiles, one-to-many child links, notifications, in-app messages | Parents see only linked children, fees, attendance and results; reminders work. |
| 11–12 | Import 400 records, client feedback, device testing, backups and recovery | Stakeholder acceptance, reconciliation checks, restore drill, signed production build. |

**Current milestone:** Six-step admissions with final Review & Admit and draft recovery, read-only admitted profiles, owner-only Users provisioning and online daily student attendance by class/date. Photo and document uploads are postponed until Blaze can be enabled. App code and rule files are in GitHub; live Firebase rules must be published and accepted on actual devices before this is client-ready. Global search is preview-only.

## UX/product design contract
- Compact, readable typography: typically 11–14 sp for supporting/body text and 16–20 sp for headings.
- Minimum practical tap target around 44–48 dp; small fonts must not mean small targets.
- Responsive single-column phone layout; constrained forms and multi-column dashboards on tablet/desktop.
- Short forms, clear required fields, keyboard-aware layouts, loading/empty/error states and feedback after saves.
- Avoid false placeholders: incomplete modules marked clearly as upcoming.
- Global search: display its dashboard entry now, but ship actual cross-module results only after source modules and secure indexes exist; include students, reports, invoices, documents and pictures. See [GLOBAL_SEARCH_SPEC.md](GLOBAL_SEARCH_SPEC.md).
- Accessibility: meaningful labels/tooltips, reasonable contrast, text scaling and keyboard navigation.
- Optimize Firestore usage through bounded queries, only loading screens that are opened, and summary count aggregation.
- English MVP, with Pakistani Urdu localization as a later planned option if the client requests it.

## Data notes for present milestone
- `attendance_days/{classId}_YYYYMMDD/marks/{studentId}`: individual daily status per admitted active student, plus a small day metadata document. Marking only changed students reduces Firestore writes.
- See [ATTENDANCE.md](ATTENDANCE.md) for feature scope and test protocol; teacher-specific access, staff attendance and aggregated reporting still need implementation.
- `classes/{classId}`: `name`, `section`, `sortKey`, `active`, `createdAt`.
- `students/{admissionNo}`: `admissionNo`, `fullName`, `searchName`, `classId`, `gender`, `rollNo`, `guardianName`, `guardianPhone`, `active`, `parentUids` (empty until parent module), timestamps.
- Stable admission number as document ID blocks duplicates. Archive via `active=false`; no destructive deletion.
- The students screen currently loads up to 1,000 records at once; review pagination, exports, and performance before exceeding that bound.
- Updated Firestore source rules allow owner/principal admission management and owner-only user provisioning, but **must be manually published and tested in Firebase Console**; Github builds do not deploy these rules. Staff/parent sign-ins show placeholders without school data. See [PROFILE_AND_USERS.md](PROFILE_AND_USERS.md).

## Client-ready definition
A debug APK is NOT a production release. Before using real student data in production:
- Appropriate roles, least-privilege Firestore and Storage rules, verified child/parent linking.
- Reliable backup + restore test, data import checks, no accidental deletion of financial history.
- Fee reconciliation, attendance accuracy, results verification, and device acceptance tests.
- Production signing, release versioning, privacy policy, app distribution plan, support and monitoring.
- Compare real usage against Firebase Spark quotas; configure billing alerts before any Blaze upgrade.

**Scope management:** features outside the 12-week core must be deferred unless they block daily school operations.
