# RPi Live Stream + Record → S3

Stream live video from a Raspberry Pi camera to a browser via HLS, with automatic MP4 recording uploaded to AWS S3.

```
RPi 4B (imx708) → RTMP → EC2 (MediaMTX) → HLS → Browser
                               ↓
                          MP4 Recording → S3 (manas-recording)
```

---

## Hardware & Stack

| Component | Detail |
|---|---|
| RPi | Raspberry Pi 4B |
| Camera | Camera Module 3 (imx708 wide noir) |
| RPi OS | Debian GNU/Linux 13 Trixie 64-bit lite |
| Server | AWS EC2 t3.small, Ubuntu 24.04 LTS |
| Media Server | MediaMTX v1.18.2 |
| Encoder | h264_v4l2m2m (VPU hardware encoder) |
| Storage | AWS S3 (ap-south-2) |

---

## Repo Structure

```
repo/
├── README.md
├── rpi/
│   ├── stream.sh              # Stream script with reconnect loop
│   ├── config.env.example     # Config template (copy to config.env)
│   ├── .gitignore
│   └── systemd/
│       └── stream.service     # Systemd service for RPi
└── server/
    ├── mediamtx.yml           # MediaMTX config
    ├── player.html            # HLS browser player
    ├── mtx-record.sh          # Called on stream start → records MP4
    ├── mtx-upload.sh          # Called on stream stop → uploads to S3
    └── systemd/
        └── mediamtx.service   # Systemd service for EC2
```

---

## RPi Setup

### Prerequisites
- OS installed, SSH working
- Camera tested with `rpicam-hello`

### 1. System Update

```bash
sudo apt update
sudo apt full-upgrade -y
sudo apt autoremove -y && sudo apt autoclean
sudo reboot
```

### 2. Install FFmpeg

```bash
sudo apt install -y ffmpeg

# Verify hardware encoder
ffmpeg -encoders 2>/dev/null | grep h264_v4l2m2m
```

Expected:
```
V..... h264_v4l2m2m    V4L2 mem2mem H.264 encoder wrapper
```

### 3. Clone Repo

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git /home/pi/stream
cd /home/pi/stream
```

### 4. Configure

```bash
cp rpi/config.env.example rpi/config.env
nano rpi/config.env
```

Fill in your values:
```bash
SERVER_IP="YOUR_EC2_PUBLIC_IP"
STREAM_KEY="cam1"
WIDTH=1280
HEIGHT=720
FRAMERATE=25
BITRATE=2000000
```

### 5. Install Systemd Service

```bash
sudo cp rpi/systemd/stream.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable stream.service
```

### 6. Start Stream

```bash
sudo systemctl start stream.service
sudo systemctl status stream.service
```

---

## AWS Setup

### 1. S3 Bucket

```
S3 → Create bucket
Name   : manas-recording
Region : ap-south-2 (Hyderabad)
Block all public access : ON
```

### 2. IAM Role

```
IAM → Roles → Create role
Trusted entity : AWS Service → EC2
Role name      : rpi-stream-ec2-role
```

Attach inline policy `rpi-stream-s3-policy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject"
    ],
    "Resource": [
      "arn:aws:s3:::manas-recording",
      "arn:aws:s3:::manas-recording/*"
    ]
  }]
}
```

### 3. EC2 Instance

```
AMI            : Ubuntu 24.04 LTS
Instance type  : t3.small
Key pair       : create + download .pem
IAM profile    : rpi-stream-ec2-profile
Storage        : 20GB gp3
```

Security group inbound rules:

| Port | Protocol | Source | Purpose |
|---|---|---|---|
| 22 | TCP | 0.0.0.0/0 | SSH |
| 1935 | TCP | 0.0.0.0/0 | RTMP ingest |
| 8888 | TCP | 0.0.0.0/0 | HLS playback |
| 8080 | TCP | 0.0.0.0/0 | Browser player |

---

## EC2 Server Setup

SSH into your instance:
```bash
ssh -i ~/.ssh/rpi-stream-key.pem ubuntu@YOUR_EC2_IP
```

### 1. Install AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
sudo apt install -y unzip
unzip /tmp/awscliv2.zip -d /tmp/
sudo /tmp/aws/install
aws --version
```

