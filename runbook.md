# On-Call Runbook — AWS ECS Production Platform

A runbook maps **an alarm → what it means → what to check → what to do**. It's the
document an on-call engineer opens at 2 AM. Having one is a core SRE practice.

Consoles:
- Dashboard: CloudWatch → Dashboards → `ecs-prod-platform-dashboard`
- Logs: CloudWatch → Log groups → `/ecs/ecs-prod-platform`
- Service: ECS → Clusters → `ecs-prod-platform-cluster` → `ecs-prod-platform-svc`

---

## Alarm: `ecs-prod-platform-http-5xx` (target 5xx high)

**Means:** the app is returning server errors to users. Also the deploy
rollback trigger — if this fires during a deployment, ECS auto-reverts.

**Check:**
1. Is a deployment in progress? ECS → service → Deployments. If yes and it's
   rolling back, the platform is already self-healing — confirm it reverts.
2. App logs for stack traces: CloudWatch Logs `/ecs/ecs-prod-platform`.
3. Dependency health: is DynamoDB / Secrets Manager reachable? (`/api/visits`, `/api/config`)

**Do:**
- If a bad deploy: let the circuit breaker roll back (automatic), or manually
  `aws ecs update-service --task-definition <last-good>`.
- If a dependency: check IAM/task-role and the DynamoDB table/secret exist.
- If load-driven: see the latency alarm below (scale out).

---

## Alarm: `ecs-prod-platform-latency` (p95 response time high)

**Means:** requests are slow (p95 > 0.5s).

**Check:**
1. CPU/memory on the dashboard — saturated?
2. Running task count vs desired — is autoscaling keeping up?
3. Downstream latency (DynamoDB throttling? — unlikely on-demand).

**Do:**
- Autoscaling should add tasks (CPU>50% or >1000 req/task). If not, check the
  scaling policies and service `desired_count` bounds.
- If a code regression, roll back to the previous task definition.

---

## Symptom: tasks won't start / flapping

**Check:** ECS → service → Events, and stopped-task reason.
Common causes:
- Image pull failure → ECR permissions / wrong tag.
- Health check failing → `/health` not returning 200 within grace period.
- Secret/DynamoDB access denied → task-role IAM.

**Do:** fix the root cause; the circuit breaker prevents a bad revision from
taking over (it rolls back automatically).

---

## Deploy went bad but DIDN'T roll back

- Confirm `deployment_circuit_breaker.rollback = true` and the `alarms` block are
  on the service.
- The 5xx alarm only trips with enough traffic — a bad version receiving no
  requests produces no 5xx. In production real traffic covers this; for demos we
  generate load.

---

## Manual rollback (last resort)

```bash
# list task def revisions, pick the last good one
aws ecs list-task-definitions --family-prefix ecs-prod-platform-app --sort DESC
# point the service at it
aws ecs update-service --cluster ecs-prod-platform-cluster \
  --service ecs-prod-platform-svc --task-definition ecs-prod-platform-app:<N>
aws ecs wait services-stable --cluster ecs-prod-platform-cluster --services ecs-prod-platform-svc
```
