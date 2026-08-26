# 0006 - Métricas de LiteLLM, con las spanmetrics de OTel como red de seguridad

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

El dashboard de la plantilla graficaba métricas inexistentes
(`litellm_request_duration_seconds_bucket`, `litellm_requests_total`,
`litellm_tokens_generated_total`). Los nombres reales son otros
(`litellm_proxy_total_requests_metric_total`,
`litellm_llm_api_time_to_first_token_metric_bucket`). Y no estaba conectado a
nada: el JSON estaba en el repo mientras Grafana provisionaba `gnetId: 1`, un
dashboard público ajeno.

De fondo hay un problema mayor: esos nombres cambian entre versiones menores de
LiteLLM, y en algunas builds el callback de Prometheus está tras licencia
enterprise.

## Decisión

**Primaria:** el callback `prometheus` de LiteLLM, vía ServiceMonitor. Es la
única fuente de TTFT, tokens, gasto y presupuesto restante por equipo; nada más
en el stack conoce esos conceptos.

**Red de seguridad:** LiteLLM también exporta trazas OTLP, y el collector tiene
el conector `spanmetrics` activado, que deriva métricas RED con prefijo
`nullnode_`. Si el callback no está disponible, hay tasa, errores y latencia sin
tocar nada.

El fallback **no** cubre TTFT, tokens ni presupuesto: eso solo lo sabe LiteLLM.

**Caché:** del exporter de Redis (`redis_keyspace_hits_total` / `misses`). Vale
porque el gateway es el único cliente de esa instancia.

**VRAM:** del DCGM exporter, solo en perfil GPU. cAdvisor reporta RAM del host,
que no dice nada sobre si un modelo cabe en la tarjeta.

## Consecuencias

- Los dashboards llevan un panel con el comando para comprobar los nombres. Un
  panel vacío no distingue "no hay tráfico" de "la métrica se renombró".
- Las reglas de grabación son la única definición de cada señal
  (`nullnode:ttft_seconds:p95`, etc.), así que una alerta no puede contradecir a
  su gráfica.
- El trigger de KEDA lleva la consulta alternativa en el values
  (`autoscaling.prometheus.fallbackQuery`).
- Actualizar LiteLLM obliga a verificar los nombres. Está en la checklist de
  `GOTO.md`.
