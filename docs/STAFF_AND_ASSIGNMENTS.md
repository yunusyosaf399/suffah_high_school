# Staff & Teacher Assignments — v0.6

This milestone uses **Cloud Firestore only**. Firebase Storage and the Blaze upgrade remain deferred.

## What works

- **Staff** dashboard module for owner and principal.
- Staff directory with search, archive filter, compact profile cards and read-only profile details.
- Add/edit staff first, optional middle and last names, role category, designation, contact phone, WhatsApp, email, date of joining, qualifications and address.
- A permanent automatically reserved identifier such as **EMP-2026-0001**, assigned in a Firestore transaction.
- Soft archive and restore a staff member without deleting linked history.
- **Assignments** tab: assign an active teacher to an active class/section for a specific subject; one teacher can teach several classes/subjects. Duplicate assignments are rejected.
- Soft archive/restore subject assignments, preserving history.
- Loading, error, empty states and responsive layouts on mobile; compact typography with touch-friendly controls.

## Database paths

- \`counters/staff_registration_YYYY\`: \`last\` staff sequence.
- \`staff/EMP-YYYY-XXXX\`: stable \`staffNo\`, \`firstName\`, \`middleName\`, \`lastName\`, \`fullName\`, \`searchName\`, \`roleType\`, \`designation\`, \`phone\`, \`email\`, \`whatsapp\`, \`joinDate\`, \`qualification\`, \`address\`, \`active\`, \`createdAt\` and \`updatedAt\`.
- \`teacher_assignments/{staffId}__{classId}__{normalizedSubject}\`: \`staffId\`, \`classId\`, \`subject\`, \`active\`, timestamps.

Both collections are bounded in the UI (500 staff, 1,000 assignments) and can be paginated when required. No user-uploaded files or bank-card activation are involved.

### Important: accounts and linking

A **staff record does not automatically create a Firebase Authentication login**. Use **Users** as the owner to create an authorized staff sign-in. Linking an account to its staff record by verified UID, and allowing the teacher to open only assigned class attendance, are separate future work. Do not confuse a staff designation or email with an authorization grant.

The current Staff directory requires owner/principal access in Firestore rules. The app restricts add/edit/archive actions to those roles.

## Required Firestore Rules publication on Android

The APK **cannot deploy rules**. The new \`staff\` and \`teacher_assignments\` permissions are committed in \`firestore.rules\` and must be published separately.

1. In Chrome on Android, open [Firebase Firestore Rules](https://console.firebase.google.com/project/suffah-high-school/firestore/rules).
2. In another tab, open [latest firestore.rules on GitHub](https://github.com/yunusyosaf399/suffah_high_school/blob/main/firestore.rules).
3. Select **Raw**, copy everything, replace existing Firestore rules, then tap **Publish**.
4. Confirm owner login continues to work.
5. Create a test teacher in Staff (e.g., name Aisha Khan, Teacher, Mathematics Teacher, valid phone), note the generated ID.
6. Go to Assignments, select the teacher and an existing class, enter Mathematics, save and reopen.
7. Try creating the same subject/class/teacher combination again: it should reject duplicates.
8. Archive the assignment and restore it. Archive and restore the staff record. No deletions should occur.
9. Test principal access. Staff-only or parent logins should not be able to read school staff or assignments.

You do **not** need to publish Storage rules or upgrade to Blaze.

## Still planned before production

- Explicit and verified Firebase UID-to-staff linking
- Teacher dashboard, teacher-specific attendance write permissions
- Staff daily attendance and leave records
- Teacher subject catalog and academic-year-based assignments
- Staff exports, payroll, documents and performance reports
- Production rules-emulator tests, audit trails, backups, import and acceptance checks
