# AWS Production Platform — ECS Fargate

[![CI](https://github.com/YOUR_USERNAME/aws-ecs-production-platform/actions/workflows/ci.yml/badge.svg)](https://github.com/YOUR_USERNAME/aws-ecs-production-platform/actions/workflows/ci.yml)

A production-style container platform on **AWS**, provisioned entirely with
**Terraform**: a containerized service on **ECS Fargate** behind an **ALB**, with
**automatic rollback on a CloudWatch alarm**, **GitHub Actions CI/CD via OIDC
(no static AWS keys)**, autoscaling, secrets management, and CloudWatch
observability. Designed to be **applied, demoed, and torn down** — free-tier
friendly.

> The app is deliberately small. The point is the **platform + reliability
> engineering** around it, on real AWS.

---

## The one thing to understand

A new version does **not** just replace the old one and hope. ECS rolls it out
gradually and **watches it**:

1. A new task definition (new image / config) is deployed.
2. ECS starts new tasks behind the ALB and shifts traffic to them.
3. The **deployment circuit breaker** + a **CloudWatch 5xx alarm** watch the new
   version. Tasks must pass ALB health checks **and** not trip the alarm.
4. If the new version fails health checks *or* the 5xx alarm fires,
   **ECS automatically rolls back to the last-good version — no human.**

**Proven live:** deploying a version that fails 40% of requests (`ERROR_RATE=0.4`)
drove the ALB 5xx metric to **905/min**, the alarm fired, and ECS reverted to the
previous task definition automatically. Real CloudWatch data from that run is in
`docs/`.

```
Developer → GitHub → GitHub Actions (OIDC, no static keys)
                          │ build image → push → ECR
                          ▼
   Internet → ALB ──────► ECS Service (Fargate, private subnets)
     (HTTP)   │             ├── task (v1)   ← rolls back here on failure
              │             └── task (v2)   ← new version under watch
              │                    │ logs/metrics
   CloudWatch alarm ◄──── 5xx / latency ────┘
        │ (circuit-breaker + alarm rollback trigger)      Auto Scaling (CPU / req)
        ▼
   auto-rollback to last-good        Secrets Manager · DynamoDB · SNS email
```

---

## Tech stack (all real, standard AWS)

| Layer | Service | Role |
|-------|---------|------|
| Compute | **ECS Fargate** | Serverless containers — no servers to manage |
| Registry | **ECR** | Private image registry (immutable tags, scan-on-push) |
| Load balancing | **ALB** | Public entry, health checks, traffic to tasks |
| Safe deploys | **ECS deployment circuit breaker + CloudWatch alarm** | Automatic rollback |
| CI/CD | **GitHub Actions + OIDC** | Build/push/deploy with **zero static AWS keys** |
| Networking | **VPC** (public/private subnets, NAT, SGs) | Tasks isolated in private subnets |
| Data | **DynamoDB** (on-demand) | App state; least-privilege access |
| Secrets | **Secrets Manager** | No secrets in code/env |
| Autoscaling | **Application Auto Scaling** | Target-tracking on CPU + requests/task |
| Observability | **CloudWatch** dashboard, alarms, logs, Container Insights | Metrics + the rollback trigger |
| Alerting | **SNS → email** | Alarm notifications |
| IaC | **Terraform** | One `apply`, one `destroy` |
| Identity | **IAM** (task / execution / OIDC roles) | Least privilege throughout |

---

## Quick start

```powershell
# 0. Tools + credentials
powershell -ExecutionPolicy Bypass -File scripts/install-tools.ps1
aws configure                                   # region: ap-south-1
powershell -ExecutionPolicy Bypass -File scripts/aws-setup.ps1

# 1. Config
cd terraform
cp terraform.tfvars.example terraform.tfvars    # set budget_alert_email

# 2. Create the stack (budget alarm is created first)
terraform init
terraform apply

# 3. Push the app image + run it
cd ..
powershell -ExecutionPolicy Bypass -File scripts/build-push.ps1 -Tag v1
# (first apply runs :v1; CI handles subsequent deploys)

# 4. Open the app
terraform -chdir=terraform output alb_url
```

### 🔥 Always tear down after a session

```powershell
powershell -ExecutionPolicy Bypass -File scripts/destroy.ps1
powershell -ExecutionPolicy Bypass -File scripts/cost-check.ps1   # confirm $0
```

See **[COST.md](COST.md)** for the full billable-resource list.

---

## Repository layout

```
app/                 Flask app (RED metrics + break-test knobs + /health, DynamoDB, Secrets)
Dockerfile           Rootless multi-stage image
terraform/           The whole platform as code (vpc, alb, ecs, iam, data, oidc, observability…)
deploy/              appspec (kept for a future CodeDeploy upgrade path)
.github/workflows/   ci.yml (lint/test/validate) + deploy.yml (OIDC → ECR → ECS rolling deploy)
scripts/             install, aws-setup, build-push, destroy, cost-check
runbook.md           On-call runbook: alarm → diagnosis → action
slo/slo.md           SLIs / SLOs / error-budget thinking
COST.md              Billable resources + teardown proof
```

---

## Learn more

- **[runbook.md](runbook.md)** — the on-call runbook (SRE artifact)
- **[slo/slo.md](slo/slo.md)** — SLIs, SLOs, error budgets
- **[COST.md](COST.md)** — cost + teardown

---

## Before you publish this repo (checklist)

- [ ] Replace `YOUR_USERNAME` in the CI badge, `terraform/oidc.tf` (`github_repo`),
      and `.github/workflows/deploy.yml` variables.
- [ ] `terraform.tfvars` (your email) is git-ignored — keep it that way.
- [ ] No AWS keys anywhere — CI uses OIDC; local uses `aws configure`.
- [ ] Confirm `terraform destroy` completed (COST.md checklist).
