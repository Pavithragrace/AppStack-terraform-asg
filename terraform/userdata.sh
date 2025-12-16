#!/bin/bash
APP_DIR="/var/www/django_app"
mkdir -p $APP_DIR
sudo apt update -y
sudo apt install -y python3 python3-pip python3-venv git unzip wget

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

cd $APP_DIR
python3 -m venv venv
source venv/bin/activate
pip install gunicorn

# CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i amazon-cloudwatch-agent.deb
