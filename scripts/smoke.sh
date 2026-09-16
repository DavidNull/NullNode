#!/usr/bin/env bash
#
# End-to-end smoke test: ingress -> auth -> router -> Ollama -> cache -> audit
# log in S3. Exits non-zero on failure so it can gate CI.
#
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

GATEWAY="${GATEWAY:-http://gateway.${HOST_SUFFIX}:8080}"
MODEL="${MODEL:-llama3.2}"
FAILURES=0

check() {
  local name="$1"
  shift
  if "$@"; then
    ok "$name"
  else
    err "$name"
    FAILURES=$((FAILURES + 1))
  fi
}

resolve_key() {
  if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
    printf '%s' "$LITELLM_MASTER_KEY"
    return 0
  fi
  kube -n nullnode-platform get secret nullnode-litellm-credentials \
    -o jsonpath='{.data.master-key}' 2>/dev/null | base64 -d
}

phase "Smoke test"
KEY="$(resolve_key || true)"
[[ -n "$KEY" ]] || die "could not resolve the gateway master key"

# 1. Liveness, no auth required.
check "gateway liveness endpoint" \
  curl -fsS --max-time 10 "${GATEWAY}/health/liveliness" -o /dev/null

# 2. An open gateway is the failure nobody notices.
log "checking that an unauthenticated call is rejected"
status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  -X POST "${GATEWAY}/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"'"${MODEL}"'","messages":[{"role":"user","content":"hi"}]}')"
if [[ "$status" == "401" || "$status" == "403" ]]; then
  ok "unauthenticated request rejected (${status})"
else
  err "unauthenticated request returned ${status}, expected 401/403"
  FAILURES=$((FAILURES + 1))
fi

# 3. Model catalogue.
check "model catalogue reachable" \
  curl -fsS --max-time 10 "${GATEWAY}/v1/models" \
  -H "Authorization: Bearer ${KEY}" -o /dev/null

# 4. A real completion. Long timeout: a cold model load is slow.
log "requesting a completion from ${MODEL} (cold start can take a minute)"
payload='{"model":"'"${MODEL}"'","messages":[{"role":"user","content":"Reply with the single word: pong"}],"max_tokens":16,"temperature":0}'
first_response="$(mktemp)"
if curl -fsS --max-time 300 -X POST "${GATEWAY}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H 'Content-Type: application/json' \
  -d "$payload" -o "$first_response"; then
  ok "completion returned"
  hint "$(head -c 300 "$first_response")"
else
  err "completion failed"
  FAILURES=$((FAILURES + 1))
fi

# 5. Same prompt again: latency is the only way to see a cache hit from
#    outside the gateway.
log "replaying the identical prompt to exercise the cache"
t0=$(date +%s%N)
curl -fsS --max-time 300 -X POST "${GATEWAY}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H 'Content-Type: application/json' \
  -d "$payload" -o /dev/null || FAILURES=$((FAILURES + 1))
t1=$(date +%s%N)
elapsed_ms=$(((t1 - t0) / 1000000))
if ((elapsed_ms < 1000)); then
  ok "cache hit (${elapsed_ms} ms)"
else
  warn "replay took ${elapsed_ms} ms - likely a cache miss"
  hint "check: kubectl -n nullnode-platform logs deploy/litellm | grep -i cache"
fi

# 6. Without metrics every dashboard is decoration.
check "gateway exports prometheus metrics" \
  bash -c "curl -fsS --max-time 10 '${GATEWAY}/metrics' | grep -q '^litellm_'"

# 7. The audit trail reached the mocked S3 bucket.
log "checking the audit log in the mocked S3 bucket"
if curl -fsS --max-time 10 "${LOCALSTACK_ENDPOINT}/nullnode-model-vault?list-type=2&prefix=audit" |
  grep -q '<Key>'; then
  ok "audit objects present in s3://nullnode-model-vault/audit"
else
  warn "no audit objects yet - LiteLLM flushes the s3 callback asynchronously"
fi

rm -f "$first_response"

printf '\n'
if ((FAILURES > 0)); then
  die "${FAILURES} smoke check(s) failed"
fi
ok "all smoke checks passed"
