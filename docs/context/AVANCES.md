# Registro de avances

## [2026-09-03] — Corrección de fallos en el pipeline de integración CI

### Síntomas observados

- La pipeline de integración (`CI / CPU-profile integration`) se quedaba esperando
  infinitamente en el paso de PostgreSQL hasta agotar el timeout de 60 min del job.
- `nullnode-root` mostraba estado `Unknown` (o sin sincronizar) en ArgoCD.
- El trigger `push → main` estaba desactivado temporalmente como workaround.

### Causa raíz identificada

**Bug crítico en `scripts/up.sh` (`phase_verify`):** el bucle de 60 intentos que
espera a que `nullnode-root` pase a `Synced` terminaba llamando a `err "..."` en
lugar de `die "..."`. La función `err` solo imprime un mensaje; `die` aborta el
script. Al no abortar, el script continuaba a la siguiente fase: `wait_for
"application/postgres to exist" 300 10`, que espera 300 × 10 s = 50 minutos si el
Application de ArgoCD no existe (situación exacta cuando `nullnode-root` no sincronizó).
Con el timeout del CI a 60 min, el job explotaba siempre durante esa espera.

El estado `Unknown` de `nullnode-root` era consecuencia del primer sync en cluster
frío (imágenes que no están en caché, primer `git clone` de ArgoCD repo-server):
con 60 intentos × 10 s = 10 min de margen, un arranque lento superaba el umbral.

### Problemas encontrados y corregidos

| # | Archivo | Problema | Fix |
|---|---------|----------|-----|
| 1 | `k8s/bootstrap/root/templates/project.yaml` | **Causa raíz.** El AppProject `nullnode` no listaba `argocd` en `destinations`. `nullnode-root` despliega los child Application CRDs al namespace `argocd`. ArgoCD valida el destino contra el AppProject antes de sincronizar → rechaza el sync → `nullnode-root` queda en estado `Unknown` con error `destination {... argocd} is not permitted in project nullnode` → los child apps nunca se crean | Añadir `namespace: argocd` a `destinations` usando `{{ .Values.argocd.namespace }}` para que no quede hardcodeado |
| 2 | `scripts/up.sh:213` | `err` en lugar de `die` al agotar el timeout — el script **no abortaba** y continuaba a la espera de 50 min de PostgreSQL (síntoma visible del fallo) | Reestructurar con flag `synced` + `die` al final si no sincronizó |
| 3 | `scripts/up.sh:200` | Timeout de sync demasiado corto: 60 × 10 s = 10 min. Margen insuficiente para el primer arranque (ArgoCD startup + primer git clone) | Aumentado a 90 × 10 s = **15 min** |
| 4 | `scripts/up.sh:220` | `wait_for "application/postgres to exist" 300 10` = **50 min por app** — causaba el "espera infinita" visible | Reducido a 60 × 10 s = **10 min** |
| 5 | `scripts/security.sh:138` | Versión de LocalStack hardcodeada: `3.8.1`. El despliegue usa `4.4.0`. El pin 3.8.1 cuelga `terraform apply` a los 3 min (provider AWS `~> 5.70` espera estabilidad S3 que 3.x nunca reporta) | Actualizado a `4.4.0` |
| 6 | `.github/workflows/ci.yaml` | Trigger `push → main` desactivado como workaround | Re-activado |

### Reestructuración del CI: core ligero vs. full manual

El job `integration` levantaba la plataforma **completa** (ollama pide 2 CPU, más el
stack de observabilidad): ~4 CPU de `requests`, demasiado para un runner estándar
de GitHub. Se separó en dos:

- **`core-integration`** (corre en `push`/`pull_request`): despliega solo
  cluster + LocalStack + ArgoCD + PostgreSQL + Redis mediante el nuevo flag
  `CORE_ONLY=true`. Valida toda la maquinaria GitOps —incluido el fix del sync de
  `nullnode-root`— con <1 CPU. Cabe en cualquier runner.
- **`integration`** (full e2e con ollama + gateway + smoke test): pasa a
  `if: github.event_name == 'workflow_dispatch'`, es decir, **manual** desde el
  botón "Run workflow". Ideal para lanzarlo en un runner self-hosted con GPU.

El flag `CORE_ONLY` se propaga: env del CI → `scripts/up.sh` →
`-var core_only` (Terraform) → valor `platform.coreOnly` del chart bootstrap →
parámetros Helm de ArgoCD sobre `nullnode-root` que desactivan
`keda`, `observabilityStack`, `otelCollector`, `ollama`, `litellm`, `presidio`,
`observability` y `global.monitoring` (esto último elimina los ServiceMonitor, que
si no dependerían de los CRDs del operador de Prometheus). Compatible con GitOps:
no se toca ningún values del repo, se sobreescribe en el Application.

### Problemas pendientes / deuda técnica identificada

- **Fijación de versiones inconsistente:** `security.sh` hardcodeaba la imagen de
  LocalStack independientemente del pin en Terraform. Si se actualiza un pin, hay
  que actualizar el scan a mano. Mejora futura: leer la versión desde el variable
  de Terraform.
