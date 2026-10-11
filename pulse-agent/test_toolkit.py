import subprocess
import unittest
from unittest.mock import patch
from pulse_toolkit import PulseToolkit


class ToolkitEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.toolkit = PulseToolkit(cli_path="/fixture/pulse")

    def test_parsed_partial_failure_retains_exit_and_evidence(self):
        response = subprocess.CompletedProcess([], 1, '{"affectedPaths":["fixture"],"failures":{"other":"denied"}}', '')
        with patch('pulse_toolkit.subprocess.run', return_value=response):
            result = self.toolkit._run_cmd(['clean'])
        self.assertEqual(1, result['exitCode'])
        self.assertEqual(['fixture'], result['affectedPaths'])
        self.assertIn('other', result['failures'])
        self.assertIn('error', result)

    def test_failed_preview_never_authorizes_mutation(self):
        with patch.object(self.toolkit, '_run_cmd', return_value={'failures': {'fixture': 'denied'}}):
            self.toolkit.clean_target('fixture', dry_run=True)
        self.assertNotIn('fixture', self.toolkit.previewed_clean_targets)
        self.assertIn('error', self.toolkit.quit_application(123, 'start'))

    def test_quit_preview_is_bound_to_exact_identity_and_consumed(self):
        with patch.object(self.toolkit, '_run_cmd', return_value={'dryRun': True}):
            self.toolkit.preview_application_quit(123, 'start')
            self.assertIn('error', self.toolkit.quit_application(123, 'other'))
            self.toolkit.quit_application(123, 'start')
            self.assertIn('error', self.toolkit.quit_application(123, 'start'))

    def test_history_bounds_are_disclosed_without_losing_minute_identity(self):
        history = {'metrics': {'cpu': [{'minute': i, 'value': 10} for i in range(100)]}, 'anomalies': list(range(30)), 'batterySessions': list(range(15))}
        with patch.object(self.toolkit, '_run_cmd', return_value=history):
            result = self.toolkit.get_diagnostic_history()
        self.assertEqual(40, result['metrics']['cpu'][0]['minute'])
        self.assertEqual(100, result['agentOutputLimits']['metrics']['cpu']['observedMinutes'])
        self.assertEqual(20, len(result['anomalies']))

    def test_observation_is_bounded_and_gets_sufficient_timeout(self):
        self.assertIn('error', self.toolkit.observe_performance(601))
        with patch.object(self.toolkit, '_run_cmd', return_value={}) as run:
            self.toolkit.observe_performance(60)
            run.assert_called_once_with(['observe', '--seconds', '60'], timeout=80)


if __name__ == '__main__':
    unittest.main()
