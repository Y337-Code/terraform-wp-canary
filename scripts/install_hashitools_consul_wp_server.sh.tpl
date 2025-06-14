#!/usr/bin/env bash

# Normalize Input Variables used below
DBName="${wp_db_name}"
DBUser="${wp_mysql_user}"
DBPassword="${wp_mysql_user_pw}"
DBRootPassword="${wp_mysql_root_pw}"
DBHost="${wp_db_host}"
ENV_NAME="${environment_name}"
EFS_MOUNT="${wp_content_mount}"
EFS_AP_ID="${wp_content_efs_ap_id}"

# enable zswap and set lz4 as the compression algorithm for maximum caching performance
echo 'GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 ipv6.disable=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg

# System Updates
yum -y update
yum -y upgrade

# WordPress Bootstrap - Download and install WordPress if wp_bootstrap is true
%{ if wp_bootstrap }
echo "WordPress bootstrap enabled - installing required packages"

# Install Apache and PHP 8 with required extensions
echo "Installing Apache HTTP server"
yum install -y httpd

echo "Installing PHP 8 via Amazon Linux Extras"
amazon-linux-extras install -y php8.2

echo "Installing PHP extensions and dependencies"
yum install -y \
    php-fpm \
    php-xml \
    php-gd \
    php-common \
    php-cli \
    php-process \
    php-pdo \
    php-intl \
    php-mysqlnd \
    php-mbstring \
    php-soap \
    wget \
    tar

echo "Package installation completed - performing pre-installation checks"

# Pre-installation validation checks
WP_BOOTSTRAP_FAILED=false

# Check 1: Verify EFS is mounted at /var/www/html
if ! mountpoint -q /var/www/html/; then
    echo "EFS filesystem is not mounted at /var/www/html - WordPress installation cannot proceed" > ~/wp_bootstrap_efs_error.txt
    echo "WordPress bootstrap failed: EFS not mounted"
    WP_BOOTSTRAP_FAILED=true
fi

# Check 2: Look for existing WordPress installation (wp-config files in wp-content directory)
if [ "$WP_BOOTSTRAP_FAILED" = false ] && [ -d "/var/www/html/wp-content" ]; then
    if find /var/www/html/wp-content/ -name "*wp-config*" -type f 2>/dev/null | grep -q .; then
        echo "Existing WordPress installation detected in wp-content directory - WordPress bootstrap skipped to prevent overwrite" > ~/wp_bootstrap_existing_error.txt
        echo "WordPress bootstrap skipped: Existing installation found"
        WP_BOOTSTRAP_FAILED=true
    fi
fi

# Check 3: Also check root web directory for wp-config files
if [ "$WP_BOOTSTRAP_FAILED" = false ] && find /var/www/html/ -maxdepth 1 -name "*wp-config*" -type f 2>/dev/null | grep -q .; then
    echo "Existing WordPress installation detected in web root directory - WordPress bootstrap skipped to prevent overwrite" > ~/wp_bootstrap_existing_error.txt
    echo "WordPress bootstrap skipped: Existing installation found in web root"
    WP_BOOTSTRAP_FAILED=true
fi

