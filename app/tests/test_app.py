"""Unit tests for the demo service. No AWS needed — boto3 is only touched when
SECRET_NAME / VISITS_TABLE are set, which they aren't in tests."""
import pytest


@pytest.fixture()
def client():
    import app as app_module
    app_module.app.config.update(TESTING=True)
    with app_module.app.test_client() as c:
        yield c


def test_index(client):
    r = client.get("/")
    assert r.status_code == 200
    body = r.get_json()
    assert body["service"] == "aws-ecs-production-platform"
    assert "version" in body and "served_by" in body


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_work_ok_by_default(client):
    r = client.get("/work")
    assert r.status_code == 200
    assert r.get_json()["result"] == "ok"


def test_metrics(client):
    r = client.get("/metrics")
    assert r.status_code == 200
    assert b"app_http_requests_total" in r.data
    assert b"app_http_request_duration_seconds" in r.data


def test_config_degrades_locally(client):
    # With SECRET_NAME unset, /api/config must not touch AWS and must 200.
    r = client.get("/api/config")
    assert r.status_code == 200
    assert r.get_json()["source"] == "local"


def test_visits_degrades_locally(client):
    r = client.get("/api/visits")
    assert r.status_code == 200
    assert r.get_json()["source"] == "local"


def test_error_rate_knob(client, monkeypatch):
    """ERROR_RATE=1.0 → every /work returns 500. This is the break-test mechanism
    that drives the CloudWatch 5xx alarm and the CodeDeploy auto-rollback."""
    import app as app_module
    monkeypatch.setattr(app_module, "ERROR_RATE", 1.0)
    for _ in range(5):
        r = client.get("/work")
        assert r.status_code == 500
        assert r.get_json()["error"] == "simulated failure"


def test_latency_knob(client, monkeypatch):
    import time

    import app as app_module
    monkeypatch.setattr(app_module, "EXTRA_LATENCY_MS", 100)
    t0 = time.time()
    r = client.get("/work")
    assert r.status_code == 200
    assert time.time() - t0 >= 0.1
