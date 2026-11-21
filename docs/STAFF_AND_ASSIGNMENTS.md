# Staff, Teacher Accounts & Teacher Portal — v0.7

This milestone uses **Firebase Authentication and Cloud Firestore only**. Firebase Storage and the Blaze upgrade remain deferred.

## Staff registration

The staff registration screen now follows the same multi-step pattern as student admission:

1. **Name & Guardian** — first, middle and last name, father/guardian name, date of birth, gender, nationality, category and designation.
2. **Contact** — mobile, WhatsApp, primary and alternate email, emergency contact, date of joining.
3. **Address** — present and permanent address, city, postal code and country.
4. **Education** — highest qualification, education details, teaching specialization, experience and previous employer.
5. **Review** — inspect all entered information before Submit.

- A new profile receives a permanent employee number such as **EMP-2026-0001** in a Firestore transaction.
- Editing never changes the employee number.
- Profiles can be archived and restored; no staff history is destructively deleted.
- Staff records are not Firebase Authentication accounts. Registration does not create a login.

## Teacher account linking

Only the owner can create Firebase sign-in accounts through **Users**.

1. Create and save a teacher profile first.
2. Open **Users → Create user account** and choose **Teacher**.
3. Select an active teacher from the staff directory.
4. Select one of the email addresses already saved on that teacher profile.
5. The teacher name is filled from the profile; the owner cannot silently create an unrelated teacher identity.
6. The account is created with role **teacher** and linked using **staffId** and **staffNo** in the user profile.
7. A second user account for the same staff profile is rejected by the app.

If the teacher has no valid email saved, edit the staff profile before creating the account. If a teacher profile is archived, its linked account cannot access teacher-only Firestore data. Suspending a user account also blocks the teacher portal.

## Teacher portal

A linked teacher signs in to a separate, restricted dashboard. It does not expose the owner dashboard, Users, all students, parent records or other teachers' payroll.

- **My teaching assignments** — active class and subject links.
- **Assignments** — create class assignments for an assigned class and subject.
- **Homework** — create homework for an assigned class and subject.
- **Examinations & marks** — see examinations published for assigned subjects and enter marks for active students in the assigned class.
- **Payroll & salary receipts** — read only the salary records linked to the teacher's own staff ID.

The teacher cannot choose an arbitrary class or subject when creating classwork. Firestore rules verify the active assignment and linked teacher identity on the server.

### Examination publishing

The owner or principal opens **Examinations**, selects an existing active teacher/class/subject assignment, enters an exam title, date and maximum marks, then publishes it. Only the linked teacher sees that exam and can enter marks.

When the Examinations screen opens, the app prepares:
- **teacher_class_links/{staffId}__{classId}** — compact index of active class assignments.
- **class_rosters/{classId}/students/{studentId}** — privacy-safe projection containing only student ID, name, roll number, class ID and active status.

This roster is intentionally separate from **students/{studentId}**. Teachers are not granted read access to student guardian, contact, address or health fields. The Examinations screen also migrates existing active teacher assignments and existing student records into these safe projections.

### Payroll status

The owner/principal **Payroll** dashboard module creates salary records, calculates net salary as basic salary plus allowances minus deductions, assigns permanent receipt numbers such as **SAL-2026-0001**, and records payment status/date/method. Payroll records are append-only for financial history; administrators can update payment status without changing the employee, pay period or salary amounts.

The teacher payroll screen is read-only. It displays records from **payroll_records** matching the signed-in teacher's linked **staffId**, including period, basic salary, allowances, deductions, net salary, receipt number, payment status and payment date. A teacher can never read another staff member's payroll records.

## Firestore paths

- **counters/staff_registration_YYYY**: atomic last sequence.
- **staff/EMP-YYYY-XXXX**: identity, guardian, contact, address, education, designation, role category, employee number and active status.
- **teacher_assignments/{staffId}__{classId}__{normalizedSubject}**: teacher/class/subject link and active status.
- **teacher_class_links/{staffId}__{classId}**: active assignment IDs used by least-privilege teacher rules.
- **users/{uid}**: teacher role plus staffId and staffNo.
- **class_rosters/{classId}/students/{studentId}**: safe student name/roll projection.
- **classwork/{workId}**: teacher-created assignment or homework.
- **examinations/{examId}** and **examinations/{examId}/marks/{studentId}**: published exams and teacher-entered marks.
- **payroll_records/{payrollId}**: owner/principal-managed salary records, readable by the linked teacher only.

No photo, document or salary PDF uploads are required. Salary receipts are currently rendered from Firestore fields.

## Required Firestore Rules publication on Android

The APK **does not deploy Firestore Rules**. If staff registration shows **permission-denied**, the current rules may not have been published, or the session may not be the approved owner/principal account.

1. In Chrome on Android, open [Firebase Firestore Rules](https://console.firebase.google.com/project/suffah-high-school/firestore/rules).
2. In another tab, open [the latest firestore.rules on GitHub](https://github.com/yunusyosaf399/suffah_high_school/blob/main/firestore.rules).
3. Select **Raw**, copy the complete file, replace the Firestore rules in Firebase Console and tap **Publish**.
4. Do not paste these rules into Storage Rules. Do not change Authentication settings for this step.
5. Sign out of the app and sign back in using the approved school owner account.
6. Try creating a teacher profile again. The owner/principal rules allow the staff counter and staff record transaction.

The latest rules add restricted access for linked teacher profiles, assignments, teacher-class links, safe class rosters, classwork, examinations, examination marks and each teacher's own payroll records. They do not grant teachers broad access to students or users.

You do **not** need to publish Storage rules or upgrade to Blaze.

## Acceptance test

1. Publish the latest Firestore Rules.
2. Register a teacher using all five steps; confirm a permanent EMP-YYYY-XXXX number is generated.
3. Edit the profile and confirm the employee number does not change.
4. In Users, choose Teacher, select the active profile and select its saved email; create the account.
5. Try creating a second account for the same staff profile; it should be rejected.
6. Assign the teacher to an active class and subject.
7. Sign in with the teacher account. Confirm only the teacher portal appears.
8. Create one assignment and one homework item; confirm each is linked to the assigned class and subject.
9. As owner/principal, publish an examination for that assignment.
10. Sign in as the teacher, open the examination, enter marks and save.
11. Confirm the teacher sees only the assigned class roster and cannot open the full Students or Users modules.
12. Add a payroll record for the teacher and confirm only that teacher can see it. Test another teacher account to verify records are isolated.
13. Archive the teacher or suspend the user and confirm teacher-only reads and writes are denied.

## Still planned

- Printable/exportable salary receipts and payroll reports
- Staff daily attendance, leave and HR reports
- Student-facing homework/assignment visibility and submission workflow
- Exam result aggregation, grade rules, result cards and parent access
- Production Rules Emulator tests, audit trails, backup/restore, imports and device acceptance checks
