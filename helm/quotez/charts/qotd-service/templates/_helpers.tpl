{{/*
Expand the name of the chart.
*/}}
{{- define "qotd-service.name" -}}
{{- "qotd-service" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "qotd-service.fullname" -}}
{{- printf "%s-%s" .Release.Name "qotd-service" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "qotd-service.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "qotd-service.labels" -}}
helm.sh/chart: {{ include "qotd-service.chart" . }}
{{ include "qotd-service.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "qotd-service.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qotd-service.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
