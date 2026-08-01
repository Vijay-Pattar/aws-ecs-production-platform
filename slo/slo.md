# SLIs / SLOs — AWS ECS Production Platform

The rollback threshold isn't arbitrary — it comes from the service's SLOs.

## Definitions

| Term | Meaning | Here |
|------|---------|------|
| **SLI** | a measured number | availability = non-5xx ÷ total requests |
| **SLO** | the target for an SLI | 99% availability, p95 latency < 500ms |
| **Error budget** | 100% − SLO | 1% of requests may fail |

## Our SLOs

| SLI | Source (CloudWatch) | SLO |
|-----|---------------------|-----|
| Availability | `HTTPCode_Target_5XX_Count` ÷ `RequestCount` (ALB) | **99%** |
| Latency (p95) | `TargetResponseTime` p95 (ALB) | **< 500 ms** |

## How the SLO maps to alarms + rollback

- **`http-5xx` alarm**: > 5 target 5xx in 60s → fires. Wired as the ECS
  deployment **rollback trigger** *and* an SNS page. It's a deliberately fast,
  sensitive tripwire so a bad deploy is caught in ~1 minute — before it burns
  meaningful error budget.
- **`latency` alarm**: p95 > 0.5s for 2 minutes → pages (autoscaling should
  react first).

## Error budget thinking (interview-ready)

- 99% SLO → 1% budget. Over 1,000,000 requests, that's 10,000 allowed failures.
- A healthy budget = permission to ship fast. An exhausted one = freeze features,
  fix reliability.
- **Burn rate** = how fast you're spending the budget. A bad deploy at 40% error
  rate burns ~40× — which is exactly why the platform rolls it back automatically
  instead of waiting for a human.

## Why this differs from the deploy gate

The deploy rollback fires at ">5 5xx in 60s" (fast, protects a release in
progress). The long-term SLO (99%/30 days) is the business objective. The fast
gate is intentionally tighter so it trips *before* real budget is spent.
