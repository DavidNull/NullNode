# IronNode - Enterprise LLMOps Platform Local

IronNode es una plataforma de IA Generativa 100% privada y de nivel Enterprise diseñada para ejecutarse localmente en una PC de desarrollo bajo un clúster K3s ligero gestionado con IaC y GitOps.

## 🚀 Características Principales

- **AI Gateway con LiteLLM**: Gestión de API keys, cuotas por departamento, enmascaramiento de PII y fallback
- **Caché Inteligente con Redis**: Integrado con LiteLLM para evitar cómputo redundante
- **AI Worker Pool con Ollama**: Desplegado como pods escalables en Kubernetes
- **Autoescalado con KEDA**: Basado en la longitud de cola de peticiones de la API
- **Observabilidad SRE**: OpenTelemetry + Prometheus + Grafana con métricas clave de IA (TTFT, Tokens/sec, VRAM)
- **GitOps**: ArgoCD + Helm Charts para gestión declarativa del ciclo de vida

## 📋 Requisitos Previos

- Docker
- k3d
- kubectl
- Terraform
- Helm

## 🎯 Inicio Rápido

```bash
# Clonar el repositorio
git clone <repository-url>
cd iron-node

# Ejecutar el script de despliegue
./scripts/up.sh
```

El script automáticamente:
1. Valida prerrequisitos (Docker, K3s/K3d, Terraform)
2. Provisiona la infraestructura base local y despliega ArgoCD
3. Despliega el ecosistema completo: LiteLLM Proxy, Redis, Ollama, KEDA, Prometheus y Grafana
4. Muestra los endpoints listos para usar

## 🔗 Endpoints

- **AI Gateway (LiteLLM)**: http://localhost:4000
- **Grafana Dashboard**: http://localhost:3000
- **Prometheus**: http://localhost:9090
- **ArgoCD UI**: http://localhost:8080

## 🛠️ Arquitectura

```
┌─────────────────────────────────────────────────────────────┐
│                    IronNode Platform                         │
├─────────────────────────────────────────────────────────────┤
│  User/Developer                                              │
│       │                                                      │
│       ▼                                                      │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │  ./up.sh     │───▶│  Terraform   │───▶│  K3d/K3s     │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│                                              │                │
│                                              ▼                │
│  ┌──────────────────────────────────────────────────────┐   │
│  │                  ArgoCD (GitOps)                     │   │
│  └──────────────────────────────────────────────────────┘   │
│       │              │              │              │        │
│       ▼              ▼              ▼              ▼        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ LiteLLM  │  │  Redis   │  │  Ollama  │  │  KEDA    │   │
│  │ Gateway  │  │  Cache   │  │ Workers  │  │ Scaler   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│       │              │              │              │        │
│       └──────────────┴──────────────┴──────────────┘        │
│                              │                               │
│                              ▼                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         Observability (Prometheus + Grafana)         │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Estructura del Proyecto

```
iron-node/
├── .github/workflows/    # CI/CD pipelines
├── terraform/            # IaC para infraestructura base
├── k8s/
│   ├── bootstrap/        # Configuración inicial de ArgoCD
│   └── platform/         # Helm Charts y manifiestos de aplicaciones
├── scripts/              # Scripts de automatización (up.sh, down.sh)
├── CONTEXT.md            # Documentación de arquitectura
├── AVANCES.md            # Registro de avances
└── GOTO.md               # Plan de acción
```

## 🧹 Limpieza

```bash
# Destruir toda la infraestructura
./scripts/down.sh
```

## 📚 Documentación

- [CONTEXT.md](CONTEXT.md) - Contexto y visión de arquitectura
- [AVANCES.md](AVANCES.md) - Registro de avances del proyecto
- [GOTO.md](GOTO.md) - Plan de acción y siguientes pasos

## 🤝 Contribución

Este proyecto sigue un enfoque de infraestructura como código y GitOps. Todas las contribuciones deben seguir los patrones establecidos en la documentación.

## 📄 Licencia

[License information]
