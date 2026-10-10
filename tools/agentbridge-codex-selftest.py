import importlib.util, pathlib, tempfile, unittest, sys
sys.dont_write_bytecode = True
from unittest.mock import patch
spec = importlib.util.spec_from_file_location("lane", pathlib.Path(__file__).with_name("agentbridge-codex-dispatch.py"))
lane = importlib.util.module_from_spec(spec); spec.loader.exec_module(lane)

def message(id=1, **changes):
    c = {"id": id, "user": {"login": lane.OWNER}, "body":
         "[AGENTBRIDGE]\nproject=curse\nfrom=DESIGNER\nto=CODEX\ntype=TASK\ntask=test\n\nHarmless data"}
    c.update(changes); return c

class Tests(unittest.TestCase):
    def test_parser(self):
        self.assertTrue(lane.parse(message()))
        self.assertTrue(lane.parse(message(body=message()["body"].replace("type=TASK", "type=REVIEW"))))
        for c in [message(user={"login":"attacker"}), message(body="echo unsafe"),
                  message(body=message()["body"].replace("to=CODEX","to=CLAUDE")),
                  message(body=message()["body"].replace("task=test","task=$(whoami)")),
                  message(body=message()["body"].replace("project=curse","project=curse\nproject=curse")),
                  message(body=message()["body"].replace("type=TASK","type=REPORT"))]:
            self.assertIsNone(lane.parse(c))
    def test_quotas(self):
        result = {"rateLimits":{"primary":{"windowDurationMins":300,"usedPercent":85},
                 "secondary":{"windowDurationMins":10080,"usedPercent":95}}}
        self.assertEqual(lane.normalize(result)["weekly_used_percent"],95)
        result["rateLimits"]["primary"]["windowDurationMins"]=15
        with self.assertRaises(RuntimeError): lane.normalize(result)
    def test_isolation(self):
        with patch.object(lane, "ROOT", pathlib.Path(tempfile.gettempdir()) / "owner"):
            with self.assertRaises(RuntimeError): lane.isolation()
        with patch.object(lane, "command", return_value="wrong"):
            with self.assertRaises(RuntimeError): lane.isolation()
    def test_pagination(self):
        self.assertEqual([c["id"] for c in lane.flatten([[message(2)], [message(1)]])],[1,2])
    def test_baseline_and_stop(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lane,"RUN",pathlib.Path(d)), \
             patch.object(lane,"isolation"), patch.object(lane,"comments",return_value=[[message(77)]]), \
             patch.object(lane,"usage") as usage, patch.object(lane,"post") as post:
            lane.run(once=True)
            state = lane.json.loads((pathlib.Path(d)/"codex-dispatch-state.json").read_text())
            self.assertEqual(state["last"],77)
            usage.assert_not_called(); post.assert_not_called()
            (pathlib.Path(d)/"codex.stop").write_text("stop")
            lane.run(once=True)
            usage.assert_not_called()
    def test_quota_keeps_task_queued(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lane,"RUN",pathlib.Path(d)), \
             patch.object(lane,"isolation"), patch.object(lane,"comments",return_value=[[message(78)]]), \
             patch.object(lane,"usage",return_value={"five_hour_used_percent":85,"weekly_used_percent":20}), \
             patch.object(lane,"post") as post:
            lane.save({"last":77,"active":None})
            lane.run(once=True)
            state=lane.json.loads((pathlib.Path(d)/"codex-dispatch-state.json").read_text())
            self.assertEqual(state["last"],77); self.assertEqual(state["status"],"QUOTA_PAUSED")
            post.assert_not_called()
    def test_interrupted_task_never_replayed(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lane,"RUN",pathlib.Path(d)), \
             patch.object(lane,"isolation"), patch.object(lane,"comments") as comments:
            lane.save({"last":77,"active":{"id":78}})
            with self.assertRaises(RuntimeError): lane.run(once=True)
            comments.assert_not_called()

    def test_current_executable_ignores_stale_npm_shim(self):
        with patch.dict(lane.os.environ, {}, clear=True), \
             patch.object(lane.shutil, "which", return_value="desktop/codex.exe") as which, \
             patch.object(pathlib.Path, "is_file", return_value=True), \
             patch.object(lane, "command", return_value="codex-cli 0.160.1"):
            self.assertEqual(lane.codex(), ["desktop/codex.exe"])
            which.assert_called_once_with("codex.exe")
    def test_old_cli_model_catalog_failure_is_rejected(self):
        with patch.dict(lane.os.environ, {"CURSE_CODEX_EXECUTABLE":"old/codex.exe"}), \
             patch.object(pathlib.Path, "is_file", return_value=True), \
             patch.object(lane, "command", return_value="codex-cli 0.118.0"):
            with self.assertRaisesRegex(RuntimeError, "older CLI rejects current model catalog/model"):
                lane.codex()
    def test_exact_smoke_002_rejection_diagnostics(self):
        with tempfile.TemporaryDirectory() as d:
            log=pathlib.Path(d)/"worker.jsonl"
            error="The 'gpt-6.1-sol' model is not supported when using Codex with a ChatGPT account."
            events=[{"type":"thread.started"},{"type":"turn.started"},
                    {"type":"error","message":error},{"type":"turn.failed","error":{"message":error}}]
            log.write_text("\n".join(lane.json.dumps(e) for e in events),encoding="utf-8")
            result=lane.worker_diagnostics(log)
            self.assertTrue(result["unsupported_model"])
            self.assertTrue(result["inference_request_attempted"])
            self.assertFalse(result["model_output_observed"])
            self.assertFalse(result["turn_completed"])
    def test_worker_argument_safety(self):
        with patch.object(lane,"worker_base",return_value=["desktop/codex.exe"]):
            args=lane.worker_args(pathlib.Path("final.md"))
            self.assertIn("workspace-write",args)
            self.assertEqual(args[-1],"-")
            self.assertNotIn("--dangerously-bypass-approvals-and-sandbox",args)

    def test_valid_config_is_preserved(self):
        with patch.object(lane, "codex", return_value=["codex"]), patch.object(lane, "command", return_value="features"):
            self.assertEqual(lane.worker_base(), ["codex"])
    def test_unknown_config_error_is_not_hidden(self):
        error = lane.subprocess.CalledProcessError(1, ["codex"], stderr="Unknown unrelated setting")
        with patch.object(lane, "codex", return_value=["codex"]), patch.object(lane, "command", side_effect=error):
            with self.assertRaises(lane.subprocess.CalledProcessError): lane.worker_base()
    def test_spent_failed_task_cannot_replay(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lane,"RUN",pathlib.Path(d)), \
             patch.object(lane,"isolation"), patch.object(lane,"comments",return_value=[[message(79)]]), \
             patch.object(lane,"usage") as usage, patch.object(lane,"post") as post:
            lane.save({"last":78,"active":None,"spent_tasks":["test"]})
            lane.run(once=True)
            state=lane.json.loads((pathlib.Path(d)/"codex-dispatch-state.json").read_text())
            self.assertEqual(state["last"],79)
            usage.assert_not_called(); post.assert_not_called()
    def test_weekly_quota_keeps_task_queued(self):
        with tempfile.TemporaryDirectory() as d, patch.object(lane,"RUN",pathlib.Path(d)), \
             patch.object(lane,"isolation"), patch.object(lane,"comments",return_value=[[message(78)]]), \
             patch.object(lane,"usage",return_value={"five_hour_used_percent":20,"weekly_used_percent":95}), \
             patch.object(lane,"post") as post:
            lane.save({"last":77,"active":None})
            lane.run(once=True)
            state=lane.json.loads((pathlib.Path(d)/"codex-dispatch-state.json").read_text())
            self.assertEqual(state["last"],77); self.assertEqual(state["status"],"QUOTA_PAUSED")
            post.assert_not_called()

    def test_worker_environment_propagation_without_python(self):
        quota={"source":"codex app-server account/rateLimits/read","observed_at":lane.time.time(),
               "five_hour_used_percent":35,"weekly_used_percent":43}
        with patch.dict(lane.os.environ, {"PATH":"stale/npm","GH_CONFIG_DIR":"owner/gh"},clear=True), \
             patch.object(lane,"codex",return_value=["desktop/codex.exe"]), \
             patch.object(lane,"worker_base",return_value=["desktop/codex.exe"]), \
             patch.object(lane,"command",return_value="codex-cli 0.160.1"), \
             patch.object(lane.shutil,"which",return_value="tools/gh.exe"):
            launch=lane.worker_launch(pathlib.Path("final.md"),quota)
            self.assertEqual(launch["argv"][0],"desktop/codex.exe")
            self.assertIn("sandbox_workspace_write.network_access=true",launch["argv"])
            self.assertEqual(launch["shell_env"]["GH_CONFIG_DIR"],"owner/gh")
            self.assertEqual(launch["shell_env"]["CURSE_CODEX_EXECUTABLE"],"desktop/codex.exe")
            self.assertEqual(launch["shell_env"]["CURSE_GH_EXECUTABLE"],"tools/gh.exe")
            self.assertEqual(lane.json.loads(launch["shell_env"]["CURSE_CODEX_USAGE_JSON"]),quota)
            self.assertEqual(launch["shell_env"]["GIT_CONFIG_VALUE_0"],lane.ROOT.as_posix())
            self.assertNotIn("python",str(launch["argv"]).lower())
            self.assertIn("Do not require Python",lane.worker_prompt(launch["metadata"],"read-only validation"))
            self.assertNotIn("GH_TOKEN",launch["shell_env"])
    def test_environment_builder_rejects_stale_or_paused_host_quota(self):
        for quota in [
            {"source":"app-server","observed_at":lane.time.time()-121,"five_hour_used_percent":20,"weekly_used_percent":20},
            {"source":"app-server","observed_at":lane.time.time(),"five_hour_used_percent":85,"weekly_used_percent":20},
            {"source":"app-server","observed_at":lane.time.time(),"five_hour_used_percent":20,"weekly_used_percent":95},
        ]:
            with patch.object(lane,"codex",return_value=["desktop/codex.exe"]), \
                 patch.object(lane.shutil,"which",return_value="tools/gh.exe"):
                with self.assertRaises(RuntimeError): lane.worker_launch(pathlib.Path("final.md"),quota)

if __name__=="__main__": unittest.main()

