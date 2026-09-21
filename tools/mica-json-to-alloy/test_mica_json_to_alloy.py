import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("mica_json_to_alloy.py")
SPEC = importlib.util.spec_from_file_location("mica_json_to_alloy", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CompilerTests(unittest.TestCase):
    def test_compiles_two_policy_pipeline(self):
        examples = Path(__file__).with_name("examples")
        compiler = MODULE.Compiler(MODULE.Aliases())
        compiler.compile_file(examples / "policy-p1.json")
        compiler.compile_file(examples / "policy-p2.json")
        output = compiler.emit("generated/test")

        self.assertIn("module generated/test", output)
        self.assertIn("Channel_Internal.memType = Protected", output)
        self.assertIn("Channel_Egress.memType = Unprotected", output)
        self.assertIn("assert ConfigurationIsValid", output)

    def test_rejects_conflicting_channel_types(self):
        first = {
            "Peers": {"Self": "P", "P": {}},
            "MemChannels": {
                "C": {"type": "PROTECTED", "mappings": {"P": {"prot": "R"}}}
            },
        }
        second = {
            "Peers": {"Self": "P", "P": {}},
            "MemChannels": {
                "C": {"type": "UNPROTECTED", "mappings": {"P": {"prot": "R"}}}
            },
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            left = root / "left.json"
            right = root / "right.json"
            left.write_text(json.dumps(first))
            right.write_text(json.dumps(second))
            compiler = MODULE.Compiler(MODULE.Aliases())
            compiler.compile_file(left)
            with self.assertRaises(MODULE.CompileError):
                compiler.compile_file(right)


if __name__ == "__main__":
    unittest.main()
