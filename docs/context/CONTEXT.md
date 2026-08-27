# NullNode — contexto y visión de arquitectura

## Qué es

Una plataforma LLMOps que corre en una estación de trabajo. El objetivo no es
tener un LLM local: es tener el entorno de control que rodea a un LLM en
producción, con las mismas piezas y los mismos compromisos, en una máquina donde
romperlo no cuesta nada.

Modelos privados, gobierno vía AI Gateway, caché de prompts, autoescalado sobre
la señal correcta y observabilidad SRE de GenAI (TTFT, tokens/s, hit rate, gasto
por equipo, VRAM). Coste: 0 €, con los servicios de AWS mockeados.

## Principio de diseño

Parecerse a producción donde importa, y ser explícito donde no puede.

Lo primero: GitOps real (un `Application` raíz, el resto se reconcilia), secretos
fuera de git, un punto de entrada, versiones pinneadas, dashboards contra
métricas que existen.

Lo segundo: dejar escrito dónde el lab se desvía y por qué. LocalStack Community
no persiste, una GPU no se reparte entre pods, los secretos están en claro en el
estado de Terraform. Está en las ADRs, no escondido.

De ahí un corolario: mejor ausente y anotado que presente y no funcional. La
versión anterior declaraba seis fases completas sobre componentes que no
existían; el registro está en [AUDITORIA-PLANTILLA.md](AUDITORIA-PLANTILLA.md).

## Capas

### 1. Control y gateway — LiteLLM + Redis + PostgreSQL

Todas las peticiones entran por aquí. El gateway valida la clave virtual,
comprueba presupuesto y límites del equipo, aplica el guardrail de PII, resuelve
por caché si puede, enruta al pool si no, y registra gasto, traza, métrica y
auditoría.

Las tres piezas son inseparables:

- **Redis** no es solo caché: el router `least-busy` y los contadores de rate
  limit necesitan estado compartido entre réplicas. Sin él, cada pod decide con
  su visión parcial y los límites son incorrectos.
- **PostgreSQL** es lo que hace reales las cuotas por departamento. Equipos,
  claves y presupuestos viven ahí, sobreviven a un reinicio y se cambian por API
  sin redespliegue.

### 2. Ejecución — Ollama

StatefulSet, no Deployment: el `storageClass` local sólo da `ReadWriteOnce`, así
que cada réplica necesita su propio volumen. Los pesos se descargan en un
initContainer, de modo que `Ready` significa "ya tiene sus modelos".

### 3. Escalado — KEDA

Escala según peticiones por segundo en el gateway, no según CPU: un servidor
bloqueado esperando a la GPU puede estar al 15% de CPU y saturado.

Con una sola GPU el techo es una réplica, así que aquí KEDA vale por el escalado
a cero —liberar VRAM cuando no hay tráfico— más que por el escalado a N
([ADR-0004](../adr/0004-scaling-signal.md)).

### 4. Observabilidad — Prometheus, Grafana, OpenTelemetry, DCGM

Tres dashboards, uno por pregunta:

- **Golden Signals**: ¿está sano? Tasa, errores, TTFT, tokens/s, hit rate.
- **FinOps y gobierno**: ¿quién consume y cuánto le queda de presupuesto?
- **Inference Runtime**: ¿qué hace el pool? Réplicas, decisiones de KEDA, VRAM.

Las reglas de grabación son la única definición de cada señal, así que paneles y
alertas no pueden contradecirse. Las trazas OTLP alimentan un conector
`spanmetrics` como red de seguridad si el callback de Prometheus no está
disponible ([ADR-0006](../adr/0006-metrics-sources.md)).

### 5. GitOps — ArgoCD

Un `AppProject` y un `Application` raíz es todo lo imperativo. Ese raíz apunta a
un chart app-of-apps donde cada template es otra `Application`, ordenadas por
sync waves: CRDs y operadores, datastores, runtime de modelos, gateway,
dashboards.

Los charts de terceros no se forkean: se consumen con el patrón multi-source
`$values`, que permite versionar los values aquí sin tocar el chart.

### 6. Infraestructura — Terraform + k3d

Dos stacks con una frontera clara:

- **`cloud-mock`**: el proveedor cloud simulado. Contenedor de LocalStack más los
  recursos de S3 y Secrets Manager. Vive fuera del clúster porque el clúster no
  puede depender de algo que necesita antes de existir
  ([ADR-0002](../adr/0002-localstack-outside-the-cluster.md)).
- **`platform-bootstrap`**: namespaces, el puente de secretos, ArgoCD y el
  Application raíz.

El clúster en sí se crea con el fichero de configuración declarativo de k3d, no
con un provider de Terraform ([ADR-0001](../adr/0001-k3d-declarative-config.md)).

### 7. Cloud mockeado — LocalStack

No es decoración: de aquí sale la seguridad de la plataforma.

- **Secrets Manager** guarda las credenciales que genera Terraform y las claves
  virtuales del Job de bootstrap. Ningún chart genera contraseñas
  ([ADR-0005](../adr/0005-secrets-flow.md)).
- **S3** recibe la auditoría de cada petición (callback `s3`), con ciclo de vida
  que expira los logs a los 30 días: son la clase de objeto que crece más rápido
  y que nadie purga.

## Perfiles de hardware

`PROFILE=gpu` (por defecto) y `PROFILE=cpu` seleccionan el fichero de values y
la imagen del nodo k3d. Cambian el modelo, los recursos, la concurrencia y los
límites de escalado; el resto es idéntico.
