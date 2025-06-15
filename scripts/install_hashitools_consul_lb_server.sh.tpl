#!/usr/bin/env bash

# enable zswap and set lz4 as the compression algorithm for maximum caching performance
echo 'GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 ipv6.disable=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg

yum -y update
# yum -y upgrade

# Install nginx and other packages directly from Amazon Linux repositories
echo "Starting nginx installation..." > ~/nginx_installation_status.txt
if yum install -y nginx amazon-cloudwatch-agent htop 2>>~/nginx_installation_status.txt; then
    echo "Nginx and packages installed successfully" >> ~/nginx_installation_status.txt
else
    echo "Failed to install nginx and packages" >> ~/nginx_installation_status.txt
fi

yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y consul consul-template htop
usermod -a -G wheel consul
sed -i 's/# %wheel/%wheel/g' /etc/sudoers

cat << EOF > /etc/consul.d/wp_lb.json
{
    "service": {
    "name": "wp-lb",
    "tags": [ "${environment_name}", "nginx", "loadbalancer" ],
    "port": 443
    },
    "checks": [
        {
            "id": "check-https",
            "name": "Listen https",
            "args": [
            "/usr/bin/curl",
            "-f",
            "-s",
            "-k",
            "https://127.0.0.1/"
            ],
            "interval": "120s"
        },
        {
            "id": "check-nginx",
            "name": "Nginx LB Service",
            "notes": "Check if nginx process is running",
            "args": [
            "/usr/bin/pgrep",
            "-x",
            "nginx"
            ],
            "interval": "120s"
        }
    ]
}
EOF

chown -R consul:consul /etc/consul.d
mkdir -p /etc/consul-template.d/
mkdir -p /usr/share/nginx/html/cache


openssl rand -base64 48 > passphrase.txt
openssl genrsa -aes128 -passout file:passphrase.txt -out server.key 2048
openssl req -new -passin file:passphrase.txt -key server.key -out server.csr \
        -subj "/C=US/O=yourorg/OU=Domain Control Validated/CN=*.yourdomain.com"
cp server.key server.key.org
openssl rsa -in server.key.org -passin file:passphrase.txt -out server.key
openssl x509 -req -days 36500 -in server.csr -signkey server.key -out server.crt
mv server.crt ssl.crt
mv server.key ssl.key
cp ssl.key /etc/ssl/certs/ssl.key
cp ssl.crt /etc/ssl/certs/ssl.crt

cat << EOF > /etc/consul-template.d/nginx-vhost.conf.ctmpl
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

