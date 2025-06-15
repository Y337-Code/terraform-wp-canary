# Required Parameters
variable "allowed_inbound_cidrs" {
  type        = list(string)
  description = "List of CIDR blocks to permit inbound Consul access from"
}

variable "wp_client_subnets" {
  type    = list(string)
}

variable "consul_server_subnets" {
  type    = list(string)
}

variable "wp_client_inbound_subnets" {
  type    = list(string)
}

variable "consul_subnets" {
  type    = list(string)
}

variable "wp_subnets" {
  type    = list(string)
}

variable "consul_version" {
  type        = string
  description = "Consul version to install"
}

variable "name_prefix" {
  type        = string
  description = "prefix used in resource names"
}

variable "owner" {
  type        = string
  description = "value of owner tag on EC2 instances"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID"
}

# Optional Parameters
variable "acl_bootstrap_bool" {
  type        = bool
  default     = true
  description = "Initial ACL Bootstrap configurations"
}

variable "lb_servers_min" {
  default     = "2"
  description = "number of min Consul instances"
}

variable "lb_servers_max" {
  default     = "2"
  description = "number of min Consul instances"
}

variable "wp_servers_min" {
  default     = "2"
  description = "number of min Consul instances"
}

variable "wp_servers_max" {
  default     = "6"
  description = "number of min Consul instances"
}

variable "consul_config" {
  type        = map(string)
  default     = {}
  description = "HCL Object with additional configuration overrides supplied to the consul servers. This is converted to JSON before rendering via the template."
}

variable "consul_cluster_version" {
  type        = string
  default     = "0.0.1"
  description = "Custom Version Tag for Upgrade Migrations"
}

variable "consul_servers" {
  type        = number
  default     = "3"
  description = "number of Consul instances"
}

variable "enable_connect" {
  type        = bool
  default     = false
  description = "Whether Consul Connect should be enabled on the cluster"
}

variable "lb_instance_type" {
  default     = ""
  description = "Instance type for Consul instances"
}

variable "wp_instance_type" {
  default     = ""
  description = "Instance type for Consul instances"
}

variable "consul_instance_type" {
  default     = ""
  description = "Instance type for Consul instances"
}

variable "key_name" {
  type        = string
  default     = "default"
  description = "SSH key name for Consul instances"
}

variable "public_ip" {
  type        = bool
  default     = false
  description = "should ec2 instance have public ip?"
}

variable "ami_id" {
  type        = string
  default     = ""
  description = "EC2 instance AMI ID"
}

variable "wp_db_name" {
  type        = string
  sensitive   = true
  default     = "wpcanary"
  description = "database name for wordpress"
}

variable "wp_mysql_user" {
  type        = string
  sensitive   = true
  default     = "wpcanary"
  description = "db user for wordpress"
}

variable "wp_mysql_user_pw" {
  type        = string
  sensitive   = true
  default     = "wpcanary"
  description = "password for the db user for wordpress"
}

variable "wp_mysql_root_pw" {
  type        = string
  sensitive   = true
  default     = "wpcanary"
  description = "root password for mysql"
}

variable "lb_ami_id" {
  type = string
  default = ""
}

variable "wp_ami_id" {
  type = string
  default = ""
}

variable "consul_ami_id" {
  type = string
  default = ""
}

variable "wp_db_host" {
  type = string
  default = "localhost"
}

variable "wp_content_mount_point" {
  type = string
}

variable "wp_content_efs_ap_id" {
  type = string
}

variable "wp_content_efs_filesystem_id" {
  type        = string
  description = "EFS filesystem ID for WordPress content"
}

variable "wp_extra_tags" {
  default = [
    {
      key                 = "Name"
      value               = "wp-server"
      propagate_at_launch = true
    },
    {
      key                 = "Cluster-Version"
      value               = "0.0.1"
      propagate_at_launch = true
    },
    {
      key                 = "Environment-Name"
      value               = "consul"
      propagate_at_launch = true
    },
    {
      key                 = "owner"
      value               = "WP"
      propagate_at_launch = true
    }
  ]
}

