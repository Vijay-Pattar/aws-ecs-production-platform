"""
AWS ECS Production Platform — demo service.

A deliberately small Flask app whose real job is to be a realistic target for a
production AWS platform: it runs as a container on ECS Fargate behind an ALB, is
deployed blue/green by CodeDeploy, and exposes the endpoints AWS needs to health-
check it and the metrics CloudWatch needs to gate/rollback a deployment.

Two "reliability knobs" (env vars) let us simulate a healthy vs. a bad release,
so we can *prove* automatic rollback on AWS the same way we do on Kubernetes:

    APP_VERSION       e.g. "1.0.0" / "2.0.0"  — shown in responses
    ERROR_RATE        0.0 .. 1.0              — fraction of /work returning 500
    EXTRA_LATENCY_MS  integer                 — artificial latency added to /work

A "bad" v2 sets ERROR_RATE=0.4 → 5xx spike → a CloudWatch alarm fires during the
blue/green deploy → CodeDeploy auto-rolls back to the previous version. No human.

Endpoints:
    GET /            -> service info (version, uptime, which task is serving)
    GET /health      -> ALB health check target (is the process up?)
    GET /work        -> simulated work (carries the injected errors/latency)
    GET /api/config  -> reads a value from Secrets Manager (proves secret wiring)
    GET /api/visits  -> increments + returns a counter in DynamoDB (proves data)
    GET /metrics     -> Prometheus-format metrics (also usable by CloudWatch agent)
"""
from __future__ import annotations

import os
import random
import socket
import time
from threading import Lock

from flask import Flask, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

# ---------------------------------------------------------------------------
# Configuration (env-driven — 12-factor style; nothing hard-coded)
# ---------------------------------------------------------------------------
APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
ERROR_RATE = float(os.getenv("ERROR_RATE", "0.0"))
EXTRA_LATENCY_MS = int(os.getenv("EXTRA_LATENCY_MS", "0"))
PORT = int(os.getenv("PORT", "8000"))

# AWS wiring (all optional — the app runs locally with none of these set).
AWS_REGION = os.getenv("AWS_REGION", "ap-south-1")
SECRET_NAME = os.getenv("SECRET_NAME", "")          # Secrets Manager secret id
VISITS_TABLE = os.getenv("VISITS_TABLE", "")        # DynamoDB table name

START_TIME = time.time()
# The task's hostname — on Fargate this is the task ID, so responses show WHICH
# task served them (handy for demoing load balancing + blue/green).
HOSTNAME = socket.gethostname()

app = Flask(__name__)

# ---------------------------------------------------------------------------
# Metrics — the RED method (Rate, Errors, Duration).
# CloudWatch primarily watches ALB metrics (5xx, latency) for rollback, but we
# also expose app-level metrics here for a fuller observability story.
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "app_http_requests_total", "Total HTTP requests",
    ["method", "endpoint", "http_status", "version"],
)
REQUEST_LATENCY = Histogram(
    "app_http_request_duration_seconds", "HTTP request latency in seconds",
    ["endpoint", "version"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

_lazy_lock = Lock()
_boto_clients: dict = {}


def _client(service):
    """Lazily create + cache a boto3 client. Imported lazily so the app has no
    hard dependency on AWS when running locally / in unit tests."""
    with _lazy_lock:
        if service not in _boto_clients:
            import boto3  # local import: keeps tests AWS-free
            _boto_clients[service] = boto3.client(service, region_name=AWS_REGION)
        return _boto_clients[service]


@app.before_request
def _start_timer():
    request._t0 = time.time()  # type: ignore[attr-defined]


@app.after_request
def _record(resp):
    endpoint = request.endpoint or "unknown"
    REQUEST_LATENCY.labels(endpoint=endpoint, version=APP_VERSION).observe(
        time.time() - getattr(request, "_t0", time.time())
    )
    REQUEST_COUNT.labels(
        method=request.method, endpoint=endpoint,
        http_status=resp.status_code, version=APP_VERSION,
    ).inc()
    return resp


@app.route("/")
def index():
    return jsonify(
        service="aws-ecs-production-platform",
        version=APP_VERSION,
        served_by=HOSTNAME,
        uptime_seconds=round(time.time() - START_TIME, 2),
    )


@app.route("/health")
def health():
    """ALB health check hits this. Keep it trivial: it should answer 'is the
    process up', not 'is my database reachable' (a slow dependency shouldn't make
    the ALB kill healthy tasks). Returns 200 always while the process lives."""
    return jsonify(status="ok", version=APP_VERSION), 200


@app.route("/work")
def work():
    """The meaningful endpoint — load + the break-test hit this.
    EXTRA_LATENCY_MS inflates latency; ERROR_RATE injects 5xx failures."""
    time.sleep(random.uniform(0.005, 0.015))  # nosec B311 - load sim, not crypto
    if EXTRA_LATENCY_MS > 0:
        time.sleep(EXTRA_LATENCY_MS / 1000.0)
    if ERROR_RATE > 0 and random.random() < ERROR_RATE:  # nosec B311
        return jsonify(error="simulated failure", version=APP_VERSION), 500
    return jsonify(result="ok", version=APP_VERSION, served_by=HOSTNAME), 200


@app.route("/api/config")
def api_config():
    """Reads a demo value from AWS Secrets Manager to prove secret wiring works
    without ever putting the secret in code/env. Degrades gracefully locally."""
    if not SECRET_NAME:
        return jsonify(source="local", note="SECRET_NAME not set"), 200
    try:
        import json
        resp = _client("secretsmanager").get_secret_value(SecretId=SECRET_NAME)
        data = json.loads(resp.get("SecretString") or "{}")
        # Only reveal a non-sensitive field, never the whole secret.
        return jsonify(source="secretsmanager", greeting=data.get("greeting", "hello")), 200
    except Exception as exc:  # pragma: no cover
        return jsonify(source="secretsmanager", error=str(exc)), 500


@app.route("/api/visits")
def api_visits():
    """Atomically increments a counter in DynamoDB and returns it — proves the
    task in a private subnet can reach the data store with least-privilege IAM."""
    if not VISITS_TABLE:
        return jsonify(source="local", visits=None, note="VISITS_TABLE not set"), 200
    try:
        resp = _client("dynamodb").update_item(
            TableName=VISITS_TABLE,
            Key={"pk": {"S": "global"}},
            UpdateExpression="ADD visits :one",
            ExpressionAttributeValues={":one": {"N": "1"}},
            ReturnValues="UPDATED_NEW",
        )
        return jsonify(source="dynamodb", visits=int(resp["Attributes"]["visits"]["N"])), 200
    except Exception as exc:  # pragma: no cover
        return jsonify(source="dynamodb", error=str(exc)), 500


@app.route("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":  # pragma: no cover
    # Bind all interfaces so the container is reachable from the ALB. Access is
    # controlled by the security group / private subnet, not by binding. nosec B104
    app.run(host="0.0.0.0", port=PORT)  # nosec B104
