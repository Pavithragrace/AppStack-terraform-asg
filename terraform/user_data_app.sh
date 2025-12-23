#!/bin/bash
set -e

APP_DIR="/var/www/django_app"
VENV_DIR="$APP_DIR/venv"
APP_USER="ubuntu"
APP_PORT=8000

# ---------------------------
# Base setup
# ---------------------------
mkdir -p "$APP_DIR"
chown -R $APP_USER:$APP_USER "$APP_DIR"

apt-get update -y
apt-get install -y python3 python3-venv python3-pip git curl unzip

# ---------------------------
# Clone repo (CRITICAL FIX)
# ---------------------------
sudo -u $APP_USER bash <<EOF
cd "$APP_DIR"
rm -rf src
git clone https://github.com/pavithragrace/AppStack-terraform-asg.git src
EOF

# ---------------------------
# Detect correct code dir
# ---------------------------
if [ -f "$APP_DIR/src/app/manage.py" ]; then
  CODE_DIR="$APP_DIR/src/app"
else
  CODE_DIR="$APP_DIR/src"
fi

# ---------------------------
# Virtualenv + deps
# ---------------------------
sudo -u $APP_USER python3 -m venv "$VENV_DIR"
sudo -u $APP_USER bash <<EOF
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install django gunicorn psycopg2-binary boto3 django-storages
EOF

# ---------------------------
# systemd service (FINAL)
# ---------------------------
cat >/etc/systemd/system/django.service <<EOF
[Unit]
Description=Django Gunicorn Service
After=network.target

[Service]
User=$APP_USER
WorkingDirectory=$CODE_DIR
ExecStart=$VENV_DIR/bin/gunicorn config.wsgi:application --bind 0.0.0.0:$APP_PORT --workers 2 --threads 4
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable django
systemctl restart django
