{{- define "vllm-ray.name" -}}
{{- default .Chart.Name .Values.global.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vllm-ray.fullname" -}}
{{- if .Values.global.fullnameOverride -}}
{{- .Values.global.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.global.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "vllm-ray.labels" -}}
app.kubernetes.io/name: {{ include "vllm-ray.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end -}}

{{- define "vllm-ray.nodeSelector" -}}
{{- $component := .component -}}
{{- $defaultPool := .defaultPool -}}
{{- $nodePools := default dict .nodePools -}}
{{- $poolName := default $defaultPool $component.nodePool -}}
{{- $poolSelector := dict -}}
{{- if and $poolName (ne $poolName "") }}
  {{- with index $nodePools $poolName }}
    {{- $poolSelector = default dict .selector }}
  {{- end }}
{{- end }}
{{- $selector := default $poolSelector $component.nodeSelector -}}
{{- if $selector -}}
{{ toYaml $selector }}
{{- end -}}
{{- end -}}

{{- define "vllm-ray.headServiceHost" -}}
{{ printf "%s-head.%s.svc.cluster.local" (include "vllm-ray.fullname" .) .Release.Namespace }}
{{- end -}}

{{- define "vllm-ray.headCommand" -}}
set -euo pipefail
pip install ray[client]=={{ .Values.versions.ray.client }} \
  && pip install ray[default]=={{ .Values.versions.ray.default }} \
  && ray start --head --port={{ .Values.head.ray.gcsPort }} --ray-client-server-port={{ .Values.head.ray.clientPort }} --block --num-cpus {{ .Values.head.ray.numCpus }}
{{- end -}}

{{- define "vllm-ray.workerCommand" -}}
set -euo pipefail
pip install ray[client]=={{ .Values.versions.ray.client }} \
  && pip install --upgrade transformers=={{ .Values.versions.transformers }} \
{{- range $pkg := default (list) .Values.worker.extraPipPackages }}
  && pip install {{ quote $pkg }} \
{{- end }}
{{- range $cmd := default (list) .Values.worker.extraShellCommands }}
  && {{ $cmd }} \
{{- end }}
  && ray start --address={{ include "vllm-ray.headServiceHost" . }}:{{ .Values.head.ray.gcsPort }} --block --num-cpus {{ .Values.worker.ray.numCpus }}
{{- end -}}

{{- define "vllm-ray.apiCommand" -}}
{{- $pipelineSize := int (default 1 .Values.api.vllm.pipelineParallelSize) -}}
{{- $dataParallelSize := int (default 1 .Values.api.dataParallelSize) -}}
{{- $workerNodesNeeded := mul $pipelineSize $dataParallelSize -}}
{{- $requiredNodes := add $workerNodesNeeded 1 -}}
{{- $vllmArgs := deepCopy (default dict .Values.api.vllm) -}}
{{- $_ := set $vllmArgs "pipelineParallelSize" $pipelineSize -}}
{{- $_ := set $vllmArgs "servedModelName" .Values.api.model.servedName -}}
{{- $apiExtraPip := default (list) .Values.api.extraPipPackages -}}
{{- $apiExtraShell := default (list) .Values.api.extraShellCommands -}}
{{- $apiExtraPipLen := len $apiExtraPip -}}
{{- $apiExtraShellLen := len $apiExtraShell -}}
{{- $apiHasExtras := or (gt $apiExtraPipLen 0) (gt $apiExtraShellLen 0) -}}
set -euo pipefail
pip install ray[client]=={{ .Values.versions.ray.client }} \
  && ray start --address={{ include "vllm-ray.headServiceHost" . }}:{{ .Values.head.ray.gcsPort }} --num-cpus {{ .Values.api.ray.numCpus }} \
  && sleep 5 \
  && pip install transformers=={{ .Values.versions.transformers }}{{- if $apiHasExtras }} \{{- end }}
{{- range $i, $pkg := $apiExtraPip }}
  && pip install {{ quote $pkg }}{{- if or (lt (add $i 1) $apiExtraPipLen) (gt $apiExtraShellLen 0) }} \{{- end }}
{{- end }}
{{- range $j, $cmd := $apiExtraShell }}
  && {{ $cmd }}{{- if lt (add $j 1) $apiExtraShellLen }} \{{- end }}
{{- end }}
REQUIRED_NODES={{ $requiredNodes }}
echo "Waiting for $REQUIRED_NODES Ray nodes in cluster..."
while true; do
  NODE_COUNT=$(ray status | grep -i "node_" | wc -l);
  if [ "$NODE_COUNT" -ge "$REQUIRED_NODES" ]; then
    echo "Ray cluster has $NODE_COUNT nodes, proceeding.";
    break;
  else
    echo "Ray cluster only has $NODE_COUNT nodes, waiting...";
    sleep 10;
  fi;
done
vllm serve {{ .Values.api.model.path }} \
{{ include "vllm-ray.renderVllmArgs" (dict "values" $vllmArgs) | nindent 2 }}
{{- end -}}

{{- define "vllm-ray.renderVllmArgs" -}}
{{- $values := .values -}}
{{- $store := dict "lines" (list) -}}
{{- if $values }}
  {{- $keys := sortAlpha (keys $values) -}}
  {{- range $idx, $key := $keys }}
    {{- $value := index $values $key -}}
    {{- $kind := kindOf $value -}}
    {{- if and (ne $value nil) (not (and (eq $kind "bool") (not $value))) }}
      {{- $flag := printf "--%s" (replace "_" "-" (snakecase $key)) -}}
      {{- if eq $kind "bool" }}
        {{- $_ := set $store "lines" (append ($store.lines) (printf "  %s" $flag)) -}}
      {{- else if eq $kind "slice" }}
        {{- range $item := $value }}
          {{- if ne $item nil }}
            {{- $_ := set $store "lines" (append ($store.lines) (printf "  %s %v" $flag $item)) -}}
          {{- end }}
        {{- end }}
      {{- else if eq $kind "map" }}
        {{- $_ := set $store "lines" (append ($store.lines) (printf "  %s '%s'" $flag (toJson $value))) -}}
      {{- else }}
        {{- $_ := set $store "lines" (append ($store.lines) (printf "  %s %v" $flag $value)) -}}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- $total := len $store.lines -}}
{{- range $idx, $line := $store.lines }}
  {{- if lt (add $idx 1) $total }}
{{ printf "%s \\\n" $line }}
  {{- else }}
{{ $line }}
  {{- end }}
{{- end }}
{{- end -}}
