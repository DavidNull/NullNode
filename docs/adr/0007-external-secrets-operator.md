# 0007 - External Secrets Operator releva al puente de Terraform

**Estado:** aceptada · **Fecha:** 2026-09-17

## Contexto

[ADR-0005](0005-secrets-flow.md) dejó el flujo con la forma correcta pero con
una pieza de laboratorio: `platform-bootstrap` leía
`nullnode/platform/credentials` de Secrets Manager con un `data source` y creaba
los Secrets de Kubernetes con `kubernetes_secret_v1`. Un `data source` solo se
reevalúa en un `terraform apply`, así que rotar una credencial en el origen no
llegaba al clúster hasta el siguiente apply. La propia ADR-0005 lo anticipaba:

> Es la forma del flujo que usarías en real: en lugar del data source, External
> Secrets Operator sobre el mismo secreto. Se sustituye una pieza.

## Decisión

Se sustituye esa pieza. El origen (Terraform → Secrets Manager mockeado) no
cambia; cambia quién proyecta a Kubernetes:

```bash
random_password (Terraform)
      │
      ▼
AWS Secrets Manager mockeado          ← única fuente de verdad, sin cambios
      │
      ▼
External Secrets Operator             ← reconcilia cada refreshInterval
      │  (ClusterSecretStore + ExternalSecret)
      ▼
Secret de Kubernetes                  ← mismo nombre y mismas claves de antes
      │  (secretKeyRef)
      ▼
Pod (LiteLLM / Postgres / Redis / Grafana)
```

Concretamente:

- El operador es el chart `external-secrets` (`k8s/platform/values/external-secrets.yaml`),
  una `Application` más del app-of-apps en la wave -20: se instala antes que los
  datastores y el gateway, que consumen lo que sincroniza.
- El proveedor AWS de ESO no tiene campo de endpoint, así que se apunta a
  LocalStack con `AWS_SECRETSMANAGER_ENDPOINT` / `AWS_STS_ENDPOINT` en el
  controlador, la misma dirección `host.k3d.internal:4566` que usan los pods.
- `k8s/charts/external-secrets-config` tiene un `ClusterSecretStore` contra ese
  Secrets Manager y un `ExternalSecret` por credencial. Cada uno acuña
  exactamente el mismo Secret y las mismas claves que proyectaba Terraform
  (`nullnode-litellm-credentials`, `nullnode-postgres-auth`,
  `nullnode-redis-auth`, `nullnode-grafana-admin`), así que ningún chart de
  consumo cambia.
- `platform-bootstrap/secrets.tf` pierde los cinco `kubernetes_secret_v1`. Queda
  el `data source` de solo lectura, que sigue alimentando los outputs de
  conveniencia (`make key`, `make grafana-password`). Terraform ya no crea
  ningún Secret de Kubernetes.
- El Secret estático `nullnode-aws-credentials` (las claves `test`/`test` que
  LocalStack ignora) pasa de Terraform a `external-secrets-config`: lo usan tanto
  los pods para hablar con el mock como el `ClusterSecretStore` para
  autenticarse. No tiene forma de credencial y ya estaba en git en los providers.

## Consecuencias

### A favor

- Rotar deja de necesitar `terraform apply` sobre `platform-bootstrap`: se cambia
  el valor en el origen y ESO lo propaga al Secret dentro de `refreshInterval`
  (1 h). En real, el origen sería el propio Secrets Manager de AWS.
- Una sola fuente de verdad y un solo dueño del Secret. Antes Terraform escribía
  el Secret; ahora es `Owner` del `ExternalSecret`, sin que dos sistemas se
  peleen por el mismo objeto.
- Es la topología de producción: el mismo operador, el mismo tipo de
  `SecretStore`, cambiando solo el backend de auth (IRSA/rol en vez de
  `test`/`test`) y el endpoint.

### En contra

- ESO actualiza el Secret, pero un pod que lee la credencial por `env`
  (`secretKeyRef`) no la recarga hasta reiniciarse. La rotación *automática de
  extremo a extremo* pide un Reloader que reinicie el Deployment al cambiar el
  Secret; sin él, rotar sigue exigiendo un rollout. No es una regresión: hoy
  tampoco se recargaba. Queda anotado como el siguiente paso.
- El controlador tiene, por diseño, RBAC de lectura/escritura sobre `secrets`
  del clúster. kube-linter lo marca (`access-to-secrets`); es inherente al
  operador y no aplica a los charts propios, que el pipeline sí escanea.
- En una migración sobre un clúster ya existente, los Secrets que creó Terraform
  no llevan la owner-reference de ESO, así que hay que borrarlos una vez para que
  el operador los readopte. En un `make up` desde cero no se da.
- Sigue en pie lo de ADR-0005: los valores están en claro en el estado local de
  Terraform y los Secrets de Kubernetes son base64, no cifrado en etcd.
