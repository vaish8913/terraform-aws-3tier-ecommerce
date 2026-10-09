#!/bin/bash
# app_version=${app_hash}
exec > /var/log/shop-boot.log 2>&1
set -x
dnf install -y python3-pip
useradd -r -s /sbin/nologin shop || true
mkdir -p /opt/shop/app
for i in 1 2 3 4 5; do
  aws s3 sync s3://${bucket}/app/ /opt/shop/app/ --region ${region} --delete && break
  sleep 10
done
pip3 install -r /opt/shop/app/requirements.txt

cat > /etc/shop.env <<EOF
AWS_REGION=${region}
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_SECRET_ARN=${secret_arn}
COOKIE_SECURE=${cookie_secure}
EOF
chmod 600 /etc/shop.env
chown -R shop:shop /opt/shop

# create tables + seed products (idempotent, safe if several instances boot together)
cd /opt/shop/app
set -a; . /etc/shop.env; set +a
python3 init_db.py

cat > /etc/systemd/system/shop.service <<EOF
[Unit]
Description=Shop API
After=network.target
[Service]
User=shop
WorkingDirectory=/opt/shop/app
EnvironmentFile=/etc/shop.env
ExecStart=/usr/local/bin/gunicorn --workers 2 --bind 0.0.0.0:8080 app:app
Restart=always
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now shop
