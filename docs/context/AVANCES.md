# Registro de avances

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
  + S3 + Secrets Manager) y `platform-bootstrap` (namespaces, secretos, ArgoCD,
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
<<<<<<< HEAD
=======
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
>>>>>>> origin/feature/security-pipelines

### Documentación

- README reescrito, con la realidad de la GPU explicada de entrada.
<<<<<<< HEAD
=======
- `docs/uso/CONECTAR.md`: guía para el dev que consume la plataforma. VS Code con
  Continue y Cline como camino principal, Open WebUI y SDKs después, y la tabla
  de resolución de nombres según desde dónde llames (navegador de Windows,
  extensión en WSL, `curl` en la distro, otro contenedor), que es la fuente
  habitual de "no conecta".
>>>>>>> origin/feature/security-pipelines
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
