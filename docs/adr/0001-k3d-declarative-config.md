# 0001 - El clúster se crea con el config declarativo de k3d

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

La plantilla usaba el provider `pvotal-tech/k3d`. Coherente sobre el papel: si
todo es IaC, el clúster también.

En la práctica es un provider comunitario con poco mantenimiento, va por detrás
del esquema de k3d y no cubre opciones necesarias aquí
(`options.runtime.gpuRequest`, filtros de nodo en volúmenes, registry). Es una
dependencia frágil en la capa que tiene que funcionar antes que todo lo demás.

## Decisión

El clúster se crea con `k3d cluster create --config infra/k3d/nullnode-<perfil>.yaml`.

Terraform sigue siendo el motor de IaC de todo lo demás:

- `infra/terraform/cloud-mock` → contenedor de LocalStack y recursos AWS.
- `infra/terraform/platform-bootstrap` → namespaces, secretos, ArgoCD y el
  Application raíz.

## Consecuencias

**A favor**

- El fichero de k3d es declarativo y versionado: no perdemos IaC.
- Todas las opciones de k3d disponibles, incluida la de GPU.
- Una dependencia menos en el arranque.

**En contra**

- El clúster no está en el estado de Terraform, así que `up.sh` comprueba si
  existe (`cluster_exists()`).
- Dos herramientas en el arranque en lugar de una.

## Alternativas descartadas

- **kind:** no expone GPU con la misma facilidad y perderíamos el balanceador
  que k3d monta para el Ingress.
- **`null_resource` con `local-exec`:** mete el clúster en el estado sin las
  garantías de un recurso real.
