#!/usr/bin/env bash


# System optimization and updates
echo 'GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 ipv6.disable=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg
yum -y update
yum install -y amazon-efs-utils

# MANDATORY: Install Apache and PHP (regardless of bootstrap setting)
echo "Installing Apache and PHP (mandatory)..." > ~/wp_installation_status.txt
if yum install -y httpd php php-fpm php-xml php-gd php-common php-cli php-process php-pdo php-intl php-mysqlnd php-mbstring php-soap 2>>~/wp_installation_status.txt; then
    echo "Apache and PHP installed successfully (mandatory)" >> ~/wp_installation_status.txt
    
    # Install SSL module
    if yum install -y mod_ssl 2>>~/wp_installation_status.txt; then
        echo "SSL module installed successfully (mandatory)" >> ~/wp_installation_status.txt
    else
        echo "SSL module installation failed (mandatory)" >> ~/wp_installation_status.txt
    fi
    
    # Enable and start Apache services with detailed logging
    echo "Enabling Apache and PHP-FPM services..." >> ~/wp_installation_status.txt
    if systemctl enable httpd 2>>~/wp_installation_status.txt; then
        echo "Apache (httpd) enabled successfully" >> ~/wp_installation_status.txt
        if systemctl enable php-fpm 2>>~/wp_installation_status.txt; then
            echo "PHP-FPM enabled successfully" >> ~/wp_installation_status.txt
            
            # Start services
            echo "Starting Apache and PHP-FPM services..." >> ~/wp_installation_status.txt
            if systemctl start httpd 2>>~/wp_installation_status.txt; then
                echo "Apache (httpd) started successfully" >> ~/wp_installation_status.txt
                if systemctl start php-fpm 2>>~/wp_installation_status.txt; then
                    echo "PHP-FPM started successfully" >> ~/wp_installation_status.txt
                    echo "All Apache services enabled and started successfully (mandatory)" >> ~/wp_installation_status.txt
                else
                    echo "Failed to start PHP-FPM service" >> ~/wp_installation_status.txt
                fi
            else
                echo "Failed to start Apache (httpd) service" >> ~/wp_installation_status.txt
            fi
        else
            echo "Failed to enable PHP-FPM service" >> ~/wp_installation_status.txt
        fi
    else
        echo "Failed to enable Apache (httpd) service" >> ~/wp_installation_status.txt
    fi
else
    echo "Failed to install Apache and PHP (mandatory)" >> ~/wp_installation_status.txt
fi

# EFS Mount Configuration
echo "EFS Mount: ${wp_content_mount}, Access Point: ${wp_content_efs_ap_id}" > ~/efs_status.txt
if [[ ! -z "${wp_content_mount}" ]]; then
    mkdir -p /var/www/html
    sed -i '/^fs-/d' /etc/fstab
    sleep 30  # Wait for EFS availability
    
    if mount -t efs -o tls,accesspoint=${wp_content_efs_ap_id} ${wp_content_mount}:/ /var/www/html/ 2>>~/efs_status.txt; then
        echo "EFS mounted successfully" >> ~/efs_status.txt
        echo "${wp_content_mount}:/ /var/www/html/ efs tls,accesspoint=${wp_content_efs_ap_id},_netdev 0 0" >> /etc/fstab
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

# Install additional packages for WordPress bootstrap
echo "Installing additional WordPress packages..." >> ~/wp_installation_status.txt
if yum install -y mariadb openssl wget tar 2>>~/wp_installation_status.txt; then
    echo "Additional WordPress packages installed successfully" >> ~/wp_installation_status.txt
