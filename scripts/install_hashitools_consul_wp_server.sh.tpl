#!/usr/bin/env bash

# System optimization
echo 'GRUB_CMDLINE_LINUX="zswap.enabled=1 zswap.compressor=lz4 ipv6.disable=1"' >> /etc/default/grub
grub2-mkconfig -o /boot/efi/EFI/amzn/grub.cfg
yum -y update && yum install -y amazon-efs-utils

# Install Apache and PHP
echo "Installing Apache/PHP..." > ~/install.log
yum install -y httpd nc php php-fpm php-xml php-gd php-common php-cli php-process php-pdo php-intl php-mysqlnd php-mbstring php-soap mod_ssl 2>>~/install.log && echo "Apache/PHP OK" >> ~/install.log || echo "Apache/PHP FAIL" >> ~/install.log

# Enable and start services
systemctl enable httpd php-fpm && systemctl start httpd php-fpm
echo "Services started" >> ~/install.log

# EFS Mount
echo "EFS: ${wp_content_mount}" >> ~/install.log
if [[ ! -z "${wp_content_mount}" ]]; then
    mkdir -p /var/www/html && sed -i '/^fs-/d' /etc/fstab && sleep 30
    if mount -t efs -o tls,accesspoint=${wp_content_efs_ap_id} ${wp_content_mount}:/ /var/www/html/ 2>>~/install.log; then
        echo "${wp_content_mount}:/ /var/www/html/ efs tls,accesspoint=${wp_content_efs_ap_id},_netdev 0 0" >> /etc/fstab
        chown ec2-user:apache /var/www/html && mkdir -p /var/www/html/wp-content && chown ec2-user:apache /var/www/html/wp-content
        echo "EFS OK" >> ~/install.log
    else
        echo "EFS FAIL" >> ~/install.log
    fi
else 
    mkdir -p /var/www/html && echo "Local storage" >> ~/install.log
fi

# Database readiness check
wait_db() {
    local max=50 wait=30 i=1
    echo "=== DATABASE CONNECTION DEBUG ===" >> ~/install.log
    echo "DB Host: ${wp_db_host}" >> ~/install.log
    echo "Aurora Master User: ${aurora_master_username}" >> ~/install.log
    echo "Aurora Master Password Length: $${#aurora_master_password}" >> ~/install.log
    echo "WordPress DB Name: ${wp_db_name}" >> ~/install.log
    echo "WordPress User: ${wp_mysql_user}" >> ~/install.log
    echo "WordPress User Password Length: $${#wp_mysql_user_pw}" >> ~/install.log
    echo "=================================" >> ~/install.log
    echo "DB check start: ${wp_db_host}" >> ~/install.log
    while [ $i -le $max ]; do
        echo "Attempting connection: mysql -h ${wp_db_host} -u ${aurora_master_username} -p[HIDDEN]" >> ~/install.log
        if timeout 10 mysql -h "${wp_db_host}" -u "${aurora_master_username}" -p"${aurora_master_password}" -e "SELECT 1;" 2>/dev/null; then
            echo "DB ready: attempt $i" >> ~/install.log
            return 0
        fi
        echo "DB wait $i/$max ($${wait}s)" >> ~/install.log
        sleep $wait
        [ $wait -lt 120 ] && wait=$((wait + 15)) || wait=120
        i=$((i + 1))
    done
    echo "DB timeout after 25min" >> ~/install.log
    return 1
}

# WordPress Bootstrap
%{ if wp_bootstrap }
echo "WP bootstrap enabled" >> ~/install.log
yum install -y mariadb105 openssl wget tar 2>>~/install.log

# Wait for database
if ! wait_db; then
    echo "DB check failed - aborting" >> ~/install.log
    exit 1
fi
echo "DB ready - proceeding" >> ~/install.log

# Check existing WordPress
WP_FAILED=false
[ -f "/var/www/html/wp-config.php" ] || [ -f "/var/www/html-local/wp-config.php" ] || [ -f "~/wordpress-backup/wp-config.php" ] && WP_FAILED=true

