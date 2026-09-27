# 0006 - LiteLLM metrics, with OTel spanmetrics as safety net

**Status:** accepted · **Date:** 2026-08-26

## Context

The template's dashboard graphed non-existent metrics
(`litellm_request_duration_seconds_bucket`, `litellm_requests_total`,
`litellm_tokens_generated_total`). The real names are different
(`litellm_proxy_total_requests_metric_total`,
`litellm_llm_api_time_to_first_token_metric_bucket`). And it wasn't connected
to anything: the JSON was in the repo while Grafana provisioned `gnetId: 1`,
a random public dashboard.

Underneath there's a bigger problem: those names change between LiteLLM minor
versions, and in some builds the Prometheus callback is behind an enterprise
license.

## Decision

**Primary:** LiteLLM's `prometheus` callback, via ServiceMonitor. It's the only
source of TTFT, tokens, spend and remaining budget per team; nothing else in the
stack knows those concepts.

**Safety net:** LiteLLM also exports OTLP traces, and the collector has the
`spanmetrics` connector enabled, which derives RED metrics with prefix
`nullnode_`. If the callback isn't available, you get rate, errors and latency
without touching anything.

The fallback does **not** cover TTFT, tokens or budget: only LiteLLM knows those.

**Cache:** from the Redis exporter (`redis_keyspace_hits_total` / `misses`).
Works because the gateway is the only client of that instance.

**VRAM:** from the DCGM exporter, only in GPU profile. cAdvisor reports host RAM,
which says nothing about whether a model fits on the card.

## Consequences

- Dashboards include a panel with the command to check names. An empty panel
  doesn't distinguish "no traffic" from "the metric was renamed".
- Recording rules are the only definition of each signal
  (`nullnode:ttft_seconds:p95`, etc.), so an alert can't contradict its graph.
- The KEDA trigger has the alternative query in the values
  (`autoscaling.prometheus.fallbackQuery`).
- Updating LiteLLM requires verifying the names. It's in the `GOTO.md` checklist.
