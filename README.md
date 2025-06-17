# Terraform WordPress Canary Project

This Terraform project deploys a WordPress infrastructure on AWS using HashiCorp Consul for service discovery and configuration management. The infrastructure includes autoscaling groups for Consul servers, WordPress application servers, and load balancer servers with caching.

## AWS Best Practices Foundation

This module is built upon the [AWS Best Practices for WordPress](https://docs.aws.amazon.com/whitepapers/latest/best-practices-wordpress/reference-architecture.html) reference architecture, providing a production-ready foundation that follows AWS recommended patterns for scalability, security, and reliability.

**Enhanced Architecture:**
This implementation extends the AWS reference architecture with advanced capabilities:

- **Service Discovery**: HashiCorp Consul enables dynamic service discovery and health checking across all components
- **Blue/Green Deployments**: Designed for seamless integration with AWS Global Accelerator for zero-downtime deployments
- **Advanced Caching**: Multi-layer caching with nginx reverse proxy and application-level optimizations
- **Performance Optimization**: Tuned for high performance under sudden and heavy traffic loads
- **Canary Deployments**: Cross-datacenter federation capabilities for gradual rollouts and A/B testing

**Key Performance Features:**

- Auto-scaling WordPress application servers with EFS shared storage
- Aurora Serverless v2 with intelligent scaling for database workloads
- Nginx load balancers with caching and SSL termination
- Consul-based health checks and automatic failover
- Optimized for burst traffic patterns and sustained high loads

This architecture maintains all AWS security and operational best practices while adding enterprise-grade deployment flexibility and performance enhancements.

## 🎉 Stable Release v0.1.0

This is a **stable release** of the Terraform WordPress Canary project.

**Release Tag**: [v0.1.0](../../releases/tag/v0.1.0)

### Key Features in v0.1.0:

- ✅ **Enhanced Database Connectivity**: 25-minute Aurora readiness check with exponential backoff
- ✅ **Comprehensive Troubleshooting**: Consolidated `~/install.log` with detailed debug information
- ✅ **Fixed Server Count Issues**: Proper variable type handling for WordPress server scaling
- ✅ **Robust Credential Management**: Separate Aurora master and WordPress application credentials
- ✅ **Production Ready**: Tested database connectivity, health checks, and installation processes
- ✅ **AWS User Data Optimization**: Scripts optimized to fit within 16KB AWS limits
- ✅ **Self-Signed Certificate Support**: Health checks compatible with self-signed SSL certificates

This version has been thoroughly tested and is recommended for production deployments.

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
**Solution**: Ensure all servers use the same gossip key from Terraform. See the [Consul Gossip Key Configuration](#consul-gossip-key-configuration) section for detailed information on generating and configuring gossip keys.

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

## Troubleshooting Consul Registration on Load Balancer Instances

If Consul is not registering properly on nginx (load balancer) instances, follow these specific troubleshooting steps:

### 1. Check Consul Installation Status

The load balancer installation process now includes Consul status logging:

```bash
# Check the installation status file
cat ~/nginx_installation_status.txt

# Look for Consul-specific entries
grep -i consul ~/nginx_installation_status.txt
```

**Expected entries**:

- "Starting Consul services..."
- "Consul enabled successfully"
- "Consul started successfully"
- "Consul is ready after X seconds"
- "All Consul services started successfully"

### 2. Verify Consul Service Status

```bash
# Check consul service status
sudo systemctl status consul
sudo systemctl status consul-template

# Check if consul is running and listening
sudo netstat -tlnp | grep consul
ps aux | grep consul
```

### 3. Check Consul Configuration Files

```bash
# Verify main consul configuration exists
cat /etc/consul.d/consul.hcl

# Check service definition
cat /etc/consul.d/wp_lb.json

# Verify file ownership
ls -la /etc/consul.d/
```

### 4. Test Consul API Connectivity

```bash
# Check if Consul API is responding
curl -s http://127.0.0.1:8500/v1/status/leader

# Check cluster members from load balancer
curl -s http://127.0.0.1:8500/v1/catalog/nodes

# Check if load balancer service is registered
curl -s http://127.0.0.1:8500/v1/catalog/service/wp-lb
```

### 5. Common Load Balancer Consul Issues

#### Issue: Consul starts but doesn't join cluster

**Root Cause**: Service startup sequence or configuration timing
**Solution**: Check the startup logs and verify Environment-Name tags

```bash
# Check consul logs for join attempts
sudo journalctl -u consul | grep -i join

# Verify environment tags match
grep "tag_value" /etc/consul.d/consul.hcl
```

#### Issue: Consul-template fails to start

**Root Cause**: Consul not ready when consul-template starts
**Solution**: The updated script now waits for Consul to be ready

```bash
# Check consul-template logs
sudo journalctl -u consul-template

# Verify consul-template configuration
cat /etc/consul-template.d/config.hcl
```

#### Issue: Service registration missing

**Root Cause**: Service definition file issues or permissions
**Solution**: Verify service definition and restart consul

```bash
# Check service definition syntax
cat /etc/consul.d/wp_lb.json

# Verify file permissions
ls -la /etc/consul.d/wp_lb.json

# Restart consul to reload services
sudo systemctl restart consul
```

### 6. Manual Consul Registration (Emergency Fix)

If automatic registration fails, you can manually register the service:

```bash
# Register load balancer service manually
curl -X PUT http://127.0.0.1:8500/v1/agent/service/register \
  -d '{
    "ID": "wp-lb",
    "Name": "wp-lb",
    "Tags": ["nginx", "loadbalancer"],
    "Port": 443,
    "Check": {
      "HTTP": "https://127.0.0.1/",
      "Interval": "120s"
    }
  }'

# Verify registration
curl -s http://127.0.0.1:8500/v1/agent/services
```

### 7. Restart Consul Services (Load Balancer)

If services are in a failed state, restart them in the correct order:

```bash
# Stop services
sudo systemctl stop consul-template
sudo systemctl stop consul

# Clear any stale data
sudo rm -rf /opt/consul/data/*

# Start services in correct order
sudo systemctl start consul

# Wait for consul to be ready
sleep 10

# Start consul-template
sudo systemctl start consul-template

# Check status
sudo systemctl status consul consul-template
```

## Troubleshooting Database Connectivity

The WordPress installation includes an advanced database readiness check that waits for Aurora Serverless to become fully operational before proceeding with WordPress installation.

### 1. Understanding the Database Readiness Check

The system implements a robust database connectivity check with the following features:

- **25-minute maximum timeout** (50 attempts with exponential backoff)
- **Exponential backoff**: Starts at 30 seconds, increases by 15 seconds each attempt, caps at 120 seconds
- **Aurora master credentials**: Uses Aurora admin credentials for initial connectivity testing
- **Comprehensive debug logging**: Detailed connection information in `~/install.log`

### 2. Check Database Connectivity Status

Access your WordPress server instance and check the installation log:

```bash
# Check the main installation log
cat ~/install.log

# Look specifically for database connectivity information
grep -A 20 "DATABASE CONNECTION DEBUG" ~/install.log

# Monitor database connectivity attempts in real-time
tail -f ~/install.log | grep -E "(DB|database)"
```

### 3. Understanding Database Debug Output

The database readiness check provides detailed debug information:

```bash
=== DATABASE CONNECTION DEBUG ===
DB Host: wp-test-cluster-default.cluster-cr6yw4qs8p1s.us-east-1.rds.amazonaws.com
Aurora Master User: wpdbadmin
Aurora Master Password Length: 12
WordPress DB Name: wordpress
WordPress User: wpuser
WordPress User Password Length: 13
DB check start: wp-test-cluster-default.cluster-cr6yw4qs8p1s.us-east-1.rds.amazonaws.com
Attempting connection: mysql -h wp-test-cluster-default.cluster-cr6yw4qs8p1s.us-east-1.rds.amazonaws.com -u wpdbadmin -p[HIDDEN]
DB wait 1/50 (30s)
DB wait 2/50 (45s)
DB wait 3/50 (60s)
...
DB ready: attempt 15
```

**Key Information**:

- **DB Host**: Aurora cluster endpoint
- **Aurora Master User**: Admin username for initial connection (e.g., `wpdbadmin`)
- **Password Length**: Confirms credentials are being passed (without exposing actual passwords)
- **WordPress DB Name**: Database name that will be created
- **WordPress User**: Application user that will be created for WordPress
- **Connection Attempts**: Shows each retry with increasing wait times

### 4. Manual Database Connectivity Testing

If the automatic check fails, you can manually test database connectivity:

```bash
# Test Aurora master credentials (replace with your actual values)
mysql -h your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com -u wpdbadmin -p

# Check if Aurora is accepting connections
telnet your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306

# Test from within the VPC (Aurora is not publicly accessible)
nc -zv your-aurora-endpoint.cluster-xxxxx.us-east-1.rds.amazonaws.com 3306
```

### 5. Common Database Connectivity Issues

#### Issue: "Unknown MySQL server host" Error

**Root Cause**: Aurora Serverless is still starting up (can take 5-20 minutes)
**Solution**: The system automatically waits up to 25 minutes. Check Aurora status in AWS Console.

```bash
# Check Aurora cluster status
aws rds describe-db-clusters --db-cluster-identifier your-cluster-name

# Monitor the readiness check progress
tail -f ~/install.log | grep "DB wait"
```

#### Issue: "Access denied" Error

**Root Cause**: Credential mismatch between Aurora master credentials and script configuration
**Solution**: Verify Aurora master credentials match Terraform configuration

```bash
# Check what credentials the script is using
grep -A 10 "DATABASE CONNECTION DEBUG" ~/install.log

# Verify Aurora master username in AWS Console
aws rds describe-db-clusters --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].MasterUsername'
```

#### Issue: Database Timeout After 25 Minutes

**Root Cause**: Aurora Serverless taking longer than expected or configuration issue
**Solution**: Check Aurora status and network connectivity

```bash
# Check if Aurora is running
aws rds describe-db-clusters --db-cluster-identifier your-cluster-name \
  --query 'DBClusters[0].Status'

# Check security group rules for Aurora
aws ec2 describe-security-groups --group-ids your-aurora-sg-id

# Verify VPC connectivity
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=your-vpc-id"
```

### 6. Database Credential Architecture

The system uses two sets of credentials:

#### Aurora Master Credentials

- **Purpose**: Initial database connection and setup
- **Username**: Aurora master username (e.g., `wpdbadmin`)
- **Password**: Aurora master password (e.g., `ChangeMe123!`)
- **Usage**: Database readiness check, database creation, user creation

#### WordPress Application Credentials

- **Purpose**: WordPress application database access
- **Username**: WordPress database user (e.g., `wpuser`)
- **Password**: WordPress user password (e.g., `wppassword123`)
- **Usage**: WordPress configuration, application runtime

### 7. Monitoring Database Setup Process

```bash
# Watch the complete database setup process
tail -f ~/install.log | grep -E "(DB|database|mysql)"

# Check if database and user creation succeeded
grep -A 5 "Setting up database using Aurora master credentials" ~/install.log

# Verify WordPress database test
grep "WP DB test" ~/install.log
```

**Expected Success Sequence**:

1. `DB check start: [aurora-endpoint]`
2. `DB ready: attempt X`
3. `DB ready - proceeding`
4. `Setting up database using Aurora master credentials...`
5. `DB setup OK`
6. `WP DB test OK`

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

### 2. Check Installation Status

The WordPress installation process now uses a consolidated log file for all operations:

```bash
# Check the main installation log (replaces multiple status files)
cat ~/install.log

# Check specific installation phases
grep -E "(Installing|Services|EFS|DB|WP|Consul)" ~/install.log

# Monitor installation progress in real-time
tail -f ~/install.log
```

**Key Log Sections**:

- **Apache/PHP Installation**: `Installing Apache/PHP...` → `Apache/PHP OK`
- **Service Startup**: `Services started`
- **EFS Mount**: `EFS: fs-xxxxx` → `EFS OK`
- **Database Connectivity**: `=== DATABASE CONNECTION DEBUG ===` → `DB ready`
- **WordPress Download**: `WP downloaded`
- **WordPress Installation**: `WP to EFS` or `WP to local`
- **Database Setup**: `DB setup OK`
- **Consul Setup**: `Consul installed` → `Consul started`

### 3. Legacy Error Files (Deprecated)

**Note**: The following error files are from older versions and have been replaced by the consolidated `~/install.log`:

#### EFS Mount Issues (Legacy)

```bash
# Check if EFS mount failed (legacy)
cat ~/wp_bootstrap_efs_error.txt
```

#### Existing Installation Detection (Legacy)

```bash
# Check if existing WordPress installation was detected (legacy)
cat ~/wp_bootstrap_existing_error.txt
```

#### General EFS Mount Issues (Legacy)

```bash
# Check general EFS mount errors (legacy)
cat ~/efs_mount_error.txt
```

**Migration Note**: All status information is now consolidated in `~/install.log` for easier troubleshooting.

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

#### Issue: PHP Extensions Missing or "amazon-linux-extras: command not found"

**Solution**: On Amazon Linux 2023, use direct yum installation instead of amazon-linux-extras:

```bash
# For Amazon Linux 2023
sudo yum install -y php php-fpm php-xml php-gd php-mysqlnd php-mbstring php-soap

# Check PHP installation
php -v
php -m | grep -E "(mysql|gd|xml|mbstring|soap)"
```

#### Issue: Apache SSL Module Errors

**Solution**: Install the SSL module properly for Amazon Linux 2023:

```bash
# Install SSL module
sudo yum install -y mod_ssl

# Check if SSL module is loaded
sudo httpd -M | grep ssl

# Test Apache configuration
sudo httpd -t
```

#### Issue: "mod_rewrite" or "mod_ssl" package not found

**Solution**: These modules are included with httpd on Amazon Linux 2023:

```bash
# mod_rewrite is built into httpd - no separate package needed
# For SSL support, install mod_ssl package
sudo yum install -y mod_ssl

# Verify modules are available
sudo httpd -M | grep -E "(rewrite|ssl)"
```

#### Issue: Database Connection Errors

**Solution**: Verify database configuration in wp-config.php and ensure RDS instance is accessible.

#### Issue: "Unable to find a match: mysql" package error

**Solution**: On Amazon Linux 2023, use `mariadb` instead of `mysql`:

```bash
# For Amazon Linux 2023
sudo yum install -y mariadb

# Check MariaDB client installation
which mysql
mysql --version
```

#### Issue: Apache not starting or httpd service not found

**Solution**: The updated WordPress script now installs httpd unconditionally at the beginning, but if it's missing:

```bash
# Install Apache (now done automatically in script)
sudo yum install -y httpd mod_ssl

# Check if httpd is installed
rpm -qa | grep httpd

# Enable and start Apache
sudo systemctl enable httpd
sudo systemctl start httpd

# Check Apache status
sudo systemctl status httpd

# Check installation status from script
cat ~/wp_installation_status.txt | grep -i apache
```

**Note**: The WordPress script now ensures Apache gets installed regardless of bootstrap settings or other package failures.

#### Enhanced Consul Installation Status Logging

The updated WordPress script now provides detailed status logging for all Consul service operations:

```bash
# Check comprehensive Consul installation status
cat ~/wp_installation_status.txt | grep -i consul

# Look for specific Consul operations
grep -E "(Consul|consul)" ~/wp_installation_status.txt
```

**Expected Consul status entries**:

- "Starting Consul setup..."
- "Consul installed successfully"
- "Creating Consul configuration..."
- "Consul configuration created successfully"
- "Starting Consul services..."
- "Consul enabled successfully"
- "AWS metadata ready"
- "Consul start succeeded"
- "Consul API ready"
- "Consul joined cluster - X members"
- "Consul startup completed"

**Troubleshooting with Consul status logs**:

```bash
# Check if Consul installation failed
grep -i "failed.*consul" ~/wp_installation_status.txt

# Check if Consul startup failed
grep -i "consul.*failed" ~/wp_installation_status.txt

# Check if AWS metadata was ready
grep -i "metadata" ~/wp_installation_status.txt

# Verify Consul startup sequence completed
grep -i "consul startup completed" ~/wp_installation_status.txt

# Check cluster join status
grep -i "joined cluster" ~/wp_installation_status.txt
```

#### Enhanced Apache Installation Status Logging

The updated WordPress script now provides detailed status logging for all Apache service operations:

```bash
# Check comprehensive Apache installation status
cat ~/wp_installation_status.txt

# Look for specific Apache operations
grep -E "(Apache|httpd|PHP-FPM)" ~/wp_installation_status.txt
```

**Expected status entries**:

- "Installing Apache and PHP (mandatory)..."
- "Apache and PHP installed successfully (mandatory)"
- "SSL module installed successfully (mandatory)"
- "Enabling Apache and PHP-FPM services..."
- "Apache (httpd) enabled successfully"
- "PHP-FPM enabled successfully"
- "Starting Apache and PHP-FPM services..."
- "Apache (httpd) started successfully"
- "PHP-FPM started successfully"
- "All Apache services enabled and started successfully (mandatory)"

**Troubleshooting with status logs**:

```bash
# Check if Apache installation failed
grep -i "failed.*apache" ~/wp_installation_status.txt

# Check if service enable operations failed
grep -i "failed.*enable" ~/wp_installation_status.txt

# Check if service start operations failed
grep -i "failed.*start" ~/wp_installation_status.txt

# Verify all operations completed successfully
grep -i "successfully" ~/wp_installation_status.txt | grep -E "(Apache|httpd|PHP-FPM)"
```

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

## Consul Gossip Key Configuration

Consul uses gossip encryption to secure communication between cluster members. This section explains how to generate and configure gossip keys for your WordPress Canary deployments.

### Overview

The **gossip key** is a base64-encoded 32-byte encryption key that Consul uses to encrypt all gossip communication between cluster members. Each WordPress deployment creates one **Consul datacenter**, and all nodes within that datacenter must share the same gossip key.

**Consul Datacenters Explained:**

- Each WordPress deployment = one Consul datacenter
- Datacenters are identified by unique names (e.g., "wp-prod-east", "wp-staging-west")
- Single datacenter: All Consul nodes communicate within one isolated cluster
- Multi-datacenter: Multiple clusters can be federated for advanced use cases

**When gossip keys are required:**

- **Optional for single deployments**: Basic security enhancement
- **Required for canary deployments**: Multiple datacenters must share the same key
- **Required for WAN federation**: Cross-datacenter communication
- **Recommended for production**: Security best practice

### Consul Datacenter Concepts

Understanding Consul datacenters is essential for canary deployments:

**Single Datacenter Architecture:**

- One WordPress deployment with its own Consul cluster
- All Consul servers, WordPress servers, and load balancers belong to one datacenter
- Isolated service discovery within the deployment

**Multi-Datacenter Architecture (Canary Deployments):**

- **Production Datacenter**: Your stable WordPress deployment
- **Canary Datacenter**: Your test/staging WordPress deployment
- **WAN Federation**: Datacenters communicate across networks for service discovery
- **Shared Service Discovery**: Services in one datacenter can discover services in another
- **Traffic Routing**: Load balancers can route traffic between datacenters for canary testing

### Canary Deployment Architecture

For canary deployments connecting multiple WordPress environments:

**Multi-Datacenter Setup Requirements:**

- **Shared Gossip Key**: All datacenters in the federation must use the same gossip encryption key
- **Network Connectivity**: Datacenters must be able to communicate across VPC/network boundaries
- **Service Discovery**: Consul enables cross-datacenter service discovery for canary routing
- **Load Balancer Integration**: Nginx can route traffic between production and canary environments

**Canary Traffic Flow:**

1. Production datacenter serves normal traffic
2. Canary datacenter runs new WordPress version/configuration
3. Load balancers use Consul service discovery to find both environments
4. Traffic can be gradually shifted from production to canary for testing

### Generation

Use the provided scripts in the `test/` directory to generate gossip keys:

**Unix/Linux/macOS:**

```bash
cd test/
./generate-gossip-key.sh
```

**Windows:**

```cmd
cd test
generate-gossip-key.bat
```

**Script Options:**

- `-u, --update-tfvars`: Automatically update terraform.tfvars with the generated key
- `-f, --file FILE`: Save the key to a specific file
- `-q, --quiet`: Output only the key (useful for scripting)
- `-h, --help`: Show help message

**Examples:**

```bash
# Generate and display key
./generate-gossip-key.sh

# Generate and automatically update terraform.tfvars
./generate-gossip-key.sh -u

# Generate and save to file
./generate-gossip-key.sh -f my-gossip.key

# Generate key for use in scripts
GOSSIP_KEY=$(./generate-gossip-key.sh -q)
```

**Important:** Generate the key once and use the same key across all deployments that need to communicate.

### Configuration

Add the generated gossip key to your `terraform.tfvars` file:

```hcl
# Consul gossip encryption key
shared_gossip_key = "your-generated-key-here"
```

**Multi-Deployment Consistency:**

- Use the **same gossip key** in all terraform.tfvars files for deployments that need to communicate
- Each deployment (datacenter) must have identical gossip key configuration
- Key mismatch will prevent datacenters from joining the federation

**Example terraform.tfvars entry:**

```hcl
shared_gossip_key = "K8n7Qz2mR5vY8x/A3sD6gJ9kL2nP5rT8uW1yE4tR7i="
```

### Network Connectivity Requirements

For canary deployments across multiple WordPress environments, ensure proper network connectivity:

**Datacenter Communication Ports:**

- **Port 8300**: Consul server RPC (server-to-server communication)
- **Port 8301**: Consul LAN gossip (TCP and UDP)
- **Port 8302**: Consul WAN gossip (TCP and UDP, for federation)

**Network Infrastructure Options:**

**VPC Peering (Same Region):**

```bash
# Example: Connect production VPC to canary VPC
aws ec2 create-vpc-peering-connection \
  --vpc-id vpc-12345678 \
  --peer-vpc-id vpc-87654321
```

**AWS Transit Gateway (Multi-Region):**

- Enables connectivity between VPCs across different AWS regions
- Supports complex routing scenarios for multiple datacenters
- Recommended for enterprise canary deployments

**Security Group Configuration:**

**Critical:** Security groups must allow connectivity for:

1. **Consul Inter-Datacenter Communication**: Ports 8300, 8301, 8302 between Consul servers
2. **Service Discovery Traffic**: Allow Consul agents to communicate across peering/transit gateway
3. **WordPress Application Traffic**: HTTP/HTTPS (80/443) for nginx upstream routing to alternate deployment
4. **Cross-VPC CIDR Blocks**: Specific CIDR ranges to allow in security groups

**Example Security Group Rules:**

```hcl
# Allow Consul WAN federation from peer datacenter
resource "aws_security_group_rule" "consul_wan_federation" {
  type              = "ingress"
  from_port         = 8302
  to_port           = 8302
  protocol          = "tcp"
  cidr_blocks       = ["10.1.0.0/16"]  # Peer datacenter VPC CIDR
  security_group_id = aws_security_group.consul_servers.id
}

# Allow HTTP traffic from peer datacenter load balancers
resource "aws_security_group_rule" "cross_datacenter_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["10.1.0.0/16"]  # Peer datacenter VPC CIDR
  security_group_id = aws_security_group.wordpress_servers.id
}
```

**Route Table Configuration:**

- Ensure route tables include routes to peer VPC CIDR blocks
- Configure Transit Gateway route tables for multi-region connectivity
- Verify return traffic routing is properly configured

### Security Considerations

**Treat as Sensitive Data:**

- Store gossip keys securely (AWS Secrets Manager, encrypted files)
- Never commit gossip keys to version control
- Use Terraform sensitive variables to prevent key exposure in logs

**Cross-Datacenter Security:**

- **Network Isolation**: Maintain network security while allowing required federation traffic
- **Principle of Least Privilege**: Only open required ports between specific resources
- **Monitoring**: Monitor cross-datacenter traffic for security anomalies

**Key Rotation:**

- Plan for coordinated key rotation across all datacenters
- Consul supports rolling key updates without downtime
- Test key rotation procedures in non-production environments

**Multi-Deployment Considerations:**

- Same key must be rotated simultaneously across all federated datacenters
- Consider using centralized key management for multiple deployments
- Document which deployments share gossip keys

### Troubleshooting Multi-Datacenter Issues

**Datacenter Join Issues:**

```bash
# Check if datacenters can see each other
consul members -wan

# Verify gossip key consistency
grep "encrypt" /etc/consul.d/consul.hcl

# Test network connectivity between datacenters
telnet <peer-consul-server-ip> 8302
```

**Cross-Datacenter Service Discovery:**

```bash
# List services from all datacenters
consul catalog services -datacenter=production
consul catalog services -datacenter=canary

# Check cross-datacenter service resolution
dig @127.0.0.1 -p 8600 wordpress.service.canary.consul
```

**Security Group Troubleshooting:**

```bash
# Test Consul federation connectivity
nc -zv <peer-consul-server-ip> 8302

# Test HTTP connectivity for nginx upstreams
curl -I http://<peer-wordpress-server-ip>/

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-12345678 \
  --query 'SecurityGroups[0].IpPermissions'
```

**Network Connectivity Verification:**

```bash
# Test VPC peering connectivity
ping <peer-vpc-instance-ip>

# Check route table entries
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-12345678"

# Verify Transit Gateway attachments
aws ec2 describe-transit-gateway-attachments
```

**Common Multi-Datacenter Issues:**

**Issue: "No WAN members found"**

- **Root Cause**: Network connectivity or security group configuration
- **Solution**: Verify ports 8302 (WAN gossip) and 8300 (server RPC) are open between datacenters

**Issue: "Gossip key mismatch"**

- **Root Cause**: Different gossip keys between datacenters
- **Solution**: Ensure all datacenters use the same shared_gossip_key value

**Issue: "Cross-datacenter service discovery fails"**

- **Root Cause**: WAN federation not properly established
- **Solution**: Check consul members -wan and verify network connectivity

**Issue: "Nginx upstream routing fails to canary"**

- **Root Cause**: Security groups blocking HTTP traffic between datacenters
- **Solution**: Allow HTTP/HTTPS traffic from load balancer security groups to WordPress server security groups across VPC boundaries

For additional Consul connectivity troubleshooting, see the [Troubleshooting Consul Connectivity](#troubleshooting-consul-connectivity) section below.

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
