# 0005 - Flujo de secretos: Terraform genera, Secrets Manager guarda, Kubernetes consume

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

La plantilla tenía esto en `k8s/platform/litellm/values.yaml`, commiteado:

```yaml
environment:
  LITELLM_MASTER_KEY: "sk-ironnode-master-key-2024"
  LITELLM_SALT_KEY: "ironnode-salt-key-2024"
  DATABASE_URL: "postgresql://user:password@postgres..."
```

Y el mismo valor duplicado a mano en el secreto de Secrets Manager. Dos
fuentes de verdad, ninguna rotable, ambas en git.

## Decisión

Una sola dirección de flujo, sin vuelta atrás:

```bash
random_password (Terraform)
      │
      ▼
AWS Secrets Manager mockeado          ← única fuente de verdad
      │  (data source, solo lectura)
      ▼
Secret de Kubernetes                  ← creado por platform-bootstrap
      │  (secretKeyRef)
      ▼
Pod (LiteLLM / Postgres / Redis / Grafana)
```

Concretamente:

- `infra/terraform/cloud-mock/secrets.tf` genera master key, salt key y las
  contraseñas de Postgres, Redis y Grafana con `random_password`, y las guarda
  en `nullnode/platform/credentials`.
- `infra/terraform/platform-bootstrap/secrets.tf` las lee con un data source y
  crea los Secrets de Kubernetes.
- Ningún chart genera contraseñas. Todos consumen `existingSecret`.
- Las claves por departamento las acuña el Job de bootstrap en
  `nullnode/litellm/department-keys`. Terraform es dueño del secreto, no de su
  contenido (`lifecycle.ignore_changes`), para que el Job pueda rotarlas.

## Consecuencias

### A favor

- Rotar la plataforma es `terraform taint` + `apply`.
- Ni un valor con forma de credencial en el repositorio.
- Es la forma del flujo que usarías en real: en lugar del data source, External
  Secrets Operator sobre el mismo secreto. Se sustituye una pieza.

### En contra

- Los secretos están en claro en el estado local de Terraform. Aceptable en un
  lab, cubierto por `.gitignore`; en real exige backend remoto cifrado.
- Si el contenedor de LocalStack se reinicia, Terraform genera valores nuevos e
  invalida las claves de departamento repartidas.
- Los Secrets de Kubernetes son base64, no cifrado: aquí no hay etcd encryption
  at rest.
