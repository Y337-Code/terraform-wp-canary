#!/usr/bin/env bash

# Normalize Input Variables
DBName="${wp_db_name}"
DBUser="${wp_mysql_user}"
DBPassword="${wp_mysql_user_pw}"
DBRootPassword="${wp_mysql_root_pw}"
DBHost="${wp_db_host}"
ENV_NAME="${environment_name}"
EFS_MOUNT="${wp_content_mount}"
EFS_AP_ID="${wp_content_efs_ap_id}"
WP_HOSTNAME="${wp_hostname}"

# System optimization and updates
echo 'GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 ipv6.disable=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg
yum -y update
yum install -y amazon-efs-utils

# EFS Mount Configuration
echo "EFS Mount: $EFS_MOUNT, Access Point: $EFS_AP_ID" > ~/efs_status.txt
if [[ ! -z "$EFS_MOUNT" ]]; then
    mkdir -p /var/www/html
    sed -i '/^fs-/d' /etc/fstab
    sleep 30  # Wait for EFS availability
    
    if mount -t efs -o tls,accesspoint=$EFS_AP_ID $EFS_MOUNT:/ /var/www/html/ 2>>~/efs_status.txt; then
        echo "EFS mounted successfully" >> ~/efs_status.txt
        echo "$EFS_MOUNT:/ /var/www/html/ efs tls,accesspoint=$EFS_AP_ID,_netdev 0 0" >> /etc/fstab
        chown ec2-user:apache /var/www/html
        mkdir -p /var/www/html/wp-content
        chown ec2-user:apache /var/www/html/wp-content
    else
        echo "EFS mount failed - using local storage" >> ~/efs_status.txt
    fi
else 
    echo "No EFS configured - using local storage" >> ~/efs_status.txt
    mkdir -p /var/www/html
fi

# WordPress Bootstrap
%{ if wp_bootstrap }
echo "WordPress bootstrap enabled" >> ~/wp_status.txt

# Install packages for Amazon Linux 2023
echo "Starting WordPress package installation..." > ~/wp_installation_status.txt
if yum install -y httpd php php-fpm php-xml php-gd php-common php-cli php-process php-pdo php-intl php-mysqlnd php-mbstring php-soap mysql openssl wget tar 2>>~/wp_installation_status.txt; then
    echo "WordPress packages installed successfully" >> ~/wp_installation_status.txt
else
    echo "Failed to install WordPress packages" >> ~/wp_installation_status.txt
fi

# Install and configure SSL module for Amazon Linux 2023
echo "Configuring SSL module..." >> ~/wp_installation_status.txt
if yum install -y mod_ssl 2>>~/wp_installation_status.txt; then
    echo "SSL module installed successfully" >> ~/wp_installation_status.txt
else
    echo "SSL module installation failed, using built-in SSL support" >> ~/wp_installation_status.txt
fi

# Pre-installation checks
WP_FAILED=false

# Check if WordPress already exists in either location
if [ -f "/var/www/html/wp-config.php" ] || [ -f "/var/www/html-local/wp-config.php" ] || [ -f "~/wordpress-backup/wp-config.php" ]; then
    echo "WordPress already exists - skipping install" > ~/wp_bootstrap_error.txt
    WP_FAILED=true
fi

