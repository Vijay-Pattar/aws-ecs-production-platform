# syntax=docker/dockerfile:1
#
# Multi-stage, rootless image for ECS Fargate.
#   Stage 1 (builder): install deps into a venv.
#   Stage 2 (runtime): copy only venv + app, run as non-root.
#
# Fargate pulls this image from ECR and runs it as a task. Small, reproducible,
# non-root = smaller attack surface (a control interviewers ask about).

# ---------- Stage 1: builder ----------
FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
COPY app/requirements.txt .
RUN pip install -r requirements.txt

# ---------- Stage 2: runtime ----------
FROM python:3.12-slim AS runtime
ARG APP_VERSION=1.0.0
RUN useradd --create-home --uid 10001 appuser
ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=8000 \
    APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY app/ /app/
USER appuser
EXPOSE 8000

# Container-level healthcheck (ECS can use this; the ALB also health-checks /health).
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0) if urllib.request.urlopen('http://localhost:8000/health').status==200 else sys.exit(1)"

# Gunicorn = production WSGI server (vs Flask's dev server).
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--threads", "4", "--access-logfile", "-", "app:app"]
