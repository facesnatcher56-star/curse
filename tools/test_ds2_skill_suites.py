import unittest
import os
import subprocess
import sys

class TestDS2SkillSuites(unittest.TestCase):
    def test_skill_suites_verification(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        checker = os.path.join(root, "tools", "check_ds2_skill_suites.py")
        res = subprocess.run([sys.executable, checker], capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, f"check_ds2_skill_suites failed:\n{res.stdout}\n{res.stderr}")
        self.assertIn("SUCCESS: DS2 Passive Skill Suites reference is 100% verified.", res.stdout)

if __name__ == "__main__":
    unittest.main()
