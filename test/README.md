# WordPress Canary Test Infrastructure

This directory contains a complete test environment for the WordPress Canary module, demonstrating how to deploy a scalable WordPress infrastructure with Consul service discovery, Aurora Serverless MySQL database, and EFS shared storage.

## Architecture Overview

The test infrastructure deploys:

- **VPC**: Multi-AZ setup with public and private subnets
- **Aurora Serverless MySQL**: Managed database with auto-scaling
- **EFS**: Shared file system for WordPress content
- **VPC Endpoints**: SSM and EFS endpoints for secure access
- **WordPress Canary Module**: Complete WordPress deployment with:
  - Consul servers for service discovery
  - WordPress application servers
  - Load balancer servers (nginx)

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
2. **Terraform** >= 1.0 installed
3. **EC2 Key Pair** (optional, for SSH access)
4. **Aurora Serverless Module** available at `../../terraform-y337-aurora-serverless`

## Quick Start

### 1. Configure Variables

Copy the example variables file and customize it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and update:

- `aws_profile`: Your AWS profile name (or leave empty to use default credentials)
- `owner`: Your team/project name
- `key_name`: Your EC2 key pair name (if you want SSH access)
- Database passwords (change from defaults)
- AMI IDs (if using custom AMIs)
- Any other settings specific to your environment

**Security Note**: The `terraform.tfvars` file contains sensitive information and is excluded from git via `.gitignore`. Never commit this file to version control.

### 1.1. Generate Consul Gossip Key (Optional)

For WAN federation or shared testing environments, generate a Consul gossip encryption key:

**Unix/Linux/macOS:**

```bash
./generate-gossip-key.sh
```

**Windows:**

```cmd
generate-gossip-key.bat
```

**Options:**

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

### 2. Initialize and Deploy

```bash
# Initialize Terraform
terraform init

# Review the deployment plan
terraform plan

# Deploy the infrastructure
terraform apply
```

### 3. Access Your WordPress Site

After deployment completes, the WordPress site will be accessible through the load balancer instances. Check the outputs for connection details:

```bash
terraform output
```

## Infrastructure Components

### Networking

- **VPC**: 192.168.0.0/16 with DNS hostnames enabled
- **Public Subnets (DMZ)**: 192.168.1.0/24, 192.168.4.0/24
- **Private Subnets (App)**: 192.168.2.0/24, 192.168.5.0/24
- **Private Subnets (DB)**: 192.168.3.0/24, 192.168.6.0/24
- **Private Subnets (Infra)**: 192.168.7.0/24, 192.168.8.0/24
- **NAT Gateways**: Dual AZ for high availability
- **Internet Gateway**: For public subnet internet access

### Database

- **Aurora Serverless v2 MySQL**: Auto-scaling from 2-16 ACUs
- **Encryption**: KMS encrypted at rest
- **Backups**: 7-day retention with automated backups
- **Multi-AZ**: Deployed across two availability zones

### Storage

- **EFS**: Burst mode performance for WordPress content
- **Encryption**: Encrypted at rest and in transit
- **Access Point**: Configured for www-data user/group
- **Mount Targets**: Available in both app subnets

### Security

- **Security Groups**: Least privilege access patterns
- **VPC Endpoints**: Private access to AWS services
- **IMDSv2**: Required on all EC2 instances
- **Network ACLs**: Default VPC security

### Monitoring

- **CloudWatch**: Basic metrics collection only
- **VPC Flow Logs**: Network traffic monitoring (optional)
- **Note**: CloudWatch alerts and email notifications have been removed from the module

## Configuration Options

### Scaling

Adjust instance counts and types in `terraform.tfvars`:

```hcl
# Consul servers (recommended: 3 or 5)
consul_servers = 3
consul_instance_type = "t3.micro"

# WordPress servers
wp_servers_min = 2
wp_servers_max = 6
wp_instance_type = "t3.small"

# Load balancer servers
lb_servers_min = 2
lb_servers_max = 4
lb_instance_type = "t3.micro"
```

### Database

Configure Aurora Serverless capacity:

```hcl
db_min_capacity = 2.0   # Minimum ACUs
db_max_capacity = 16.0  # Maximum ACUs
db_cluster_count = 2    # Number of instances
```

### Security

Restrict access to your IP range:

```hcl
allowed_inbound_cidrs = ["203.0.113.0/24"]  # Your office IP range
```

## Outputs

The infrastructure provides these key outputs:

- **VPC and Subnet IDs**: For integration with other resources
- **Database Endpoints**: Aurora cluster connection details
- **EFS Information**: File system and access point IDs
- **Security Group IDs**: For additional resource integration
- **Autoscaling Group Names**: For monitoring and management

## Cost Optimization

For testing/development environments:

1. **Use smaller instance types**:

   ```hcl
   consul_instance_type = "t3.nano"
   wp_instance_type = "t3.micro"
   lb_instance_type = "t3.nano"
   ```

2. **Reduce Aurora capacity**:

   ```hcl
   db_min_capacity = 0.5
   db_max_capacity = 4.0
   ```

3. **Single AZ deployment** (not recommended for production):
   ```hcl
   aws_zone_b = "a"  # Use same AZ as zone_a
   ```

## Troubleshooting

### Common Issues

1. **Module not found**: Ensure the Aurora module exists at `../terraform-y337-aurora-serverless`
2. **Permission errors**: Verify AWS credentials have necessary permissions
3. **Resource limits**: Check AWS service limits in your region
4. **Key pair errors**: Ensure the specified key pair exists in your region

### Debugging

Enable Terraform debug logging:

```bash
export TF_LOG=DEBUG
terraform apply
```

Check AWS CloudWatch logs for application-level issues.

### Cleanup

To destroy the infrastructure:

```bash
terraform destroy
```

**Note**: This will permanently delete all resources including the database. Ensure you have backups if needed.

## Security Considerations

### Production Deployment

For production use, consider:

1. **Change all default passwords**
2. **Use AWS Secrets Manager** for sensitive values
3. **Enable VPC Flow Logs** for security monitoring
4. **Implement WAF** for web application protection
5. **Use private subnets** for all application components
6. **Enable GuardDuty** for threat detection
7. **Regular security updates** for AMIs

### Network Security

- All application servers are in private subnets
- Database access restricted to application subnets
- VPC endpoints provide secure AWS service access
- Security groups follow least privilege principles

## Support

For issues with:

- **WordPress Canary Module**: Check the main module documentation
- **Aurora Module**: Refer to the terraform-y337-aurora-serverless documentation
- **AWS Resources**: Consult AWS documentation and support

## License

This test infrastructure inherits the license from the parent WordPress Canary project.
