# 0003 - Single entry point via Ingress

**Status:** accepted · **Date:** 2026-08-26

## Context

The template mapped a host port per service (4000, 3000, 8080, 9090) with
`LoadBalancer` Services. Three problems: every new service requires recreating
the cluster, ports clash with whatever you're already running, and it doesn't
look like production.

On top of that, a kustomize patch added port 4000 to the `argocd-server` Service,
pointing the gateway to the wrong place.

## Decision

k3d only publishes 8080→80 and 8443→443 on the loadbalancer. Traefik (which comes
with k3s) routes by host:

| Host | Component |
| --- | --- |
| `gateway.nullnode.localhost` | LiteLLM |
| `grafana.nullnode.localhost` | Grafana |
| `prometheus.nullnode.localhost` | Prometheus |
| `argocd.nullnode.localhost` | ArgoCD |

All internal Services are `ClusterIP`.

## Consequences

### Pros

- Adding a component is adding an Ingress, no need to touch the cluster.
- Two host ports instead of five.
- The same Ingress works against a real cluster by changing the DNS suffix.

### Cons

- You need to resolve `*.nullnode.localhost`. Browsers do it on their own,
  `curl` with glibc doesn't always: `make hosts` prints the `/etc/hosts` line.
- Alternative without touching `/etc/hosts`: `global.hostSuffix: 127.0.0.1.nip.io`,
  which resolves via public DNS. Not the default because it's usually blocked in
  corporate networks.