# WordPress installation
if [ "$WP_FAILED" = false ]; then
    # Always save WordPress to home directory as backup
    echo "Downloading WordPress..." >> ~/wp_installation_status.txt
    mkdir -p ~/wordpress-backup
    cd /tmp
    if wget https://wordpress.org/latest.tar.gz 2>>~/wp_installation_status.txt; then
        tar -xzf latest.tar.gz
        cp -R wordpress/* ~/wordpress-backup/
        rm -rf wordpress latest.tar.gz
        echo "WordPress backup saved to ~/wordpress-backup/" >> ~/wp_installation_status.txt
    else
        echo "WordPress download failed" >> ~/wp_installation_status.txt
        WP_FAILED=true
    fi
    
    if [ "$WP_FAILED" = false ]; then
        # Try EFS first, fallback to local storage
        if cp -R ~/wordpress-backup/* /var/www/html/ 2>>~/wp_installation_status.txt; then
            WORDPRESS_DIR="/var/www/html"
            echo "WordPress installed to EFS: $WORDPRESS_DIR" >> ~/wp_installation_status.txt
        else
            echo "EFS copy failed, using local storage" >> ~/wp_installation_status.txt
            mkdir -p /var/www/html-local
            cp -R ~/wordpress-backup/* /var/www/html-local/
            WORDPRESS_DIR="/var/www/html-local"
            echo "WordPress installed to local storage: $WORDPRESS_DIR" >> ~/wp_installation_status.txt
            
            # Update Apache DocumentRoot for local storage
            sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot \"$WORDPRESS_DIR\"|g" /etc/httpd/conf/httpd.conf
        fi
        
        # Configure WordPress
        cp $WORDPRESS_DIR/wp-config-sample.php $WORDPRESS_DIR/wp-config.php
        sed -i "s/database_name_here/$DBName/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/username_here/$DBUser/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/password_here/$DBPassword/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/localhost/$DBHost/g" $WORDPRESS_DIR/wp-config.php
        
        # WordPress salts
        SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
        printf '%s\n' "g/put your unique phrase here/d" a "$SALT" . w | ed -s $WORDPRESS_DIR/wp-config.php
        
        # WordPress URLs
        echo "define( 'WP_HOME', 'https://$WP_HOSTNAME' );" >> $WORDPRESS_DIR/wp-config.php
        echo "define( 'WP_SITEURL', 'https://$WP_HOSTNAME' );" >> $WORDPRESS_DIR/wp-config.php
        
        # SSL Configuration
        mkdir -p /etc/ssl/private /etc/ssl/certs
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/wordpress.key -out /etc/ssl/certs/wordpress.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=$WP_HOSTNAME"
        
        # Apache SSL config with dynamic DocumentRoot
        cat > /etc/httpd/conf.d/wordpress-ssl.conf << EOL
<VirtualHost *:80>
    DocumentRoot $WORDPRESS_DIR
    RewriteEngine On
    RewriteCond %%{HTTPS} off
    RewriteRule ^(.*)$ https://%%{HTTP_HOST}%%{REQUEST_URI} [R=301,L]
</VirtualHost>
<VirtualHost *:443>
    DocumentRoot $WORDPRESS_DIR
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/wordpress.crt
    SSLCertificateKeyFile /etc/ssl/private/wordpress.key
    <Directory "$WORDPRESS_DIR">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOL
        
        # Database setup
        mysql -h "$DBHost" -u root -p"$DBRootPassword" << EOF
CREATE DATABASE IF NOT EXISTS $DBName DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$DBUser'@'%' IDENTIFIED BY '$DBPassword';
GRANT ALL PRIVILEGES ON $DBName.* TO '$DBUser'@'%';
FLUSH PRIVILEGES;
EOF
        
        # Set permissions
        chown -R ec2-user:apache $WORDPRESS_DIR/
        find $WORDPRESS_DIR/ -type d -exec chmod 755 {} \;
        find $WORDPRESS_DIR/ -type f -exec chmod 644 {} \;
        
        # Enable and start Apache
        systemctl enable httpd
        systemctl start httpd
        echo "Apache enabled and started, serving from: $WORDPRESS_DIR" >> ~/wp_installation_status.txt
        
        echo "WordPress installation completed successfully" >> ~/wp_status.txt
    fi
fi
%{ else }
echo "WordPress bootstrap disabled" >> ~/wp_status.txt
%{ endif }

# System configuration
cat >> /etc/security/limits.conf << 'EOL'
apache soft nofile 65536
apache hard nofile 65536
apache soft nproc 16384
apache hard nproc 16384
EOL

cat >> /etc/httpd/conf.modules.d/00-mpm.conf << 'EOL'
<IfModule mpm_prefork_module>
    StartServers 5
    MinSpareServers 5
    MaxSpareServers 10
    ServerLimit 2000
    MaxRequestWorkers 2000
    MaxConnectionsPerChild 0
</IfModule>
EOL

# System tuning
cat >> /etc/sysctl.conf << 'EOL'
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

# Network configuration
cat >> /etc/sysconfig/network << 'EOL'
NETWORKING_IPV6=no
IPV6INIT=no
EOL

sed -i '/udp6\s\+tpi_clts\s\+v\s\+inet6\s\+udp\s\+-\s\+-/ s/^/#/' /etc/netconfig
sed -i '/tcp6\s\+tpi_cots_ord\s\+v\s\+inet6\s\+tcp\s\+-\s\+-/ s/^/#/' /etc/netconfig

# Disable unused protocols
for proto in dccp sctp rds tipc cramfs freevxfs jffs2 hfs hfsplus squashfs udf; do
    echo "install $proto /bin/false" > /etc/modprobe.d/$proto.conf
done

# PHP optimization
total_ram=$(free -m | awk '/^Mem:/ {print $2}')
max_ram=$((total_ram * 70 / 100))
calc_pm_max_children=$((max_ram / 32))
calc_pm_start_servers=$((calc_pm_max_children / 4))
calc_pm_min_spare_servers=$((calc_pm_start_servers / 2))
calc_pm_max_spare_servers=$((calc_pm_start_servers * 2))

sed -i "s/pm.max_children = .*/pm.max_children = $calc_pm_max_children/" /etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers = .*/pm.start_servers = $calc_pm_start_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = $calc_pm_min_spare_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $calc_pm_max_spare_servers/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_requests = .*/pm.max_requests = 300/" /etc/php-fpm.d/www.conf

