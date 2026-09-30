{{/*
Chart name.
*/}}
{{- define "samba-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified name — the prefix of every object ("<fullname>-controller-manager", ...).
With release name "samba-operator" this is "samba-operator", matching upstream's kustomize
`namePrefix: samba-operator-`, so existing installs are adopted in place.
*/}}
{{- define "samba-operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 40 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 40 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 40 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "samba-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Selector labels. Kept identical to upstream's (`control-plane: controller-manager`) because a
Deployment's selector is immutable — anything else would break in-place adoption.
*/}}
{{- define "samba-operator.selectorLabels" -}}
control-plane: controller-manager
{{- end }}

{{- define "samba-operator.labels" -}}
{{ include "samba-operator.selectorLabels" . }}
helm.sh/chart: {{ include "samba-operator.chart" . }}
app.kubernetes.io/name: {{ include "samba-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "samba-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (printf "%s-controller-manager" (include "samba-operator.fullname" .)) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
image reference: repository@digest, or repository:tag.
Usage: include "samba-operator.image" (dict "image" .Values.image "default" .Chart.AppVersion)
*/}}
{{- define "samba-operator.image" -}}
{{- if .image.digest }}
{{- printf "%s@%s" .image.repository .image.digest }}
{{- else }}
{{- printf "%s:%s" .image.repository (default .default .image.tag) }}
{{- end }}
{{- end }}
