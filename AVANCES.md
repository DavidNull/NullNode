# Registro de Avances (Progress Log)

## [2026-08-23] - Inicialización del Proyecto
- Definición del stack tecnológico completo (K3s, Terraform, ArgoCD, LiteLLM, Redis, Ollama, KEDA, Prometheus, Grafana).
- Creación de la estructura de directorios base del repositorio (`terraform/`, `k8s/`, `scripts/`, `.github/`).
- Establecimiento de los archivos de gobernanza del proyecto (`CONTEXT.md`, `AVANCES.md`, `GOTO.md`).

## [2026-08-23] - Fase 1: Infraestructura Base e IaC
- ✅ Completado: Escritura de `terraform/main.tf` para provisionar clúster K3d/K3s local
- ✅ Completado: Creación de `terraform/variables.tf` con configuración de variables
- ✅ Completado: Creación de `terraform/outputs.tf` con endpoints de salida
- ✅ Completado: Scripts de automatización `scripts/up.sh` y `scripts/down.sh` con validación de prerrequisitos
- ✅ Completado: Configuración de `.gitignore` para archivos sensibles

## [2026-08-23] - Fase 2: Bootstrap de GitOps & ArgoCD
- ✅ Completado: Manifiesto inicial en `k8s/bootstrap/argo-cd/kustomization.yaml` para instalar ArgoCD
- ✅ Completado: Patrón App-of-Apps en `k8s/platform/argocd-apps.yaml` para orquestar despliegues

## [2026-08-23] - Fase 3: AI Gateway & Caché (LiteLLM + Redis)
- ✅ Completado: Helm Chart personalizado para LiteLLM (`k8s/platform/litellm/`)
- ✅ Completado: Configuración de integración con Redis en `values.yaml`
- ✅ Completado: Definición de variables de entorno para autenticación y cuotas
- ✅ Completado: Templates de Kubernetes (deployment, service, configmap, secret, HPA)

## [2026-08-23] - Fase 4: AI Worker Pool & Autoescalado (Ollama + KEDA)
- ✅ Completado: Helm Chart para Ollama (`k8s/platform/ollama/`)
- ✅ Completado: Configuración de PVC para almacenamiento de modelos
- ✅ Completado: Objeto `ScaledObject` de KEDA para autoescalado basado en cola de Redis

## [2026-08-23] - Fase 5: Observabilidad y Dashboards
- ✅ Completado: Configuración de Prometheus y Grafana en `values.yaml`
- ✅ Completado: Dashboard de Grafana enfocado en métricas de GenAI (TTFT, tokens/sec, memoria)
- ✅ Completado: Configuración de CI/CD en `.github/workflows/` (lint-helm, load-test)
- ✅ Completado: Actualización de README.md con documentación completa
