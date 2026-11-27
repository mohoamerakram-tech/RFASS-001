#!/bin/bash
set -euo pipefail

BACKUP_DIR="/opt/ai-lab/backups"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

STAMP="$(date +%Y-%m-%d_%H%M%S)"
ARCHIVE="$BACKUP_DIR/hermes-backup-${STAMP}.tar.gz"

tar -czf "$ARCHIVE" \
  --exclude='data/cache' \
  --exclude='data/audio_cache' \
  --exclude='data/image_cache' \
  --exclude='data/logs' \
  --exclude='data/backups' \
  -C /opt/ai-lab/hermes \
  docker-compose.yml data

chmod 600 "$ARCHIVE"

# Keep only the 7 most recent backups
ls -1t "$BACKUP_DIR"/hermes-backup-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
