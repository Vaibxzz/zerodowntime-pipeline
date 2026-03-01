#!/usr/bin/env bash
# canary-analysis.sh — Monitors canary health over a time window and decides
# whether to promote or roll back.
#
# Usage: canary-analysis.sh <analysis_seconds> <error_rate_threshold_pct>
#
# The script polls the canary pods every 15 seconds, checking:
#   1. Pod readiness (kubectl)
#   2. HTTP 200 from the canary service (via temporary curl pod)
#
# Outputs: sets GitHub Actions output `healthy=true|false`

set -euo pipefail

ANALYSIS_DURATION="${1:-120}"
ERROR_THRESHOLD="${2:-5}"
NAMESPACE="${NAMESPACE:-zerodowntime}"
POLL_INTERVAL=15

CANARY_SVC="zerodowntime-app-canary"
TOTAL_CHECKS=0
FAILED_CHECKS=0

echo "=== Canary Analysis ==="
echo "Duration:    ${ANALYSIS_DURATION}s"
echo "Threshold:   ${ERROR_THRESHOLD}% error rate"
echo "Poll every:  ${POLL_INTERVAL}s"
echo ""

START=$(date +%s)
END=$((START + ANALYSIS_DURATION))

while [ "$(date +%s)" -lt "${END}" ]; do
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  ELAPSED=$(($(date +%s) - START))
  printf "[%ds] Check #%d: " "${ELAPSED}" "${TOTAL_CHECKS}"

  READY_PODS=$(kubectl get pods -n "${NAMESPACE}" \
    -l "app=zerodowntime-app,track=canary" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    2>/dev/null | grep -c "True" || echo "0")

  if [ "${READY_PODS}" -eq 0 ]; then
    echo "FAIL — no ready canary pods"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    sleep "${POLL_INTERVAL}"
    continue
  fi

  HTTP_STATUS=$(kubectl run "canary-check-$(date +%s)" \
    --image=curlimages/curl:8.5.0 \
    --restart=Never \
    --rm \
    -n "${NAMESPACE}" \
    -i --quiet \
    -- -s -o /dev/null -w '%{http_code}' -m 5 \
    "http://${CANARY_SVC}.${NAMESPACE}.svc.cluster.local/healthz" 2>/dev/null || echo "000")

  if [ "${HTTP_STATUS}" = "200" ]; then
    echo "PASS — ${READY_PODS} ready pod(s), health 200"
  else
    echo "FAIL — health check returned ${HTTP_STATUS}"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi

  sleep "${POLL_INTERVAL}"
done

if [ "${TOTAL_CHECKS}" -gt 0 ]; then
  ERROR_RATE=$(( (FAILED_CHECKS * 100) / TOTAL_CHECKS ))
else
  ERROR_RATE=100
fi

echo ""
echo "=== Analysis Complete ==="
echo "Total checks: ${TOTAL_CHECKS}"
echo "Failed:       ${FAILED_CHECKS}"
echo "Error rate:   ${ERROR_RATE}%"
echo "Threshold:    ${ERROR_THRESHOLD}%"

if [ "${ERROR_RATE}" -le "${ERROR_THRESHOLD}" ]; then
  echo "Result: HEALTHY — promoting canary"
  echo "healthy=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
  echo "Result: UNHEALTHY — rolling back canary"
  echo "healthy=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
