import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("release_privacy",ROOT/"scripts/audit-release-privacy.py")
audit=importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)

class PrivacyTests(unittest.TestCase):
    def test_reports_locations_without_disclosing_values(self):
        token=b"gh"+b"p_"+b"A"*36
        details=audit.inspect("sample.txt",token,{token},{})
        self.assertIn("credential_token",{r["category"] for r in details})
        self.assertNotIn(token.decode(),json.dumps(details))

    def test_markers_paths_and_realistic_email_are_detected(self):
        for value,category in [(b"co"+b"dex","unwanted_tool_marker"),(b"C:"+b"/Users/"+b"ExamplePerson/file","local_user_path"),(b"private"+b"@"+b"mail.provider.com","review_email")]:
            self.assertIn(category,{r["category"] for r in audit.inspect("sample",value,set(),{})})
        self.assertEqual(audit.inspect("test",b"user@vpn.example.com /home/user",set(),{}),[])

    def test_only_exact_public_fixture_material_is_allowed(self):
        block=b"-----BEGIN PRIVATE KEY-----\n"+b"A"*80+b"\n-----END PRIVATE KEY-----"
        self.assertTrue(audit.inspect("fixture",block,set(),{}))
        allow={"fixture":[hashlib.sha256(block).hexdigest()]}
        self.assertEqual(audit.inspect("fixture",block,set(),allow),[])
        self.assertTrue(audit.inspect("other",block,set(),allow))

if __name__=="__main__":unittest.main()
