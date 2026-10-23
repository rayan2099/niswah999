import unittest
from check_client_config import validate

class ClientConfigTests(unittest.TestCase):
    def valid(self):
        return {"NISWAH_PUSH_ENABLED":True,"FIREBASE_PROJECT_ID":"niswah-example",
          "FIREBASE_MESSAGING_SENDER_ID":"123456","FIREBASE_API_KEY":"public-example",
          "FIREBASE_ANDROID_APP_ID":"1:123456:android:abc123","FIREBASE_IOS_APP_ID":"1:123456:ios:abc456"}
    def test_mobile_config(self):
        validate(self.valid())
    def test_server_credentials_rejected(self):
        for field in ("FIREBASE_SERVICE_ACCOUNT_JSON","PRIVATE_KEY","SUPABASE_SERVICE_ROLE_KEY"):
            with self.subTest(field=field),self.assertRaises(ValueError):validate({**self.valid(),field:"synthetic"})
    def test_web_app_and_disabled_release_rejected(self):
        with self.assertRaises(ValueError):validate({**self.valid(),"FIREBASE_ANDROID_APP_ID":"1:123456:web:abc"})
        with self.assertRaises(ValueError):validate({**self.valid(),"NISWAH_PUSH_ENABLED":False})
    def test_wrong_sender_or_platform_rejected(self):
        with self.assertRaises(ValueError):validate({**self.valid(),"FIREBASE_IOS_APP_ID":"1:888:ios:abc"})
        validate({**self.valid(),"FIREBASE_IOS_APP_ID":""},"android")

if __name__ == '__main__':unittest.main()
