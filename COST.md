# COST.md — what this stack costs and how to make it $0

> Golden rule: **`terraform destroy` after every session.** A budget alarm is
> created first (Phase 0) as a backstop, but destroying is what actually stops cost.

## Billable resources (while running)

| Resource | Rough cost | Notes |
|----------|-----------|-------|
| **NAT gateway** | ~$0.045/hr + data | The biggest item. Lets private tasks reach the internet. ~$1/day if left up. |
| **Application Load Balancer** | ~$0.0225/hr + LCU | Public entry point. ~$0.55/day. |
| **Fargate tasks** | ~$0.012/hr per task (0.25 vCPU/0.5GB) | 2 tasks baseline; free-tier gives some hours. |
| **Elastic IP (for NAT)** | free while attached | Charged only if left unattached. |
| ECR | free | Under 500MB storage. |
| DynamoDB | free | On-demand, tiny traffic — within free tier. |
| Secrets Manager | ~$0.40/secret/mo | Prorated; pennies for a day. |
| CloudWatch (logs/alarms/dashboard) | ~free | Small volume, 7-day log retention. |
| Budget / SNS | free | |

**Rough total if left running: ~$1.5–2/day.** For an apply → demo → destroy
session (an hour or two): **well under $1.**

## Teardown

```powershell
powershell -ExecutionPolicy Bypass -File scripts/destroy.ps1
# or:
cd terraform; terraform destroy -auto-approve
```

## Confirm $0 after destroy (checklist)

`terraform destroy` removes everything it created. Double-check nothing lingers:

```powershell
powershell -ExecutionPolicy Bypass -File scripts/cost-check.ps1
```

That script checks for: running ECS services, NAT gateways, load balancers, and
unattached Elastic IPs (the usual sources of surprise charges). All should be empty.

Also glance at **AWS Console → Billing → Cost Explorer** the next day to confirm
the line items stopped.

## Why these choices keep cost down
- **DynamoDB, not RDS** — on-demand + free-tier, no idle instance cost, instant create/destroy.
- **Single NAT gateway** (not one per AZ) — halves the priciest item; fine for a demo.
- **Smallest Fargate size** (0.25 vCPU / 0.5 GB).
- **7-day log retention** — logs don't accumulate cost.
- **Everything in Terraform** — one command creates, one command destroys. No orphaned resources.
