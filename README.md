# Terraform WordPress Canary Project

This Terraform project deploys a WordPress infrastructure on AWS using HashiCorp Consul for service discovery and configuration management. The infrastructure includes autoscaling groups for Consul servers, WordPress application servers, and load balancer servers with caching.

## WordPress Bootstrap Feature

The project includes an optional WordPress bootstrap feature that automatically downloads and installs the latest version of WordPress when enabled.

### Enabling WordPress Bootstrap

To enable automatic WordPress installation, set the following variable in your Terraform configuration:

```hcl
wp_bootstrap = true
```

**Default**: `false` (WordPress bootstrap is disabled by default)

### Important: Preventing Race Conditions

**When using WordPress bootstrap (`wp_bootstrap = true`), it is recommended to set the WordPress Auto Scaling Group to minimum and maximum of 1 instance during initial deployment to prevent race conditions.**

Multiple WordPress instances attempting to bootstrap simultaneously can cause:

- Database initialization conflicts
- File system race conditions on shared EFS storage
- Incomplete WordPress installations
- SSL certificate generation conflicts

**Recommended configuration for bootstrap:**

```hcl
# During initial deployment with bootstrap
wp_servers_min = 1
wp_servers_max = 1
wp_bootstrap   = true
```

**After successful bootstrap, you can scale up:**

```hcl
# After WordPress is successfully installed
wp_servers_min = 2
wp_servers_max = 6
wp_bootstrap   = false  # Disable bootstrap for subsequent deployments
```

This approach ensures:

- Clean WordPress installation without conflicts
- Proper database schema creation
- Correct file permissions on shared storage
- Successful SSL certificate generation

## Troubleshooting Load Balancer (Nginx)

If the load balancer servers fail to install or start nginx properly, follow these troubleshooting steps:

### 1. Check Nginx Installation Status

The load balancer installation process creates a status file in the home directory:

```bash
# Check nginx installation status
cat ~/nginx_installation_status.txt
```

**Location**: `/home/ec2-user/nginx_installation_status.txt`
**Content**: Shows the progress of EPEL repository installation, nginx package installation, and service startup

### 2. Verify Nginx Installation and Service Status

```bash
# Check if nginx is installed
which nginx
nginx -v

# Check nginx service status
sudo systemctl status nginx
sudo systemctl is-enabled nginx
sudo systemctl is-active nginx

# Check if nginx is listening on port 443
sudo netstat -tlnp | grep :443
sudo ss -tlnp | grep :443
```

### 3. Check Nginx Configuration

```bash
# Test nginx configuration syntax
sudo nginx -t

# Check nginx configuration file
sudo cat /etc/nginx/nginx.conf

# Check if consul-template generated the config
ls -la /etc/consul-template.d/
cat /etc/consul-template.d/nginx-vhost.conf.ctmpl
```

### 4. Check SSL Certificates

```bash
# Verify SSL certificates exist
ls -la /etc/ssl/certs/ssl.crt
ls -la /etc/ssl/certs/ssl.key

# Check certificate details
sudo openssl x509 -in /etc/ssl/certs/ssl.crt -text -noout
```

### 5. Check Consul Template Service

```bash
# Check consul-template service status
sudo systemctl status consul-template
sudo journalctl -u consul-template -f

# Check if consul-template is updating nginx config
sudo tail -f /var/log/nginx/error.log
```

### 6. Manual Nginx Installation (if needed)

If the automatic installation fails, you can manually install nginx:

```bash
# Install EPEL repository
sudo yum install -y epel-release

# Update package list
sudo yum update -y

# Install nginx
sudo yum install -y nginx

# Enable and start nginx
sudo systemctl enable nginx
sudo systemctl start nginx

# Check status
sudo systemctl status nginx
```

### 7. Common Nginx Issues and Solutions

#### Issue: "amazon-linux-extras: command not found" or "Unable to find a match: epel-release"

**Solution**: This error occurs on Amazon Linux 2023 where `amazon-linux-extras` and `epel-release` are not available. The updated script now uses direct `yum install nginx` from the native Amazon Linux repositories, which is compatible with both Amazon Linux 2 and 2023.

#### Issue: Nginx fails to start

**Solution**: Check nginx configuration and logs:

```bash
sudo nginx -t
sudo journalctl -u nginx -f
sudo tail -f /var/log/nginx/error.log
```

#### Issue: SSL certificate errors

**Solution**: Regenerate SSL certificates:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/certs/ssl.key \
  -out /etc/ssl/certs/ssl.crt \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=your-domain.com"
```

#### Issue: Port 443 already in use

**Solution**: Check what's using the port and stop conflicting services:

```bash
sudo netstat -tlnp | grep :443
sudo systemctl stop httpd  # If Apache is running
sudo systemctl disable httpd
```

### 8. Useful Nginx Commands

```bash
# Reload nginx configuration
sudo systemctl reload nginx

# Restart nginx service
sudo systemctl restart nginx

# Check nginx access logs
sudo tail -f /var/log/nginx/access.log

