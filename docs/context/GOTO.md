# Plan de acción

## Ahora: validar

Nada de esto se ha ejecutado. Orden de comprobación:

- [ ] `make versions-check` — las versiones de charts de terceros están pinneadas
      sin acceso a red. Si alguna no resuelve, corregir `k8s/platform/values.yaml`
      y `infra/terraform/platform-bootstrap/variables.tf`.
- [ ] `make validate` — helm lint y render en ambos perfiles, terraform validate,
      shellcheck, yamllint. Es lo mismo que corre CI.
- [ ] Pushear a `main` (o apuntar el bootstrap a una rama con
      `-var gitops_target_revision=...`). ArgoCD reconcilia desde git, no desde
      el working tree.
- [ ] `PROFILE=cpu make up` primero: descarta la GPU del diagnóstico y tarda
      menos.
- [ ] `make smoke`.
- [ ] `PROFILE=gpu make up` una vez el perfil CPU converja.
- [ ] Verificar los nombres de las métricas de LiteLLM contra la versión
      pinneada (ADR-0006). Afecta a los tres dashboards, a las reglas de
      grabación y al trigger de KEDA. Comando en `../ops/VERSIONS.md`.

## Siguiente: cerrar lo que está a medias

- [ ] **Fijar las versiones de los escáneres en CI.** `trivy`, `shellcheck` y
      `checkov` se instalan como *latest* (apt/pip) en los workflows. Cada release
      nueva puede meter reglas que ponen el gate en rojo sin tocar una línea de
      código — ya pasó con KSV-0014/0109, DS-0002 y AWS-0132 al subir Trivy.
      Pinnearlos (como ya se hace con las imágenes) hace el pipeline determinista.
- [ ] **Confirmar el test de integración en CI.** El blocker estaba en el mock:
      LocalStack 3.8.1 colgaba `aws_s3_bucket_lifecycle_configuration` contra el
      provider AWS 5.100. Subido a 4.4.0 (ver VERSIONS.md), el `apply` pasa en
      local. Falta verlo verde en CI tras el push — recordar que ArgoCD reconcilia
      desde el SHA pusheado, no desde el working tree.
- [ ] **Backend de trazas.** El collector recibe OTLP y deriva spanmetrics, pero
      las trazas mueren en el exporter `debug`. Añadir Tempo y su datasource en
      Grafana para poder abrir una petición lenta y ver dónde se fue el tiempo.
- [ ] **Guardrail de PII por defecto.** Presidio está cableado y apagado por
      RAM. Medir coste en latencia y memoria; si es asumible, encenderlo en el
      perfil GPU.
- [ ] **NetworkPolicies.** Escritas y desactivadas. Encenderlas de una en una,
      verificando entre cada paso.
- [ ] **Escalado a cero.** Implementado y apagado. Medir cuánto tarda el pool en
      despertar y si `num_retries` basta para no perder la primera petición.
- [ ] **Presupuestos por usuario además de por equipo.** LiteLLM lo soporta;
      ahora mismo solo hay equipos por departamento.
- [ ] **Open WebUI como componente opcional.** Hoy se documenta como
      `docker run` (cliente, no infraestructura). Meterlo en el app-of-apps con
      `enabled: false` daría chat con Ingress y clave de departamento inyectada
      desde el Secret, sin pasos manuales.
- [ ] **Escaneo de las imágenes grandes en el gate.** LiteLLM y Ollama están
      fuera porque sus CVEs vienen de las capas base de CUDA y Python. Con una
      allowlist por capa base sí serían accionables.

## Después: lo que hace falta para que se parezca a producción

- [ ] **External Secrets Operator** en lugar del data source. El flujo ya tiene
      la forma correcta (ADR-0005): el operador leería el mismo secreto y
      mantendría los Secrets sincronizados, con rotación sin `terraform apply`.
- [ ] **Un modelo hosted en el catálogo.** Con todo local el gasto es cero y el
      dashboard de FinOps es un ensayo. Un proveedor de pago detrás de una
      variable convierte los presupuestos en un control real.
- [ ] **Fallbacks de modelo.** `router_settings` soporta cadenas de fallback. Con
      un solo modelo por perfil no hay nada que probar.
- [ ] **Etcd encryption at rest** y firma de imágenes. Ahora los Secrets de
      Kubernetes son base64 sin más.
- [ ] **Evaluación continua.** Un job periódico con un set de prompts de
      referencia que publique métricas de calidad, para detectar que un cambio
      de modelo o cuantización empeoró las respuestas.
- [ ] **Versionado de prompts en el bucket.** El prefijo `prompts/` existe y el
      versioning del bucket está activado, pero nada escribe ahí todavía.
- [ ] **Multi-tenant real.** Un namespace por departamento con cuotas de
      recursos, no solo cuotas lógicas en el gateway.

## Ideas sin compromiso

- Interfaz de administración propia. LiteLLM ya trae UI; una capa con la vista
  de FinOps por departamento tendría sentido si esto se usa en equipo.
- `vLLM` como alternativa a Ollama para medir throughput con batching continuo.
- Caché semántica por embeddings en lugar de exacta. LiteLLM lo soporta y
  subiría el hit rate con prompts parafraseados.
- Chaos testing: matar el pool bajo carga y comprobar que el gateway degrada en
  lugar de colgarse.

---

## Fases completadas

Todas se rehicieron el 2026-08-26 sobre la base auditada. El detalle está en
[AVANCES.md](AVANCES.md) y las razones de cada cambio en
[las ADRs](../adr/).

- [x] **Fase 1 — Infraestructura e IaC.** Clúster declarativo con k3d en dos
      perfiles, imagen CUDA de k3s, dos stacks de Terraform, scripts de ciclo de
      vida idempotentes con fases.
- [x] **Fase 2 — GitOps.** ArgoCD por Helm desde Terraform, un `AppProject` y un
      `Application` raíz, app-of-apps con sync waves y patrón multi-source
      `$values` para los charts de terceros.
- [x] **Fase 3 — Gateway y caché.** LiteLLM con claves virtuales, presupuestos y
      límites por departamento, caché en Redis, router con estado compartido.
      Charts de Redis y PostgreSQL, que antes no existían.
- [x] **Fase 4 — Pool de inferencia y autoescalado.** Ollama como StatefulSet con
      volumen por réplica y precarga de modelos, KEDA (operador incluido) sobre
      métrica de Prometheus.
- [x] **Fase 5 — Observabilidad.** kube-prometheus-stack, OTel Collector con
      spanmetrics, DCGM en perfil GPU, tres dashboards contra métricas reales,
      reglas de grabación y ocho alertas con runbook.
- [x] **Fase 6 — Cloud mockeado.** LocalStack fuera del clúster, S3 con
      auditoría de peticiones y ciclo de vida, Secrets Manager como fuente única
      de credenciales.
- [x] **Fase 7 — Seguridad, guardrails y tooling.** Flujo de secretos sin nada en
      git, `securityContext` restringido, Presidio cableado, NetworkPolicies
      escritas, suite de validación offline, smoke test end-to-end, perfil de
      carga k6, CI completo, runbook y ADRs.
