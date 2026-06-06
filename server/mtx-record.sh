#!/bin/bash
MTX_PATH="$1"
SAFE_NAME=$(echo "$MTX_PATH" | tr '/' '_')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT="/tmp/recordings/${SAFE_NAME}_${TIMESTAMP}.mp4"

echo "[record] Starting recording: $OUTPUT"

ffmpeg -y \
  -i "rtmp://localhost:1935/${MTX_PATH}" \
  -c:v copy \
  -c:a copy \
  -f mp4 "$OUTPUT"
