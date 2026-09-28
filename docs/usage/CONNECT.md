# Connecting a client to the platform

NullNode exposes **one HTTP endpoint compatible with the OpenAI API**. It doesn't
bring a chat interface on purpose: a client isn't infrastructure. What it brings
is everything around the call —authentication, budget, rate limit, cache,
traces, audit— and that works with any client that knows how to speak OpenAI.

This document is for the dev who arrives, not for whoever operates the platform.
If something doesn't respond, [RUNBOOK.md](../ops/RUNBOOK.md).

The three things you always need:

| | |
| --- | --- |
| **Base URL** | `http://gateway.nullnode.localhost:8080/v1` |
| **API key** | your department key (below) |
| **Model** | `llama3.2` · `qwen2.5-coder` (GPU profile only) |

## Get your key

```bash
make department-keys
```

```json
{
  "engineering": "sk-...",
  "data-science": "sk-...",
  "support": "sk-..."
}
```

Use your department's key, **not** the master key (`make key`). Two reasons:

- Your consumption appears in the FinOps dashboard with its `team_alias`. With the
  master key the spend shows up unattributed.
- The department key has budget and RPM/TPM limits. The master key has no ceiling,
  which is exactly what you don't want to distribute.

To set it in your environment:

```bash
export NULLNODE_API_KEY="$(make -s department-keys \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["engineering"])')"
```

---

## VS Code

VS Code doesn't talk to custom endpoints by itself: it needs an extension that
accepts an OpenAI-compatible provider. Two options, both work equally well against
NullNode.

> GitHub Copilot **doesn't** work for this: its endpoint isn't configurable.

### Continue

[Continue](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
is the most direct: autocomplete and chat in the side panel.

1. Install the extension from the marketplace.
2. Open the palette (`Ctrl+Shift+P`) → **Continue: Open config.json**.
3. Add the provider:

```json
{
  "models": [
    {
      "title": "NullNode qwen2.5-coder",
      "provider": "openai",
      "model": "qwen2.5-coder",
      "apiBase": "http://gateway.nullnode.localhost:8080/v1",
      "apiKey": "sk-YOUR-DEPARTMENT-KEY"
    },
    {
      "title": "NullNode llama3.2",
      "provider": "openai",
      "model": "llama3.2",
      "apiBase": "http://gateway.nullnode.localhost:8080/v1",
      "apiKey": "sk-YOUR-DEPARTMENT-KEY"
    }
  ],
  "tabAutocompleteModel": {
    "title": "NullNode autocomplete",
    "provider": "openai",
    "model": "qwen2.5-coder",
    "apiBase": "http://gateway.nullnode.localhost:8080/v1",
    "apiKey": "sk-YOUR-DEPARTMENT-KEY"
  }
}
```

Autocomplete fires many short requests. That's where you'll see the prompt cache
working and, if you overdo it, your department's rate limit returning 429. Both
are the design working.

### Cline

[Cline](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev)
is an agent: reads and edits files, runs commands.

In the extension settings:

- **API Provider**: `OpenAI Compatible`
- **Base URL**: `http://gateway.nullnode.localhost:8080/v1`
- **API Key**: your department key
- **Model ID**: `qwen2.5-coder`

An honest warning: an agent that edits files needs to follow complex instructions
and use tools. A locally quantized 7B model will fail at tasks where a hosted
model wouldn't. For the purpose of this lab —seeing governance, cache and
observability over real agent traffic— it works perfectly; for real work, you'll
notice the difference.

### Where does the extension go if you're on WSL2?

Install it in the **WSL** extension, not the local Windows one. In VS Code, bottom
left should say `WSL: <your-distro>`. If the extension runs on Windows and the
cluster on WSL, gateway name resolution gets complicated unnecessarily.

---

## Open WebUI, if you want a real chat

Open WebUI is available as an optional app-of-apps component. To enable it:

```bash
# In k8s/platform/values.yaml (or values-gpu.yaml / values-cpu.yaml)
components:
  openWebui:
    enabled: true
    wave: "25"
    values:
      defaultDepartment: engineering
```

After applying the change with GitOps, the chat will be available at:
`http://chat.nullnode.localhost`

### Integrated version features

- **Automatic Ingress:** No need to configure ports manually
- **Injected key:** Uses LiteLLM's master key from the Secret, no environment variables
- **Sync wave:** Deploys after the gateway (wave 25 vs 20) guaranteeing availability
- **GitOps:** Everything managed from git, like the rest of the platform
- **Security:** NetworkPolicy configured, PodDisruptionBudget for HA
- **Monitoring:** ServiceMonitor integrated with Prometheus
- **Dependencies:** Init container waits for gateway to be available

### Advanced configuration

```yaml
components:
  openWebui:
    enabled: true
    values:
      defaultDepartment: engineering
      resources:
        requests:
          cpu: 200m
          memory: 512Mi
        limits:
          memory: 1Gi
      networkPolicy:
        enabled: true  # false by default
```

### Manual version (docker run)

If you prefer not to integrate it in the cluster, you can keep using the external
container:

```bash
docker run -d --name nullnode-chat -p 3001:8080 \
  --add-host gateway.nullnode.localhost:host-gateway \
  -e OPENAI_API_BASE_URL=http://gateway.nullnode.localhost:8080/v1 \
  -e OPENAI_API_KEY="$NULLNODE_API_KEY" \
  ghcr.io/open-webui/open-webui:main
```

The `--add-host gateway.nullnode.localhost:host-gateway` isn't optional: from
inside another container that name doesn't resolve, and without it Open WebUI
starts but finds no model.

---

## curl and SDKs

Any OpenAI SDK pointing to the gateway:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://gateway.nullnode.localhost:8080/v1",
    api_key="sk-YOUR-DEPARTMENT-KEY",
)

