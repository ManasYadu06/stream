#!/bin/bash
MTX_PATH="$1"
SAFE_NAME=$(echo "$MTX_PATH" | tr '/' '_')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Get latest recording for this path
FILE=$(ls -t /tmp/recordings/${SAFE_NAME}_*.mp4 2>/dev/null | head -1)

if [ -z "$FILE" ]; then
  echo "[upload] No recording found for $MTX_PATH"
  exit 1
fi

# S3 key preserves stream path + timestamp
S3_KEY="${MTX_PATH}/${TIMESTAMP}.mp4"

echo "[upload] Uploading $FILE → s3://manas-recording/$S3_KEY"
aws s3 cp "$FILE" "s3://manas-recording/$S3_KEY" --region ap-south-2

if [ $? -eq 0 ]; then
  echo "[upload] Success — removing local file"
  rm "$FILE"
else
  echo "[upload] Failed — keeping local file"
  exit 1
fi
