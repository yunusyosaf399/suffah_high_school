# Manual Firestore test student generator

Use a separate test project whenever possible. The target must have the existing 11 active class IDs. This workflow adds synthetic admitted students, rosters, inventory directory and parent views; it does not create user accounts, fees, attendance, exam marks, or modify existing exam snapshots.

Configure repository Settings > Secrets and variables > Actions > New repository secret named FIREBASE_SEED_SERVICE_ACCOUNT with a Google service account JSON credential for the intended test project. Grant only Cloud Datastore User (roles/datastore.user) on that project, not Owner/Editor. Never commit the credential. Restrict repository write access because Firebase Admin bypasses Firestore client rules. Rotate/delete the key when no longer needed.

Open Actions > Firestore Test Student Generator > Run workflow on main. Set project ID, count (default 100), and dry-run. Review the log. To write, choose apply and type the exact project ID in confirm. The workflow never runs on push or pull request.

Count means total desired records in this fixed seed series, not additional records on each run. Per-student transactions create six new linked records and a migration marker and advance two counters. Re-running skips existing markers. A failed transaction creates no partial student; earlier successful transactions remain. This does not remove test data automatically. Test students affect dashboard totals and future fee generation. No actual student names or contact details are used.
