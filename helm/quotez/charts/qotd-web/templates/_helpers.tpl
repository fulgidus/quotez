{{/*
Expand the name of the chart.
*/}}
{{- define "qotd-web.name" -}}
{{- "qotd-web" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "qotd-web.fullname" -}}
{{- printf "%s-%s" .Release.Name "qotd-web" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "qotd-web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "qotd-web.labels" -}}
helm.sh/chart: {{ include "qotd-web.chart" . }}
{{ include "qotd-web.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "qotd-web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "qotd-web.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
