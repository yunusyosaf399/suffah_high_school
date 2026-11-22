# Designated Attendance Teacher — v0.9

Attendance responsibility is **separate from subjects**. A teacher can teach multiple subjects in many classes but can be designated as the attendance teacher for **one class only**. A class has **one designated attendance teacher** at a time.

## Owner / principal setup

1. Ensure the teacher is an active staff member and has a linked teacher login in **Users**.
2. Open **Attendance → Assign class attendance teachers** (top-right icon), or open **Staff → Teacher profile → Assign attendance class**.
3. Choose the teacher and one class/section, then **Save assignment**.
4. To change responsibilities, use **Change teacher** or assign the teacher to another class. The app atomically replaces earlier class/teacher links so no duplicate responsibility remains.
5. To remove an assignment, select **Remove teacher**. This does **not** delete past attendance or student records.

## Teacher workflow

1. Sign in with the teacher's linked email and password.
2. Open **My class attendance** in the teacher portal.
3. Only the designated class is shown. The class selector is disabled.
4. Select today's date or an earlier date. Mark each student **Present**, **Absent**, **Late**, or **Leave**. Unmarked students are **not** automatically absent.
5. Use **Mark remaining present** if appropriate, then **Save attendance**.

If no class is assigned, the teacher sees an instructional empty state and cannot open any class attendance register.

## Firestore model and privacy

- `attendance_class_assignments/{classId}` — authoritative assignment for each class, containing staffId, classId, className, staffName and active.
- `attendance_teacher_links/{staffId}` — the teacher's one-class lookup, readable only by that linked teacher and owner/principal.
- `class_rosters/{classId}/students/{studentId}` — safe projections containing names and roll numbers, with no guardian contact, address, or health data.
- `attendance_days/{classId}_YYYYMMDD/marks/{studentId}` — existing attendance storage.

Assignments are changed in one Firestore transaction, and the app migrates existing students to the safe roster if the one-time migration is not yet completed. New and edited students continue to update those roster projections.

Firestore Rules verify the active linked teacher account, matching active staff and class, both attendance mappings and the active student roster before mark writes. The teacher never gains general read access to `students` or `classes`. Teacher saves use batches of at most eight student marks to stay inside Firestore security rule lookup limits.

## Required Firebase deployment

The APK cannot publish rules. Copy the **complete** latest [firestore.rules](https://raw.githubusercontent.com/yunusyosaf399/suffah_high_school/main/firestore.rules) file into the [Firestore Rules Console](https://console.firebase.google.com/project/suffah-high-school/firestore/rules) and click **Publish**.

No Firebase Storage or Blaze upgrade is needed.

## Acceptance checks

1. Assign Teacher A to Grade 5-A. Confirm the teacher login sees only Grade 5-A in attendance.
2. Mark one student absent and another present. Save and reload to confirm saved marks.
3. Confirm the teacher cannot open other classes or read full student guardian/contact fields.
4. Assign Teacher A to Grade 6-B. Confirm Grade 5-A attendance access is revoked and history preserved.
5. Assign Teacher B to Grade 6-B. Confirm Teacher A loses attendance access and Teacher B gains access.
6. Archive the teacher or class. Confirm teacher attendance reads/writes are denied by rules.
7. Confirm owner and principal retain their ability to mark attendance for all classes.
8. Confirm teacher's subject teaching assignments/exams/homework are unaffected.

These UI tests are automated; Firestore Rules should also be exercised against the Firebase Emulator before using real school data.
