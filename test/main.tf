# Terraform configuration
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure AWS Provider
provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile != "" ? var.aws_profile : null
  default_tags {
    tags = var.common_tags
  }
}

# Data sources
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# Generate unique resource identifier
resource "random_id" "resource_id" {
  byte_length = 4
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux2" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
  
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################################################################
#                                 VPC Creation                                 #
################################################################################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "${var.name_prefix}-vpc-${var.environment}"
  }
}

################################################################################
#                         Subnet Creation                                      #
################################################################################

# DMZ Subnets (Public)
resource "aws_subnet" "dmz_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.dmz_subnet_a_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_a}"
  
  tags = {
    Name = "${var.name_prefix}-dmz-${var.aws_zone_a}-${var.environment}"
    Type = "Public"
  }
}

resource "aws_subnet" "dmz_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.dmz_subnet_b_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_b}"
  
  tags = {
    Name = "${var.name_prefix}-dmz-${var.aws_zone_b}-${var.environment}"
    Type = "Public"
  }
}

# App Subnets (Private)
resource "aws_subnet" "app_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_a_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_a}"
  
  tags = {
    Name = "${var.name_prefix}-app-${var.aws_zone_a}-${var.environment}"
    Type = "Private"
  }
}

resource "aws_subnet" "app_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_b_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_b}"
  
  tags = {
    Name = "${var.name_prefix}-app-${var.aws_zone_b}-${var.environment}"
    Type = "Private"
  }
}

# DB Subnets (Private)
resource "aws_subnet" "db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_a_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_a}"
  
  tags = {
    Name = "${var.name_prefix}-db-${var.aws_zone_a}-${var.environment}"
    Type = "Private"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_b_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_b}"
  
  tags = {
    Name = "${var.name_prefix}-db-${var.aws_zone_b}-${var.environment}"
    Type = "Private"
  }
}

# Infra Subnets (Private)
resource "aws_subnet" "infra_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.infra_subnet_a_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_a}"
  
  tags = {
    Name = "${var.name_prefix}-infra-${var.aws_zone_a}-${var.environment}"
    Type = "Private"
  }
}

resource "aws_subnet" "infra_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.infra_subnet_b_cidr
  availability_zone = "${var.aws_region}${var.aws_zone_b}"
  
  tags = {
    Name = "${var.name_prefix}-infra-${var.aws_zone_b}-${var.environment}"
    Type = "Private"
  }
}

################################################################################
#                    Internet Gateway and NAT Gateways                        #
################################################################################

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  
  tags = {
    Name = "${var.name_prefix}-igw-${var.environment}"
  }
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat_a" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
  
  tags = {
    Name = "${var.name_prefix}-eip-nat-${var.aws_zone_a}-${var.environment}"
  }
}

resource "aws_eip" "nat_b" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
  
  tags = {
    Name = "${var.name_prefix}-eip-nat-${var.aws_zone_b}-${var.environment}"
  }
}

# NAT Gateways
resource "aws_nat_gateway" "nat_a" {
  allocation_id = aws_eip.nat_a.id
  subnet_id     = aws_subnet.dmz_a.id
  depends_on    = [aws_internet_gateway.main]
  
  tags = {
    Name = "${var.name_prefix}-nat-${var.aws_zone_a}-${var.environment}"
  }
}

resource "aws_nat_gateway" "nat_b" {
  allocation_id = aws_eip.nat_b.id
  subnet_id     = aws_subnet.dmz_b.id
  depends_on    = [aws_internet_gateway.main]
  
  tags = {
    Name = "${var.name_prefix}-nat-${var.aws_zone_b}-${var.environment}"
  }
}

################################################################################
#                              Route Tables                                    #
################################################################################

# Public Route Table for DMZ subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt-public-${var.environment}"
  }
}

# Private Route Tables for App subnets
resource "aws_route_table" "private_a" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt-private-${var.aws_zone_a}-${var.environment}"
  }
}

resource "aws_route_table" "private_b" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt-private-${var.aws_zone_b}-${var.environment}"
  }
}

# DB Route Tables
resource "aws_route_table" "db_a" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_a.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt-db-${var.aws_zone_a}-${var.environment}"
  }
}

