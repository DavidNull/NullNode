{{- define "external-secrets-config.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "external-secrets-config.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "external-secrets-config.labels" -}}
helm.sh/chart: {{ include "external-secrets-config.chart" . }}
app.kubernetes.io/name: {{ include "external-secrets-config.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nullnode
{{- end -}}
