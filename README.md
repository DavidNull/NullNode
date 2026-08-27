# NullNode

Plataforma LLMOps completa, privada y local. Un clúster K3s de un nodo sobre tu
máquina, con las piezas que tendría un despliegue enterprise: gateway con claves
y presupuestos por departamento, caché de prompts, autoescalado del pool de
inferencia, observabilidad de GenAI y todo gestionado por GitOps.

Coste: 0 €. Todo corre en tu hardware y los servicios de AWS están mockeados.

```bash
make up          # perfil GPU (por defecto)
PROFILE=cpu make up
make status
make smoke
```

---

## Lo que hay que saber antes de arrancar

**1. Por defecto asume GPU NVIDIA.** Es lo que hace esto usable: un modelo de 3B
en GPU responde en un par de segundos, en CPU te vas a la decena larga.

Hacen falta cuatro cosas, y la tercera sorprende a todo el mundo:

1. Driver NVIDIA en el host. En WSL2, **en Windows**, no dentro de la distro.
2. `nvidia-container-toolkit` **dentro** de la distro WSL, y Docker reiniciado.
3. Una imagen de k3s con el runtime de NVIDIA. Los nodos de k3d son
   contenedores, y la imagen oficial no lo trae: `make k3s-cuda-image`, una vez.
4. El device plugin en el clúster. Este se instala solo con el perfil GPU.

El preflight de `make up` comprueba los tres primeros y dice cuál falta, en
lugar de fallar a mitad del despliegue.

**Sin GPU:** `PROFILE=cpu make up`. Funciona igual con un modelo de 1B, y todo
lo demás —gateway, caché, cuotas, dashboards, autoescalado— es idéntico. Solo
esperas más por cada respuesta.

**2. Con una sola GPU, escalar el pool a más réplicas no sirve.** El device
plugin asigna la tarjeta en exclusiva a un pod, así que la segunda réplica se
queda `Pending`. La concurrencia se consigue con `OLLAMA_NUM_PARALLEL`, no con
réplicas. En perfil CPU sí escala horizontalmente. Ver
[ADR-0004](docs/adr/0004-scaling-signal.md).

**3. La plataforma se reconcilia desde git, no desde tu copia local.** Editar un
fichero no hace nada hasta que lo pusheas a la revisión que ArgoCD sigue. Para
iterar sobre una rama:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=mi-rama
```

**4. El primer arranque tarda 10-20 minutos.** Se descargan la pila de
observabilidad y los pesos de los modelos. Cortar con `^C` es seguro: ArgoCD
sigue reconciliando por dentro.

**5. No hay UI de chat dentro de la plataforma.** Lo que sale de `make up` es un
endpoint compatible con OpenAI. El camino previsto es un dev conectando VS Code
con Continue o Cline: [docs/uso/CONECTAR.md](docs/uso/CONECTAR.md).

**6. Nada de esto se ha ejecutado todavía.** Las versiones de los charts de
terceros están pinneadas sin acceso a red: pasa `make versions-check` antes del
primer despliegue. Y los nombres de las métricas de LiteLLM dependen de la
versión pinneada, lo que afecta a dashboards, alertas y al trigger de KEDA
([ADR-0006](docs/adr/0006-metrics-sources.md)).

---

## Arquitectura

```
                       ┌──────────────────────────────────────────┐
   tú ──── :8080 ─────▶│ Traefik (Ingress, incluido en k3s)       │
                       └───┬───────────┬───────────┬──────────────┘
                           │           │           │
              gateway.*    │  grafana.*│ argocd.*  │ prometheus.*
                           ▼           ▼           ▼
   ┌───────────────────────────────┐  ┌──────────────────────────────┐
   │  LiteLLM  (AI Gateway)        │  │  Observabilidad              │
   │  · claves virtuales           │  │  · Prometheus + Grafana      │
   │  · presupuesto/TPM por equipo │─▶│  · OTel Collector            │
   │  · caché de prompts           │  │  · DCGM (VRAM, perfil GPU)   │
   │  · guardrail PII (Presidio)   │  │  · 3 dashboards GenAI        │
   │  · auditoría a S3             │  └──────────────────────────────┘
   └───┬───────────┬───────────┬───┘                  ▲
       │           │           │                      │ métrica de rps
       ▼           ▼           ▼                      │
   ┌────────┐  ┌────────┐  ┌──────────────┐    ┌──────┴──────┐
   │ Redis  │  │Postgres│  │   Ollama     │◀───│    KEDA     │
   │ caché  │  │ claves │  │ StatefulSet  │    │ autoescalado│
   │ +router│  │ cuotas │  │ + PVC modelos│    └─────────────┘
   └────────┘  └────────┘  └──────────────┘

   ─────────────────────── fuera del clúster ───────────────────────
   ┌──────────────────────────────────────────────────────────────┐
   │  LocalStack  ·  S3 (auditoría/prompts)  ·  Secrets Manager   │
   │  Contenedor en el host, no un pod. Ver ADR-0002.             │
   └──────────────────────────────────────────────────────────────┘
