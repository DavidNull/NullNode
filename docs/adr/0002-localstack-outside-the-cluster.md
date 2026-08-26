# 0002 - LocalStack corre fuera del clúster

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

La plantilla desplegaba LocalStack como chart gestionado por ArgoCD, y a la vez
Terraform creaba el bucket y el secreto contra `http://localhost:4566`. Eso es
un interbloqueo:

1. Terraform necesita LocalStack para crear el secreto.
2. El secreto lo consume LiteLLM, que lo despliega ArgoCD.
3. ArgoCD es lo que despliega LocalStack.

Además el chart publicaba el endpoint con un `NodePort: 4566`, fuera del rango
válido de NodePort (30000-32767), así que nunca habría respondido en el puerto
que Terraform buscaba.

## Decisión

LocalStack es un contenedor Docker en el host, gestionado por Terraform con el
provider `kreuzwerker/docker`, publicado en el puerto 4566. Los pods lo
alcanzan por `http://host.k3d.internal:4566`, el nombre DNS que k3d inyecta en
CoreDNS.

El chart `k8s/platform/localstack/` se ha eliminado.

## Consecuencias

**A favor**

- Se rompe el ciclo: LocalStack → recursos AWS → clúster → plataforma.
- Los charts se configuran igual que contra AWS de verdad; solo cambia el
  endpoint.
- Sobrevive a `k3d cluster delete`.

**En contra**

- Una pieza fuera de GitOps. Compromiso consciente: es la que *simula el
  proveedor*, no parte de la plataforma.
- El puerto queda expuesto en todas las interfaces, porque los pods lo alcanzan
  por la IP del host en el bridge de Docker.
- LocalStack Community no persiste estado: si el contenedor se reinicia, bucket
  y secretos desaparecen. `make up` los recrea.
