import sys
import unittest
from pathlib import Path


API_DIR = Path(__file__).resolve().parents[1] / "server" / "api"
sys.path.insert(0, str(API_DIR))

import autodoctor_service


class ServiceStartupModeTests(unittest.TestCase):
    def setUp(self):
        self.original_frozen = getattr(sys, "frozen", None)

    def tearDown(self):
        if self.original_frozen is None:
            if hasattr(sys, "frozen"):
                delattr(sys, "frozen")
        else:
            sys.frozen = self.original_frozen

    def test_non_frozen_no_args_uses_command_line_handler(self):
        if hasattr(sys, "frozen"):
            delattr(sys, "frozen")

        self.assertFalse(
            autodoctor_service.should_start_service_dispatcher(["service.py"])
        )

    def test_frozen_no_args_uses_service_dispatcher(self):
        sys.frozen = True

        self.assertTrue(
            autodoctor_service.should_start_service_dispatcher(["service.exe"])
        )

    def test_frozen_with_command_uses_command_line_handler(self):
        sys.frozen = True

        self.assertFalse(
            autodoctor_service.should_start_service_dispatcher(["service.exe", "start"])
        )


class FakeProcess:
    def __init__(self, exit_code):
        self.exit_code = exit_code

    def poll(self):
        return self.exit_code


class ChildProcessStartupTests(unittest.TestCase):
    def test_child_process_exit_during_startup_raises(self):
        with self.assertRaisesRegex(RuntimeError, "exited during startup"):
            autodoctor_service.ensure_child_process_running(
                FakeProcess(1),
                ["autodoctor_api.exe"],
                grace_seconds=0,
            )

    def test_child_process_still_running_passes(self):
        autodoctor_service.ensure_child_process_running(
            FakeProcess(None),
            ["autodoctor_api.exe"],
            grace_seconds=0,
        )


if __name__ == "__main__":
    unittest.main()
