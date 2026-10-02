from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


MODULE_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(MODULE_DIR))
MODULE_PATH = MODULE_DIR / "validate_shipping_closure.py"
SPEC = importlib.util.spec_from_file_location("validate_shipping_closure", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
shipping_closure = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = shipping_closure
SPEC.loader.exec_module(shipping_closure)
validate_chat_balloon_contract = shipping_closure.validate_chat_balloon_contract


class ChatBalloonClosureTest(unittest.TestCase):
    @staticmethod
    def _contract(*paths: str) -> dict[str, list[str]]:
        return {
            "export_resources": list(paths),
            "include_files": [],
            "pck_files": [],
        }

    def test_code_drawn_source_and_asset_free_contract_pass(self) -> None:
        source = "func _draw() -> void:\n\tdraw_style_box(_bubble_style(), Rect2())\n"
        self.assertEqual(validate_chat_balloon_contract(source, self._contract()), [])

    def test_legacy_source_dependency_fails_closed(self) -> None:
        source = (
            'const TEX_ROOT := "res://content/core_pack/ui/chat_balloon/"\n'
            'var center := "c.png"\n'
        )
        failures = validate_chat_balloon_contract(source, self._contract())
        self.assertEqual(len(failures), 1)
        self.assertIn("legacy PNG dependencies", failures[0])

    def test_legacy_png_in_shipping_contract_fails_closed(self) -> None:
        contract = self._contract("res://content/core_pack/ui/chat_balloon/arrow.png")
        failures = validate_chat_balloon_contract("func _draw():\n\tpass\n", contract)
        self.assertEqual(len(failures), 1)
        self.assertIn("entered the shipping closure", failures[0])


if __name__ == "__main__":
    unittest.main()