### 2. Verify IAM Role

```bash
aws sts get-caller-identity --region ap-south-2
```

Should show `assumed-role/rpi-stream-ec2-role`.

### 3. Install FFmpeg

```bash
sudo apt update && sudo apt install -y ffmpeg
ffmpeg -version | head -n1
```

### 4. Install MediaMTX

```bash
LATEST=$(curl -s https://api.github.com/repos/bluenviron/mediamtx/releases/latest \
  | grep tag_name | cut -d'"' -f4)

curl -L "https://github.com/bluenviron/mediamtx/releases/download/${LATEST}/mediamtx_${LATEST}_linux_amd64.tar.gz" \
  -o /tmp/mediamtx.tar.gz

tar -xzf /tmp/mediamtx.tar.gz -C /tmp/
sudo mv /tmp/mediamtx /usr/local/bin/
sudo chmod +x /usr/local/bin/mediamtx
mediamtx --version
```

### 5. Deploy Server Files

```bash
# Clone repo
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git /tmp/repo

# MediaMTX config
sudo mkdir -p /etc/mediamtx
sudo cp /tmp/repo/server/mediamtx.yml /etc/mediamtx/

# Recording + upload scripts
sudo cp /tmp/repo/server/mtx-record.sh /usr/local/bin/
sudo cp /tmp/repo/server/mtx-upload.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/mtx-record.sh
sudo chmod +x /usr/local/bin/mtx-upload.sh

# Player page
sudo mkdir -p /var/www
sudo cp /tmp/repo/server/player.html /var/www/

# Recordings directory
sudo mkdir -p /tmp/recordings
sudo chmod 777 /tmp/recordings
```

### 6. Install Nginx (Player Page)

```bash
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/player << 'EOF'
server {
    listen 8080;
    root /var/www;
    index player.html;
}
EOF

sudo ln -s /etc/nginx/sites-available/player /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl restart nginx
sudo systemctl enable nginx
```

### 7. Install MediaMTX Service

```bash
sudo cp /tmp/repo/server/systemd/mediamtx.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable mediamtx
sudo systemctl start mediamtx
sudo systemctl status mediamtx
```

---

## Access URLs

| URL | Purpose |
|---|---|
| `http://YOUR_EC2_IP:8080/player.html` | Browser player |
| `http://YOUR_EC2_IP:8888/live/cam1/index.m3u8` | Raw HLS stream |
| `s3://manas-recording/live/cam1/` | Recorded MP4 files |

---

## Stream Controls (RPi)

```bash
# Start stream
sudo systemctl start stream.service

# Stop stream (triggers S3 upload)
sudo systemctl stop stream.service

# View live logs
journalctl -u stream.service -f

# Check status
sudo systemctl status stream.service
```

## Server Controls (EC2)

```bash
# Restart MediaMTX
sudo systemctl restart mediamtx

# View live logs
journalctl -u mediamtx -f

# Check recordings
ls -lh /tmp/recordings/

# Check S3
aws s3 ls s3://manas-recording/live/cam1/ --region ap-south-2
```

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Stream not connecting | Check `SERVER_IP` in `config.env`, verify port 1935 open |
| HLS 500 error | Restart MediaMTX, check `journalctl -u mediamtx` |
| Black screen in browser | Wait 10s for 7 HLS segments to buffer |
| S3 upload failing | Check IAM role attached to EC2, verify `aws sts get-caller-identity` |
| Recording filename empty | Check `$MTX_PATH` in `mtx-record.sh` logs |
| `h264_v4l2m2m` not found | Reinstall FFmpeg: `sudo apt install --reinstall ffmpeg` |

---

## Notes

- `config.env` is gitignored — never commit real `SERVER_IP` or credentials
- EC2 uses IAM role for S3 access — no access keys stored on server
- Stream auto-reconnects every 5s if dropped (handled in `stream.sh`)
- MediaMTX and stream service both auto-restart on crash via systemd
- Local MP4 is deleted after successful S3 upload to save EC2 disk space
- `/tmp/recordings/` is cleared on reboot — S3 is the permanent store
