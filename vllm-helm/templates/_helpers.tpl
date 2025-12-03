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

{{- define "vllm-ray.headServiceHost" -}}
{{ printf "%s-head.%s.svc.cluster.local" (include "vllm-ray.fullname" .) .Release.Namespace }}
{{- end -}}

{{- define "vllm-ray.headCommand" -}}
set -euo pipefail
pip install ray[client]=={{ .Values.head.ray.clientVersion }} \
  && pip install ray[default]=={{ .Values.head.ray.defaultVersion }} \
  && ray start --head --port={{ .Values.head.ray.gcsPort }} --ray-client-server-port={{ .Values.head.ray.clientPort }} --block --num-cpus {{ .Values.head.ray.numCpus }}
{{- end -}}

{{- define "vllm-ray.workerCommand" -}}
set -euo pipefail
pip install ray[client]=={{ .Values.worker.ray.clientVersion }} \
  && pip install --upgrade transformers{{- if .Values.worker.transformers.version }}=={{ .Values.worker.transformers.version }}{{- end }} \
  && ray start --address={{ include "vllm-ray.headServiceHost" . }}:{{ .Values.head.ray.gcsPort }} --block --num-cpus {{ .Values.worker.ray.numCpus }}
{{- end -}}

{{- define "vllm-ray.apiCommand" -}}
{{- $pipelineSize := int (default 1 .Values.api.vllm.pipelineParallelSize) -}}
{{- $dataParallelSize := int (default 1 .Values.api.dataParallelSize) -}}
{{- $workerNodesNeeded := mul $pipelineSize $dataParallelSize -}}
{{- $requiredNodes := add $workerNodesNeeded 1 -}}
set -euo pipefail
pip install ray[client]=={{ .Values.api.ray.clientVersion }} \
  && ray start --address={{ include "vllm-ray.headServiceHost" . }}:{{ .Values.head.ray.gcsPort }} --num-cpus {{ .Values.api.ray.numCpus }} \
  && sleep 5 \
  && pip install transformers=={{ .Values.api.transformersVersion }}
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
  --host {{ .Values.api.vllm.host }} \
  --port {{ .Values.api.vllm.port }} \
  --swap-space {{ .Values.api.vllm.swapSpace }} \
  --dtype {{ .Values.api.vllm.dtype }} \
  --served-model-name {{ .Values.api.model.servedName }} \
  --distributed-executor-backend {{ .Values.api.vllm.distributedExecutorBackend }} \
{{- if .Values.api.vllm.trustRemoteCode }}
  --trust-remote-code \
{{- end }}
  --tensor-parallel-size {{ .Values.api.vllm.tensorParallelSize }} \
  --pipeline-parallel-size {{ $pipelineSize }} \
  --max-model-len {{ .Values.api.vllm.maxModelLen }} \
  --gpu-memory-utilization {{ .Values.api.vllm.gpuMemoryUtilization }} \
  --cpu-offload-gb {{ .Values.api.vllm.cpuOffloadGb }} \
  --max-num-seqs {{ .Values.api.vllm.maxNumSeqs }}
{{- end -}}
