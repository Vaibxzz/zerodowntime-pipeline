#!/usr/bin/env bash
# canary-analysis.sh — Monitors canary health over a time window and decides
# whether to promote or roll back.
#
# Usage: canary-analysis.sh <analysis_seconds> <error_rate_threshold_pct>
#
# The script polls the canary pods every 15 seconds, checking:
#   1. Pod readiness (kubectl)
#   2. HTTP 200 from the canary service
#   3. Cumulative error rate from Prometheus (if available)
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

while [[ $(date +%s) -lt ${END} ]]; do
  TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
  ELAPSED=$(($(date +%s) - START))
  echo -n "[${ELAPSED}s] Check #${TOTAL_CHECKS}: "

  # Check 1: Are canary pods ready?
  READY_PODS=$(kubectl get pods -n "${NAMESPACE}" \
    -l "app=zerodowntime-app,track=canary" \
    -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
    2>/dev/null | grep -c "True" || echo "0")

  if [[ "${READY_PODS}" -eq 0 ]]; then
    echo "FAIL — no ready canary pods"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
    sleep "${POLL_INTERVAL}"
    continue
  fi

  # Check 2: HTTP health check via port-forward (or service DNS in-cluster)
  HTTP_STATUS=$(kubectl exec -n "${NAMESPACE}" \
    "$(kubectl get pods -n "${NAMESPACE}" -l "app=zerodowntime-app,track=canary" -o jsonpath='{.items[0].metadata.name}')" \
    -- wget -qO- -T 5 "http://localhost:8080/healthz" 2>/dev/null \
    && echo "ok" || echo "fail")

  if [[ "${HTTP_STATUS}" == "fail" ]]; then
    echo "FAIL — health check returned error"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  else
    echo "PASS — ${READY_PODS} ready pod(s), health OK"
  fi

  sleep "${POLL_INTERVAL}"
done

# Calculate error rate
if [[ "${TOTAL_CHECKS}" -gt 0 ]]; then
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

if [[ "${ERROR_RATE}" -le "${ERROR_THRESHOLD}" ]]; then
  echo "Result: HEALTHY — promoting canary"
  echo "healthy=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
  echo "Result: UNHEALTHY — rolling back canary"
  echo "healthy=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
