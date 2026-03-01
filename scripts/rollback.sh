#!/usr/bin/env bash
# rollback.sh — Tear down the canary and optionally roll back stable.
#
# Usage: rollback.sh [--full]
#   --full   Also rollback the stable deployment to its previous revision
#
# Required env vars:
#   NAMESPACE  — Kubernetes namespace (default: zerodowntime)

set -euo pipefail

NAMESPACE="${NAMESPACE:-zerodowntime}"
FULL_ROLLBACK=false
[[ "${1:-}" == "--full" ]] && FULL_ROLLBACK=true

echo "=== Canary Rollback ==="

# 1. Remove canary traffic
echo "[1/4] Setting canary traffic weight to 0%"
kubectl annotate ingress zerodowntime-app-canary \
  nginx.ingress.kubernetes.io/canary-weight="0" \
  -n "${NAMESPACE}" --overwrite 2>/dev/null || true

# 2. Scale down canary
echo "[2/4] Scaling canary deployment to 0"
kubectl scale deployment/zerodowntime-app-canary \
  --replicas=0 -n "${NAMESPACE}" 2>/dev/null || true

# 3. Wait for canary pods to terminate
echo "[3/4] Waiting for canary pods to terminate"
kubectl rollout status deployment/zerodowntime-app-canary \
  -n "${NAMESPACE}" --timeout=60s 2>/dev/null || true

# 4. Optionally roll back stable
if [[ "${FULL_ROLLBACK}" == "true" ]]; then
  echo "[4/4] Rolling back stable deployment to previous revision"
  kubectl rollout undo deployment/zerodowntime-app -n "${NAMESPACE}"
  kubectl rollout status deployment/zerodowntime-app \
    -n "${NAMESPACE}" --timeout=300s
else
  echo "[4/4] Stable deployment unchanged — canary-only rollback complete"
fi

echo ""
echo "=== Rollback Complete ==="
echo "Canary: scaled to 0, traffic weight 0%"
if [[ "${FULL_ROLLBACK}" == "true" ]]; then
  echo "Stable: rolled back to previous revision"
fi
