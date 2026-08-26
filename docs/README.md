# Documentación

## `context/` — contexto del proyecto

Estos cuatro ficheros son el estado del proyecto por escrito. Se commitean a
propósito: son lo que hay que leer (persona o agente) para retomar el trabajo sin
reconstruir el razonamiento desde el código.

| Fichero | Para qué |
| --- | --- |
| [CONTEXT.md](context/CONTEXT.md) | Qué es la plataforma y por qué está montada así |
| [GOTO.md](context/GOTO.md) | Qué falta, en orden |
| [AVANCES.md](context/AVANCES.md) | Qué se hizo y cuándo |
| [AUDITORIA-PLANTILLA.md](context/AUDITORIA-PLANTILLA.md) | Qué estaba roto en la versión inicial |

Al cerrar un bloque de trabajo se actualizan `AVANCES.md` y `GOTO.md`. Si la
decisión cambia la arquitectura, además va una ADR.

## `ops/` — operación

| Fichero | Para qué |
| --- | --- |
| [RUNBOOK.md](ops/RUNBOOK.md) | Diagnóstico por síntoma y por alerta |
| [VERSIONS.md](ops/VERSIONS.md) | Versiones pinneadas y cómo actualizarlas |

## `adr/` — decisiones de arquitectura

Una [ADR](adr/) por decisión que no se entiende leyendo el código. Los
comentarios del repositorio las referencian por ruta.
