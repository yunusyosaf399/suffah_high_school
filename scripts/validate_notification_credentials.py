"""Check credential shape, Google authentication, Firestore read and FCM validation.
Never print the key, access token, account email or raw API responses.
"""
import json
import os
import sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

def main():
    raw = os.environ.get("FIREBASE_NOTIFICATION_SERVICE_ACCOUNT", "")
    if not raw:
        print("Missing repository secret FIREBASE_NOTIFICATION_SERVICE_ACCOUNT.")
        return 1
    try:
        data = json.loads(raw)
        if data.get("type") != "service_account" or data.get("project_id") != "suffah-high-school":
            print("Expected a service account JSON for suffah-high-school.")
            return 1
        creds = service_account.Credentials.from_service_account_info(data, scopes=[
            "https://www.googleapis.com/auth/datastore",
            "https://www.googleapis.com/auth/firebase.messaging",
        ])
        session = AuthorizedSession(creds)
        res = session.post("https://firestore.googleapis.com/v1/projects/suffah-high-school/databases/(default)/documents:runQuery",
            json={"structuredQuery":{"from":[{"collectionId":"message_alerts"}],"limit":1}}, timeout=30)
        print("Firestore permission check:", res.status_code)
        if res.status_code != 200:
            return 1
        # validate_only never sends a notification. An unused topic avoids handling device tokens.
        res = session.post("https://fcm.googleapis.com/v1/projects/suffah-high-school/messages:send",
            json={"validate_only":True,"message":{"topic":"school-notification-validation","notification":{"title":"Validation","body":"Validation only"}}},timeout=30)
        print("FCM validation-only check:",res.status_code)
        if res.status_code != 200:
            return 1
        print("Notification credentials validated. No message sent and no Firestore writes performed.")
        return 0
    except Exception as exc:
        print("Credential validation failed:",type(exc).__name__)
        return 1

if __name__ == "__main__":
    sys.exit(main())
