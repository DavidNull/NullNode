# Plan de Acción y Siguiente Pasos (GOTO)

## ✅ Fase 1: Infraestructura Base e IaC - COMPLETADA
- [x] Escribir el script en `terraform/main.tf` para levantar un clúster K3d/K3s local optimizado para desarrollo.
- [x] Crear los scripts de automatización de ciclo de vida (`scripts/up.sh` y `scripts/down.sh`).

## ✅ Fase 2: Bootstrap de GitOps & ArgoCD - COMPLETADA
- [x] Configurar el manifiesto inicial en `k8s/bootstrap/argo-cd/` para instalar ArgoCD automáticamente.
- [x] Diseñar el patrón App-of-Apps en `k8s/platform/argocd-apps.yaml` para orquestar los despliegues posteriores.

## ✅ Fase 3: AI Gateway & Caché (LiteLLM + Redis) - COMPLETADA
- [x] Desarrollar el Helm Chart personalizado para LiteLLM (`k8s/platform/litellm/`).
- [x] Configurar la integración con Redis para habilitar caché semántica de prompts.
- [x] Definir variables de entorno para autenticación y cuotas simuladas por departamentos.

## ✅ Fase 4: AI Worker Pool & Autoescalado (Ollama + KEDA) - COMPLETADA
- [x] Configurar el despliegue de Ollama en Kubernetes (`k8s/platform/ollama/`) con volúmenes persistentes (`PVC`) para almacenamiento de modelos.
- [x] Implementar el objeto `ScaledObject` de KEDA (`k8s/platform/keda/`) para gestionar la concurrencia del worker pool.

## ✅ Fase 5: Observabilidad y Dashboards (OTel + Prometheus + Grafana) - COMPLETADA
- [x] Desplegar la pila de Prometheus y Grafana dentro del clúster.
- [x] Autoprovisionar dashboards en Grafana enfocados en métricas de GenAI (TTFT, generación de tokens, VRAM, latencia de inferencia).
- [x] Configurar pipelines de CI/CD para linting y load testing.

## ✅ Fase 6: Cloud Mocking con LocalStack - COMPLETADA
- [x] Configurar provider de AWS en Terraform para redirigir a LocalStack
- [x] Definir recursos S3 y Secrets Manager mockeados en Terraform
- [x] Crear Helm Chart personalizado para LocalStack en k8s/platform/localstack/
- [x] Integrar LocalStack en el patrón App-of-Apps de ArgoCD
- [x] Configurar LiteLLM para consumir secretos desde LocalStack
- [x] Actualizar script up.sh con validación de salud de LocalStack
- [x] Actualizar documentación de control (CONTEXT.md, AVANCES.md, GOTO.md)

## 🔄 Fase 7: Próximos Pasos y Mejoras
- [ ] Instalar y configurar Redis como deployment independiente en el clúster
- [ ] Configurar OpenTelemetry Collector para exportar trazas a Jaeger o backend compatible
- [ ] Implementar autenticación real con gestión de API keys por departamento
- [ ] Configurar reglas de alerta en Prometheus para métricas críticas de IA
- [ ] Desarrollar interfaz web de administración (logo y UI pendientes)
- [ ] Implementar pruebas de integración end-to-end
- [ ] Documentación de operación y troubleshooting
- [ ] Configurar backup/restore de secretos desde S3 mockeado
- [ ] Implementar rotación automática de secretos en Secrets Manager
