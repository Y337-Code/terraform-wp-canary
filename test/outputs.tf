# VPC Outputs
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

# Subnet Outputs
output "dmz_subnet_ids" {
  description = "IDs of the DMZ (public) subnets"
  value       = [aws_subnet.dmz_a.id, aws_subnet.dmz_b.id]
}

output "app_subnet_ids" {
  description = "IDs of the application (private) subnets"
  value       = [aws_subnet.app_a.id, aws_subnet.app_b.id]
}

output "db_subnet_ids" {
  description = "IDs of the database (private) subnets"
  value       = [aws_subnet.db_a.id, aws_subnet.db_b.id]
}

output "infra_subnet_ids" {
  description = "IDs of the infrastructure (private) subnets"
  value       = [aws_subnet.infra_a.id, aws_subnet.infra_b.id]
}

# Database Outputs
output "aurora_cluster_endpoint" {
  description = "Aurora cluster endpoint"
  value       = module.aurora_mysql.aurora_endpoint
  sensitive   = true
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora cluster reader endpoint"
  value       = module.aurora_mysql.aurora_reader_endpoint
  sensitive   = true
}

output "aurora_cluster_id" {
  description = "Aurora cluster identifier"
  value       = module.aurora_mysql.aurora_cluster_id
}

output "aurora_cluster_port" {
  description = "Aurora cluster port"
  value       = module.aurora_mysql.aurora_port
}

output "aurora_cluster_database_name" {
  description = "Aurora cluster database name"
  value       = module.aurora_mysql.aurora_database_name
}

# EFS Outputs
output "efs_file_system_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.wordpress_content.id
}

output "efs_access_point_id" {
  description = "ID of the EFS access point"
  value       = aws_efs_access_point.wordpress_content.id
}

output "efs_mount_target_ids" {
  description = "IDs of the EFS mount targets"
  value       = [
    aws_efs_mount_target.wordpress_content_a.id,
    aws_efs_mount_target.wordpress_content_b.id
  ]
}

# Security Group Outputs
output "efs_security_group_id" {
  description = "ID of the EFS security group"
  value       = aws_security_group.efs.id
}

output "aurora_security_group_id" {
  description = "ID of the Aurora security group"
  value       = aws_security_group.aurora.id
}

# VPC Endpoint Outputs
output "vpc_endpoint_efs_id" {
  description = "ID of the EFS VPC endpoint"
  value       = aws_vpc_endpoint.efs.id
}

# WordPress Module Outputs
output "consul_servers_asg_id" {
  description = "ID of the Consul servers autoscaling group"
  value       = module.wordpress_canary.consul_server_autoscaling_group_id
}

output "wp_servers_asg_id" {
  description = "ID of the WordPress/Load Balancer servers autoscaling group"
  value       = module.wordpress_canary.wp_asg_id
}

output "consul_server_instance_ids" {
  description = "Instance IDs of the Consul servers"
  value       = module.wordpress_canary.consul_server_instance_ids
}

output "consul_server_private_ips" {
  description = "Private IP addresses of the Consul servers"
  value       = module.wordpress_canary.consul_server_private_ips
}

output "consul_gossip_encryption_key" {
  description = "Consul gossip encryption key"
  value       = module.wordpress_canary.consul_gossip_encryption_key
  sensitive   = true
}

# Network Configuration
output "nat_gateway_ips" {
  description = "Public IP addresses of the NAT gateways"
  value       = [aws_eip.nat_a.public_ip, aws_eip.nat_b.public_ip]
}

output "availability_zones" {
  description = "Availability zones used"
  value       = ["${var.aws_region}${var.aws_zone_a}", "${var.aws_region}${var.aws_zone_b}"]
}

# Environment Information
output "environment" {
  description = "Environment name"
  value       = var.environment
}

output "name_prefix" {
  description = "Name prefix used for resources"
  value       = var.name_prefix
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

# Connection Information
output "database_connection_info" {
  description = "Database connection information"
  value = {
    endpoint     = module.aurora_mysql.aurora_endpoint
    port         = module.aurora_mysql.aurora_port
    database     = var.database_name
    username     = var.db_master_username
  }
  sensitive = true
}

output "efs_mount_info" {
  description = "EFS mount information"
  value = {
    file_system_id   = aws_efs_file_system.wordpress_content.id
    access_point_id  = aws_efs_access_point.wordpress_content.id
    mount_point      = var.wp_content_mount_point
  }
}
