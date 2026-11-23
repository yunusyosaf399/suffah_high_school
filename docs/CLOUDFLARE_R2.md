# Private Cloudflare R2 student storage

This app saves student data and file metadata in Firestore, with student photos
and certificates in a PRIVATE Cloudflare R2 bucket behind an authenticated
Cloudflare Worker. Firebase Storage/Blaze is not required.

## Set up the Worker

1. In the Cloudflare dashboard open **R2 Object Storage**. Create a bucket named
   **suffah-school-files** using Standard storage. If your existing bucket
   has a different name, change **bucket_name** in
   **cloudflare/student-files/wrangler.toml**.
2. Keep the bucket private: **do not enable public r2.dev access** or a
   public bucket domain.
3. On a computer with Node.js, check out this repository and run these commands
   from its root:

       cd cloudflare/student-files
       npm install
       npx wrangler login
       npx wrangler deploy

4. Copy the HTTPS Worker URL printed by Wrangler. It will resemble
   https://suffah-student-files.YOUR-SUBDOMAIN.workers.dev
5. In GitHub open the repository **Settings → Secrets and variables → Actions →
   Variables → New repository variable**. Set name **R2_WORKER_URL** to the
   Worker URL, without a trailing slash.
6. Run the **Android APK — Suffah High School** workflow and install the new
   APK. The build forwards the Worker URL with Flutter's --dart-define option.

For local Flutter builds, add this option to flutter run:

    --dart-define=R2_WORKER_URL=https://YOUR-WORKER.workers.dev

The Worker already uses the Firebase project ID **suffah-high-school**. Update
the Worker FIREBASE_PROJECT_ID variable if you ever switch Firebase projects.
The Worker relies on its R2 binding, not R2 API keys.

## Admissions and existing student edits

- Students → Add student → **Student**: upload or replace the student photo.
  The device compresses it to WebP, maximum 100 KiB.
- **Review**: upload a birth certificate, transfer certificate, previous-school
  certificate, medical report, or other document. Accepted formats: PDF, JPG,
  PNG and WebP, maximum 5 MiB per document.
- Students → existing student → **Edit student**: the same controls support
  adding, replacing or removing files.
- Student profile: the photo is displayed privately, image documents can be
  previewed, and PDFs can be saved locally for viewing with the device's PDF
  viewer.
- The existing Firestore fields **photoPath** and **attachments** store only
  object keys, filenames, sizes and content types. Never store raw files in
  Firestore.

## Security

Every Worker request validates a Firebase Authentication ID token with
Google's signing keys. The Worker then reads the student record through
Firestore REST using the *same user's ID token*. The existing Firestore rules
limit student access to the owner and principal, so users cannot circumvent
those rules through R2. No Firebase service-account keys are required.

The Worker does not expose public image URLs. The R2 bucket must remain
private. Never put R2 credentials or Firebase service-account JSON in the app
or GitHub repository. Uploaded documents are private school records.

After a successful Firestore update, the app may delete a replaced/removed R2
object. The Worker refuses deletion while Firestore still references that
object. Interrupted updates can create orphaned uploaded files and need
reconciliation as part of production maintenance.

## Existing Firebase Storage photos

If a student record previously stored a Firebase Storage path, its file is
not automatically moved into R2. Re-upload it through the Edit Student flow
or plan an authorized migration first. The private R2 Worker only serves
new R2 object keys.

Cloudflare's free tiers have usage allowances rather than unlimited free
usage. Monitor both R2 and Workers usage.

## Acceptance test

1. Deploy Worker and configure repository variable before building APK.
2. Register a test student, upload a photo and a birth certificate, and save.
3. Open the student profile; confirm the photo appears and the document opens.
4. Edit student; replace the photo, remove a certificate, and save. Reopen the
   profile and confirm Firestore metadata and R2 access reflect those changes.
5. Sign in as an unauthorized role; confirm Worker access is rejected.
6. Test expired auth, missing Worker URL, offline uploads and oversized files.
