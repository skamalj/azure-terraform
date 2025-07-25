cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-config
data:
  prometheus.yaml: |
    global:
      scrape_interval: 5s
      evaluation_interval: 30s

    scrape_configs:
      - job_name: 'vllm'
        static_configs:
          - targets: ['vllm-api:8000']
EOF
