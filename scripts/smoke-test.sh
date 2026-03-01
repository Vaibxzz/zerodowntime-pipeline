#!/usr/bin/env bash
# smoke-test.sh — Run lightweight HTTP checks against the deployed service.
#
# Usage: smoke-test.sh <track>
#   track: "stable" | "canary"
#
# Exits 0 if all checks pass, 1 otherwise.

set -euo pipefail

TRACK="${1:-stable}"
NAMESPACE="${NAMESPACE:-zerodowntime}"
RETRIES=5
RETRY_DELAY=5

case "${TRACK}" in
  canary) SVC="zerodowntime-app-canary" ;;
  *)      SVC="zerodowntime-app" ;;
esac

echo "=== Smoke Tests (${TRACK}) ==="
echo "Service: ${SVC}"
echo "Namespace: ${NAMESPACE}"
echo ""

# Wait for at least one ready pod
echo "[1/4] Waiting for ready pods..."
kubectl wait --for=condition=ready pod \
  -l "app=zerodowntime-app" \
  -n "${NAMESPACE}" \
  --timeout=120s

PASS=0
FAIL=0

run_check() {
  local NAME="$1"
  local PATH="$2"
  local EXPECTED_STATUS="${3:-200}"

  for i in $(seq 1 "${RETRIES}"); do
    POD=$(kubectl get pods -n "${NAMESPACE}" -l "app=zerodowntime-app" \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    STATUS=$(kubectl exec -n "${NAMESPACE}" "${POD}" -- \
      wget -qSO /dev/null -T 5 "http://localhost:8080${PATH}" 2>&1 \
      | grep "HTTP/" | awk '{print $2}' || echo "000")

    if [[ "${STATUS}" == "${EXPECTED_STATUS}" ]]; then
      echo "  PASS: ${NAME} (${STATUS})"
      PASS=$((PASS + 1))
      return 0
    fi

    echo "  RETRY ${i}/${RETRIES}: ${NAME} got ${STATUS}, expected ${EXPECTED_STATUS}"
    sleep "${RETRY_DELAY}"
  done

  echo "  FAIL: ${NAME} — never returned ${EXPECTED_STATUS}"
  FAIL=$((FAIL + 1))
  return 1
}

echo "[2/4] Testing liveness endpoint..."
run_check "Liveness" "/healthz"

echo "[3/4] Testing readiness endpoint..."
run_check "Readiness" "/readyz"

echo "[4/4] Testing API status endpoint..."
run_check "API Status" "/api/v1/status"

echo ""
echo "=== Results ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [[ "${FAIL}" -gt 0 ]]; then
  echo "Smoke tests FAILED"
  exit 1
fi

echo "All smoke tests PASSED"
