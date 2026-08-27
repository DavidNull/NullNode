# 0004 - Señal de autoescalado: KEDA para inferencia, HPA para el gateway

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

La plantilla tenía un `ScaledObject` con trigger de Redis sobre la lista
`litellm:queue`. Esa lista no existe: LiteLLM usa Redis como caché y estado del
router, no como cola. El escalador habría leído 0 siempre.

El gateway, en paralelo, tenía un HPA sobre CPU y memoria al 80%.

## Decisión

Dos señales distintas, por razones distintas:

**Ollama → KEDA con trigger de Prometheus.** Mide peticiones por segundo hacia
el pool. La señal correcta para un servidor de inferencia es la demanda que le
llega: un pod bloqueado esperando a la GPU puede estar al 15% de CPU y saturado.

**LiteLLM → HPA sobre CPU.** Aquí la CPU sí mide algo: serialización JSON,
conteo de tokens, llamadas a guardrails, escritura de logs.

## Con una sola GPU, escalar horizontalmente no sirve

El device plugin asigna la GPU en exclusiva a un pod. Por tanto:

- `maxReplicas: 1` en el perfil GPU. Una réplica extra se queda `Pending`.
- La concurrencia se compra vertical: `OLLAMA_NUM_PARALLEL=4`.
- El perfil CPU sí escala horizontal (`maxReplicas: 3`): los cores se reparten.

¿Para qué KEDA entonces? Por el escalado a cero. `autoscaling.scaleToZero`
libera la VRAM cuando no hay tráfico, que en una estación de trabajo es lo que
quieres para usar la GPU para otra cosa.

Está desactivado por defecto porque la petición que despierta el pool falla: el
gateway conecta antes de que exista el pod. Con `router.numRetries: 3` y
timeouts amplios se sobrevive, pero el primer usuario tras un rato de
inactividad espera 30-60 segundos.

## Consecuencias

- Escalar depende de que Prometheus esté sano. Si cae, KEDA mantiene la última
  cuenta de réplicas: fallo seguro.
- `restoreToOriginalReplicaCount: true` para que borrar el `ScaledObject` no
  deje el StatefulSet clavado.
- Ventana de bajada de 10 minutos: un model load cuesta decenas de segundos y
  hacer flapping es peor que mantener un pod caliente.
- ArgoCD ignora `/spec/replicas` (en `argocd.tf`). Sin eso, el self-heal y el
  autoescalador se pelean por el campo.
