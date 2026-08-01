# ============================================================================
# NOTE: CodeDeploy blue/green was the original design, but it requires the AWS
# account to be fully activated (new accounts hit SubscriptionRequiredException).
# We switched to the built-in ECS deployment controller with a CIRCUIT BREAKER
# (see ecs.tf), which does automatic rollback natively, needs no CodeDeploy, and
# is a very common production pattern for ECS. The green target group in alb.tf
# is kept so the stack can be upgraded to CodeDeploy blue/green later with no
# rework once the account is activated.
#
# Interview note — how the two compare:
#   CodeDeploy blue/green : spins up a full parallel task set, shifts ALL traffic
#     at once (or canary %), bakes, then tears down old. Instant rollback = flip
#     traffic back. Best for zero-in-flight-risk cutovers.
#   ECS rolling + circuit breaker : replaces tasks gradually behind one target
#     group; if new tasks can't go healthy (or a rollback alarm trips), ECS
#     reverts to the last-good task definition automatically. Simpler, cheaper,
#     no extra service. This is what this project uses.
# ============================================================================
