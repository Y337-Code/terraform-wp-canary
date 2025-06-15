# AWS Configuration
variable "aws_profile" {
  type        = string
  description = "AWS profile to use for authentication"
  default     = ""
}

# Region and Availability Zone Configuration
variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-east-1"
}

variable "aws_zone_a" {
  type        = string
  description = "First availability zone suffix"
  default     = "a"
}

variable "aws_zone_b" {
  type        = string
  description = "Second availability zone suffix"
  default     = "b"
}

# Environment and Naming
variable "environment" {
  type        = string
  description = "Environment name"
  default     = "test"
}

variable "name_prefix" {
  type        = string
  description = "Prefix for resource naming"
  default     = "wp-test"
}

# VPC Configuration
variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "192.168.0.0/16"
}

variable "dmz_subnet_a_cidr" {
  type        = string
  description = "CIDR block for DMZ subnet A"
  default     = "192.168.1.0/24"
}

variable "dmz_subnet_b_cidr" {
  type        = string
  description = "CIDR block for DMZ subnet B"
  default     = "192.168.4.0/24"
}

variable "app_subnet_a_cidr" {
  type        = string
  description = "CIDR block for App subnet A"
  default     = "192.168.2.0/24"
}

variable "app_subnet_b_cidr" {
  type        = string
  description = "CIDR block for App subnet B"
  default     = "192.168.5.0/24"
}

variable "db_subnet_a_cidr" {
  type        = string
  description = "CIDR block for DB subnet A"
  default     = "192.168.3.0/24"
}

variable "db_subnet_b_cidr" {
  type        = string
  description = "CIDR block for DB subnet B"
  default     = "192.168.6.0/24"
}

variable "infra_subnet_a_cidr" {
  type        = string
  description = "CIDR block for Infra subnet A"
  default     = "192.168.7.0/24"
}

variable "infra_subnet_b_cidr" {
  type        = string
  description = "CIDR block for Infra subnet B"
  default     = "192.168.8.0/24"
}

# Database Configuration
variable "database_name" {
  type        = string
  description = "Name of the WordPress database"
  default     = "wordpress"
}

variable "db_master_username" {
  type        = string
  description = "Master username for Aurora database"
  default     = "wpdbadmin"
}

variable "db_master_password" {
  type        = string
  description = "Master password for Aurora database"
  default     = "ChangeMe123!"
  sensitive   = true
}

variable "db_min_capacity" {
  type        = number
  description = "Minimum Aurora Serverless capacity"
  default     = 2.0
}

variable "db_max_capacity" {
  type        = number
  description = "Maximum Aurora Serverless capacity"
  default     = 16.0
}

variable "db_cluster_count" {
  type        = number
  description = "Number of Aurora cluster instances"
  default     = 2
}

# WordPress Configuration
variable "wp_mysql_user" {
  type        = string
  description = "WordPress MySQL user"
  default     = "wpuser"
}

variable "wp_mysql_user_pw" {
  type        = string
  description = "WordPress MySQL user password"
  default     = "wppassword123"
  sensitive   = true
}

variable "wp_mysql_root_pw" {
  type        = string
  description = "WordPress MySQL root password"
  default     = "rootpassword123"
  sensitive   = true
}

variable "wp_content_mount_point" {
  type        = string
  description = "Mount point for WordPress content EFS"
  default     = "/var/www/html/wp-content"
}

# WordPress Module Configuration
variable "consul_servers" {
  type        = number
  description = "Number of Consul servers"
  default     = 3
}

variable "consul_version" {
  type        = string
  description = "Consul version to install"
  default     = "1.15.2"
}

variable "consul_cluster_version" {
  type        = string
  description = "Consul cluster version"
  default     = "v1"
}

variable "consul_ami_id" {
  type        = string
  description = "AMI ID for Consul servers"
  default     = ""  # Will use data source to find latest Amazon Linux 2
}

variable "consul_instance_type" {
  type        = string
  description = "Instance type for Consul servers"
  default     = "t3.micro"
}

variable "wp_ami_id" {
  type        = string
  description = "AMI ID for WordPress servers"
  default     = ""  # Will use data source to find latest Amazon Linux 2
}

variable "wp_instance_type" {
  type        = string
  description = "Instance type for WordPress servers"
  default     = "t3.large"
}

variable "wp_servers_min" {
  type        = number
  description = "Minimum number of WordPress servers"
  default     = 1
}

variable "wp_servers_max" {
  type        = number
  description = "Maximum number of WordPress servers"
  default     = 1
}

variable "lb_ami_id" {
  type        = string
  description = "AMI ID for load balancer servers"
  default     = ""  # Will use data source to find latest Amazon Linux 2
}

variable "lb_instance_type" {
  type        = string
  description = "Instance type for load balancer servers"
  default     = "t3.medium"
}

variable "lb_servers_min" {
  type        = number
  description = "Minimum number of load balancer servers"
  default     = 2
}

variable "lb_servers_max" {
  type        = number
  description = "Maximum number of load balancer servers"
  default     = 4
}

variable "key_name" {
  type        = string
  description = "EC2 Key Pair name for SSH access"
  default     = ""
}

variable "public_ip" {
  type        = bool
  description = "Whether to assign public IPs to instances"
  default     = false
}

variable "acl_bootstrap_bool" {
  type        = string
  description = "Whether to bootstrap Consul ACLs"
  default     = "true"
}

variable "enable_connect" {
  type        = string
  description = "Whether to enable Consul Connect"
  default     = "true"
}

variable "consul_config" {
  description = "Additional Consul configuration"
  type        = map(string)
  default     = {}
}

variable "shared_gossip_key" {
  description = "Shared Consul gossip encryption key for WAN federation"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_wan_federation" {
  type        = string
  description = "Whether to enable WAN federation"
  default     = "false"
}

variable "peer_datacenter_name" {
  type        = string
  description = "Peer datacenter name for federation"
  default     = ""
}

variable "peer_datacenter_region" {
  type        = string
  description = "Peer datacenter region for federation"
  default     = ""
}

variable "peer_environment_name" {
  type        = string
  description = "Peer environment name for federation"
  default     = ""
}

variable "wp_bootstrap" {
  type        = string
  description = "WordPress bootstrap configuration"
  default     = "true"
}


# Additional Required Variables for WordPress Module
variable "owner" {
  type        = string
  description = "Owner tag for EC2 instances"
  default     = "wp-test-team"
}

variable "allowed_inbound_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks to permit inbound Consul access from"
  default     = ["192.168.0.0/16"]
}

# Tags
variable "common_tags" {
  type        = map(string)
  description = "Common tags to apply to all resources"
  default = {
    Environment = "test"
    Project     = "wordpress-canary-test"
    Automation  = "terraform"
  }
}

variable "wp_hostname" {
  type        = string
  description = "Hostname for WordPress site"
  default     = "wp-test.example.com"
}