variable "lb_extra_tags" {
  default = [
    {
      key                 = "Name"
      value               = "lb-server"
      propagate_at_launch = true
    },
    {
      key                 = "Cluster-Version"
      value               = "0.0.1"
      propagate_at_launch = true
    },
    {
      key                 = "Environment-Name"
      value               = "consul"
      propagate_at_launch = true
    },
    {
      key                 = "owner"
      value               = "WP"
      propagate_at_launch = true
    }
  ]
}

variable "consul_extra_tags" {
  default = [
    {
      key                 = "Name"
      value               = "consul-server"
      propagate_at_launch = true
    },
    {
      key                 = "Cluster-Version"
      value               = "0.0.1"
      propagate_at_launch = true
    },
    {
      key                 = "Environment-Name"
      value               = "consul"
      propagate_at_launch = true
    },
    {
      key                 = "owner"
      value               = "WP"
      propagate_at_launch = true
    }
  ]
}


variable "consul_external_egress_all_cidrs" {
  description = "CIDR blocks for consul external egress all rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wp_to_consul_serf_tcp_cidrs" {
  description = "CIDR blocks for wp_to_consul_serf_tcp rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_wan_tcp_ingress_cidrs" {
  description = "CIDR blocks for consul_wan_tcp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_wan_udp_ingress_cidrs" {
  description = "CIDR blocks for consul_wan_udp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_wan_tcp_egress_cidrs" {
  description = "CIDR blocks for consul_wan_tcp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_wan_udp_egress_cidrs" {
  description = "CIDR blocks for consul_wan_udp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_rpc_wan_ingress_cidrs" {
  description = "CIDR blocks for consul_rpc_wan_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_rpc_wan_egress_cidrs" {
  description = "CIDR blocks for consul_rpc_wan_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_api_wan_ingress_cidrs" {
  description = "CIDR blocks for consul_api_wan_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_api_wan_egress_cidrs" {
  description = "CIDR blocks for consul_api_wan_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_serf_lan_tcp_ingress_cidrs" {
  description = "CIDR blocks for consul_serf_lan_tcp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_serf_lan_tcp_egress_cidrs" {
  description = "CIDR blocks for consul_serf_lan_tcp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_serf_lan_udp_ingress_cidrs" {
  description = "CIDR blocks for consul_serf_lan_udp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_serf_lan_udp_egress_cidrs" {
  description = "CIDR blocks for consul_serf_lan_udp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_dns_wan_tcp_ingress_cidrs" {
  description = "CIDR blocks for consul_dns_wan_tcp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_dns_wan_tcp_egress_cidrs" {
  description = "CIDR blocks for consul_dns_wan_tcp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_dns_wan_udp_ingress_cidrs" {
  description = "CIDR blocks for consul_dns_wan_udp_ingress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "consul_dns_wan_udp_egress_cidrs" {
  description = "CIDR blocks for consul_dns_wan_udp_egress rule (WAN Federation)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wp_consul_icmp_igr_cidrs" {
  description = "CIDR blocks for wp_consul_icmp_igr rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wp_consul_external_egress_all_cidrs" {
  description = "CIDR blocks for wp_consul_external_egress_all rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wp_client_external_ingress_https_cidrs" {
  description = "CIDR blocks for wp_client_external_ingress_https rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "wp_client_external_ingress_http_cidrs" {
  description = "CIDR blocks for wp_client_external_ingress_http rule"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# WAN Federation Parameters
variable "enable_wan_federation" {
  type        = bool
  default     = false
  description = "Whether to enable WAN federation with another Consul datacenter"
}

variable "peer_datacenter_name" {
  type        = string
  default     = ""
  description = "Name of the peer datacenter to join via WAN"
}

variable "peer_datacenter_region" {
  type        = string
  default     = ""
  description = "AWS region of the peer datacenter"
}

variable "peer_environment_name" {
  type        = string
  default     = ""
  description = "Environment name tag value of the peer datacenter's Consul servers"
}

variable "shared_gossip_key" {
  type        = string
  default     = ""
  description = "Shared gossip encryption key for WAN federation. Must be the same across all datacenters."
  sensitive   = true
}

variable "wp_bootstrap" {
  type        = bool
  default     = false
  description = "Whether to automatically download and install the latest version of WordPress during server initialization"
}

variable "wp_hostname" {
  type        = string
  description = "Hostname/domain for WordPress site (used for WP_HOME and WP_SITEURL)"
}