- **Sin verificación real de fin de primer arranque:** el `wait_for` de ArgoCD
  comprueba que el objeto `Application` existe, pero no espera a que el repo-server
  haya completado el primer clone. En clusters muy lentos (redes restrictivas,
  GitHub throttling) podría seguir fallando. Mejora futura: sondear
  `status.reconciledAt` o `status.conditions`.
- **Diagrama de timeouts:** los valores de `wait_for` en `phase_verify` no están
  documentados. Añadir una tabla en el RUNBOOK con los plazos y por qué se
  eligieron.

---

## [2026-08-26] — Auditoría y reconstrucción de la plataforma

Revisión del repositorio frente a lo que declaraban `GOTO.md` y `AVANCES.md`. La
estructura era razonable, pero el conjunto no arrancaba: nueve defectos
bloqueantes (dos impiden un `terraform init`), seis componentes marcados como
desplegados que no existían y catorce errores de configuración. Inventario en
[AUDITORIA-PLANTILLA.md](AUDITORIA-PLANTILLA.md).

Las fases 1-6 se rehacen. Las entradas anteriores quedan al final del fichero
como histórico, pero no describen el estado actual.

### Renombrado

`ironnode` → `nullnode` en todo el árbol: clúster, namespaces, charts, bucket,
secretos y documentación. Coherente con el repositorio y con el remoto.

### Infraestructura

- Clúster con configuración declarativa de k3d en dos perfiles
  (`infra/k3d/nullnode-{gpu,cpu}.yaml`), eliminando el provider comunitario de
  Terraform. ADR-0001.
- `Dockerfile` para la imagen de k3s con runtime NVIDIA, necesaria para que un
  nodo de k3d (que es un contenedor) pueda ver la GPU.
- Terraform partido en dos stacks con frontera explícita: `cloud-mock` (LocalStack
  - S3 - Secrets Manager) y `platform-bootstrap` (namespaces, secretos, ArgoCD,
  Application raíz).
- LocalStack pasa a ser un contenedor en el host, resolviendo el interbloqueo de
  la versión anterior. ADR-0002.
- Un solo punto de entrada: Traefik con enrutado por host en el 8080, en lugar de
  un puerto del host por servicio. ADR-0003.

### Seguridad y gobierno

- Flujo de secretos unidireccional: `random_password` → Secrets Manager mockeado
  → Secret de Kubernetes → pod. Ningún chart genera contraseñas. ADR-0005.
- Job de bootstrap de departamentos: crea equipos con presupuesto, TPM y RPM,
  acuña una clave por departamento y las publica en Secrets Manager. No regenera
  una clave ya registrada: LiteLLM guarda hashes y recrearla la invalidaría.
- Guardrail de PII con Presidio, cableado y desactivado por memoria. El flag del
  gateway se deriva del componente, así que no pueden divergir.
- Auditoría de cada petición al bucket de S3 mockeado, con regla de ciclo de vida
  que expira los logs a los 30 días.
- `securityContext` restringido en todos los charts propios. LiteLLM usa la
  variante `litellm-non_root` de la imagen, que existe precisamente para eso.
- NetworkPolicies escritas para los datastores, desactivadas por defecto.

### Componentes que faltaban

- **Redis** (chart nuevo): caché de prompts y estado del router, con exporter.
  Configurado como caché: memoria acotada, LRU, sin persistencia.
- **PostgreSQL** (chart nuevo): equipos, claves virtuales, presupuestos e
  histórico de gasto. Sin esto las cuotas por departamento no son implementables.
- **KEDA**: el operador, que antes no se instalaba en ningún sitio.
- **kube-prometheus-stack**: Application bien formada, con los targets del plano
  de control de k3s desactivados para que no queden permanentemente rojos.
- **OpenTelemetry Collector**: documentado antes, ausente del repositorio.
  Recibe OTLP de LiteLLM y deriva métricas RED con `spanmetrics`.
- **NVIDIA device plugin** y **DCGM exporter** en el perfil GPU. El segundo es
  la única fuente real de VRAM.

### Gateway e inferencia

- Chart de LiteLLM reescrito: `model_list` con el parámetro `model` que faltaba,
  caché en Redis, router con estado compartido, callbacks de Prometheus, OTel y
  S3, probes contra los endpoints reales (`/health/liveliness`,
  `/health/readiness`), `--config` pasado al proceso, checksum del ConfigMap para
  que un cambio de configuración reinicie los pods, e initContainer que espera a
  Postgres antes de las migraciones.
- Eliminados el bloque `security_settings` inventado y el `drop_params` como
  lista, que descartaba el contenido de las peticiones.
- Chart de Ollama reescrito: StatefulSet con volumen por réplica, precarga en
  initContainer (el `postStart` anterior no podía funcionar, no hay servidor
  todavía) y sin el `nodeSelector` a una Tesla K80 que dejaba el pod `Pending`.
- Trigger de KEDA sobre métrica de Prometheus en lugar de una lista de Redis que
  LiteLLM nunca escribe. ADR-0004.
