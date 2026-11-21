# Suffah High School — Android preview APK

## Build on GitHub Actions
Open: https://github.com/yunusyosaf399/suffah_high_school/actions/workflows/android-apk.yml

- On a phone, use Chrome's **Desktop site** if buttons are hidden.
- Choose **Run workflow**, select `main`, and tap **Run workflow**.
- Open the newest **Android APK — Suffah High School** run.
- Wait until the **Build and test Android APK** job succeeds.
- Scroll to **Artifacts** and download `Suffah-High-School-Android-Debug-APK` (ZIP).
- Extract the ZIP. It contains `app-debug.apk`. Open the APK on Android and allow installation from Chrome / Files when prompted.

The workflow also runs automatically when the app source or workflow changes are pushed to `main`, provided GitHub Actions is enabled.

## What can be tested
1. Open APK with internet access.
2. Sign in using the email/password created in Firebase Authentication.
3. The Firestore owner document must exist at `users/<your Firebase Auth UID>` with:
   - `role` = `owner`
   - `active` = `true` (boolean)
   - `displayName` = a text name
4. Verify the owner dashboard opens, module preview tiles render, and Sign out works.
5. Verify invalid credentials display a clear error message.

The modules are previews: no admissions, fee, result, or attendance workflows are implemented. Other roles are intentionally blocked.

This APK is **debug signed for testing**, not ready for Play Store production. Do not distribute to parents or staff yet. The first iOS and Windows builds need their own registration and platform validation.

## Troubleshooting
If no workflow runs appear, manually select Run workflow. If GitHub reports a failure, inspect the failed job logs and share them for correction. GitHub Actions artifacts are ZIP archives and may require GitHub authentication in private repositories.

This build does not upgrade Firebase billing, write student records, or change the previous Supabase project.
