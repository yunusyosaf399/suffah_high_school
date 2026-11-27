# Account and portal deployment

This feature is intentionally separated from live deployment. Run tests and review the PR before deploying. The parent portal never reads private student or whole-class exam documents directly using Firestore client credentials.

## Firebase

From the repository root, with an authorized Firebase CLI session and the school's billing plan supporting Cloud Functions:

    firebase deploy --only firestore:rules,firestore:indexes,functions:schoolPortal --project suffah-high-school

Wait for the collection-group marks/studentId index to finish building. This is needed for a child's attendance and past results. The existing finance scheduler is not redeployed by the command above.

## Cloudflare R2

After the Firebase function is deployed, deploy the Worker from cloudflare/student-files using the existing authorized deployment process. Its new GET /v1/parent-files endpoint uses schoolPortal to verify that the requested file is still attached to the authenticated parent's linked child. Old administrator-only upload/delete endpoints remain unchanged. No public bucket or new secret is required.

## Test accounts

- Owner: Users > create account > Parent / guardian, then open the account and select verified child records. Save permission switches and links. Do not link unverified guardians.
- Teacher: create the linked teacher account as before, open the account to add employment contract fields and restrict feature permissions. Payroll uses existing salary bills and rates.
- Principal: existing operational permissions are preserved, but only owner can manage accounts; the owner can restrict examination and messaging access.
- Examiner: retains review/release and existing exam-management access, but only owner/principal may create formal annual terms.
- Removal: suspension is reversible; removal retains the school user document as an inactive audit record. Authentication deletion additionally calls the deployed backend, and can be retried from the removed account if that call fails. No admission or staff record is deleted.
- Messages: parent/teacher to school administration, with private per-account conversation; refresh to see replies. No push notifications or parent-to-teacher direct messages yet.

Lists are bounded for read cost; the app displays a limitation warning when records are truncated. Staff service months are calculated from joining date, not actual attendance.

Check the app on Windows and Android before rollout. Test revocation, parent-child isolation, private marks, file downloads and account deletion with test accounts, not production records.