- ArgoCD ignora `/spec/replicas`: sin eso el self-heal y el autoescalador se
  pelean por el campo indefinidamente.

### Observabilidad

- Tres dashboards nuevos contra métricas que existen, provisionados por el
  sidecar de Grafana. El anterior graficaba tres métricas inventadas y no estaba
  conectado a nada.
- Reglas de grabación como única definición de cada señal, para que paneles y
  alertas no puedan contradecirse.
- Ocho alertas con anclaje al runbook, incluida la de presupuesto de equipo casi
  agotado y la de VRAM alta.
- Hit rate de caché derivado del exporter de Redis, legítimo porque el gateway es
  el único cliente de esa instancia.

### Herramientas y CI

- `Makefile` como interfaz del operador, con `make help`.
- `scripts/up.sh` reescrito: modo estricto, trap de error con línea y comando,
  fases con `--only` y `--from`, preflight con comprobación de versiones y
  diagnóstico específico de GPU, esperas sobre condiciones reales.
- `status.sh`, `smoke.sh` (end-to-end: ingress → auth → modelo → caché →
  auditoría, incluyendo que una petición sin autenticar sea rechazada),
  `validate.sh` (todo lo verificable sin clúster) y `versions-check.sh`.
- CI reconstruido: helm lint y render en ambos perfiles, kubeconform, Terraform
  fmt y validate, shellcheck, yamllint, y un job de integración que levanta el
  perfil CPU completo y pasa el smoke test.
- Perfil de carga k6: mide TTFT vía `waiting` con `stream:true` y compara
  prompts únicos contra repetidos. Sustituye a un `ab -p test-payload.json` cuyo
  fichero no existía.
- `renovate.json` con custom manager para los pins del app-of-apps.
- Pipeline de seguridad (`security.yaml`, `make security`): Trivy sobre
  Terraform y Dockerfile, Trivy y kube-linter sobre los manifiestos
  renderizados, Checkov, gitleaks contra árbol e historia, y CVEs de imágenes
  como informativo. Se escanea el render, no las plantillas: `securityContext`,
  límites y tags solo existen después de templar.
- Pipeline de formato (`format.yaml`, `make fmt-check`): `terraform fmt`, shfmt,
  actionlint, hadolint y markdownlint.
- `make check` como puerta única de PR. Hallazgos aceptados documentados con su
  motivo en `.trivyignore` y `.checkov.yaml`; casi todos son controles sin
  significado contra un mock (KMS, replicación, access logging).
- tfsec queda como opt-in (`WITH_TFSEC=true`): Aqua lo integró en Trivy y
  `trivy config` corre las mismas reglas, así que por defecto duplicaría
  hallazgos.

### Documentación

- README reescrito, con la realidad de la GPU explicada de entrada.
- `docs/uso/CONECTAR.md`: guía para el dev que consume la plataforma. VS Code con
  Continue y Cline como camino principal, Open WebUI y SDKs después, y la tabla
  de resolución de nombres según desde dónde llames (navegador de Windows,
  extensión en WSL, `curl` en la distro, otro contenedor), que es la fuente
  habitual de "no conecta".
- `../ops/RUNBOOK.md`: diagnóstico por síntoma y por alerta.
- `../ops/VERSIONS.md`: inventario de pins y checklist de actualización de LiteLLM.
- `../adr/`: seis ADRs con las decisiones y sus contrapartidas.
- `AUDITORIA-PLANTILLA.md`: qué estaba roto y qué se hizo.

### Sin verificar

Nada de esto se ha ejecutado. Las versiones de charts de terceros están pinneadas
sin acceso a red (`make versions-check` antes del primer despliegue) y los nombres
de las métricas de LiteLLM dependen de la versión pinneada (ADR-0006).

---

## Registro histórico

> Las entradas siguientes son del andamio inicial. Se conservan por trazabilidad;
> describen intenciones y no el estado del repositorio. El detalle de qué de esto
> no era cierto está en [AUDITORIA-PLANTILLA.md](AUDITORIA-PLANTILLA.md).

### [2026-08-23] Inicialización del proyecto

- Definición del stack tecnológico completo.
- Estructura de directorios base y ficheros de gobernanza.

### [2026-08-23] Fases 1-5

- `terraform/` con provider de k3d, variables y outputs.
- Scripts `up.sh` y `down.sh`.
- Bootstrap de ArgoCD vía kustomize y patrón app-of-apps.
- Charts de LiteLLM y Ollama, `ScaledObject` de KEDA.
- Values de Prometheus/Grafana y un dashboard de métricas de IA.
- Workflows de lint y load test.

### [2026-08-24] Fase 6 — Cloud mocking con LocalStack

- Provider de AWS en Terraform apuntando a LocalStack.
- Bucket S3 `ironnode-model-vault` y secreto `ironnode/litellm-master-key`.
- Chart de LocalStack in-cluster e integración en el app-of-apps.
- Validación de salud de LocalStack en `up.sh`.