# Load dynamic modules. See /usr/share/doc/nginx/README.dynamic.
include /usr/share/nginx/modules/*.conf;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    {{ \$canary := key "canary" }}
    {{ if eq \$canary "true" }}
    # Trust ALB to pass the real client IP
    set_real_ip_from 0.0.0.0/0;
    real_ip_header X-Forwarded-For;
    real_ip_recursive on;

    # Geo-based canary IP detection
    geo __IS_CANARY_IP__ {
        default 0;
        {{ key "canary_ip" }}
    }
    {{ end }}

    proxy_cache_path /usr/share/nginx/cache levels=1:2 keys_zone=wpcache:10m inactive=1h max_size=2g;
    proxy_buffers 16 32k;
    proxy_buffer_size 64k;
    proxy_connect_timeout 10s;
    proxy_read_timeout 120s;
    proxy_send_timeout 120s;
    client_max_body_size 256M;

    log_format main '[request_id: \$request_id] [\$time_local] [Cache:\$upstream_cache_status] [\$host] [Remote_Addr: \$remote_addr] - \$remote_user [\$time_local] "\$request" '
                    '\$status \$body_bytes_sent "\$http_referer" '
                    '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 4096;
    server_tokens off;
    ssl_session_cache shared:SSL:20m;
    ssl_session_timeout 10m;
    gzip on;
    gzip_proxied any;
    gzip_types text/plain text/css application/javascript application/json;
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    include /etc/nginx/conf.d/*.conf;

    {{ \$canary := key "canary" }}
    {{ if eq \$canary "true" }}
    upstream consulWebserviceCanary {
        least_conn;
        keepalive 30;
        {{ range service "wp-webserver@${peer_datacenter_name}" }}
        server {{ .Address }}:{{ .Port }} weight={{ keyOrDefault (print .Node "/numWorkers") "1" }};
        {{ end }}
    }

    upstream consulWebservice {
        least_conn;
        keepalive 30;
        {{ range service "wp-webserver@${datacenter}" }}
        server {{ .Address }}:{{ .Port }} weight={{ keyOrDefault (print .Node "/numWorkers") "1" }};
        {{ end }}
    }
    {{ else }}
    upstream consulWebservice {
        least_conn;
        keepalive 30;
        {{ range service "wp-webserver@${datacenter}" }}
        server {{ .Address }}:{{ .Port }} weight={{ keyOrDefault (print .Node "/numWorkers") "1" }};
        {{ end }}
    }
    {{ end }}

    server {
        listen 443 ssl;
        ssl_certificate /etc/ssl/certs/ssl.crt;
        ssl_certificate_key /etc/ssl/certs/ssl.key;

        proxy_cache wpcache;
        proxy_cache_background_update on;
        proxy_cache_lock on;
        proxy_cache_use_stale off;
        proxy_cache_valid 200 302 10m;
        proxy_cache_valid 404 1m;

        add_header CC-X-Request-ID \$request_id;
        add_header X-GG-Cache-Status \$upstream_cache_status;
        add_header X-GG-Cache-Date \$upstream_http_date;

        set \$backend consulWebservice;

        {{ \$canary := key "canary" }}
        {{ if eq \$canary "true" }}
        if (\$is_canary_ip = 1) {
            set \$backend consulWebserviceCanary;
        }
        {{ end }}

        location / {
            proxy_pass https://\$backend;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$host;
            proxy_ssl_verify off;
            proxy_http_version 1.1;
            proxy_set_header Connection "";
        }
    }
}
EOF

cat << EOF > /etc/consul-template.d/config.hcl
template {
  source = "/etc/consul-template.d/nginx-vhost.conf.ctmpl"
  destination = "/etc/nginx/nginx.conf"
  command = "systemctl reload nginx"
}
EOF

cat << EOF > /etc/systemd/system/consul-template.service
[Unit]
Description=consul-template
Requires=network-online.target
After=network-online.target consul.service
ConditionFileNotEmpty=/etc/consul-template.d/config.hcl

[Service]
User=consul
Group=consul
Restart=always
ExecStart=/usr/bin/sudo /usr/bin/consul-template -config=/etc/consul-template.d/config.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
KillSignal=SIGINT
PIDFile=/var/run/consul-template.pid

[Install]
WantedBy=multi-user.target
EOF

sed -i 's/__IS_CANARY_IP__/\$is_canary_ip/g' /etc/consul-template.d/nginx-vhost.conf.ctmpl

chmod -R 644 /etc/systemd/system/consul-template.service

chown -R consul:consul /etc/consul-template.d

systemctl restart consul

# Enable and start nginx with status logging
echo "Enabling and starting nginx..." >> ~/nginx_installation_status.txt
if systemctl enable nginx 2>>~/nginx_installation_status.txt; then
    echo "Nginx enabled successfully" >> ~/nginx_installation_status.txt
    if systemctl start nginx 2>>~/nginx_installation_status.txt; then
        echo "Nginx started successfully" >> ~/nginx_installation_status.txt
        echo "Nginx installation and startup completed" >> ~/nginx_installation_status.txt
    else
        echo "Failed to start nginx" >> ~/nginx_installation_status.txt
    fi
else
    echo "Failed to enable nginx" >> ~/nginx_installation_status.txt
fi

echo "Configuring system time"
timedatectl set-timezone UTC

echo "Starting deployment from AMI: ${ami}"
INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
AVAILABILITY_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
LOCAL_IPV4=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`

cat << EOF > /etc/consul.d/consul.hcl
datacenter                  = "${datacenter}"
server                      = false
data_dir                    = "/opt/consul/data"
advertise_addr              = "$${LOCAL_IPV4}"
client_addr                 = "0.0.0.0"
log_level                   = "INFO"
ui                          = true
encrypt                     = "${gossip_key}"
enable_local_script_checks  = true
# AWS cloud join
retry_join                  = ["provider=aws tag_key=Environment-Name tag_value=${environment_name}"]
EOF

# Add WAN federation configuration if peer datacenter is specified
if [ ! -z "${peer_datacenter_name}" ]; then
  cat << EOF > /etc/consul.d/wan_federation.hcl
# Enable cross-datacenter service discovery
translate_wan_addrs = true
EOF

  # Store the peer datacenter name in Consul's KV store for use in templates
  sleep 10 # Wait for Consul to start
  consul kv put peer_datacenter_name "${peer_datacenter_name}"
  
  # Note: The peer environment name for WAN federation should include the "-consul" suffix
  # This is handled in the server configuration
fi

chown -R consul:consul /etc/consul.d
chmod -R 640 /etc/consul.d/*

systemctl daemon-reload
systemctl enable consul
systemctl enable consul-template
systemctl start consul
systemctl start consul-template

cat << EOF > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json
{
        "agent": {
                "metrics_collection_interval": 60,
                "run_as_user": "root"
        },
        "logs": {
                "logs_collected": {
                        "files": {
                                "collect_list": [
                                        {
                                                "file_path": "/var/log/nginx/access.log",
                                                "log_group_name": "nginx-access.log",
                                                "log_stream_name": "{instance_id}",
                                                "retention_in_days": -1
                                        },
                                        {
                                                "file_path": "/var/log/nginx/error.log",
                                                "log_group_name": "nginx-error.log",
                                                "log_stream_name": "{instance_id}",
                                                "retention_in_days": -1
                                        }
                                ]
                        }
                }
        },
        "metrics": {
                "aggregation_dimensions": [
                        [
                                "InstanceId"
                        ]
                ],
                "metrics_collected": {
                        "disk": {
                                "measurement": [
                                        "used_percent"
                                ],
                                "metrics_collection_interval": 60,
                                "resources": [
                                        "*"
                                ]
                        },
                        "mem": {
                                "measurement": [
                                        "mem_used_percent"
                                ],
                                "metrics_collection_interval": 60
                        }
                }
        }
}
EOF

systemctl daemon-reload
systemctl enable amazon-cloudwatch-agent.service
systemctl start amazon-cloudwatch-agent.service

# Note: Monit is not available in Amazon Linux 2023 repositories
# Using systemd for service monitoring instead

cat <<EOL >> /etc/sysctl.conf
net.core.somaxconn = 4096
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_max_syn_backlog = 1280
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_timestamps = 0
fs.file-max = 70000
fs.suid_dumpable = 0
kernel.exec-shield = 1
kernel.randomize_va_space = 2
EOL

sysctl -p

cat <<EOL >> /etc/sysconfig/network
NETWORKING_IPV6=no
IPV6INIT=no
EOL

sudo sed -i '/udp6\s\+tpi_clts\s\+v\s\+inet6\s\+udp\s\+-\s\+-/ s/^/#/' /etc/netconfig
sudo sed -i '/tcp6\s\+tpi_cots_ord\s\+v\s\+inet6\s\+tcp\s\+-\s\+-/ s/^/#/' /etc/netconfig

echo "install dccp /bin/false" > /etc/modprobe.d/dccp.conf
echo "install sctp /bin/false" > /etc/modprobe.d/sctp.conf
echo "install rds /bin/false" > /etc/modprobe.d/rds.conf
echo "install tipc /bin/false" > /etc/modprobe.d/tipc.conf
echo "install cramfs /bin/false" > /etc/modprobe.d/cramfs.conf
echo "install freevxfs /bin/false" > /etc/modprobe.d/freevxfs.conf
echo "install jffs2 /bin/false" > /etc/modprobe.d/jffs2.conf
echo "install hfs /bin/false" > /etc/modprobe.d/hfs.conf
echo "install hfsplus /bin/false" > /etc/modprobe.d/hfsplus.conf
echo "install squashfs /bin/false" > /etc/modprobe.d/squashfs.conf
echo "install udf /bin/false" > /etc/modprobe.d/udf.conf

# Note: tuned is not available in Amazon Linux 2023 repositories
# Network optimizations are handled via sysctl.conf above

# systemctl reboot
