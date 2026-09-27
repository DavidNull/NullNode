# 0004 - Autoscaling signal: KEDA for inference, HPA for gateway

**Status:** accepted · **Date:** 2026-08-26

## Context

The template had a `ScaledObject` with a Redis trigger on the `litellm:queue`
list. That list doesn't exist: LiteLLM uses Redis as cache and router state,
not as a queue. The scaler would have always read 0.

The gateway, in parallel, had an HPA on CPU and memory at 80%.

## Decision

Two different signals, for different reasons:

**Ollama → KEDA with Prometheus trigger.** Measures requests per second to the
pool. The correct signal for an inference server is the demand it receives: a
pod blocked waiting for the GPU might be at 15% CPU and saturated.

**LiteLLM → HPA on CPU.** Here CPU does measure something: JSON serialization,
token counting, guardrail calls, log writing.

## With a single GPU, horizontal scaling doesn't help

The device plugin assigns the GPU exclusively to one pod. Therefore:

- `maxReplicas: 1` in the GPU profile. An extra replica stays `Pending`.
- Concurrency is bought vertically: `OLLAMA_NUM_PARALLEL=4`.
- The CPU profile does scale horizontally (`maxReplicas: 3`): cores are shared.

Why KEDA then? For scale-to-zero. `autoscaling.scaleToZero` frees VRAM when
there's no traffic, which on a workstation is what you want to use the GPU for
something else.

It's disabled by default because the request that wakes the pool fails: the
gateway connects before the pod exists. With `router.numRetries: 3` and wider
timeouts you survive, but the first user after a period of inactivity waits
30-60 seconds.

## Consequences

- Scaling depends on Prometheus being healthy. If it goes down, KEDA keeps the
  last replica count: fail-safe.
- `restoreToOriginalReplicaCount: true` so deleting the `ScaledObject` doesn't
  leave the StatefulSet stuck.
- 10-minute cooldown window: a model load takes tens of seconds and flapping is
  worse than keeping a pod warm.
- ArgoCD ignores `/spec/replicas` (in `argocd.tf`). Without that, self-heal and
  the autoscaler fight over the field.
