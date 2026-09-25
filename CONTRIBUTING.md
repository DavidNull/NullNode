# Contributing to NullNode

¡Gracias por tu interés en contribuir a NullNode! Este proyecto es un laboratorio personal de LLMOps, pero las contribuciones son bienvenidas.

## Cómo Contribuir

### Reportar Bugs

Antes de reportar un bug, busca si ya existe un issue similar. Si no, crea un nuevo issue con:

- **Título:** Descripción breve del problema
- **Descripción:** Detalles del comportamiento esperado vs actual
- **Pasos para reproducir:** Pasos específicos para recrear el problema
- **Entorno:** Sistema operativo, versiones de Docker/k3d/Helm/Terraform
- **Logs:** Salida relevante de `make status`, `make smoke`, o logs específicos

### Sugerir Mejoras

Para sugerencias de nuevas características o mejoras:

- **Título:** Descripción breve de la mejora
- **Descripción:** Explica la mejora y por qué sería útil
- **Alternativas:** Menciona soluciones alternativas que has considerado
- **Impacto:** Cómo afectaría a la arquitectura existente

### Pull Requests

1. **Fork** el repositorio
2. Crea una **rama** para tu feature/fix (`feature/tu-nombre`)
3. **Commitea** tus cambios con mensajes claros
4. **Push** a tu rama
5. Crea un **Pull Request** describiendo tus cambios

### Estándar de Código

- Sigue los patrones existentes en el proyecto
- Usa **Helm** para cambios en k8s
- Usa **Terraform** para cambios en infraestructura
- **Valida** tus cambios con `make validate` antes de commitear
- **Documenta** cambios relevantes en README o docs/

### Testing

Antes de enviar un PR:

```bash
make validate    # Validación de helm, terraform, scripts
make smoke      # Test end-to-end si tienes el clúster corriendo
```

## Proceso de Revisión

Las PRs se revisarán con atención a:

- **Funcionalidad:** ¿El cambio funciona como esperado?
- **Arquitectura:** ¿Se alinea con los patrones existentes?
- **Documentación:** ¿Está documentado apropiadamente?
- **Testing:** ¿Incluye validación?

## Estilo de Comunicación

- Sé respetuoso y constructivo
- Acepta feedback de manera positiva
- Explica tus razonamientos claramente
- Pregunta si algo no está claro

## Licencia

Al contribuir, aceptas que tus contribuciones se publicen bajo la misma licencia que el proyecto.

## Contacto

Para preguntas generales, abre un issue con la etiqueta `question`.

---

**Nota:** Este es un proyecto personal de aprendizaje. Las contribuciones se manejan en el tiempo libre, así que ten paciencia con las revisiones.
