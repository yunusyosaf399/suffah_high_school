# Class Subjects & Multi-Class Teacher Assignments

## Owner workflow

1. Open **Classes**, choose a class/section (e.g. Grade 5 – A), and select **Add subject**.
2. Enter the **subject name** (required), **subject code**, **periods per week** (0–30), and **description/syllabus details**. Add as many subjects as the class needs.
3. Open **Staff**, select an active teacher profile, and tap **Assign classes & subjects**. (You can also assign from the **Assignments** tab.)
4. Choose a class, tick one or more subjects, change to another class and tick more subjects, then **Save assignments**. Up to **six** combinations can be saved atomically at a time; repeat for additional subjects.
5. Teacher assignments remain individual records for each teacher–class–subject combination. Owner may archive/restore them in Staff → Assignments.

## Data model

- `classes/{classId}/subjects/{subjectId}`: per-class subject name, code, description, weeklyPeriods, nameKey, active flag and audit timestamps.
- `teacher_assignments/{staffId}__{classId}__{normalizedSubject}`: now includes `subjectId` referencing the class's catalog entry, along with the class, teacher, and subject name.
- `teacher_class_links/{staffId}__{classId}`: index of active assignment IDs; multiple subjects in one class share this index entry.

Subject names are immutable after creation to keep assignment references stable. Owners can edit the code, weekly periods and description, or archive/restore the subject. Existing older teacher assignments without a subjectId remain readable and can be archived. When reassigning an archived legacy assignment, the new subjectId is linked. New teacher assignments must use an active subject from that class's catalog.

## Payroll is paused

Salary and payroll screens have been removed from both owner/principal and teacher dashboards pending a redesigned payroll workflow. Existing historical `payroll_records` are preserved. New payroll writes are blocked by Firestore Rules, and teachers cannot read historical payroll records while the module is disabled.

## Required Firebase step

**The APK cannot publish Firestore Rules.** Before using the new catalog, replace the Firestore Rules in the Firebase Console with the **complete** latest [firestore.rules](https://raw.githubusercontent.com/yunusyosaf399/suffah_high_school/main/firestore.rules) file and click **Publish**.

Do not add a permissive catch-all rule. Firebase Storage and Blaze remain deferred.

## Test

- Create Mathematics and English in Grade 5 – A with different details, and Science in Grade 6 – B.
- Select one active teacher, tick Grade 5 Mathematics + English, change class, tick Grade 6 Science, and save.
- Confirm the three distinct assignments appear. Confirm saving a duplicate active assignment is rejected.
- Confirm that another teacher can also be assigned the same class subject.
- Confirm an archived subject is unavailable for new assignments; previously published documents are not deleted.
- Confirm the teacher portal lists the assigned subjects and that the payroll tile is absent.
