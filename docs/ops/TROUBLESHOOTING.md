# Troubleshooting

Problemas frecuentes ordenados por cuándo aparecen.

---

## Durante `make setup` / preflight

### "Docker not found" al ejecutar `make setup`

Docker es el único requisito previo que no se puede instalar desde el Makefile.
Sigue la guía de instalación para tu sistema:
<https://docs.docker.com/engine/install/>

En WSL2, instala Docker Desktop en Windows y activa la integración con tu
distro en Settings → Resources → WSL Integration.

### "the GPU profile is selected but Docker cannot reach an NVIDIA GPU"

El preflight te dice exactamente cuál de los tres pasos falta:

1. **Driver NVIDIA** → instálalo en Windows (no en WSL). Reinicia.
2. **nvidia-container-toolkit** → dentro de la distro WSL:
   ```bash
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
     | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
     | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
   sudo nvidia-ctk runtime configure --runtime=docker
   sudo systemctl restart docker
   ```
3. **Imagen CUDA de k3s** → `make k3s-cuda-image` (tarda unos minutos, solo una vez).

Si no tienes GPU, usa `PROFILE=cpu make up`.

### "k3d X.Y.Z is too old"

```bash
curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.7.4 bash
```

---

## Durante `make up`

### El clúster ya existe y `make up` falla al crearlo

```bash
k3d cluster delete nullnode
make up
```

O si quieres conservar el estado: `make up --from cloud-mock` para saltarte la
fase del clúster.

### LocalStack no arranca / `terraform apply` falla en cloud-mock

LocalStack corre como contenedor Docker. Comprueba:

```bash
docker ps -a | grep localstack
docker logs localstack
```

Si el contenedor existe pero no responde:

```bash
docker rm -f localstack
make up --from cloud-mock
```

Si hay un error de puertos ocupados (`4566 already in use`):

```bash
lsof -i :4566
# mata el proceso que lo ocupa, luego:
make up --from cloud-mock
```

### ArgoCD no sincroniza / aplicaciones en `Unknown` o `OutOfSync`

ArgoCD reconcilia desde git, no desde tu copia local. Si acabas de hacer
cambios, asegúrate de haberlos pusheado:

```bash
git push
make sync
```

Si la revisión de gitops no coincide con la rama que estás trabajando:

```bash
terraform -chdir=infra/terraform/platform-bootstrap apply \
  -var gitops_target_revision=mi-rama
```

### Pods en `Pending` (perfil GPU)

Casi siempre es que el device plugin de NVIDIA no está listo todavía o el pod
pide la GPU antes de que el plugin la registre. Espera un minuto y comprueba:

```bash
kubectl get pods -n nullnode-platform -o wide
kubectl describe pod <pod-en-pending> -n nullnode-platform
```

Si el evento dice `0/1 nodes have sufficient nvidia.com/gpu`, el device plugin
aún no está listo:

```bash
kubectl rollout status ds/nvidia-device-plugin-daemonset -n kube-system
```

### Ollama tarda mucho en arrancar

Normal en el primer arranque: está descargando los pesos del modelo. Con `make
logs-ollama` puedes ver el progreso. Para llama3.2 (3B) espera entre 5 y 15
minutos según tu conexión.

---

## Durante `make smoke`

### "DNS resolution failed" para `gateway.nullnode.localhost`

Las entradas de `/etc/hosts` no están añadidas. Ejecuta `make hosts` para ver
la línea exacta y añádela:

```bash
make hosts
# 127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost ...
sudo tee -a /etc/hosts <<< "127.0.0.1 gateway.nullnode.localhost grafana.nullnode.localhost prometheus.nullnode.localhost argocd.nullnode.localhost"
```

En Windows, si accedes desde el navegador, añade la misma línea a
`C:\Windows\System32\drivers\etc\hosts` (como administrador).

### "401 Unauthorized" en el smoke test

La clave maestra no llegó al pod de LiteLLM. Comprueba que el secret existe:

```bash
kubectl get secret litellm-master-key -n nullnode-platform
```

Si no existe, es que el `platform-bootstrap` de Terraform no terminó bien.
Revisa el output: `terraform -chdir=infra/terraform/platform-bootstrap output`.

### "cache miss en todas las peticiones repetidas"

Redis no está configurado como backend de caché en LiteLLM, o el pod de Redis
no está Ready:

```bash
kubectl rollout status statefulset/redis -n nullnode-platform
kubectl -n nullnode-platform logs deployment/litellm | grep -i cache
```

### "no audit log en S3"

El callback de S3 de LiteLLM no está llegando a LocalStack. Comprueba que
LocalStack sigue vivo:

```bash
curl http://127.0.0.1:4566/_localstack/health
```

Si LocalStack murió (pasa si Docker se reinicia):

```bash
make up --from cloud-mock
```

---

## CI / GitHub Actions

### Todos los jobs de CI fallan con "Permission denied"

Los scripts en `scripts/` necesitan permiso de ejecución. Si clonas el repo y
los permisos no se conservaron:

```bash
chmod +x scripts/up.sh scripts/down.sh scripts/security.sh scripts/smoke.sh \
         scripts/status.sh scripts/validate.sh scripts/versions-check.sh
git update-index --chmod=+x scripts/up.sh scripts/down.sh scripts/security.sh
git commit -m "fix: restore execute permissions on scripts"
git push
```

### `markdownlint` falla con "conflict marker"

Hay conflictos de merge sin resolver en algún `.md`. Búscalos:

```bash
grep -r "^<<<<<<< " docs/
```

Resuélvelos manualmente y haz commit.

### El job de integración agota el timeout (45 min)

El modelo no terminó de descargarse. En CI solo se usa el perfil CPU con un
modelo de 1B, pero el runner puede estar saturado. Opciones:

- Relanzar el job desde la UI de GitHub (Actions → Re-run failed jobs).
- Si falla repetidamente, revisa que el modelo configurado para CPU sea
  `llama3.2:1b` y no uno más grande.

---

## Terraform

### "Error: No valid credential sources found"

Terraform intenta conectarse a AWS real en lugar de a LocalStack. Asegúrate de
que las variables de entorno mock están presentes:

```bash
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=eu-west-1
```

El stack `cloud-mock` las inyecta automáticamente al arrancar desde `make up`,
pero si ejecutas Terraform directamente tendrás que exportarlas.

### "state lock" al relanzar `make up`

Si un `apply` anterior se interrumpió puede quedar un lock. Con LocalStack como
backend, borrarlo es sencillo:

```bash
terraform -chdir=infra/terraform/cloud-mock force-unlock <lock-id>
```

El lock-id aparece en el mensaje de error.

---

## Observabilidad

### Paneles de Grafana vacíos

Las métricas de LiteLLM dependen de la versión pinneada del chart
([ADR-0006](../adr/0006-metrics-sources.md)). Si actualizaste LiteLLM, los
nombres de las métricas pueden haber cambiado. Comprueba:

```bash
curl -s http://gateway.nullnode.localhost:8080/metrics | grep litellm
```

Y compara con las reglas de grabación en
`k8s/charts/nullnode-observability/templates/`.

### "No data" en el panel de VRAM (solo perfil GPU)

El exporter DCGM tarda en arrancar. Espera 2-3 minutos tras el primer boot del
clúster. Si sigue sin aparecer:

```bash
kubectl get pods -n kube-system | grep dcgm
kubectl logs -n kube-system <dcgm-pod>
```
