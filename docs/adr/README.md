# Decisiones de arquitectura

Una ADR por decisión que no es obvia leyendo el código. Si algo en el repo te
parece raro, la explicación probablemente está aquí.

Los ficheros van en inglés porque los comentarios del código los referencian por
ruta; el contenido va en castellano, como el resto de la documentación.

| # | Decisión | Estado |
| --- | --- | --- |
| [0001](0001-k3d-declarative-config.md) | El clúster se crea con el config declarativo de k3d, no con un provider de Terraform | Aceptada |
| [0002](0002-localstack-outside-the-cluster.md) | LocalStack corre fuera del clúster | Aceptada |
| [0003](0003-single-entrypoint.md) | Un único punto de entrada por Ingress en lugar de un puerto por servicio | Aceptada |
| [0004](0004-scaling-signal.md) | KEDA sobre métrica de Prometheus para inferencia, HPA de CPU para el gateway | Aceptada |
| [0005](0005-secrets-flow.md) | Los secretos nacen en Terraform, viven en Secrets Manager y se proyectan a Kubernetes | Aceptada |
| [0006](0006-metrics-sources.md) | Métricas de LiteLLM con fallback a spanmetrics de OTel | Aceptada |