# Proceed with WordPress installation only if all checks pass
if [ "$WP_BOOTSTRAP_FAILED" = false ]; then
    echo "Pre-installation checks passed - proceeding with WordPress installation"

    # Create web directory if it doesn't exist
    mkdir -p /var/www/html

    # Download latest WordPress
    cd /tmp
    wget https://wordpress.org/latest.tar.gz
    tar -xzf latest.tar.gz

    # Move WordPress files to web root
    cp -R wordpress/* /var/www/html/
    rm -rf wordpress latest.tar.gz

    # Create wp-config.php from sample
    cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php

    # Configure database settings in wp-config.php
    sed -i "s/database_name_here/$DBName/g" /var/www/html/wp-config.php
    sed -i "s/username_here/$DBUser/g" /var/www/html/wp-config.php
    sed -i "s/password_here/$DBPassword/g" /var/www/html/wp-config.php
    sed -i "s/localhost/$DBHost/g" /var/www/html/wp-config.php

    # Generate WordPress salts and keys
    SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
    STRING='put your unique phrase here'
    printf '%s\n' "g/$STRING/d" a "$SALT" . w | ed -s /var/www/html/wp-config.php

    # Set proper ownership and permissions recursively
    chown -R ec2-user:apache /var/www/html/
    find /var/www/html/ -type d -exec chmod 755 {} \;
    find /var/www/html/ -type f -exec chmod 644 {} \;

    echo "WordPress installation completed successfully"
else
    echo "WordPress bootstrap failed - continuing with server setup"
fi
%{ else }
echo "WordPress bootstrap disabled - assuming WordPress is already installed"
%{ endif }

# limits.conf Configuration
cat <<EOL >> /etc/security/limits.conf
apache       soft    nofile         65536
apache       hard    nofile         65536
apache       soft    nproc          16384
apache       hard    nproc          16384
EOL

# httpd.conf Configuration
cat <<EOL >> /etc/httpd/conf.modules.d/00-mpm.conf
<IfModule mpm_prefork_module>
    StartServers             5
    MinSpareServers          5
    MaxSpareServers         10
    ServerLimit           2000
    MaxRequestWorkers     2000
    MaxConnectionsPerChild   0
</IfModule>
EOL

# Add the parameters to /etc/sysctl.conf
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

echo "ProxyTimeout 300" >> /etc/httpd/conf/httpd.conf

total_ram=$(free -m | awk '/^Mem:/ {print $2}')
max_ram=$((total_ram * 70 / 100))

# Update PHP-FPM configuration
sed -i "s/pm.max_children = .*/pm.max_children = $calc_pm_max_children/" /etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers = .*/pm.start_servers = $calc_pm_start_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = $calc_pm_min_spare_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $calc_pm_max_spare_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_requests = .*/pm.max_requests = 300/" /etc/php-fpm.d/www.conf

# OPcache Configuration
# Define the directory to search for PHP files. Change this to your PHP files directory.
search_directory="/var/www/html"

php_file_count=$(find $search_directory -type f -name "*.php" | wc -l)
calc_max_accelerated_files=$((php_file_count + (php_file_count / 2)))
calc_memory_consumption=$((calc_max_accelerated_files / 100))

# Update OPcache configuration
cat <<EOL >> /etc/php.ini
; Existing configuration here...
; Add or update the OPcache configuration below:
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=$calc_memory_consumption
opcache.interned_strings_buffer=256
opcache.max_accelerated_files=$calc_max_accelerated_files
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.fast_shutdown=1
EOL

systemctl enable php-fpm.service

systemctl enable httpd

if [[ ! -z "$EFS_MOUNT" ]]; then
    sed -i '/^fs-/d' /etc/fstab
    mount -t efs -o tls,accesspoint=$EFS_AP_ID $EFS_MOUNT:/ /var/www/html/
    chown ec2-user:apache wp-content
    echo "$EFS_MOUNT:/ /var/www/html/ efs tls,accesspoint=$EFS_AP_ID,_netdev 0 0" >> /etc/fstab
else 
    echo "EFS Mount point not found" > ~/efs_mount_error.txt
fi

sed -i "s/'localhost'/'$DBHost'/g" /var/www/html/wp-config.php

sed -i "s/\(define( 'DB_HOST', '\)[^']*\.rds\.amazonaws\.com'/\1$DBHost'/" /var/www/html/wp-config.php

yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y consul tuned

# cleanup previous consul data so instance will join cluster
rm -rf /opt/consul/data

cat << EOF > /etc/consul.d/wp_lb.json
{
  "service": {
    "name": "wp-webserver",
    "tags": [ "${environment_name}", "WordPress", "webserver" ],
    "port": 443
    },
    "check": {
      "id": "webserver_up",
      "name": "Fetch index page from WP webserver",
      "http": "http://127.0.0.1/index.php",
      "interval": "30s",
      "timeout": "5s"
    }
}
EOF

cat << EOF > /etc/consul.d/wp_lb.json
{
    "service": {
        "name": "wp-webserver",
        "tags": [ "${environment_name}", "WordPress", "webserver" ],
        "port": 443
    },
    "check": {
        "id": "webserver_up",
        "name": "WP Service",
        "notes": "WP webserver service status",
        "args": [
            "/usr/lib64/nagios/plugins/check_procs",
            "-C",
            "httpd"
            ],
        "interval": "120s"
    }
}
EOF

chown -R consul:consul /etc/consul.d

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

sudo systemctl enable tuned
sudo tuned-adm profile network-throughput

systemctl reboot
