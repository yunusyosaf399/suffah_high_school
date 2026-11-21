# Suffah High School

Flutter school-management app for a school of approximately 400 students today,
with headroom for 800+. Target platforms: Android first, then Windows and iOS.

## Current stack
- **Firebase Authentication**: Email/password for owner, principal and provisioned staff/parent accounts
- **Cloud Firestore**: school users, classes, admissions, daily attendance, staff, teacher assignments, classwork, examinations and privacy-safe class rosters
- **Flutter**: compact, responsive interface for phones, tablets and wider screens
- **GitHub Actions**: automatically tests, analyzes and builds the Android debug APK

## What works
- Firebase owner sign-in, sign-out and profile verification
- Owner dashboard with Firestore summary counts
- Class/section creation, listing and archival
- Six-step student admission wizard with read-only ST-YYYY-XXXX registration, final Review & Admit and resumable drafts (uploads deferred)
- Read-only admitted student profiles; only owner/principal can open the edit wizard
- Owner-only Users module: create Firebase Auth accounts, assign school roles, suspend/reactivate school access
- Staff registration wizard: Name & Guardian, Contact, Address, Education, Review and Submit; permanent employee IDs, profile editing and archive/restore
- Owner can create a teacher login by selecting an active teacher profile and choosing one of its saved email addresses
- Dedicated teacher portal: assigned classes, create assignments and homework, view assigned examinations, enter marks, and read personal payroll/salary receipts
- Owner/principal examination publishing for assigned classes; student name/roll-number projections keep private guardian and contact data out of teacher views
- Staff directory: search, profile details, archive/restore and class/subject teacher assignments
- Daily class attendance: Present/Absent/Late/Leave, explicit unmarked states, date history and changed-only Firestore saves
- Student search, class filters and archival
- Dashboard global search preview (cross-module search is planned; no live results yet)
- Classes page includes an explicit Firestore connection diagnostic, retries and error messages
- Student/class lists start with an online read, with retry and timeout feedback
- Student page retains visible Add Student / Manage Classes actions while Firestore loads
- Error, loading, empty and confirmation states

## Next priorities
Staff daily attendance, owner payroll entry and receipt publishing, result cards and exports,
parent accounts linking multiple children, notices and messaging.

See [staff and teacher assignments](docs/STAFF_AND_ASSIGNMENTS.md),
[daily attendance](docs/ATTENDANCE.md),
[student profile and Users rules](docs/PROFILE_AND_USERS.md),
[admissions setup](docs/ADMISSIONS_WIZARD.md),
[global search scope](docs/GLOBAL_SEARCH_SPEC.md),
[three-month delivery plan](docs/RELEASE_PLAN.md) and
[Firebase setup](docs/FIREBASE_SETUP.md).

## Android test APK
Open the [Android APK workflow](https://github.com/yunusyosaf399/suffah_high_school/actions/workflows/android-apk.yml).
After a successful run, download the artifact named
`Suffah-High-School-Android-Debug-APK`. It is a ZIP with `app-debug.apk`.
See the [APK testing guide](docs/APK_TESTING.md).

Android preview updates now reuse a stable debug signing identity and increment the version code on each build. To keep the signing key across GitHub cache eviction, follow [APK update signing setup](docs/APK_UPDATES.md). The first update from older debug builds can still require one uninstall.

**Development APK only:** The school modules are being completed incrementally.
Do not use real sensitive student information until production permission checks,
backups and acceptance testing are in place. Windows and iOS Firebase
configuration still need to be completed.

## Historical Supabase design
The repository retains [Supabase migrations](supabase/migrations),
the prior [offline-first architecture](docs/ARCHITECTURE.md),
and the [local SQLite schema](local/offline_schema.sql) as historical references.
They are **not the active backend** for the Flutter MVP.
Do not delete the previous Supabase project until migration and retirement
are explicitly approved.
