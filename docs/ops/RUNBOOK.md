# Runbook

Diagnóstico por síntoma. Cada alerta apunta aquí por su ancla.

Primer comando siempre: `make status` — endpoints, pods no sanos, Applications y
ScaledObjects en una pantalla.

---

## Arranque

### El primer `make up` tarda mucho

Normal: ~1 GiB de imágenes de observabilidad más 2-5 GiB por modelo. 10-20
minutos.

`^C` es seguro, ArgoCD sigue reconciliando. Retomar con `make status` o
`kubectl -n argocd get applications -w`.

### `PROFILE=gpu` falla en el preflight

El mensaje dice cuál de las tres comprobaciones falló:

1. **Docker no ve la GPU.** Driver en el host (en Windows, no en WSL),
   `nvidia-container-toolkit` dentro de la distro WSL, Docker reiniciado
   después. Verificar:
   `docker run --rm --gpus all nvidia/cuda:12.6.2-base-ubuntu24.04 nvidia-smi`
2. **Falta la imagen CUDA.** `make k3s-cuda-image`.
3. Sin GPU: `PROFILE=cpu make up`.

### Las Applications quedan en `Unknown` o `ComparisonError`

Casi siempre ArgoCD no puede leer el repositorio. Reconcilia desde
`gitops.repoURL` en la revisión configurada, no desde tu copia local: sin push,
los cambios no existen para él.

```bash
kubectl -n argocd get application nullnode-root -o jsonpath='{.status.conditions}' | jq
kubectl -n argocd logs deploy/argocd-repo-server --tail=100
```

Para iterar sin pushear a `main`, apunta el bootstrap a tu rama:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=mi-rama
```

---

## Alertas

### NullNodeGatewayDown

Por orden:

```bash
kubectl -n nullnode-platform get pods -l app.kubernetes.io/name=litellm
kubectl -n nullnode-platform logs deploy/litellm --tail=200
```

Causas habituales:

- **`CrashLoopBackOff` al arrancar:** migraciones de Prisma. Comprueba que
  Postgres está `Ready` y que existe `nullnode-postgres-auth`. El initContainer
  lo cubre, así que si llegas aquí Postgres arrancó y luego cayó.
- **Config inválida:** un error de sintaxis mata el proceso al segundo.
  `kubectl -n nullnode-platform get cm litellm-config -o yaml`.
- **Falta el secreto:** `platform-bootstrap` no llegó a aplicar.
  `./scripts/up.sh --only platform`.

### NullNodeGatewayHighErrorRate

Separar por código: significan cosas opuestas.

```promql
sum by (status_code) (rate(litellm_proxy_failed_requests_metric_total[5m]))
```

- **429:** gobierno funcionando. Un equipo agotó presupuesto o su RPM/TPM.
  Decisión de negocio: subir el límite en `departments` o dejar que module.
- **401/403:** claves mal repartidas o revocadas.
- **5xx:** el pool de inferencia. Ir a `NullNodeWorkerPoolEmpty`.
- **408/504:** timeouts. Modelo grande para el hardware, o
  `OLLAMA_NUM_PARALLEL` por encima de lo que aguanta la VRAM.

### NullNodeTimeToFirstTokenDegraded

La única latencia que el usuario nota. Por orden de probabilidad:

1. **El modelo salió de VRAM.** `OLLAMA_KEEP_ALIVE` expiró y cada llamada
   recarga. Subirlo en el values del perfil.
2. **Más concurrencia que `OLLAMA_NUM_PARALLEL`.** Las peticiones se encolan
   dentro de Ollama sin que suba nada en Kubernetes. Comparar rps del gateway
   contra el valor configurado.
3. **El pool escaló a la baja con tráfico.** Panel "KEDA scaling decisions".
4. **Contención de VRAM** con `OLLAMA_MAX_LOADED_MODELS > 1`: dos modelos se
   turnan y ambos van peor.

```bash
kubectl -n nullnode-platform logs statefulset/ollama --tail=100 | grep -i "load\|memory"
```

### NullNodeCacheHitRateLow

Informativa. Tres causas, y la tercera es la que importa:

1. La carga es diversa. Nada que arreglar.
2. `cache.ttlSeconds` corto para el patrón de uso.
3. **Redis evicta bajo presión de `maxmemory`.** Subir el TTL no arregla nada.
   Mirar evicciones primero:

```promql
rate(redis_evicted_keys_total[5m])
```

Si hay evicciones, subir `config.maxmemory` antes de tocar el TTL.

### NullNodeTeamBudgetNearlyExhausted

A cero, el gateway devuelve 429 a las claves de ese equipo. Es lo diseñado.

```bash
KEY=$(make -s key)
curl -s http://gateway.nullnode.localhost:8080/team/list \
  -H "Authorization: Bearer $KEY" | jq '.[] | {team_alias, spend, max_budget}'
