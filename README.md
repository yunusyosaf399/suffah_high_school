# Suffah High School

Flutter school-management app for a school of approximately 400 students today,
with headroom for 800+. Target platforms: Android first, then Windows and iOS.

## Current stack
- **Firebase Authentication**: Email/password, initial owner account
- **Cloud Firestore**: owner profile, school classes, and student admission records
- **Flutter**: compact, responsive interface for phones, tablets and wider screens
- **GitHub Actions**: automatically tests, analyzes and builds the Android debug APK

## What works
- Firebase owner sign-in, sign-out and profile verification
- Owner dashboard with Firestore summary counts
- Class/section creation, listing and archival
- Student admissions, editing, search, class filters and archival
- Error, loading, empty and confirmation states

## Next priorities
Daily attendance, staff/teacher assignments, fees and receipts, examinations,
parent accounts linking multiple children, notices and messaging.

See [three-month delivery plan](docs/RELEASE_PLAN.md) and
[Firebase setup](docs/FIREBASE_SETUP.md).

## Android test APK
Open the [Android APK workflow](https://github.com/yunusyosaf399/suffah_high_school/actions/workflows/android-apk.yml).
After a successful run, download the artifact named
`Suffah-High-School-Android-Debug-APK`. It is a ZIP with `app-debug.apk`.
See the [APK testing guide](docs/APK_TESTING.md).

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
