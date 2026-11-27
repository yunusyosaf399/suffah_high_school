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

## Teacher portal direct access

The teacher profile, contract, salary and performance screens now use authenticated Firestore queries instead of schoolPortal. Messaging uses the same private portal_threads documents via Firestore. Deploy firestore:rules before testing; a Cloud Function is not required for these teacher features. Teachers cannot write staff, contract or payroll records. Performance analytics needs both academic and analytics permissions and only includes marks from papers whose existing security rules permit access; the UI flags excluded historical papers and bounded data. The owner can start conversations from active parent/teacher accounts; the principal can reply to existing threads with participant metadata. Parents still need schoolPortal for child records and the Worker for document previews. Authentication deletion still needs schoolPortal.

## Parent account creation
Select Parent / guardian, choose active admitted children, review their recorded guardian name, relationship, phone and email, then confirm the verified guardian links and enter or correct the email. The account and all selected students' guardian email fields are saved in a single Firestore transaction. Existing Firebase emails cannot be reused to create a second login; open the existing parent account to manage child links instead. No new backend is needed for provisioning itself. The parent child-data portal still requires schoolPortal deployment.

## Direct Firestore parent portal (supersedes the parent Cloud Function requirement)
Pull the feature branch and deploy `firebase deploy --only firestore:rules,firestore:indexes --project suffah-high-school`. After the marks/studentId collection-group index is ready, sign in as owner, open Users & accounts and click Sync parent records. This backfills linked child profiles, attachments, attendance and safe class timetable projections. New admissions, account links, attendance and exam changes maintain the views. Parents read only linked student details and released marks. The R2 Worker must be redeployed for document previews/downloads: its read-only parent endpoint now checks Firestore directly. The existing Cloud Function is optional for parent/teacher reading and remains necessary for permanent Auth deletion. If older app versions edit data, sync parent records again. Class timetable projections exclude student rosters; historical class access is validated against a linked child's roster history. New exam publishing is still committed first; if copying the timetable fails, a warning directs the owner to sync instead of retrying the original examination.