# OPcache
php_file_count=$(find /var/www/html -name "*.php" 2>/dev/null | wc -l)
calc_max_accelerated_files=$((php_file_count + (php_file_count / 2)))
calc_memory_consumption=$((calc_max_accelerated_files / 100))

cat >> /etc/php.ini << EOL
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=$calc_memory_consumption
opcache.interned_strings_buffer=256
opcache.max_accelerated_files=$calc_max_accelerated_files
opcache.validate_timestamps=1
opcache.revalidate_freq=2
opcache.fast_shutdown=1
EOL

systemctl enable php-fpm httpd

# Update WordPress DB config if exists
if [ -f "/var/www/html/wp-config.php" ]; then
    sed -i "s/define( 'DB_HOST', '[^']*' );/define( 'DB_HOST', '$DBHost' );/g" /var/www/html/wp-config.php
    sed -i "s/define( \"DB_HOST\", \"[^\"]*\" );/define( \"DB_HOST\", \"$DBHost\" );/g" /var/www/html/wp-config.php
fi

# Consul setup
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y consul
rm -rf /opt/consul/data

cat > /etc/consul.d/wp_lb.json << EOF
{
    "service": {
        "name": "wp-webserver",
        "tags": [ "${environment_name}", "WordPress", "webserver" ],
        "port": 443
    },
    "check": {
        "id": "webserver_up",
        "name": "WP Service",
        "args": ["/usr/bin/pgrep", "-x", "httpd"],
        "interval": "120s"
    }
}
EOF

chown -R consul:consul /etc/consul.d
timedatectl set-timezone UTC

# Instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
LOCAL_IPV4=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /etc/consul.d/consul.hcl << EOF
datacenter = "${datacenter}"
server = false
data_dir = "/opt/consul/data"
advertise_addr = "$LOCAL_IPV4"
client_addr = "0.0.0.0"
log_level = "INFO"
ui = true
encrypt = "${gossip_key}"
enable_local_script_checks = true
retry_join = ["provider=aws tag_key=Environment-Name tag_value=${environment_name}"]
EOF

# WAN federation if configured
if [ ! -z "${peer_datacenter_name}" ]; then
    cat > /etc/consul.d/wan_federation.hcl << EOF
translate_wan_addrs = true
EOF
    sleep 10
    consul kv put peer_datacenter_name "${peer_datacenter_name}"
fi

chown -R consul:consul /etc/consul.d
chmod -R 640 /etc/consul.d/*

systemctl daemon-reload
systemctl enable consul
# Note: tuned is not available in Amazon Linux 2023 repositories
# Network optimizations are handled via sysctl.conf above