if [ "$WP_FAILED" = false ]; then
    # Download WordPress
    mkdir -p ~/wordpress-backup && cd /tmp
    if wget https://wordpress.org/latest.tar.gz 2>>~/install.log; then
        tar -xzf latest.tar.gz && cp -R wordpress/* ~/wordpress-backup/ && rm -rf wordpress latest.tar.gz
        echo "WP downloaded" >> ~/install.log
    else
        echo "WP download failed" >> ~/install.log
        WP_FAILED=true
    fi
    
    if [ "$WP_FAILED" = false ]; then
        # Install WordPress
        if cp -R ~/wordpress-backup/* /var/www/html/ 2>>~/install.log; then
            WORDPRESS_DIR="/var/www/html"
            echo "WP to EFS" >> ~/install.log
        else
            mkdir -p /var/www/html-local && cp -R ~/wordpress-backup/* /var/www/html-local/
            WORDPRESS_DIR="/var/www/html-local"
            sed -i "s|DocumentRoot \"/var/www/html\"|DocumentRoot \"$WORDPRESS_DIR\"|g" /etc/httpd/conf/httpd.conf
            echo "WP to local" >> ~/install.log
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
        
        # Apache SSL config
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
        
        # Database setup using Aurora master credentials
        echo "Setting up database using Aurora master credentials..." >> ~/install.log
        if mysql -h "${wp_db_host}" -u "${aurora_master_username}" -p"${aurora_master_password}" << EOF 2>>~/install.log
CREATE DATABASE IF NOT EXISTS ${wp_db_name} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${wp_mysql_user}'@'%' IDENTIFIED BY '${wp_mysql_user_pw}';
GRANT ALL PRIVILEGES ON ${wp_db_name}.* TO '${wp_mysql_user}'@'%';
FLUSH PRIVILEGES;
EOF
        then
            echo "DB setup OK" >> ~/install.log
            mysql -h "${wp_db_host}" -u "${wp_mysql_user}" -p"${wp_mysql_user_pw}" -e "SELECT 1;" 2>>~/install.log && echo "WP DB test OK" >> ~/install.log || echo "WP DB test FAIL" >> ~/install.log
        else
            echo "DB setup FAIL" >> ~/install.log
        fi
        
        # Set permissions
        chown -R ec2-user:apache $WORDPRESS_DIR/
        find $WORDPRESS_DIR/ -type d -exec chmod 755 {} \;
        find $WORDPRESS_DIR/ -type f -exec chmod 644 {} \;
        
        systemctl enable httpd && systemctl start httpd
        echo "WP install complete: $WORDPRESS_DIR" >> ~/install.log
    fi
fi
%{ else }
echo "WP bootstrap disabled" >> ~/install.log
yum install -y mariadb105 openssl wget tar 2>>~/install.log
%{ endif }

# System configuration
echo -e "apache soft nofile 65536\napache hard nofile 65536\napache soft nproc 16384\napache hard nproc 16384" >> /etc/security/limits.conf
echo -e "<IfModule mpm_prefork_module>\nStartServers 5\nMinSpareServers 5\nMaxSpareServers 10\nServerLimit 2000\nMaxRequestWorkers 2000\nMaxConnectionsPerChild 0\n</IfModule>" >> /etc/httpd/conf.modules.d/00-mpm.conf
echo -e "NETWORKING_IPV6=no\nIPV6INIT=no" >> /etc/sysconfig/network

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
echo -e "opcache.enable=1\nopcache.enable_cli=0\nopcache.memory_consumption=128\nopcache.interned_strings_buffer=256\nopcache.max_accelerated_files=4000\nopcache.validate_timestamps=1\nopcache.revalidate_freq=2\nopcache.fast_shutdown=1" >> /etc/php.ini

systemctl enable php-fpm httpd

# Consul setup
echo "Consul setup" >> ~/install.log
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum install -y consul 2>>~/install.log && echo "Consul installed" >> ~/install.log || echo "Consul install FAIL" >> ~/install.log
rm -rf /opt/consul/data

cat > /etc/consul.d/wp_lb.json << EOF
{
"service": {
"name": "wp-webserver",
"tags": [ "${environment_name}", "WordPress", "webserver" ],
"port": 443
},
"checks": [
{
"id": "apache_process",
"name": "Apache Process Check",
"args": ["/usr/bin/pgrep", "-x", "httpd"],
"interval": "30s",
"timeout": "5s"
},
{
"id": "https_port",
"name": "HTTPS Port Check",
"args": ["nc", "-z", "localhost", "443"],
"interval": "30s",
"timeout": "5s"
},
{
"id": "http_port",
"name": "HTTP Port Check", 
"args": ["nc", "-z", "localhost", "80"],
"interval": "30s",
"timeout": "5s"
}
]
}
EOF

chown -R consul:consul /etc/consul.d && timedatectl set-timezone UTC

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

# WAN federation
if [ ! -z "${peer_datacenter_name}" ]; then
    cat > /etc/consul.d/wan_federation.hcl << EOF
translate_wan_addrs = true
EOF
    sleep 10 && consul kv put peer_datacenter_name "${peer_datacenter_name}"
fi

chown -R consul:consul /etc/consul.d && chmod -R 640 /etc/consul.d/*

# Start Consul
systemctl daemon-reload && systemctl enable consul 2>>~/install.log

# Wait for AWS metadata
for i in {1..10}; do
    curl -s --max-time 3 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1 && break
    sleep 2
done

if systemctl start consul 2>>~/install.log; then
    echo "Consul started" >> ~/install.log
    # Wait for Consul API
    for i in {1..15}; do
        if curl -s --max-time 3 http://127.0.0.1:8500/v1/status/leader >/dev/null 2>&1; then
            sleep 3
            consul members >/dev/null 2>&1 && MEMBER_COUNT=$(consul members 2>/dev/null | wc -l) && echo "Consul cluster: $${MEMBER_COUNT} members" >> ~/install.log
            break
        fi
        sleep 2
    done
else
    echo "Consul start FAIL" >> ~/install.log
fi
