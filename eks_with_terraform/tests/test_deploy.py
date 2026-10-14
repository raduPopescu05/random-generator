"""Offline safety tests: never call AWS, kubectl, Helm, or Terraform."""
import base64
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import deploy

CONFIG = {
    'cluster_name': 'test-cluster', 'region': 'eu-central-1', 'aws_profile': 'dev',
    'vpc_id': 'vpc-test', 'controller_role_arn': 'arn:aws:iam::123456789012:role/test',
    'backend_image': 'example.com/backend:v1', 'frontend_image': 'example.com/frontend:v1',
}


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.root_patch = patch.object(deploy, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        self.app = deploy.Deployment(CONFIG)

    def test_kubeconfig_and_profile_are_project_local(self):
        self.assertEqual(self.app.env['KUBECONFIG'], str(self.root / '.local/kubeconfig'))
        self.assertEqual(self.app.env['AWS_PROFILE'], 'dev')
        self.assertEqual(self.app.env['AWS_REGION'], 'eu-central-1')

    def test_changed_image_requires_terraform_apply(self):
        (self.root / 'terraform.tfvars.json').write_text(json.dumps(dict(CONFIG, backend_image='example.com/backend:v2')))
        with patch.object(deploy, 'command', return_value=json.dumps(CONFIG)):
            with self.assertRaisesRegex(deploy.DeploymentError, 'backend_image differs'):
                deploy.load_config()
            # Cleanup uses the deployed state, even if local config was edited.
            self.assertEqual(deploy.load_config(require_current=False), CONFIG)

    def test_render_quotes_values_and_rejects_missing_inputs(self):
        value = 'a"\nmalicious: value'
        rendered = deploy.render_text('image: "__IMAGE__"', {'IMAGE': value})
        self.assertEqual(rendered, 'image: ' + json.dumps(value))
        with self.assertRaises(deploy.DeploymentError):
            deploy.render_text('image: "__MISSING__"', {})

    def test_existing_secret_is_not_rotated(self):
        data = {key: base64.b64encode(b'existing').decode() for key in ('DB_PASSWORD', 'DB_ROOT_PASSWORD')}
        with patch.object(self.app, 'kube', return_value=json.dumps({'data': data})) as kube:
            self.app.ensure_secret()
        self.assertEqual(kube.call_count, 1)
        self.assertIn('get', kube.call_args.args)

    def test_incomplete_secret_is_not_overwritten(self):
        with patch.object(self.app, 'kube', return_value='{"data": {}}') as kube:
            with self.assertRaisesRegex(deploy.DeploymentError, 'lacks required passwords'):
                self.app.ensure_secret()
        self.assertEqual(kube.call_count, 1)

    def test_new_passwords_go_only_through_stdin(self):
        with patch.object(self.app, 'kube', side_effect=['', 'secret/app-db created']) as kube:
            self.app.ensure_secret()
        call = kube.call_args
        self.assertEqual(call.args, ('create', '-f', '-'))
        self.assertTrue(call.kwargs['sensitive'])
        secret = json.loads(call.kwargs['input_text'])
        self.assertNotEqual(secret['stringData']['DB_PASSWORD'], secret['stringData']['DB_ROOT_PASSWORD'])
        self.assertFalse((self.root / '.local/db.env').exists())

    def test_aws_permission_failure_stops_cleanup_before_deletion(self):
        with patch.object(self.app, 'kube', return_value='{"items": []}') as kube, \
             patch.object(self.app, 'controller_resources', side_effect=deploy.DeploymentError('AccessDenied')), \
             patch.object(self.app, 'run') as run:
            with self.assertRaisesRegex(deploy.DeploymentError, 'AccessDenied'):
                self.app.down()
        self.assertEqual(kube.call_count, 1)
        run.assert_not_called()

    def test_unfinished_alb_cleanup_keeps_namespace_and_controller(self):
        with patch.object(self.app, 'kube', return_value='{"items": []}') as kube, \
             patch.object(self.app, 'controller_resources', return_value=[{'ResourceARN': 'alb'}]), \
             patch.object(deploy, 'wait_until', side_effect=deploy.DeploymentError('Timed out')), \
             patch.object(self.app, 'run') as run:
            with self.assertRaisesRegex(deploy.DeploymentError, 'Timed out'):
                self.app.down()
        self.assertFalse(any(call.args[:2] == ('delete', 'namespace') for call in kube.call_args_list))
        run.assert_not_called()

    def test_cleanup_deletes_ingress_before_namespace_and_uninstall(self):
        calls = []
        def kube(*args, **kwargs):
            calls.append(args)
            return '{"items": []}' if args[:2] == ('get', 'ingress') else ''
        def run(args, **kwargs):
            calls.append(tuple(args))
            return json.dumps([{'name': deploy.RELEASE}]) if args[:2] == ['helm', 'list'] else ''
        def wait(description, probe, **kwargs):
            self.assertTrue(probe())
        with patch.object(self.app, 'kube', side_effect=kube), \
             patch.object(self.app, 'controller_resources', return_value=[]), \
             patch.object(deploy, 'wait_until', side_effect=wait), \
             patch.object(self.app, 'run', side_effect=run):
            self.app.down()
        ingress = next(i for i,c in enumerate(calls) if c[:4] == ('-n', deploy.NAMESPACE, 'delete', 'ingress'))
        namespace = next(i for i,c in enumerate(calls) if c[:2] == ('delete', 'namespace'))
        uninstall = next(i for i,c in enumerate(calls) if c[:2] == ('helm', 'uninstall'))
        self.assertLess(ingress, namespace)
        self.assertLess(namespace, uninstall)

    def test_deploy_order_and_only_app_pods_restart(self):
        calls = []
        def kube(*args, **kwargs):
            calls.append(args)
            return ''
        def run(args, **kwargs):
            calls.append(tuple(args))
            return ''
        def wait(description, probe, **kwargs):
            return probe()
        with patch.object(self.app, 'render', return_value=self.root), \
             patch.object(self.app, 'kube', side_effect=kube), \
             patch.object(self.app, 'run', side_effect=run), \
             patch.object(self.app, 'ensure_secret'), \
             patch.object(self.app, 'ingress_host', return_value='test.eu-central-1.elb.amazonaws.com'), \
             patch.object(self.app, 'healthy', return_value=True), \
             patch.object(deploy, 'wait_until', side_effect=wait):
            self.app.up()
        restart_calls = [call for call in calls if 'restart' in call]
        self.assertEqual([call[-1] for call in restart_calls], ['deployment/api', 'deployment/web'])
        db_ready = next(i for i,c in enumerate(calls) if 'deployment/db' in c)
        api_apply = next(i for i,c in enumerate(calls) if c[:2] == ('apply', '-f') and c[-1].endswith('20-backend.yaml'))
        web_ready = next(i for i,c in enumerate(calls) if 'deployment/web' in c and 'status' in c)
        ingress_apply = next(i for i,c in enumerate(calls) if c[:2] == ('apply', '-f') and c[-1].endswith('40-ingress.yaml'))
        self.assertLess(db_ready, api_apply)
        self.assertLess(web_ready, ingress_apply)

    def test_subprocess_failure_redacts_secret_output(self):
        result = deploy.subprocess.CompletedProcess([], 1, stdout='password', stderr='password')
        with patch.object(deploy.subprocess, 'run', return_value=result):
            with self.assertRaises(deploy.DeploymentError) as caught:
                deploy.command(['kubectl', 'create', '-f', '-'], input_text='password', sensitive=True)
        self.assertNotIn('password', str(caught.exception))


if __name__ == '__main__':
    unittest.main()
