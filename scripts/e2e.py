#!/usr/bin/env python3
"""Real CLI subprocess and debug-agent protocol tests. No external Python packages."""
import concurrent.futures
import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

BINARY = str(pathlib.Path(sys.argv.pop(1)).resolve()) if len(sys.argv) > 1 else '.build/debug/charge-beep'


class EndToEnd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='charge-beep-e2e-')
        self.env = dict(os.environ, CHARGE_BEEP_HOME=self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, ok=True):
        result = subprocess.run([BINARY, *args], env=self.env, text=True, capture_output=True, timeout=15)
        self.assertEqual(result.returncode == 0, ok, result.stderr)
        return result.stdout

    def status(self):
        return json.loads(self.run_cli('status', '--json'))

    def test_cli_settings_survive_new_processes_and_bad_input(self):
        self.assertEqual(self.status()['threshold'], 1)
        self.run_cli('set', 'threshold', '6')
        self.run_cli('set', 'enabled', 'false')
        for n in ['0', '101', '-1', '1.5', 'NaN']:
            self.run_cli('set', 'threshold', n, ok=False)
        self.assertEqual(self.status()['threshold'], 6)
        self.assertFalse(self.status()['enabled'])
        self.assertIn('version', self.status())
        self.run_cli('status', 'extra', ok=False)
        self.run_cli('set', 'enabled', 'yes', ok=False)

    def test_concurrent_cli_writers_do_not_lose_unrelated_fields(self):
        # Each CLI call is an independent process using the shared lock inode.
        for _ in range(8):
            self.run_cli('set', 'threshold', '1')
            self.run_cli('set', 'enabled', 'true')
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                a = pool.submit(self.run_cli, 'set', 'threshold', '9')
                b = pool.submit(self.run_cli, 'set', 'enabled', 'false')
                a.result(); b.result()
            self.assertEqual((self.status()['threshold'], self.status()['enabled']), (9, False))

    def test_corrupt_settings_are_reported_not_silently_overwritten(self):
        path = pathlib.Path(self.tmp.name) / 'settings.json'
        path.write_text('{broken')
        self.run_cli('status', '--json', ok=False)
        self.run_cli('set', 'threshold', '4', ok=False)
        self.assertEqual(path.read_text(), '{broken')

    def test_two_users_are_isolated(self):
        self.run_cli('set', 'threshold', '20')
        with tempfile.TemporaryDirectory() as other:
            result = subprocess.run([BINARY, 'status', '--json'], text=True, capture_output=True,
                                    env=dict(os.environ, CHARGE_BEEP_HOME=other), check=True, timeout=15)
        self.assertEqual(json.loads(result.stdout)['threshold'], 1)

    def test_agent_process_reload_threshold_repeat_ac_switch_unknown_and_disabled(self):
        proc = subprocess.Popen([BINARY, '_test-agent'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, env=self.env, text=True, bufsize=1)
        def event(now, current=1, on_battery=True, active=True):
            value = dict(now=now, current=current, maximum=100, onBattery=on_battery, active=active)
            proc.stdin.write(json.dumps(value) + '\n'); proc.stdin.flush()
            line = proc.stdout.readline()
            self.assertTrue(line, 'Agent exited unexpectedly')
            return json.loads(line)
        try:
            self.assertFalse(event(0, current=2)['beep'])
            self.assertTrue(event(1)['beep'])
            self.assertFalse(event(1.1)['beep'])
            self.assertTrue(event(11)['beep'])
            self.assertIsNone(event(12, on_battery=False)['next'])
            self.assertTrue(event(13)['beep'])
            self.assertIsNone(event(14, active=False)['next'])
            self.assertTrue(event(15)['beep'])
            self.run_cli('set', 'enabled', 'false')
            self.assertIsNone(event(16)['next'])
            self.run_cli('set', 'enabled', 'true')
            self.run_cli('set', 'threshold', '5')
            self.assertTrue(event(17, current=5)['beep'])
            self.assertIsNone(event(18, current=None)['next'])
            self.assertFalse(event(19, current=6)['beep'])
        finally:
            proc.stdin.close()
            proc.wait(timeout=5)
            self.assertEqual(proc.returncode, 0, proc.stderr.read())
            proc.stdout.close(); proc.stderr.close()


if __name__ == '__main__':
    unittest.main(verbosity=2)
