# School office internet voice calls

## Scope
Parents and teachers with Messages permission can call the office via the phone icon on their dashboard or conversation. The owner and authorized principals can answer the call. One call per caller; one office device can claim each call. No video or phone carrier calling, and no call audio is recorded or uploaded. Firestore stores the latest session state per caller; SDP is removed on a normal end. Stale sessions expire and can be replaced. This is an initial foreground implementation: Android can receive an FCM notification in the background and open the app to answer; it is not a native lock-screen phone UI and does not keep calls alive when the app is backgrounded. Windows receives calls while the app is running. No automatic redial or callback.

## Deploy
1. Pull main, run flutter pub get and deploy firestore:rules to suffah-high-school.
2. Run Deploy Android message notifications, mode deploy.
3. Build Windows and Android again. Both devices need the updated app. Allow microphone and Android notification permissions. The Android and Windows builds and actual microphone/speaker calls must be verified.
4. For reliable calls across networks, create a Cloudflare Realtime TURN key. Add its key ID and key API token as GitHub Actions secrets TURN_KEY_ID and TURN_KEY_API_TOKEN respectively, then deploy the Worker again. Never embed these credentials in the app. The Worker validates Firebase identity and returns temporary ICE credentials. Without TURN, direct STUN connections may work but some mobile/corporate networks will fail. TURN usage is subject to Cloudflare pricing and quotas.
5. Test with two different accounts: parent on Android, owner on Windows; then reverse platforms if applicable. Test answer, decline, timeout, mute, hangup, permission denial and an interrupted connection. Check office phone notification on Android. No Firebase Cloud Functions or Blaze upgrade is needed by this architecture.

## Limitations
Non-trickle ICE signaling waits up to 12 seconds to gather candidates on each side. An unanswered call expires after about 60 seconds, connected sessions have a maximum of 55 minutes. Call signaling is limited to authorized participants and office users, not a guarantee of end-to-end identity verification. FCM is best-effort and does not guarantee a timely background alert. The existing conversation deletion feature does not delete separate call session metadata. Do not test with real students before validating access and device behavior.
