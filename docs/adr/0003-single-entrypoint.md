# 0003 - Un único punto de entrada por Ingress

**Estado:** aceptada · **Fecha:** 2026-08-26

## Contexto

La plantilla mapeaba un puerto del host por servicio (4000, 3000, 8080, 9090)
con Services `LoadBalancer`. Tres problemas: cada servicio nuevo obliga a
recrear el clúster, los puertos chocan con lo que ya tengas corriendo, y no se
parece a producción.

Encima, un parche de kustomize añadía el puerto 4000 al Service de
`argocd-server`, apuntando el gateway al sitio equivocado.

## Decisión

k3d publica solo 8080→80 y 8443→443 en el loadbalancer. Traefik (que ya viene
con k3s) enruta por host:

| Host | Componente |
| --- | --- |
| `gateway.nullnode.localhost` | LiteLLM |
| `grafana.nullnode.localhost` | Grafana |
| `prometheus.nullnode.localhost` | Prometheus |
| `argocd.nullnode.localhost` | ArgoCD |

Todos los Services internos son `ClusterIP`.

## Consecuencias

### A favor

- Añadir un componente es añadir un Ingress, sin tocar el clúster.
- Dos puertos del host en lugar de cinco.
- El mismo Ingress vale contra un clúster real cambiando el sufijo DNS.

### En contra

- Hay que resolver `*.nullnode.localhost`. Los navegadores lo hacen solos,
  `curl` con glibc no siempre: `make hosts` imprime la línea de `/etc/hosts`.
- Alternativa sin tocar `/etc/hosts`: `global.hostSuffix: 127.0.0.1.nip.io`,
  que resuelve por DNS público. No es el defecto porque en redes corporativas
  suele estar bloqueado.
