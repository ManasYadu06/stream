#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${SCRIPT_DIR}/config.env"

if [ ! -f "${CONFIG}" ]; then
    echo "[stream] ERROR: config.env not found at ${CONFIG}"
    exit 1
fi

source "${CONFIG}"

if [ -z "${SERVER_IP}" ]; then
    echo "[stream] ERROR: SERVER_IP is not set in config.env"
    exit 1
fi

RTMP_URL="rtmp://${SERVER_IP}/live/${STREAM_KEY}"
echo "[stream] Starting stream to ${RTMP_URL}"

while true; do
    rpicam-vid -t 0 \
        --width ${WIDTH} \
        --height ${HEIGHT} \
        --framerate ${FRAMERATE} \
        --bitrate ${BITRATE} \
        --inline --flush -o - | \
    ffmpeg -re -i pipe:0 \
        -c:v copy \
        -g ${FRAMERATE} \
        -f flv "${RTMP_URL}"

    echo "[stream] Disconnected. Retrying in 5s..."
    sleep 5
done
