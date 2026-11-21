# Suffah High School — Firebase bootstrap

## Registered project
- Firebase project ID: `suffah-high-school`
- Android application ID: `com.suffah.school.suffah_high_school`
- Firebase Auth: Email/Password enabled; one initial owner account
- Firestore: default database created, currently deny-all in console until rules are explicitly published
- Billing: Spark during initial setup

## Bootstrap owner
The initial owner Firebase Authentication UID is `tQt6vca2zuagZipvknBwcmSRcrc2`.
The `firestore.rules` file pins this UID as the ONLY authorized client during setup.
The UID is an identifier, **not a password or administrative service-account key**.
Do not promote a user based on an email address, a self-declared `role` field,
or an unrestricted registration endpoint.

## Deploy from phone (after review)
1. In Firebase Console > Firestore Database > Rules, select all existing rules.
2. Replace them with the complete content of the tracked `firestore.rules` file.
3. Publish; confirm publishing succeeded.
4. In Firestore > Data, create collection `users`, document ID equal to the
   exact owner UID above, with fields `role` (string) = `owner`,
   `active` (boolean) = `true`, and `displayName` (string) = `School Owner`.
   The Firebase Console is trusted administration; app-side client rules are
   a separate safeguard.
5. Test as owner and unauthenticated / second user before real school data.
   An Auth account existing in the Users page alone does NOT mean the
   Flutter application is signed in or that owner access has been tested.

## Important limits
This is only the bootstrap policy, NOT production role-based authorization.
Only the owner can access all school documents, so it is NOT ready for teachers,
parents, other staff or students. Owner UID replacement must be carefully
managed by a trusted administrator; losing this Auth account can lock out
client-side access. Admin SDK/server credentials bypass Firestore rules and
must be protected separately.

## Next schema and role design
- `users/{uid}`: role, active, display name, linked student IDs (parent)
- `students/{studentId}`: admission number, class/section, contact summary
- `students/{studentId}/attendance/{yyyy-MM-dd}`: per-student attendance
- `students/{studentId}/feePeriods/{yyyy-MM}`: monthly balances / status
- `students/{studentId}/results/{assessmentId}`: exam/assessment reports
- `classes/{classId}`: section and academic year
- `staff/{staffId}`: staff records
- `messages/{messageId}`: constrained school-to-parent communications
- `notices/{noticeId}`: school announcements

The eventual policies must verify parent-to-student links using
trusted administrative data, limit teachers to assigned classes,
restrict finance writes to accountant/owner, and protect the entire
transaction history. Avoid keeping user-authoritative role/child-list
fields writable by parents. Add rules tests and indexes before opening
access to any user other than the owner.

## App build status
`android/app/google-services.json`, Gradle plugin, and FlutterFire
dependencies have been committed. Firebase initialization is coded for
Android, but a device build and sign-in flow have NOT been tested.
This repository may still contain earlier Supabase design files;
keep them until Firebase functionality and migration are verified.

## Safe production readiness checklist
- Test least-privilege access and account recovery.
- Implement secure provisioning for parent and staff accounts.
- Verify multiple children under one parent and prevent cross-parent reads.
- Configure secure student-photo upload rules and enforce <=100 KiB WebP.
- Implement verified backup/restore before collecting real records.
- Configure App Check, monitoring, budget alerts, and audit logging.
