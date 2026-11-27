#!/bin/bash
set -euo pipefail

# 1. Ensure DOCKER-USER LAN/Tailnet isolation rules are present (e.g., after Docker restart)
if ! iptables -C DOCKER-USER -s 172.28.0.0/24 -d 192.168.0.0/16 -j DROP 2>/dev/null; then
  /usr/local/sbin/ai-lab-net-isolate.sh
fi

# 2. Ensure hermes-agent container is running (unless container was explicitly removed via `hermes-ctl down`)
if docker inspect hermes-agent >/dev/null 2>&1; then
  STATE="$(docker inspect --format '{{.State.Status}}' hermes-agent 2>/dev/null || echo unknown)"
  if [ "$STATE" != "running" ]; then
    cd /opt/ai-lab/hermes && docker compose up -d
    exit 0
  fi

  # 3. Auto-recover if Telegram got parked in DEGRADED state after a boot-time Wi-Fi outage
  LOG="/opt/ai-lab/hermes/data/logs/gateway.log"
  if [ -f "$LOG" ]; then
    LAST_LINE="$(grep -E '✓ telegram connected|✗ telegram failed to connect' "$LOG" | tail -n 1 || true)"
    if echo "$LAST_LINE" | grep -q '✗ telegram failed to connect'; then
      # Only restart if Telegram API is actually reachable right now
      if curl -sf --max-time 5 -o /dev/null https://api.telegram.org; then
        logger -t ai-lab-healthcheck "Telegram was parked after outage; restarting hermes-agent to reconnect"
        docker restart hermes-agent >/dev/null
      fi
    fi
  fi
fi