# Check nginx error logs
sudo tail -f /var/log/nginx/error.log

# Test nginx configuration
sudo nginx -t

# Check nginx version and modules
nginx -V
```

## Troubleshooting Consul Connectivity

If Consul servers are not connecting to each other or forming a cluster, follow these troubleshooting steps:

### 1. Check Consul Service Status

```bash
# Check consul service status
sudo systemctl status consul
sudo journalctl -u consul -f

# Check if consul is running
ps aux | grep consul
```

### 2. Verify Environment Tags

The most common issue is mismatched environment tags. Consul uses AWS tags to discover other nodes.

```bash
# Check the current instance's tags
aws ec2 describe-instances --instance-ids $(curl -s http://169.254.169.254/latest/meta-data/instance-id) \
  --query 'Reservations[].Instances[].Tags[?Key==`Environment-Name`].Value' --output text

# Check what consul is looking for in its config
grep "tag_value" /etc/consul.d/consul.hcl
```

**Expected**: Both should show the same value (e.g., `wp-test-consul`)

### 3. Verify Consul Configuration

```bash
# Check consul configuration
cat /etc/consul.d/consul.hcl

# Verify gossip encryption key is set
grep "encrypt" /etc/consul.d/consul.hcl

# Check bootstrap_expect matches actual server count
grep "bootstrap_expect" /etc/consul.d/consul.hcl
```

### 4. Check AWS Discovery

```bash
# Test AWS discovery manually
aws ec2 describe-instances \
  --filters "Name=tag:Environment-Name,Values=wp-test-consul" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].[InstanceId,PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output table
```

### 5. Check Network Connectivity

```bash
# Check if consul ports are open
sudo netstat -tlnp | grep consul
sudo ss -tlnp | grep consul

# Test connectivity to other consul servers (replace IP with actual server IPs)
telnet <other-consul-server-ip> 8300
telnet <other-consul-server-ip> 8301
telnet <other-consul-server-ip> 8302
```

### 6. Check Consul Logs for Specific Errors

```bash
# Look for discovery errors
sudo journalctl -u consul | grep -i "discover-aws"

# Look for join errors
sudo journalctl -u consul | grep -i "join"

# Look for leader election issues
sudo journalctl -u consul | grep -i "leader"
```

### 7. Manual Consul Join (Emergency Fix)

If automatic discovery fails, you can manually join nodes:

```bash
# Get IP addresses of other consul servers
aws ec2 describe-instances \
  --filters "Name=tag:Environment-Name,Values=wp-test-consul" \
           "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].PrivateIpAddress' --output text

# Manually join each server (run on each consul server)
consul join <ip-of-server-1> <ip-of-server-2> <ip-of-server-3>

# Check cluster status
consul members
```

### 8. Common Consul Issues and Solutions

#### Issue: "No servers to join"

**Root Cause**: Environment-Name tag mismatch or missing tags
**Solution**: Ensure all instances have the correct `Environment-Name` tag

#### Issue: "No cluster leader"

**Root Cause**: Not enough servers for quorum or network connectivity issues
**Solution**:

- Verify `bootstrap_expect` matches actual server count
- Check network connectivity between servers
- Ensure security groups allow consul ports (8300, 8301, 8302)

#### Issue: "Encrypt key mismatch"

**Root Cause**: Different gossip encryption keys on different servers
**Solution**: Ensure all servers use the same gossip key from Terraform

#### Issue: "Permission denied" errors

**Root Cause**: Consul user permissions or file ownership issues
**Solution**:

```bash
sudo chown -R consul:consul /etc/consul.d
sudo chmod -R 640 /etc/consul.d/*
```

### 9. Restart Consul Cluster (Last Resort)

If all else fails, restart the entire consul cluster:

```bash
# On each consul server (one at a time, wait for each to rejoin)
sudo systemctl stop consul
sudo rm -rf /opt/consul/data/*
sudo systemctl start consul

# Check cluster status after each restart
consul members
```

### 10. Useful Consul Commands

```bash
# Check cluster members
consul members

# Check cluster leader
consul operator raft list-peers

# Check cluster health
consul operator autopilot get-config

# Check consul version
consul version

# Reload consul configuration
consul reload
```

## Troubleshooting WordPress Bootstrap

If WordPress bootstrap fails or doesn't work as expected, follow these troubleshooting steps:

### 1. Access Your EC2 Instance

Use AWS Systems Manager (SSM) to access your WordPress server instance:

```bash
# List available instances
aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId,Name,PingStatus]' --output table

# Connect to your WordPress server instance
aws ssm start-session --target i-1234567890abcdef0
```

**Note**: Ensure your EC2 instances have the SSM agent installed and proper IAM roles attached for SSM access.

### 2. Check Bootstrap Error Files

The bootstrap process creates error files in the home directory (`/home/ec2-user/`) when issues occur:

#### EFS Mount Issues

```bash
# Check if EFS mount failed
cat ~/wp_bootstrap_efs_error.txt
```

**Location**: `/home/ec2-user/wp_bootstrap_efs_error.txt`
**Content**: Indicates EFS filesystem is not mounted at `/var/www/html/`

#### Existing Installation Detection

```bash
# Check if existing WordPress installation was detected
cat ~/wp_bootstrap_existing_error.txt
```

**Location**: `/home/ec2-user/wp_bootstrap_existing_error.txt`
**Content**: Indicates existing WordPress files were found, preventing overwrite

#### General EFS Mount Issues

```bash
# Check general EFS mount errors
cat ~/efs_mount_error.txt
```

**Location**: `/home/ec2-user/efs_mount_error.txt`
**Content**: Indicates EFS mount point configuration issues

### 3. Verify System Status

#### Check EFS Mount Status

```bash
# Verify EFS is mounted
mountpoint /var/www/html/
df -h | grep /var/www/html

# Check EFS mount in fstab
grep efs /etc/fstab

# Check mount logs
dmesg | grep -i efs
journalctl -u efs-utils
```

#### Check Web Server Status

```bash
# Check Apache HTTP server status
sudo systemctl status httpd
sudo systemctl status php-fpm

# Check if services are enabled
sudo systemctl is-enabled httpd
sudo systemctl is-enabled php-fpm
```

#### Verify PHP Installation

```bash
# Check PHP version and modules
php -v
php -m | grep -E "(mysql|gd|xml|mbstring|soap)"

# Test PHP-FPM configuration
sudo php-fpm -t
```

### 4. Check WordPress Installation

#### Verify WordPress Files

```bash
# Check if WordPress files exist
ls -la /var/www/html/
ls -la /var/www/html/wp-config.php

# Check file ownership and permissions
ls -la /var/www/html/ | head -10
```

#### Test WordPress Functionality

Use the command-line web browser `lynx` to test WordPress:

```bash
# Install lynx if not available
sudo yum install -y lynx

# Test WordPress homepage
lynx http://localhost/
lynx http://localhost/wp-admin/

# Test specific WordPress files
lynx http://localhost/wp-config.php
lynx http://localhost/index.php
```

### 5. Check System Logs

#### Bootstrap Process Logs

```bash
# Check cloud-init logs for bootstrap process
sudo cat /var/log/cloud-init.log | grep -i wordpress
sudo cat /var/log/cloud-init-output.log | grep -i wordpress

# Check system messages
sudo journalctl -u cloud-init
sudo dmesg | grep -i error
```

#### Web Server Logs

```bash
# Check Apache error logs
sudo tail -f /var/log/httpd/error_log
sudo tail -f /var/log/httpd/access_log

# Check PHP-FPM logs
sudo tail -f /var/log/php-fpm/www-error.log
```

### 6. Manual WordPress Installation

If bootstrap fails, you can manually install WordPress:

```bash
# Ensure packages are installed
sudo yum install -y httpd php php-mysqlnd php-fpm wget tar

# Download and extract WordPress
cd /tmp
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz

# Copy to web root (ensure EFS is mounted first)
sudo cp -R wordpress/* /var/www/html/
sudo rm -rf /tmp/wordpress /tmp/latest.tar.gz

# Set proper ownership and permissions
sudo chown -R ec2-user:apache /var/www/html/
sudo find /var/www/html/ -type d -exec chmod 755 {} \;
sudo find /var/www/html/ -type f -exec chmod 644 {} \;

# Create wp-config.php
sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
```

### 7. Common Issues and Solutions

#### Issue: EFS Not Mounted

**Solution**: Check EFS configuration, security groups, and mount targets in your Terraform configuration.

#### Issue: Permission Denied Errors

**Solution**: Verify file ownership and permissions:

```bash
sudo chown -R ec2-user:apache /var/www/html/
sudo find /var/www/html/ -type d -exec chmod 755 {} \;
sudo find /var/www/html/ -type f -exec chmod 644 {} \;
```

#### Issue: PHP Extensions Missing

**Solution**: Ensure PHP 8.2 and extensions are installed:

```bash
sudo amazon-linux-extras install -y php8.2
sudo yum install -y php-fpm php-xml php-gd php-mysqlnd php-mbstring php-soap
```

#### Issue: Database Connection Errors

**Solution**: Verify database configuration in wp-config.php and ensure RDS instance is accessible.

### 8. Useful Commands

```bash
# Check all WordPress-related processes
ps aux | grep -E "(httpd|php-fpm|mysql)"

# Monitor real-time logs
sudo tail -f /var/log/httpd/error_log /var/log/php-fpm/www-error.log

# Test network connectivity
curl -I http://localhost/
wget --spider http://localhost/

# Check disk space
df -h
du -sh /var/www/html/
```

## Architecture Overview

- **Consul Servers**: Service discovery and configuration management
- **WordPress Servers**: Application servers with optional bootstrap
- **Load Balancer Servers**: Nginx load balancers
- **EFS**: Shared storage for WordPress content
- **RDS**: Database backend for WordPress

## Support

For additional support, check:

- CloudWatch logs for your EC2 instances
- AWS Systems Manager Session Manager for console access
- Terraform state files for resource status
- AWS Console for infrastructure health