```

Una petición: entra por Traefik → LiteLLM valida la clave del departamento y su
presupuesto → consulta la caché en Redis → si es miss, enruta a Ollama →
registra gasto en Postgres, traza en el collector, métrica en Prometheus y la
petición completa en S3.

| Capa | Componente | Qué hace |
| --- | --- | --- |
| Gateway | LiteLLM | Endpoint compatible con OpenAI. Claves virtuales por departamento con presupuesto, TPM y RPM. Caché, guardrail de PII, auditoría. |
| Caché | Redis | Caché de prompts y estado compartido del router. |
| Gobierno | PostgreSQL | Equipos, claves y presupuestos. Sobreviven a un reinicio y se cambian por API. |
| Inferencia | Ollama | StatefulSet con caché de modelos por réplica y precarga de pesos. |
| Escalado | KEDA | Escala según peticiones por segundo, no según CPU. |
| Observabilidad | Prometheus, Grafana, OTel, DCGM | TTFT, tokens/s, hit rate, gasto por equipo, VRAM. |
| Guardrails | Presidio | Detección y enmascarado de PII. Opcional. |
| Cloud mock | LocalStack | S3 y Secrets Manager. De aquí salen los secretos. |
| GitOps | ArgoCD | App-of-apps con sync waves, un solo Application raíz. |
| IaC | Terraform, k3d | Dos stacks: cloud mockeado y bootstrap de la plataforma. |

## Requisitos

Docker, k3d ≥ 5.6, kubectl, Helm ≥ 3.14, Terraform ≥ 1.6. El preflight de
`make up` los comprueba y enlaza la instalación de lo que falte.

También `make`, que en una WSL2 recién instalada no viene:
`sudo apt install make`. Si prefieres no instalarlo, todos los targets son
envoltorios finos sobre `scripts/`:

| `make` | equivalente |
| --- | --- |
| `make up` | `./scripts/up.sh` |
| `make down` | `./scripts/down.sh` |
| `make status` | `./scripts/status.sh` |
| `make smoke` | `./scripts/smoke.sh` |
| `make validate` | `./scripts/validate.sh` |
| `make security` | `./scripts/security.sh` |
| `PROFILE=cpu make up` | `PROFILE=cpu ./scripts/up.sh` |

16 GiB de RAM y ~60 GiB de disco en perfil GPU; 8 GiB de RAM en CPU.

## Arranque

```bash
git clone https://github.com/DavidNull/NullNode.git
cd NullNode

make k3s-cuda-image     # solo perfil GPU, solo la primera vez
make up
make hosts              # imprime la línea para /etc/hosts
```

| Endpoint | |
| --- | --- |
| Gateway | `http://gateway.nullnode.localhost:8080` |
| Grafana | `http://grafana.nullnode.localhost:8080` |
| Prometheus | `http://prometheus.nullnode.localhost:8080` |
| ArgoCD | `http://argocd.nullnode.localhost:8080` |
| LocalStack | `http://127.0.0.1:4566` |

Un solo puerto, enrutado por host ([ADR-0003](docs/adr/0003-single-entrypoint.md)).

## Cómo hablar con la plataforma

