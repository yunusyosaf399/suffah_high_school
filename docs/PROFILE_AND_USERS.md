# Student profiles, principal edits and owner-managed user accounts

## App workflow (v0.4 preview)

- An admitted student now opens in **Student profile**, a read-only, responsive screen containing student, guardian, academic, contact/address, health and uploaded-document metadata. The student's registration and roll numbers remain visible and immutable.
- Owner and principal see an **Edit student** action. Every other role sees a read-only profile only if future access policies explicitly permit that role to open it.
- Draft admissions are still opened in the multi-step wizard; the Students list shows drafts even when the **Active only** filter is on.
- The admission wizard now has seven tabs: Student, Contact, Guardian, Academic, Health, Documents, **Review**. The last tab summarizes entered fields and asks for an explicit **Apply admission** confirmation before changing a draft to admitted.
- Reopening an admitted student from Edit uses the same wizard but says **Save changes**, never a second admission.
- The Users module appears in the dashboard **only for the owner**. The owner can create an email/password Auth account for Principal, Teacher, Accountant, Office staff, or Parent. Owner can suspend/activate accounts via the school role profile.
- Principal gets access to Students and Classes after publishing the new rules. Other new user roles can sign in, but see a clearly labeled account-ready screen until their own modules and verified policies are finished. Parent-to-many-children links are not implemented yet.

## IMPORTANT: Publish the new Firestore rules from Android

The GitHub APK workflow builds app code **but cannot deploy rules** to your Firebase Console. The current console may still contain the initial **owner-only** policy. Without publishing the tracked rules, principal accounts will see permission-denied on Classes or Students.

1. Open [Firebase Console → Suffah High School → Firestore Database → Rules](https://console.firebase.google.com/project/suffah-high-school/firestore/rules).
2. Open the exact repository file [firestore.rules](https://github.com/yunusyosaf399/suffah_high_school/blob/main/firestore.rules) in a second tab. Copy all its contents.
3. Replace the Rules editor with that text and select **Publish**.
4. Verify that the published version exists. Owner should continue to sign in.
5. In the app, Owner → Users → Create user account → choose **Principal**, enter the name/email, and confirm. The owner remains logged in.
6. Copy the generated temporary password and share it only with the intended person through a secure channel. An email reset request is attempted, but delivery depends on Firebase mail configuration.
7. Sign in as the principal on a different phone or after signing out as owner. Verify that Students and Classes load, an admitted profile opens read-only, and the **Edit student** action works. Verify principal **does not** see Users.
8. Create a Teacher/Parent test account; it must not access Students, Firestore admissions, or Users.
9. Deactivate a test account in Users; after relaunch, that user's app sign-in should be denied school access even though its Firebase Auth identity still exists.

The **source rules have been changed**, but deployment is a separate step. If you are not ready to publish them, continue owner-only testing; do not interpret principal permission errors as an APK bug.

## What the rules enforce

- Owner: the initial verified Firebase Auth UID, not an email or self-claimed role.
- Principal: a signed-in user with an active, owner-created \`users/{uid}\` profile and \`role='principal'\`.
- Only owner/principal may read or change \`students\`, \`classes\`, and registration \`counters\`.
- Registration number, roll number, created timestamp, and parent linking cannot be rewritten through the student update rule.
- No client may delete a student.
- Only owner may create school role profiles or suspend/reactivate other accounts; no user may promote themselves or disable the original owner.
- Other roles may read only their **own** user role document and do not yet have school-data permissions.
- Cloud Storage's [storage.rules](https://github.com/yunusyosaf399/suffah_high_school/blob/main/storage.rules) similarly permits owner/principal for student photos/documents, but **requires separate deployment, an enabled Storage bucket, Blaze, and Firestore/Storage rules access permissions**. The Firebase Console may prompt you to enable cross-product rules access. Storage rule lookups incur Firestore read usage.

## Firebase account-provisioning limitations

Firebase Auth's public client SDK provides email/password registration, **not** an admin-only identity creation API. To keep the owner signed in, the app signs the newly created user into a **separate secondary Firebase app instance**, then uses the owner's original Firestore session to assign a trusted role.

- If Firestore role creation fails, the app attempts to delete the just-created Auth account.
- If this rollback also fails, clean up the incomplete Auth account in the Firebase Console before retrying.
- The temporary password is **never stored in Firestore**. The owner sees it after account creation to copy once.
- A suspended account still exists in Firebase Authentication, but cannot access school data because the school role is inactive. This is not an Admin SDK \`disabled\` flag.
- Creating Auth accounts is **not itself restricted to the owner at the Firebase Auth service level**; third parties could create *unapproved* Auth identities through other clients. Those identities get no school role and cannot access student records under the new Firestore rules. For a hardened production system use privileged server-side Auth provisioning (Admin SDK/Cloud Functions) plus policy testing, audit trails, secure invitation emails, MFA, and account recovery.
- Test with two physical devices and Firebase Rules Emulator before client production.

## Status

App source and GitHub Actions tests can be completed in this chat. The user's live Firebase project is not connected to this chat as a deployable Firebase plugin, so **rule publication and first real principal account creation must be tested on the user's phone**. Do not claim live permissions changed solely because the files were committed.
