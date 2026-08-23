# IronNode - Contexto y Visión de Arquitectura

## Visión General
IronNode es una plataforma local de LLMOps diseñada para emular un entorno de producción Enterprise en una estación de trabajo individual. Permite consumir modelos de lenguaje de forma completamente privada, aplicando gobernanza mediante un AI Gateway, optimización de costes con caché semántica, autoescalado inteligente y observabilidad SRE avanzada (TTFT, tokens por segundo y consumo de recursos).

## Arquitectura de Componentes
1. **Capa de Control y Gateway (LiteLLM + Redis):** Intercepta todas las peticiones, valida claves de API, aplica cuotas de uso, enmascara datos sensibles (PII) y resuelve peticiones recurrentes mediante caché en Redis.
2. **Capa de Ejecución de IA (Ollama):** Worker pool de modelos locales gestionados en Kubernetes.
3. **Capa de Escalado (KEDA):** Ajusta los recursos de los pods de inferencia basándose en la cola de peticiones en lugar de la CPU estricta.
4. **Capa de Observabilidad (OpenTelemetry + Prometheus + Grafana):** Recopila trazas y métricas específicas de GenAI para visualizarlas en dashboards profesionales de SRE y FinOps.
5. **Capa GitOps (Terraform + ArgoCD):** Toda la infraestructura y despliegues se gestionan de manera declarativa. Cero comandos manuales en producción o laboratorio.
