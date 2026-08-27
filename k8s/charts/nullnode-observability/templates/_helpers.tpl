{{- define "nullnode-observability.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "nullnode-observability.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "nullnode-observability.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "nullnode-observability.labels" -}}
helm.sh/chart: {{ include "nullnode-observability.chart" . }}
{{ include "nullnode-observability.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: nullnode
{{- end -}}

{{- define "nullnode-observability.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nullnode-observability.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* Host name for this component's Ingress, built from the injected suffix. */}}
{{- define "nullnode-observability.host" -}}
{{- printf "%s.%s" ((.Values.ingress | default dict).hostPrefix | default (include "nullnode-observability.name" .)) .Values.global.hostSuffix -}}
{{- end -}}