response = client.chat.completions.create(
    model="llama3.2",
    messages=[{"role": "user", "content": "Hello"}],
)
print(response.choices[0].message.content)
```

```bash
curl http://gateway.nullnode.localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer $NULLNODE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"Hello"}]}'
```

Useful endpoints beyond inference:

| Endpoint | For what |
| --- | --- |
| `GET /v1/models` | What models your key can use |
| `GET /key/info` | Your key's budget, spend and limits |
| `GET /health/readiness` | If the gateway is ready (no auth) |
| `GET /metrics` | Prometheus metrics (no auth) |

```bash
curl -s http://gateway.nullnode.localhost:8080/key/info \
  -H "Authorization: Bearer $NULLNODE_API_KEY" | python3 -m json.tool
```

---

## Name resolution: what works from where

This is the confusing part, because there are three different places you can call
the gateway from and each resolves names differently.

| From | Does `gateway.nullnode.localhost` resolve? | What to do |
| --- | --- | --- |
| Browser on Windows | Yes | Nothing. Chromium and Firefox resolve `*.localhost` to 127.0.0.1 on their own, and WSL2 forwards Windows `localhost` to the distro. `http://grafana.nullnode.localhost:8080` opens directly. |
| VS Code extension in WSL | Yes, if you add `/etc/hosts` | `make hosts` prints the line. See below. |
| `curl` inside WSL distro | No by default | `make hosts`, or `curl --resolve` |
| Another Docker container | No | `--add-host gateway.nullnode.localhost:host-gateway` |

The reason for the asterisk: browsers treat `.localhost` as special and resolve it
internally. **glibc doesn't**, so `curl`, Python, Node and extensions running
inside the distro need the entry in `/etc/hosts`.

```bash
make hosts
# prints:
# 127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost prometheus.nullnode.localhost argocd.nullnode.localhost

sudo sh -c 'make -s hosts >> /etc/hosts'
```

Without touching `/etc/hosts`, for a one-off test:

```bash
curl --resolve gateway.nullnode.localhost:8080:127.0.0.1 \
  http://gateway.nullnode.localhost:8080/health/liveliness
```

If you prefer never editing `/etc/hosts`, change `global.hostSuffix` in
`k8s/platform/values.yaml` to `127.0.0.1.nip.io`, which resolves via public DNS.
It's not the default because it's usually blocked in corporate networks
([ADR-0003](../adr/0003-single-entrypoint.md)).

---

## When something doesn't work

**`connection refused` or name doesn't resolve.** First, check the platform is
up: `make status`. If it is, it's name resolution: look at the table above
depending on where you're calling from.

**`401 Unauthorized`.** The key doesn't exist or was regenerated. `make
department-keys` again. If LocalStack restarted, Terraform generated new
credentials and the old ones stopped working
([ADR-0005](../adr/0005-secrets-flow.md)).

**`429 Too Many Requests`.** Your department exhausted budget or exceeded its
RPM/TPM limit. It's not a failure, it's the platform doing its job. Check how
much you have left with `/key/info`, and if you need more, the budget section in
the [RUNBOOK](../ops/RUNBOOK.md#nullnodeteambudgetnearlyexhausted).

**`404` on the model.** The model name has to be in the gateway's catalog, which
depends on the profile: `qwen2.5-coder` only exists on GPU. `GET /v1/models` tells
you what's there.

**First response takes a minute and the rest are fine.** Cold start: the model
was loading into VRAM. If it always happens, raise `OLLAMA_KEEP_ALIVE`.

**It's just slow.** Check the profile. On CPU with a 1B model, tens of seconds
per response is expected, not a malfunction.
