# Conectar un cliente a la plataforma

NullNode expone **un endpoint HTTP compatible con la API de OpenAI**. No trae
interfaz de chat, a propósito: un cliente no es infraestructura. Lo que trae es
todo lo que rodea a la llamada —autenticación, presupuesto, rate limit, caché,
trazas, auditoría— y eso funciona con cualquier cliente que sepa hablar OpenAI.

Este documento es para el dev que llega, no para quien opera la plataforma. Si
algo no responde, [RUNBOOK.md](../ops/RUNBOOK.md).

Los tres datos que necesitas siempre:

| | |
| --- | --- |
| **Base URL** | `http://gateway.nullnode.localhost:8080/v1` |
| **API key** | tu clave de departamento (abajo) |
| **Modelo** | `llama3.2` · `qwen2.5-coder` (solo perfil GPU) |

## Consigue tu clave

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

Usa la de tu departamento, **no** la master key (`make key`). Dos razones:

- Tu consumo aparece en el dashboard de FinOps con su `team_alias`. Con la
  master key el gasto sale sin atribuir.
- La clave de departamento lleva presupuesto y límites de RPM/TPM. La master key
  no tiene techo, que es justo lo que no quieres repartir.

Para dejarla en el entorno:

```bash
export NULLNODE_API_KEY="$(make -s department-keys \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["engineering"])')"
```

---

## VS Code

VS Code no habla con endpoints personalizados por sí solo: necesita una
extensión que acepte un proveedor compatible con OpenAI. Dos opciones, ambas
funcionan igual de bien contra NullNode.

> GitHub Copilot **no** sirve para esto: su endpoint no es configurable.

### Continue

