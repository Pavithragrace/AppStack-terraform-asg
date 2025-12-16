#!/bin/bash
set -euo pipefail

APP_DIR="/var/www/django_app"
VENV_DIR="$APP_DIR/venv"
APP_PORT="8000"
APP_USER="ubuntu"
LOG_DIR="/var/log/django"

mkdir -p "$APP_DIR" "$LOG_DIR"
chown -R "$APP_USER:$APP_USER" "$APP_DIR" "$LOG_DIR"

apt-get update -y
apt-get install -y python3 python3-pip python3-venv git unzip wget jq

# AWS CLI v2
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install

REGION="${aws_region}"
PARAM_PREFIX="${param_prefix}"
APP_REPO_URL="${app_repo_url}"
APP_REPO_REF="${app_repo_ref}"

DB_HOST=$(aws ssm get-parameter --region "$REGION" --name "$PARAM_PREFIX/db_host" --query "Parameter.Value" --output text)
DB_NAME=$(aws ssm get-parameter --region "$REGION" --name "$PARAM_PREFIX/db_name" --query "Parameter.Value" --output text)
DB_USER=$(aws ssm get-parameter --region "$REGION" --name "$PARAM_PREFIX/db_user" --query "Parameter.Value" --output text)
DB_PASSWORD=$(aws ssm get-parameter --region "$REGION" --with-decryption --name "$PARAM_PREFIX/db_password" --query "Parameter.Value" --output text)
S3_BUCKET=$(aws ssm get-parameter --region "$REGION" --name "$PARAM_PREFIX/static_bucket" --query "Parameter.Value" --output text)

# Clone app (recommended)
if [[ -n "$APP_REPO_URL" ]]; then
  sudo -u "$APP_USER" bash -lc "cd $APP_DIR && rm -rf src && git clone --depth 1 --branch $APP_REPO_REF $APP_REPO_URL src"
else
  mkdir -p "$APP_DIR/src"
fi

sudo -u "$APP_USER" bash -lc "python3 -m venv $VENV_DIR"
sudo -u "$APP_USER" bash -lc "source $VENV_DIR/bin/activate && pip install --upgrade pip wheel setuptools"

# Install deps (supports your structure: repo/app/requirements.txt)
if [[ -f "$APP_DIR/src/app/requirements.txt" ]]; then
  sudo -u "$APP_USER" bash -lc "source $VENV_DIR/bin/activate && pip install -r $APP_DIR/src/app/requirements.txt"
elif [[ -f "$APP_DIR/src/requirements.txt" ]]; then
  sudo -u "$APP_USER" bash -lc "source $VENV_DIR/bin/activate && pip install -r $APP_DIR/src/requirements.txt"
else
  sudo -u "$APP_USER" bash -lc "source $VENV_DIR/bin/activate && pip install django gunicorn psycopg2-binary boto3 django-storages"
fi

cat >/etc/django.env <<EOF
AWS_REGION=$REGION
DB_HOST=$DB_HOST
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASSWORD=$DB_PASSWORD
DB_PORT=5432
AWS_S3_BUCKET_NAME=$S3_BUCKET
DJANGO_DEBUG=false
DJANGO_SECRET_KEY=$(uuidgen)
EOF
chmod 600 /etc/django.env

# Find manage.py
if [[ -f "$APP_DIR/src/app/manage.py" ]]; then
  CODE_DIR="$APP_DIR/src/app"
else
  CODE_DIR="$APP_DIR/src"
fi

# Run migrations + collectstatic (retry DB connect)
sudo -u "$APP_USER" bash -lc "set -e; source $VENV_DIR/bin/activate; cd $CODE_DIR;
for i in {1..30}; do
  python -c 'import os, psycopg2; psycopg2.connect(host=os.environ.get("DB_HOST"), dbname=os.environ.get("DB_NAME"), user=os.environ.get("DB_USER"), password=os.environ.get("DB_PASSWORD"), port=5432).close()'     && break || true
  sleep 10
done
python manage.py migrate --noinput || true
python manage.py collectstatic --noinput || true
"

cat >/etc/systemd/system/django.service <<EOF
[Unit]
Description=Django Gunicorn Service
After=network.target

[Service]
User=$APP_USER
WorkingDirectory=$CODE_DIR
EnvironmentFile=/etc/django.env
ExecStart=$VENV_DIR/bin/gunicorn config.wsgi:application --bind 0.0.0.0:$APP_PORT --workers 2 --threads 4 --timeout 60
Restart=always
StandardOutput=append:$LOG_DIR/gunicorn.out.log
StandardError=append:$LOG_DIR/gunicorn.err.log

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable django
systemctl restart django

# CloudWatch Agent (logs)
wget -q https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -O /tmp/cw-agent.deb
dpkg -i /tmp/cw-agent.deb || true

cat >/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          { "file_path": "/var/log/django/gunicorn.out.log", "log_group_name": "/$PARAM_PREFIX/django", "log_stream_name": "{instance_id}-out" },
          { "file_path": "/var/log/django/gunicorn.err.log", "log_group_name": "/$PARAM_PREFIX/django", "log_stream_name": "{instance_id}-err" },
          { "file_path": "/var/log/syslog", "log_group_name": "/$PARAM_PREFIX/syslog", "log_stream_name": "{instance_id}" }
        ]
      }
    }
  }
}
EOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a stop || true
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || true
