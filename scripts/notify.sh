#!/usr/bin/env bash
# notify.sh — Send deployment notifications to Slack and optionally Discord.
#
# Usage: notify.sh "<message>" "<color: good|warning|danger>" "<image_tag>"
#
# Required env vars:
#   SLACK_WEBHOOK_URL  — Slack Incoming Webhook URL
# Optional:
#   DISCORD_WEBHOOK_URL — Discord Webhook URL
#   GITHUB_REPOSITORY   — owner/repo  (set automatically by GitHub Actions)
#   GITHUB_RUN_ID       — run id      (set automatically by GitHub Actions)
#   GITHUB_SERVER_URL   — server url  (set automatically by GitHub Actions)

set -euo pipefail

MESSAGE="${1:?Usage: notify.sh <message> <color> <tag>}"
COLOR="${2:-warning}"
TAG="${3:-unknown}"

RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0}"

# ── Slack ────────────────────────────────────────
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  PAYLOAD=$(cat <<EOF
{
  "attachments": [{
    "color": "${COLOR}",
    "blocks": [
      {
        "type": "section",
        "text": {
          "type": "mrkdwn",
          "text": "${MESSAGE}\n*Tag:* \`${TAG}\`\n*Repo:* \`${GITHUB_REPOSITORY:-unknown}\`\n<${RUN_URL}|View Run>"
        }
      }
    ]
  }]
}
EOF
)
  curl -sf -X POST "${SLACK_WEBHOOK_URL}" \
    -H 'Content-Type: application/json' \
    -d "${PAYLOAD}" \
    && echo "Slack notification sent" \
    || echo "WARNING: Slack notification failed"
else
  echo "SLACK_WEBHOOK_URL not set — skipping Slack"
fi

# ── Discord ──────────────────────────────────────
if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  case "${COLOR}" in
    good)    DISCORD_COLOR=3066993  ;; # green
    warning) DISCORD_COLOR=16776960 ;; # yellow
    danger)  DISCORD_COLOR=15158332 ;; # red
    *)       DISCORD_COLOR=3447003  ;; # blue
  esac

  DISCORD_PAYLOAD=$(cat <<EOF
{
  "embeds": [{
    "title": "Deployment Update",
    "description": "${MESSAGE}\n**Tag:** \`${TAG}\`\n**Repo:** \`${GITHUB_REPOSITORY:-unknown}\`\n[View Run](${RUN_URL})",
    "color": ${DISCORD_COLOR}
  }]
}
EOF
)
  curl -sf -X POST "${DISCORD_WEBHOOK_URL}" \
    -H 'Content-Type: application/json' \
    -d "${DISCORD_PAYLOAD}" \
    && echo "Discord notification sent" \
    || echo "WARNING: Discord notification failed"
else
  echo "DISCORD_WEBHOOK_URL not set — skipping Discord"
fi