resource "aws_route_table" "db_b" {
  vpc_id = aws_vpc.main.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_b.id
  }
  
  tags = {
    Name = "${var.name_prefix}-rt-db-${var.aws_zone_b}-${var.environment}"
  }
}

################################################################################
#                         Route Table Associations                            #
################################################################################

resource "aws_route_table_association" "dmz_a" {
  subnet_id      = aws_subnet.dmz_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "dmz_b" {
  subnet_id      = aws_subnet.dmz_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app_a" {
  subnet_id      = aws_subnet.app_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "app_b" {
  subnet_id      = aws_subnet.app_b.id
  route_table_id = aws_route_table.private_b.id
}

resource "aws_route_table_association" "db_a" {
  subnet_id      = aws_subnet.db_a.id
  route_table_id = aws_route_table.db_a.id
}

resource "aws_route_table_association" "db_b" {
  subnet_id      = aws_subnet.db_b.id
  route_table_id = aws_route_table.db_b.id
}

resource "aws_route_table_association" "infra_a" {
  subnet_id      = aws_subnet.infra_a.id
  route_table_id = aws_route_table.private_a.id
}

resource "aws_route_table_association" "infra_b" {
  subnet_id      = aws_subnet.infra_b.id
  route_table_id = aws_route_table.private_b.id
}

################################################################################
#                              Security Groups                                #
################################################################################

# Security Group for EFS
resource "aws_security_group" "efs" {
  name_prefix = "${var.name_prefix}-efs-"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.app_subnet_a_cidr, var.app_subnet_b_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.name_prefix}-sg-efs-${var.environment}"
  }
}

# Security Group for Aurora Database
resource "aws_security_group" "aurora" {
  name_prefix = "${var.name_prefix}-aurora-"
  vpc_id      = aws_vpc.main.id
  
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.app_subnet_a_cidr, var.app_subnet_b_cidr]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "${var.name_prefix}-sg-aurora-${var.environment}"
  }
}

################################################################################
#                              VPC Endpoints                                  #
################################################################################

# EFS VPC Endpoint - Keep this for EFS connectivity
resource "aws_vpc_endpoint" "efs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.elasticfilesystem"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.app_a.id, aws_subnet.app_b.id]
  security_group_ids  = [aws_security_group.efs.id]
  private_dns_enabled = true
  
  tags = {
    Name = "${var.name_prefix}-vpce-efs-${var.environment}"
  }
}

################################################################################
#                              EFS Filesystem                                 #
################################################################################

resource "aws_efs_file_system" "wordpress_content" {
  creation_token   = "${var.name_prefix}-wp-content-${var.environment}"
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  encrypted        = false
  
  tags = {
    Name = "${var.name_prefix}-efs-wp-content-${var.environment}"
  }
}

# EFS Mount Targets
resource "aws_efs_mount_target" "wordpress_content_a" {
  file_system_id  = aws_efs_file_system.wordpress_content.id
  subnet_id       = aws_subnet.app_a.id
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_mount_target" "wordpress_content_b" {
  file_system_id  = aws_efs_file_system.wordpress_content.id
  subnet_id       = aws_subnet.app_b.id
  security_groups = [aws_security_group.efs.id]
}

# EFS Access Point
resource "aws_efs_access_point" "wordpress_content" {
  file_system_id = aws_efs_file_system.wordpress_content.id
  
  posix_user {
    gid = 0  # root group
    uid = 0  # root user
  }
  
  root_directory {
    path = "/"
    creation_info {
      owner_gid   = 0
      owner_uid   = 0
      permissions = "777"
    }
  }
  
  tags = {
    Name = "${var.name_prefix}-efs-ap-wp-content-${var.environment}"
  }
}

################################################################################
#                          Aurora Serverless Database                         #
################################################################################

# DB Subnet Group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.name_prefix}-aurora-subnet-group-${var.environment}"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]
  
  tags = {
    Name = "${var.name_prefix}-aurora-subnet-group-${var.environment}"
  }
}

# Aurora Serverless MySQL using external module
module "aurora_mysql" {
  source = "../../terraform-y337-aurora-serverless"
  
  # Database Configuration
  engine_type     = "mysql"
  database_name   = var.database_name
  application     = var.name_prefix
  environment     = var.environment
  