[Continue](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
es la más directa: autocompletado y chat en el panel lateral.

1. Instala la extensión desde el marketplace.
2. Abre la paleta (`Ctrl+Shift+P`) → **Continue: Open config.json**.
3. Añade el proveedor:

```json
{
  "models": [
    {
      "title": "NullNode qwen2.5-coder",
      "provider": "openai",
      "model": "qwen2.5-coder",
      "apiBase": "http://gateway.nullnode.localhost:8080/v1",
      "apiKey": "sk-TU-CLAVE-DE-DEPARTAMENTO"
    },
    {
      "title": "NullNode llama3.2",
      "provider": "openai",
      "model": "llama3.2",
      "apiBase": "http://gateway.nullnode.localhost:8080/v1",
      "apiKey": "sk-TU-CLAVE-DE-DEPARTAMENTO"
    }
  ],
  "tabAutocompleteModel": {
    "title": "NullNode autocomplete",
    "provider": "openai",
    "model": "qwen2.5-coder",
    "apiBase": "http://gateway.nullnode.localhost:8080/v1",
    "apiKey": "sk-TU-CLAVE-DE-DEPARTAMENTO"
  }
}
```

El autocompletado dispara muchas peticiones cortas. Ahí es donde vas a ver la
caché de prompts trabajando y, si te pasas, el rate limit de tu departamento
devolviendo 429. Ambas cosas son el diseño funcionando.

### Cline

[Cline](https://marketplace.visualstudio.com/items?itemName=saoudrizwan.claude-dev)
es un agente: lee y edita ficheros, ejecuta comandos.

En los ajustes de la extensión:

- **API Provider**: `OpenAI Compatible`
- **Base URL**: `http://gateway.nullnode.localhost:8080/v1`
- **API Key**: tu clave de departamento
- **Model ID**: `qwen2.5-coder`

Un aviso honesto: un agente que edita ficheros necesita seguir instrucciones
complejas y usar herramientas. Un modelo de 7B cuantizado en local va a fallar
en tareas donde un modelo hosted no falla. Para el propósito de este lab —ver
gobierno, caché y observabilidad sobre tráfico de agente real— sirve
perfectamente; para trabajo de verdad, notarás la diferencia.

### ¿Dónde va la extensión si estás en WSL2?

Instálala en la extensión de **WSL**, no en el Windows local. En VS Code,
abajo a la izquierda debe decir `WSL: <tu-distro>`. Si la extensión corre en
Windows y el clúster en WSL, la resolución del nombre del gateway se complica
sin necesidad.

---

## Open WebUI, si quieres un chat de verdad

No es parte de la plataforma. Un contenedor y listo:

```bash
docker run -d --name nullnode-chat -p 3001:8080 \
  --add-host gateway.nullnode.localhost:host-gateway \
  -e OPENAI_API_BASE_URL=http://gateway.nullnode.localhost:8080/v1 \
  -e OPENAI_API_KEY="$NULLNODE_API_KEY" \
  ghcr.io/open-webui/open-webui:main
```

Abre `http://localhost:3001`.

El `--add-host gateway.nullnode.localhost:host-gateway` no es opcional: desde
dentro de otro contenedor ese nombre no resuelve, y sin él Open WebUI arranca
pero no encuentra ningún modelo.

Meterlo dentro del clúster, con Ingress y la clave inyectada desde el Secret,
está en [GOTO.md](../context/GOTO.md) como componente opcional.

---

## curl y SDKs

Cualquier SDK de OpenAI apuntando al gateway:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://gateway.nullnode.localhost:8080/v1",
    api_key="sk-TU-CLAVE-DE-DEPARTAMENTO",
)

response = client.chat.completions.create(
    model="llama3.2",
    messages=[{"role": "user", "content": "Hola"}],
)
print(response.choices[0].message.content)
```

```bash
curl http://gateway.nullnode.localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer $NULLNODE_API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"Hola"}]}'
```

Endpoints útiles más allá de los de inferencia:

| Endpoint | Para qué |
| --- | --- |
| `GET /v1/models` | Qué modelos puede usar tu clave |
| `GET /key/info` | Presupuesto, gasto y límites de tu clave |
| `GET /health/readiness` | Si el gateway está listo (sin autenticación) |
| `GET /metrics` | Métricas Prometheus (sin autenticación) |

```bash
curl -s http://gateway.nullnode.localhost:8080/key/info \
  -H "Authorization: Bearer $NULLNODE_API_KEY" | python3 -m json.tool
```

---

## Resolución de nombres: qué funciona desde dónde

Esta es la parte que confunde, porque hay tres sitios distintos desde los que
se puede llamar al gateway y cada uno resuelve los nombres de forma diferente.

| Desde | ¿Resuelve `gateway.nullnode.localhost`? | Qué hacer |
| --- | --- | --- |
| Navegador en Windows | Sí | Nada. Chromium y Firefox resuelven `*.localhost` a 127.0.0.1 por su cuenta, y WSL2 reenvía `localhost` de Windows a la distro. `http://grafana.nullnode.localhost:8080` abre directamente. |
| Extensión de VS Code en WSL | Sí, si añades `/etc/hosts` | `make hosts` imprime la línea. Ver abajo. |
| `curl` dentro de la distro WSL | No por defecto | `make hosts`, o `curl --resolve` |
| Otro contenedor Docker | No | `--add-host gateway.nullnode.localhost:host-gateway` |

El motivo del asterisco: los navegadores tratan `.localhost` como especial y lo
resuelven internamente. **glibc no**, así que `curl`, Python, Node y las
extensiones que corren dentro de la distro necesitan la entrada en `/etc/hosts`.

```bash
make hosts
# imprime:
# 127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost prometheus.nullnode.localhost argocd.nullnode.localhost

sudo sh -c 'make -s hosts >> /etc/hosts'
```

Sin tocar `/etc/hosts`, para una prueba puntual:

```bash
curl --resolve gateway.nullnode.localhost:8080:127.0.0.1 \
  http://gateway.nullnode.localhost:8080/health/liveliness
```

Si prefieres no editar `/etc/hosts` nunca, cambia `global.hostSuffix` en
`k8s/platform/values.yaml` a `127.0.0.1.nip.io`, que resuelve por DNS público.
No es el valor por defecto porque en redes corporativas suele estar bloqueado
([ADR-0003](../adr/0003-single-entrypoint.md)).

---

## Cuando algo no va

**`connection refused` o el nombre no resuelve.** Antes de nada, comprueba que
la plataforma está arriba: `make status`. Si lo está, es resolución de nombres:
mira la tabla de arriba según desde dónde estés llamando.

**`401 Unauthorized`.** La clave no existe o se regeneró. `make department-keys`
otra vez. Si LocalStack se reinició, Terraform generó credenciales nuevas y las
antiguas dejaron de valer ([ADR-0005](../adr/0005-secrets-flow.md)).

**`429 Too Many Requests`.** Tu departamento agotó presupuesto o pasó su límite
de RPM/TPM. No es un fallo, es la plataforma haciendo su trabajo. Mira cuánto te
queda con `/key/info`, y si necesitas más, la sección de presupuestos del
[RUNBOOK](../ops/RUNBOOK.md#nullnodeteambudgetnearlyexhausted).

**`404` sobre el modelo.** El nombre del modelo tiene que estar en el catálogo
del gateway, que depende del perfil: `qwen2.5-coder` solo existe en GPU.
`GET /v1/models` te dice qué hay.

**La primera respuesta tarda un minuto y las siguientes van bien.** Cold start:
el modelo se estaba cargando en VRAM. Si pasa siempre, sube
`OLLAMA_KEEP_ALIVE`.

**Va lento sin más.** Mira el perfil. En CPU con un modelo de 1B, decenas de
segundos por respuesta es lo esperado, no una avería.