Lo que `make up` te deja es **un endpoint HTTP compatible con OpenAI**. No hay
UI de chat dentro: eso lo pone el cliente que enchufes. El caso principal es un
dev que conecta VS Code y trabaja contra la plataforma en lugar de contra un
Ollama suelto.

Los tres datos, siempre los mismos:

| | |
| --- | --- |
| Base URL | `http://gateway.nullnode.localhost:8080/v1` |
| API key | tu clave de departamento (`make department-keys`) |
| Modelo | `llama3.2` · `qwen2.5-coder` (perfil GPU) |

### VS Code en tres pasos

1. Instala [Continue](https://marketplace.visualstudio.com/items?itemName=Continue.continue)
   **en la extensión de WSL**, no en el Windows local.
2. `make department-keys` y copia la clave de tu departamento.
3. Paleta → *Continue: Open config.json*:

```json
{
  "models": [{
    "title": "NullNode qwen2.5-coder",
    "provider": "openai",
    "model": "qwen2.5-coder",
    "apiBase": "http://gateway.nullnode.localhost:8080/v1",
    "apiKey": "sk-TU-CLAVE-DE-DEPARTAMENTO"
  }]
}
```

Copilot no sirve: su endpoint no es configurable. Cline funciona igual, con
`API Provider: OpenAI Compatible`.

Todo lo que pase por ahí queda con presupuesto, rate limit, caché, traza,
métrica y auditoría en S3. Ese es el punto del ejercicio.

### Lo demás

```bash
# comprobar la cadena
curl http://gateway.nullnode.localhost:8080/v1/chat/completions \
  -H "Authorization: Bearer $(make -s key)" \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2","messages":[{"role":"user","content":"Hola"}]}'
```

Lánzalo dos veces y mira la latencia: la segunda sale de Redis.

Chat con interfaz (Open WebUI), SDKs, endpoints de administración, y la tabla de
qué nombre resuelve desde dónde —navegador de Windows, extensión en WSL, `curl`
en la distro, otro contenedor— en
**[docs/uso/CONECTAR.md](docs/uso/CONECTAR.md)**.

Resumen de esa tabla, que es lo que más confunde: desde un **navegador de
Windows** funciona sin tocar nada, porque Chromium resuelve `*.localhost` solo y
WSL2 reenvía `localhost`. Desde **dentro de la distro** (curl, Python, las
extensiones de VS Code) hace falta `make hosts`, porque glibc no trata
`.localhost` como especial. Desde **otro contenedor**, `--add-host`.

## Comandos

```
make up                  Levanta la plataforma
make down                La tira, conservando los modelos descargados
make purge               La tira todo, modelos incluidos
make status              Endpoints, credenciales y lo que no esté sano
make smoke               Test end-to-end: ingress → auth → modelo → caché → S3
make validate            Todo lo verificable sin clúster (lo mismo que CI)
make security            Trivy, Checkov, kube-linter, gitleaks
make fmt-check           terraform fmt, shfmt, actionlint, hadolint, markdownlint
make check               validate + security: lo que tiene que pasar un PR
make load-test           Perfil de carga con k6
make logs                Logs del gateway
make key                 Master key del gateway
make department-keys     Claves virtuales por departamento
make versions-check      Comprueba que las versiones pinneadas existen
make help                Todo lo anterior con descripciones
```

`scripts/up.sh` acepta `--only <fase>` y `--from <fase>` para retomar un arranque
a medias sin repetir lo que ya funcionó.

Antes de pushear: `make check`. Los scripts saltan las herramientas que no
tengas instaladas con un aviso, así que un escaneo parcial en local no bloquea;
en CI están todas.

## Calidad y seguridad

Tres pipelines, y las tres se pueden correr en local con la misma
configuración:

| Workflow | `make` | Qué hace |
| --- | --- | --- |
| `ci.yaml` | `make validate` | Helm lint y render en ambos perfiles, kubeconform, Terraform validate, shellcheck, yamllint, y un job de integración que levanta el perfil CPU y pasa el smoke test |
| `security.yaml` | `make security` | Trivy sobre Terraform y Dockerfile, Trivy y kube-linter sobre los manifiestos **renderizados**, Checkov, gitleaks (árbol e historia), y CVEs de imágenes como informativo |
| `format.yaml` | `make fmt-check` | `terraform fmt`, shfmt, actionlint, hadolint, markdownlint |

`make check` corre validación y seguridad juntas: es lo que tiene que pasar un
PR.

Dos detalles que no son obvios:

- **Se escanean los manifiestos renderizados, no las plantillas.** Las
  propiedades que importan —`securityContext`, límites de recursos, tags de
  imagen, montajes del host— solo existen después de templar. Escanear
  `templates/` no ve ninguna.
- **tfsec ya no se desarrolla por separado:** Aqua lo integró en Trivy, y
  `trivy config` corre el mismo conjunto de reglas. Está disponible como opt-in
  (`WITH_TFSEC=true make security`) para quien tenga el pipeline estandarizado
  sobre él, pero por defecto no se ejecuta para no duplicar hallazgos.

Los hallazgos aceptados están en [`.trivyignore`](.trivyignore) y
[`.checkov.yaml`](.checkov.yaml), cada uno con su motivo. Casi todos son
controles que no significan nada contra un mock: KMS, replicación
cross-region, access logging de un bucket falso.

## Estructura

```
NullNode/
├── Makefile                     Interfaz del operador
├── infra/
│   ├── k3d/                     Config declarativo del clúster (perfiles gpu/cpu)
│   │   └── cuda/                Imagen de k3s con runtime NVIDIA
│   └── terraform/
│       ├── cloud-mock/          LocalStack + S3 + Secrets Manager
│       └── platform-bootstrap/  Namespaces, secretos, ArgoCD, Application raíz
├── k8s/
│   ├── bootstrap/root/          AppProject + Application raíz (el único apply imperativo)
│   ├── platform/                App-of-apps: cada template es una Application
│   │   └── values/              Values de los charts de terceros
│   └── charts/                  Charts propios: litellm, ollama, redis, postgres,
│                                presidio, nullnode-observability
├── scripts/                     up, down, status, smoke, validate, security, versions-check
├── tests/load/                  Perfil de carga k6
└── docs/                        Ver abajo
```

## Documentación

`docs/` está commiteado a propósito. Es el estado del proyecto por escrito: lo
que hay que leer —persona o agente— para retomar el trabajo sin reconstruir el
razonamiento desde el código.

```
docs/
├── context/     Contexto del proyecto: qué es, qué falta, qué se hizo
│   ├── CONTEXT.md               Qué es la plataforma y por qué está montada así
│   ├── GOTO.md                  Qué falta, en orden
│   ├── AVANCES.md               Qué se hizo y cuándo
│   └── AUDITORIA-PLANTILLA.md   Qué estaba roto en la versión inicial
├── uso/         Para el dev que consume la plataforma
│   └── CONECTAR.md              VS Code, Open WebUI, SDKs, resolución de nombres
├── ops/         Para quien la opera
│   ├── RUNBOOK.md               Diagnóstico por síntoma y por alerta
│   └── VERSIONS.md              Versiones pinneadas y cómo actualizarlas
└── adr/         Una ADR por decisión que no se entiende leyendo el código
```

Convención al cerrar un bloque de trabajo: actualizar `AVANCES.md` y `GOTO.md`.
Si la decisión cambia la arquitectura, además una ADR. Los comentarios del
código referencian las ADRs por ruta, así que renombrar un fichero de `adr/`
implica actualizar esas referencias.

Punto de entrada según lo que busques:

- Quiero usarla desde el IDE → [docs/uso/CONECTAR.md](docs/uso/CONECTAR.md)
- Algo falla → [docs/ops/RUNBOOK.md](docs/ops/RUNBOOK.md)
- Por qué está hecho así → [docs/adr/](docs/adr/)
- Qué es esto → [docs/context/CONTEXT.md](docs/context/CONTEXT.md)
- Qué viene después → [docs/context/GOTO.md](docs/context/GOTO.md)

Los comentarios del código están en inglés; la documentación, en castellano.

## Licencia

Sin definir.