else
    echo "Failed to install additional WordPress packages" >> ~/wp_installation_status.txt
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
        sed -i "s/database_name_here/${wp_db_name}/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/username_here/${wp_mysql_user}/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/password_here/${wp_mysql_user_pw}/g" $WORDPRESS_DIR/wp-config.php
        sed -i "s/localhost/${wp_db_host}/g" $WORDPRESS_DIR/wp-config.php
        
        # WordPress salts
        SALT=$(curl -L https://api.wordpress.org/secret-key/1.1/salt/)
        printf '%s\n' "g/put your unique phrase here/d" a "$SALT" . w | ed -s $WORDPRESS_DIR/wp-config.php
        
        # WordPress URLs
        echo "define( 'WP_HOME', 'https://${wp_hostname}' );" >> $WORDPRESS_DIR/wp-config.php
        echo "define( 'WP_SITEURL', 'https://${wp_hostname}' );" >> $WORDPRESS_DIR/wp-config.php
        
        # SSL Configuration
        mkdir -p /etc/ssl/private /etc/ssl/certs
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/wordpress.key -out /etc/ssl/certs/wordpress.crt -subj "/C=US/ST=State/L=City/O=Organization/CN=${wp_hostname}"
        
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
        mysql -h "${wp_db_host}" -u root -p"${wp_mysql_root_pw}" << EOF
CREATE DATABASE IF NOT EXISTS ${wp_db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${wp_mysql_user}'@'%' IDENTIFIED BY '${wp_mysql_user_pw}';
GRANT ALL PRIVILEGES ON ${wp_db_name}.* TO '${wp_mysql_user}'@'%';
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

# Install additional packages for non-bootstrap mode
echo "Installing additional packages (no bootstrap)..." >> ~/wp_installation_status.txt
if yum install -y mariadb openssl wget tar 2>>~/wp_installation_status.txt; then
    echo "Additional packages installed successfully (no bootstrap)" >> ~/wp_installation_status.txt
else
    echo "Failed to install additional packages (no bootstrap)" >> ~/wp_installation_status.txt
fi
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

# Consul setup with status logging
echo "Starting Consul setup..." >> ~/wp_installation_status.txt
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
if yum install -y consul 2>>~/wp_installation_status.txt; then
    echo "Consul installed successfully" >> ~/wp_installation_status.txt
    rm -rf /opt/consul/data
else
    echo "Failed to install Consul" >> ~/wp_installation_status.txt
fi

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

echo "Creating Consul configuration..." >> ~/wp_installation_status.txt
chown -R consul:consul /etc/consul.d
chmod -R 640 /etc/consul.d/*
echo "Consul configuration created successfully" >> ~/wp_installation_status.txt

# Consul startup with logging
echo "Starting Consul services..." >> ~/wp_installation_status.txt
systemctl daemon-reload

if systemctl enable consul 2>>~/wp_installation_status.txt; then
    echo "Consul enabled successfully" >> ~/wp_installation_status.txt
    
    # Wait for AWS metadata
    for i in {1..10}; do
        if curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
            echo "AWS metadata ready" >> ~/wp_installation_status.txt
            break
        fi
        sleep 2
    done
    
    # Start Consul
    if systemctl start consul 2>>~/wp_installation_status.txt; then
        echo "Consul start succeeded" >> ~/wp_installation_status.txt
        
        # Wait for Consul API
        for i in {1..15}; do
            if curl -s --max-time 3 http://127.0.0.1:8500/v1/status/leader >/dev/null 2>&1; then
                echo "Consul API ready" >> ~/wp_installation_status.txt
                sleep 3
                if consul members >/dev/null 2>&1; then
                    MEMBER_COUNT=$(consul members 2>/dev/null | wc -l)
                    echo "Consul joined cluster - $${MEMBER_COUNT} members" >> ~/wp_installation_status.txt
                    echo "Consul startup completed" >> ~/wp_installation_status.txt
                else
                    echo "Consul API ready, cluster join pending" >> ~/wp_installation_status.txt
                fi
                break
            fi
            sleep 2
        done
    else
        echo "Consul start failed - manual start required" >> ~/wp_installation_status.txt
    fi
else
    echo "Failed to enable Consul" >> ~/wp_installation_status.txt
fi
