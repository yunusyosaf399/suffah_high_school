# Android APK update signing — Suffah High School

## Why Android previously rejected an update

GitHub-hosted Actions runners create a **new debug keystore** when they have no saved signing identity. A new keystore means a different APK certificate. Android will not update an installed app when the package name is the same but the signing certificate differs. Uninstalling succeeds because the old package identity is removed.

## What changed

- GitHub Actions now restores `~/.android/debug.keystore` from an Actions cache before the build, or generates and caches it the first time.
- APKs use `flutter build apk --debug --build-number "${{ github.run_number }}"`: the Android `versionCode` increases automatically with each run.
- A repository secret named `SUFFAH_DEBUG_KEYSTORE_BASE64` takes precedence over the cache, for a signing identity that survives cache eviction.
- No release signing key is stored in GitHub source files.

**Caveat:** GitHub Actions caches are not permanent (commonly expire after seven days without access or may be evicted sooner). The cache alone is helpful during active development, but the repository secret is the reliable fix. If the cache is lost before a secret is configured, a new key will be generated and another one-time uninstall will be necessary.

## Set a permanent preview signing key (recommended)

A dedicated PREVIEW-ONLY debug signing key was generated separately from the repository. Its Base64 text file should be provided privately to the school project owner; it is not committed to source control.

From your Android phone:
1. Open the privately supplied `suffah_preview_debug_keystore.b64.txt` file and **copy the entire single-line text** (without spaces/newlines added by your editor).
2. Open https://github.com/yunusyosaf399/suffah_high_school/settings/secrets/actions
3. Tap **New repository secret**.
4. Name: `SUFFAH_DEBUG_KEYSTORE_BASE64`
5. Value: paste the entire Base64 string, then select **Add secret**.
6. Open the `Android APK — Suffah High School` workflow and run it again on `main`.
7. Install the APK from this new workflow. If Android rejects an update from an older APK, uninstall the older preview once.
8. Following builds will use **the same key** and a higher build number, so Android should offer a normal update without deleting the app.

The preview key has a standard Android debug-keystore password and alias (`android`, `androiddebugkey`). It is **not a production signing key**. Do not put the Base64 text, keystore, password, or service credentials into GitHub commits or public chat messages.

## Production release

Generate a separate, privately protected production upload/signing key and configure the `release` Gradle signing configuration. Never publish a real school app with the preview/debug key. Test an upgrade path from the chosen final release key.

## If updates still fail

Check Android's error: `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means the APK signature differs, while `INSTALL_FAILED_VERSION_DOWNGRADE` means the new APK has a lower version code. Use the GitHub Actions run number and the signing certificate fingerprint to identify which condition happened.

Cloud Firestore student and class records are not deleted by uninstalling the Android app, but local app settings and pending offline data can be lost; avoid uninstalling once real client data is in use.
