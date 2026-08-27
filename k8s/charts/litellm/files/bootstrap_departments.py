#!/usr/bin/env python3
"""Turn the declared departments into LiteLLM teams and virtual keys.

Runs as an ArgoCD PostSync hook, so it has to be safe on every sync:

  * a team is created only if no team has that alias;
  * a key is minted only if the department has none recorded in Secrets Manager.

The second rule matters: LiteLLM stores key hashes, not keys, so a key we cannot
read back must not be re-created. Regenerating would silently invalidate
whatever consumers hold.

Standard library only - the image is plain python:alpine.
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE_URL = os.environ["LITELLM_BASE_URL"].rstrip("/")
MASTER_KEY = os.environ["LITELLM_MASTER_KEY"]
DEPARTMENTS = json.loads(os.environ["DEPARTMENTS_JSON"])

AWS_ENDPOINT = os.environ.get("AWS_ENDPOINT_URL", "")
AWS_REGION = os.environ.get("AWS_REGION", "eu-west-1")
SECRET_ID = os.environ.get("DEPARTMENT_KEYS_SECRET_ID", "")
PUBLISH = os.environ.get("PUBLISH_KEYS", "false").lower() == "true"

TIMEOUT = 30


def log(msg: str) -> None:
    print(f"[bootstrap] {msg}", flush=True)


def request(url: str, *, method: str = "GET", headers: dict | None = None,
            body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        raw = resp.read().decode()
    return json.loads(raw) if raw else {}


def litellm(path: str, *, method: str = "GET", body: dict | None = None) -> dict:
    return request(
        f"{BASE_URL}{path}",
        method=method,
        headers={"Authorization": f"Bearer {MASTER_KEY}"},
        body=body,
    )


# LocalStack does not verify SigV4, so a plausible Authorization header is
# enough and botocore stays out of the image. Only valid against the mock -
# real AWS would reject this outright.
def secretsmanager(target: str, payload: dict) -> dict:
    return request(
        AWS_ENDPOINT,
        method="POST",
        headers={
            "Content-Type": "application/x-amz-json-1.1",
            "X-Amz-Target": f"secretsmanager.{target}",
            "Authorization": (
                "AWS4-HMAC-SHA256 Credential=test/20240101/"
                f"{AWS_REGION}/secretsmanager/aws4_request, "
                "SignedHeaders=host;x-amz-target, Signature=mock"
            ),
        },
        body=payload,
    )


def wait_for_gateway(attempts: int = 60, delay: int = 5) -> None:
    for attempt in range(1, attempts + 1):
        try:
            request(f"{BASE_URL}/health/readiness")
            log(f"gateway ready after {attempt} attempt(s)")
            return
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
            log(f"gateway not ready ({exc}); retrying in {delay}s")
            time.sleep(delay)
    sys.exit("gateway never became ready")


def load_recorded_keys() -> dict:
    if not (PUBLISH and SECRET_ID and AWS_ENDPOINT):
        return {}
    try:
        current = secretsmanager("GetSecretValue", {"SecretId": SECRET_ID})
        recorded = json.loads(current.get("SecretString") or "{}")
        recorded.pop("_bootstrap", None)
        return recorded
    except Exception as exc:  # noqa: BLE001 - a missing secret is fine
        log(f"could not read {SECRET_ID}: {exc}")
        return {}


def existing_teams() -> dict:
    try:
        teams = litellm("/team/list")
    except Exception as exc:  # noqa: BLE001
        log(f"/team/list failed ({exc}); assuming no teams exist yet")
        return {}
    if isinstance(teams, dict):
        teams = teams.get("teams", [])
    return {
        team["team_alias"]: team["team_id"]
        for team in teams
        if team.get("team_alias")
    }


def main() -> int:
    wait_for_gateway()

    teams = existing_teams()
    recorded = load_recorded_keys()
    log(f"{len(teams)} team(s) present, {len(recorded)} key(s) already recorded")

    minted = dict(recorded)
    failures = []

    for dept in DEPARTMENTS:
        name = dept["name"]

        team_id = teams.get(name)
        if team_id:
            log(f"{name}: team already exists ({team_id})")
        else:
            try:
                created = litellm("/team/new", method="POST", body={
                    "team_alias": name,
                    "max_budget": dept.get("maxBudget"),
                    "budget_duration": dept.get("budgetDuration"),
                    "tpm_limit": dept.get("tpmLimit"),
                    "rpm_limit": dept.get("rpmLimit"),
                    "models": dept.get("models", []),
                    "metadata": {"managed_by": "nullnode-bootstrap"},
                })
                team_id = created["team_id"]
                log(f"{name}: team created ({team_id})")
            except Exception as exc:  # noqa: BLE001
                log(f"{name}: team creation FAILED: {exc}")
                failures.append(name)
                continue

        if name in recorded:
            log(f"{name}: key already recorded, leaving it alone")
            continue

        try:
            key = litellm("/key/generate", method="POST", body={
                "team_id": team_id,
                "key_alias": f"{name}-{int(time.time())}",
                "max_budget": dept.get("maxBudget"),
                "budget_duration": dept.get("budgetDuration"),
                "tpm_limit": dept.get("tpmLimit"),
                "rpm_limit": dept.get("rpmLimit"),
                "models": dept.get("models", []),
                "metadata": {"department": name, "managed_by": "nullnode-bootstrap"},
            })
            minted[name] = key["key"]
            log(f"{name}: virtual key minted")
        except Exception as exc:  # noqa: BLE001
            log(f"{name}: key generation FAILED: {exc}")
            failures.append(name)

    if PUBLISH and SECRET_ID and AWS_ENDPOINT and minted != recorded:
        try:
            secretsmanager("PutSecretValue", {
                "SecretId": SECRET_ID,
                "SecretString": json.dumps(minted, indent=2),
            })
            log(f"{len(minted)} key(s) stored in {SECRET_ID}")
        except Exception as exc:  # noqa: BLE001
            log(f"could not write {SECRET_ID}: {exc}")
            failures.append("secrets-manager")

    if failures:
        log(f"finished with failures: {', '.join(sorted(set(failures)))}")
        return 1

    log("all departments reconciled")
    return 0


if __name__ == "__main__":
    sys.exit(main())
