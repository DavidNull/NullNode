# Test de humo

Vive en [`scripts/smoke.sh`](../../scripts/smoke.sh), no aquí, porque usa la
librería compartida de shell y forma parte del flujo del operador
(`make smoke`).

No comprueba que los pods estén arriba: recorre la cadena completa.

| Paso | Qué demuestra |
| --- | --- |
| `/health/liveliness` | Ingress, enrutado de Traefik y el proceso del gateway |
| `POST` sin autenticar | Que la autenticación se aplica de verdad |
| `/v1/models` | Que el catálogo renderizado desde el values cargó |
| `/v1/chat/completions` | Router, Ollama, pesos en disco, acceso a la GPU |
| Repetir el mismo prompt | Que la caché de Redis está conectada y se usa |
| `/metrics` | Que el callback de Prometheus está activo |
| `s3://nullnode-model-vault/audit` | Que la auditoría llega a LocalStack |

Ejecutar después de `make up`, o en CI contra un clúster efímero.
