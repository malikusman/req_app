import json
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

from fastapi.testclient import TestClient
from app import deep_dive_plan
from app.config import settings
from app.main import app


class DeepDivePlanTest(unittest.TestCase):
    def test_unavailable_model_produces_no_plan(self):
        with patch.object(deep_dive_plan, "llm_configured", return_value=False), patch.object(
            deep_dive_plan, "build_chat_openai"
        ) as factory:
            with self.assertRaisesRegex(deep_dive_plan.PlanUnavailable, "model_unavailable"):
                deep_dive_plan.generate_plan({"title": "Invoices"})
            factory.assert_not_called()

    def test_plan_generation_uses_shared_model_and_reports_bad_output(self):
        model = Mock()
        plan = {"sections": [{"title": "Confirm the baseline"}]}
        context = {"title": "Invoices", "open_clarifications": [{"id": 7}]}
        with (
            patch.object(deep_dive_plan, "llm_configured", return_value=True),
            patch.object(deep_dive_plan, "is_open", return_value=False),
            patch.object(deep_dive_plan, "record_success"),
            patch.object(deep_dive_plan, "record_failure"),
            patch.object(deep_dive_plan, "build_chat_openai", return_value=model),
        ):
            model.invoke.return_value = SimpleNamespace(content=json.dumps(plan))
            self.assertEqual(deep_dive_plan.generate_plan(context), {"generated_by": "llm", "plan": plan})
            self.assertEqual(json.loads(model.invoke.call_args.args[0][1].content), context)
            model.invoke.return_value = SimpleNamespace(content="{}", response_metadata={"finish_reason": "length"})
            with self.assertRaisesRegex(deep_dive_plan.PlanUnavailable, "plan_generation_failed"):
                deep_dive_plan.generate_plan(context)

    def test_endpoint_requires_internal_authentication_and_reports_failure(self):
        client = TestClient(app)
        path = "/v1/consultant/deep_dive/plan"
        with patch.object(deep_dive_plan, "generate_plan", side_effect=deep_dive_plan.PlanUnavailable("model_unavailable")) as generate:
            self.assertEqual(client.post(path, json={"context": {}}).status_code, 401)
            generate.assert_not_called()
            response = client.post(path, json={"context": {}}, headers={"X-Internal-Token": settings.internal_api_token})
            self.assertEqual(response.status_code, 503)
            self.assertEqual(response.json(), {"detail": {"error": "model_unavailable"}})


if __name__ == "__main__":
    unittest.main()