  # Authentication
  master_username = var.db_master_username
  master_password = var.db_master_password
  
  # Capacity
  min_capacity = var.db_min_capacity
  max_capacity = var.db_max_capacity
  cluster_count = var.db_cluster_count
  
  # Networking
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.aurora.id]
  
  # Backup and Maintenance
  skip_final_snapshot          = true
  deletion_protection          = false
  backup_retention_period      = 7
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:04:30-sun:08:00"
  
  # Tags
  tags = var.common_tags
}

################################################################################
#                          WordPress Canary Module                            #
################################################################################

module "wordpress_canary" {
  source = "../"
  
  # Ensure Aurora is fully created before EC2 instances
  depends_on = [
    module.aurora_mysql.aurora_cluster_id,
    module.aurora_mysql.aurora_endpoint
  ]
  
  # Required Variables
  name_prefix               = var.name_prefix
  owner                     = var.owner
  allowed_inbound_cidrs     = var.allowed_inbound_cidrs
  vpc_id                    = aws_vpc.main.id
  
  # Networking - Required subnet variables
  consul_server_subnets     = [aws_subnet.infra_a.id, aws_subnet.infra_b.id]
  wp_client_subnets         = [aws_subnet.app_a.id, aws_subnet.app_b.id]
  wp_client_inbound_subnets = [aws_subnet.dmz_a.id, aws_subnet.dmz_b.id]
  consul_subnets            = [var.infra_subnet_a_cidr, var.infra_subnet_b_cidr]
  wp_subnets                = [var.app_subnet_a_cidr, var.app_subnet_b_cidr]
  
  # Consul Configuration
  consul_servers         = var.consul_servers
  consul_version         = var.consul_version
  consul_cluster_version = var.consul_cluster_version
  consul_ami_id          = var.consul_ami_id != "" ? var.consul_ami_id : data.aws_ami.amazon_linux2.id
  consul_instance_type   = var.consul_instance_type
  
  # WordPress Configuration
  wp_ami_id       = var.wp_ami_id != "" ? var.wp_ami_id : data.aws_ami.amazon_linux2.id
  wp_instance_type = var.wp_instance_type
  wp_servers_min   = var.wp_servers_min
  wp_servers_max   = var.wp_servers_max
  
  # Load Balancer Configuration
  lb_ami_id       = var.lb_ami_id != "" ? var.lb_ami_id : data.aws_ami.amazon_linux2.id
  lb_instance_type = var.lb_instance_type
  lb_servers_min   = var.lb_servers_min
  lb_servers_max   = var.lb_servers_max
  
  # Database Configuration
  wp_db_name       = var.database_name
  wp_db_host       = module.aurora_mysql.aurora_endpoint
  wp_mysql_user    = var.wp_mysql_user
  wp_mysql_user_pw = var.wp_mysql_user_pw
  wp_mysql_root_pw = var.wp_mysql_root_pw
  
  # EFS Configuration
  wp_content_mount_point      = var.wp_content_mount_point
  wp_content_efs_ap_id        = aws_efs_access_point.wordpress_content.id
  wp_content_efs_filesystem_id = aws_efs_file_system.wordpress_content.id
  
  # Instance Configuration
  key_name  = var.key_name
  public_ip = var.public_ip
  
  # Consul Features
  acl_bootstrap_bool    = var.acl_bootstrap_bool
  enable_connect        = var.enable_connect
  consul_config         = var.consul_config
  enable_wan_federation = var.enable_wan_federation
  peer_datacenter_name  = var.peer_datacenter_name
  peer_datacenter_region = var.peer_datacenter_region
  peer_environment_name = var.peer_environment_name
  
  # WordPress Bootstrap
  wp_bootstrap = var.wp_bootstrap
  
  # WordPress Hostname
  wp_hostname = var.wp_hostname
  
  # Tags
  consul_extra_tags = [
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress-canary-test"
      propagate_at_launch = true
    }
  ]
  
  wp_extra_tags = [
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress-canary-test"
      propagate_at_launch = true
    }
  ]
  
  lb_extra_tags = [
    {
      key                 = "Environment"
      value               = var.environment
      propagate_at_launch = true
    },
    {
      key                 = "Project"
      value               = "wordpress-canary-test"
      propagate_at_launch = true
    }
  ]
}