```

Subir presupuesto sin redespliegue (los equipos viven en Postgres):

```bash
curl -X POST http://gateway.nullnode.localhost:8080/team/update \
  -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
  -d '{"team_id":"<id>","max_budget":500}'
```

Para que el cambio sea permanente, editar `departments` en el values y commitear.

### NullNodeWorkerPoolEmpty

Hay tráfico y cero réplicas listas.

```bash
kubectl -n nullnode-platform get pods -l app.kubernetes.io/name=ollama
kubectl -n nullnode-platform describe pod ollama-0
```

- **`Pending` / `Insufficient nvidia.com/gpu`:** la GPU está reclamada. Con
  una tarjeta, `maxReplicas` tiene que ser 1 (ADR-0004). Si hay un pod viejo
  terminando, esperar.
- **`Pending` / `Insufficient memory`:** los requests no caben. Bajarlos o usar
  un modelo menor.
- **`Init:0/1` mucho tiempo:** descargando pesos.
  `kubectl -n nullnode-platform logs ollama-0 -c preload-models -f`
- **Cero réplicas y todo sano:** `scaleToZero` activo y el pool durmiendo.

### NullNodeWorkerPoolCrashLooping

Casi siempre OOM:

```bash
kubectl -n nullnode-platform get pod ollama-0 \
  -o jsonpath='{.status.containerStatuses[0].lastState}' | jq
```

`OOMKilled` significa límite por debajo del working set. Un 7B cuantizado
necesita ~6 GiB de RAM del contenedor incluso en GPU (KV cache, tokenizer,
buffers). Subir `resources.limits.memory` o bajar de modelo.

### NullNodeGpuMemoryHigh

La siguiente carga fallará o desalojará un modelo residente.

```bash
kubectl -n nullnode-observability port-forward svc/dcgm-exporter 9400:9400
curl -s localhost:9400/metrics | grep DCGM_FI_DEV_FB
```

Bajar `OLLAMA_MAX_LOADED_MODELS` a 1 o usar cuantizaciones más agresivas
(`:q4_0`).

---

## Problemas que no tienen alerta

### `curl` no resuelve `gateway.nullnode.localhost`

glibc no resuelve `*.localhost` (los navegadores sí).

```bash
make hosts   # imprime la línea para /etc/hosts
```

O saltárselo: `curl --resolve gateway.nullnode.localhost:8080:127.0.0.1 ...`

### Las claves de departamento no aparecen

`make department-keys` lee el secreto de Secrets Manager que escribe el Job de
bootstrap. Si sale vacío o `_bootstrap: pending`:

```bash
kubectl -n nullnode-platform get jobs
kubectl -n nullnode-platform logs job/<litellm-bootstrap-...>
```

Es un hook PostSync: solo corre si la Application `litellm` sincroniza bien.
Idempotente, y no regenera claves ya registradas.

### Un panel de Grafana está vacío

Distinguir "no hay tráfico" de "la métrica se renombró":

```bash
KEY=$(make -s key)
curl -s http://gateway.nullnode.localhost:8080/metrics | grep '^litellm_' | cut -d'{' -f1 | sort -u
```

Comparar con las expresiones del panel. Los nombres cambian entre versiones
menores de LiteLLM: ADR-0006.

### ArgoCD marca Ollama o LiteLLM como `OutOfSync` para siempre

Debería estar cubierto: `argocd.tf` configura `ignoreDifferences` sobre
`/spec/replicas`, porque KEDA y el HPA son dueños del campo. Si reaparece,
comprobar que el ConfigMap las mantiene:

```bash
kubectl -n argocd get cm argocd-cm -o yaml | grep -A3 ignoreDifferences
```

### Todo está raro después de reiniciar Docker

LocalStack Community no persiste: al reiniciar, bucket y secretos desaparecen y
los pods fallan las llamadas a S3.

```bash
./scripts/up.sh --only cloud-mock   # recrea bucket y secretos
```

Ojo: Terraform genera credenciales nuevas, así que las claves de departamento
repartidas dejan de valer (ADR-0005).
