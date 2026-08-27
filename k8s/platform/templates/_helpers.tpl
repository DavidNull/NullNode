{{/*
ArgoCD Application for a chart in this repo.

  {{ include "nullnode.localApp" (dict "root" $ "name" "redis" "component" .Values.components.redis) }}

The child chart's values.yaml is the base; environment-specific bits come in
through valuesObject so the charts stay portable.
*/}}
{{- define "nullnode.localApp" -}}
{{- $root := .root -}}
{{- $c := .component -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: {{ $root.Values.argocd.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ $c.wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: nullnode
  source:
    repoURL: {{ $root.Values.gitops.repoURL | quote }}
    targetRevision: {{ $root.Values.gitops.targetRevision | quote }}
    path: k8s/charts/{{ $c.chart | default .name }}
    helm:
      releaseName: {{ .name }}
      valuesObject:
        global:
          {{- toYaml $root.Values.global | nindent 10 }}
        {{- with $c.values }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ $c.namespace | default $root.Values.global.namespace }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 3
{{- end -}}

{{/*
ArgoCD Application for an upstream chart. Values come from this repo via the
multi-source `$values` ref, which keeps the chart unforked.
*/}}
{{- define "nullnode.upstreamApp" -}}
{{- $root := .root -}}
{{- $c := .component -}}
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: {{ $root.Values.argocd.namespace }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ $c.wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: nullnode
  sources:
    - repoURL: {{ $c.repoURL | quote }}
      chart: {{ $c.chart | quote }}
      targetRevision: {{ $c.version | quote }}
      helm:
        releaseName: {{ .name }}
        {{- with $c.valuesFile }}
        valueFiles:
          - $values/k8s/platform/values/{{ . }}
        {{- end }}
        {{- with $c.values }}
        valuesObject:
          {{- toYaml . | nindent 10 }}
        {{- end }}
    - repoURL: {{ $root.Values.gitops.repoURL | quote }}
      targetRevision: {{ $root.Values.gitops.targetRevision | quote }}
      ref: values
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ $c.namespace | default $root.Values.global.namespace }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      {{- range $c.extraSyncOptions }}
      - {{ . }}
      {{- end }}
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
  revisionHistoryLimit: 3
{{- end -}}
