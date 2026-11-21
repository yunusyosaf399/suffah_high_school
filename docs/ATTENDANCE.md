# Daily student attendance — Suffah High School v0.5

## Current scope

The Attendance dashboard module is enabled for the **owner and principal**. It is online-first and does **not** require Firebase Storage or the Blaze upgrade.

### Workflow

1. Open **Attendance** on the owner/principal dashboard.
2. Select a class and section. The screen loads only its active, admitted students (drafts and archived students are excluded).
3. Choose today or an earlier date using the date picker.
4. Mark each student's status: **Present, Absent, Late, Leave**.
5. Remaining students are **Unmarked**, never automatically absent.
6. Use **Mark remaining present** only after identifying absences; it does not overwrite already recorded Present/Absent/Late/Leave marks.
7. Tap the permanent **Save attendance** action at the bottom. Only changed student records are written.
8. Return to the same date/class to review or correct its marks. Switching registers with unsaved changes prompts for confirmation.

A compact summary displays Present, Absent, Late, Leave and Unmarked counts. The roster can be searched by name, roll number or registration number. Date selection allows revisiting earlier saved attendance.

### Database design

The source code uses the following Cloud Firestore paths:

- \`attendance_days/{classId}_YYYYMMDD\` — small day metadata (\`date\`, \`classId\`, \`lastEditedBy\`, \`lastEditedAt\`).
- \`attendance_days/{classId}_YYYYMMDD/marks/{studentId}\` — one record per student/day, with \`studentId\`, \`classId\`, \`date\`, \`status\`, \`updatedBy\` and \`updatedAt\`.

The parent-facing app will eventually read only its linked child's mark, **not the class-wide register**. This is why a per-student subcollection is used instead of a single map containing every student's attendance.

The implementation:
- Fetches only the selected class roster (up to 1,000 records) and the selected date's marks.
- Keeps existing historical marks when later saving corrections.
- Writes only changed students in batches of up to 400 marks, each with a metadata update. A retry writes the same stable document IDs.
- Does **not** automatically delete attendance. Retention and archival policy will be revisited when reliable reports/backups are implemented.
- Does **not** require composite indexes for the direct class/date register used by this screen.
- Currently reflects the **presently enrolled/active class roster**, not a historical snapshot of transfers. Preserve older marks; historical enrollment snapshots and reporting are future tasks.

### Required Firestore Rules publication

The Android APK cannot change Firebase Console security rules. The new \`attendance_days\` rules are committed in \`firestore.rules\`, but need to be published in the Firebase Console:

1. Open https://console.firebase.google.com/project/suffah-high-school/firestore/rules.
2. Open https://github.com/yunusyosaf399/suffah_high_school/blob/main/firestore.rules and select **Raw** to copy the complete latest file.
3. Replace the Firestore Rules editor content and **Publish**.
4. Test as the existing owner using one class and two sample students.
5. Confirm the saved marks reappear after leaving and re-entering Attendance.
6. Verify that an unapproved/parent account cannot read or edit class attendance.

**Do not paste \`storage.rules\` here.** Storage rules are unrelated to attendance, and the Blaze/Storage setup can remain unfinished.

### Current permissions and future modules

- Owner and principal can read/write attendance, subject to published rules.
- Teacher account dashboard and class-assignment-limited attendance access are **not yet implemented**.
- Parent account access to its own children is **not yet implemented**.
- Attendance notifications, exports, monthly summaries, roll reports, staff attendance and transfer-aware historical rosters remain future milestones.
- Cloud Storage uploads of student photos and documents are hidden from the current admission wizard because the Blaze upgrade has been deferred.

### Acceptance test

Create or use a small test class with two admitted students. Mark one absent, then use **Mark remaining present**. Save. The summary should report 1 Present, 1 Absent, 0 Unmarked. Reopen the same class and date and confirm the statuses persist. Change one student's status and save again; the other student's original mark must remain unchanged.
