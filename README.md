# Terraform WordPress Canary Project

This Terraform project deploys a WordPress infrastructure on AWS using HashiCorp Consul for service discovery and configuration management. The infrastructure includes autoscaling groups for Consul servers, WordPress application servers, and load balancer servers.

## WordPress Bootstrap Feature

The project includes an optional WordPress bootstrap feature that automatically downloads and installs the latest version of WordPress when enabled.

### Enabling WordPress Bootstrap

To enable automatic WordPress installation, set the following variable in your Terraform configuration:

```hcl
wp_bootstrap = true
```

**Default**: `false` (WordPress bootstrap is disabled by default)

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
