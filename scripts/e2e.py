#!/usr/bin/env python3
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BINARY = str(Path(sys.argv.pop(1)).resolve())


class CLIIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='charge-beep-cli-')
        self.addCleanup(self.tmp.cleanup)
        self.env = dict(os.environ, CHARGE_BEEP_HOME=self.tmp.name)

    def cli(self, *args, success=True):
        result = subprocess.run([BINARY, *args], env=self.env, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
        return result.stdout

    def status(self):
        return json.loads(self.cli('status', '--json'))

    def test_commands_persist_settings_and_reject_invalid_input_without_changes(self):
        self.cli('set', 'threshold', '6')
        self.cli('set', 'enabled', 'false')
        before = (Path(self.tmp.name) / 'settings.json').read_bytes()
        for args in [('set', 'threshold', '0'), ('set', 'threshold', '101'),
                     ('set', 'threshold', '1.5'), ('set', 'enabled', 'yes'),
                     ('status', 'extra'), ('_test-agent',)]:
            with self.subTest(args=args):
                self.cli(*args, success=False)
                self.assertEqual((Path(self.tmp.name) / 'settings.json').read_bytes(), before)
        state = self.status()
        self.assertEqual((state['threshold'], state['enabled']), (6, False))
        self.assertEqual(state['version'], self.cli('version').strip())

    def test_writers_wait_for_the_lock_then_preserve_each_others_changes(self):
        self.cli('set', 'threshold', '1')
        processes = []
        try:
            with (Path(self.tmp.name) / 'settings.lock').open('r+') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                for args in [('set', 'threshold', '9'), ('set', 'enabled', 'false')]:
                    process = subprocess.Popen([BINARY, *args], env=self.env, text=True,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    processes.append(process)
                for process in processes:
                    with self.assertRaises(subprocess.TimeoutExpired):
                        process.wait(timeout=0.25)
                self.assertEqual(self.status()['threshold'], 1)
                fcntl.flock(lock, fcntl.LOCK_UN)
            for process in processes:
                _, error = process.communicate(timeout=10)
                self.assertEqual(process.returncode, 0, error)
            state = self.status()
            self.assertEqual((state['threshold'], state['enabled']), (9, False))
        finally:
            for process in processes:
                if process.poll() is None:
                    process.kill()
                process.communicate(timeout=5)

    def test_corrupt_config_is_reported_without_replacing_it(self):
        path = Path(self.tmp.name) / 'settings.json'
        path.write_text('{broken')
        self.cli('status', '--json', success=False)
        self.cli('set', 'threshold', '4', success=False)
        self.assertEqual(path.read_text(), '{broken')


if __name__ == '__main__':
    unittest.main(verbosity=2)
