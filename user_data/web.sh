#!/bin/bash
# web_version=${web_hash}
exec > /var/log/web-boot.log 2>&1
set -x
dnf install -y nginx
for i in 1 2 3 4 5; do
  aws s3 sync s3://${bucket}/web/ /usr/share/nginx/html/ --region ${region} --delete && break
  sleep 10
done
cat > /etc/nginx/nginx.conf <<'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;
events { worker_connections 1024; }
http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /var/log/nginx/access.log;
  sendfile on;
  server_tokens off;
  server {
    listen 80 default_server;
    server_name _;
    root /usr/share/nginx/html;
    index index.html;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    # /login -> login.html, /cart -> cart.html
    location / { try_files $uri $uri.html $uri/ =404; }
  }
}
EOF
systemctl enable --now nginx
