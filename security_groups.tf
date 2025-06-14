# creates security group to group access rules under - named with a random UUId and suffix (why?)
resource "aws_security_group" "consul" {
  name                        = "${random_id.environment_name.hex}-consul-sg"
  description                 = "Consul servers"
  vpc_id                      = var.vpc_id
}

################################################################################
#            Consul Server Rules                                               #
################################################################################

resource "aws_security_group_rule" "consul_external_egress_all" {
  security_group_id           = aws_security_group.consul.id
  type                        = "egress"
  from_port                   = 0
  to_port                     = 0
  protocol                    = "-1"
  cidr_blocks                 = var.consul_external_egress_all_cidrs
}

resource "aws_security_group_rule" "consul_ssh_igr" {
  security_group_id           = aws_security_group.consul.id
  type                        = "ingress"
  from_port                   = 22
  to_port                     = 22
  protocol                    = "tcp"
  cidr_blocks                 = var.allowed_inbound_cidrs
}

// This rule allows Consul RPC.
resource "aws_security_group_rule" "consul_rpc" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8300
    to_port                  = 8300
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.consul.id
}

// This rule allows Consul API.
resource "aws_security_group_rule" "consul_api_tcp" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8500
    to_port                  = 8500
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.consul.id
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "consul_dns_tcp" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8600
    to_port                  = 8600
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.consul.id
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "consul_dns_udp" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8600
    to_port                  = 8600
    protocol                 = "udp"
    source_security_group_id = aws_security_group.consul.id
}

###
resource "aws_security_group_rule" "wp_to_consul_rpc" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8300
    to_port                  = 8300
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.wp_client.id
}

// This rule allows Consul Serf TCP.
resource "aws_security_group_rule" "wp_to_consul_serf_tcp" {
    security_group_id       = aws_security_group.consul.id
    type                    = "ingress"
    from_port               = 8301
    to_port                 = 8302
    protocol                = "tcp"
    cidr_blocks             = var.wp_to_consul_serf_tcp_cidrs
}

// These rules allow Consul WAN gossip for federation
resource "aws_security_group_rule" "consul_wan_tcp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8302
    to_port           = 8302
    protocol          = "tcp"
    cidr_blocks       = var.consul_wan_tcp_ingress_cidrs
    description       = "Allow incoming Consul WAN gossip TCP traffic"
}

resource "aws_security_group_rule" "consul_wan_udp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8302
    to_port           = 8302
    protocol          = "udp"
    cidr_blocks       = var.consul_wan_udp_ingress_cidrs
    description       = "Allow incoming Consul WAN gossip UDP traffic"
}

// These rules allow Consul WAN gossip egress for federation
resource "aws_security_group_rule" "consul_wan_tcp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8302
    to_port           = 8302
    protocol          = "tcp"
    cidr_blocks       = var.consul_wan_tcp_egress_cidrs
    description       = "Allow outgoing Consul WAN gossip TCP traffic"
}

resource "aws_security_group_rule" "consul_wan_udp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8302
    to_port           = 8302
    protocol          = "udp"
    cidr_blocks       = var.consul_wan_udp_egress_cidrs
    description       = "Allow outgoing Consul WAN gossip UDP traffic"
}

// These rules allow Consul RPC traffic for cross-datacenter communication
resource "aws_security_group_rule" "consul_rpc_wan_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8300
    to_port           = 8300
    protocol          = "tcp"
    cidr_blocks       = var.consul_rpc_wan_ingress_cidrs
    description       = "Allow incoming Consul RPC traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_rpc_wan_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8300
    to_port           = 8300
    protocol          = "tcp"
    cidr_blocks       = var.consul_rpc_wan_egress_cidrs
    description       = "Allow outgoing Consul RPC traffic to other datacenters"
}

// These rules allow Consul API traffic for cross-datacenter communication (needed for UI)
resource "aws_security_group_rule" "consul_api_wan_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8500
    to_port           = 8500
    protocol          = "tcp"
    cidr_blocks       = var.consul_api_wan_ingress_cidrs
    description       = "Allow incoming Consul API traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_api_wan_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8500
    to_port           = 8500
    protocol          = "tcp"
    cidr_blocks       = var.consul_api_wan_egress_cidrs
    description       = "Allow outgoing Consul API traffic to other datacenters"
}

// These rules allow Consul Serf LAN traffic for cross-datacenter service discovery
resource "aws_security_group_rule" "consul_serf_lan_tcp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8301
    to_port           = 8301
    protocol          = "tcp"
    cidr_blocks       = var.consul_serf_lan_tcp_ingress_cidrs
    description       = "Allow incoming Consul Serf LAN TCP traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_serf_lan_tcp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8301
    to_port           = 8301
    protocol          = "tcp"
    cidr_blocks       = var.consul_serf_lan_tcp_egress_cidrs
    description       = "Allow outgoing Consul Serf LAN TCP traffic to other datacenters"
}

resource "aws_security_group_rule" "consul_serf_lan_udp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8301
    to_port           = 8301
    protocol          = "udp"
    cidr_blocks       = var.consul_serf_lan_udp_ingress_cidrs
    description       = "Allow incoming Consul Serf LAN UDP traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_serf_lan_udp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8301
    to_port           = 8301
    protocol          = "udp"
    cidr_blocks       = var.consul_serf_lan_udp_egress_cidrs
    description       = "Allow outgoing Consul Serf LAN UDP traffic to other datacenters"
}

// These rules allow Consul DNS traffic for cross-datacenter service discovery
resource "aws_security_group_rule" "consul_dns_wan_tcp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8600
    to_port           = 8600
    protocol          = "tcp"
    cidr_blocks       = var.consul_dns_wan_tcp_ingress_cidrs
    description       = "Allow incoming Consul DNS TCP traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_dns_wan_tcp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8600
    to_port           = 8600
    protocol          = "tcp"
    cidr_blocks       = var.consul_dns_wan_tcp_egress_cidrs
    description       = "Allow outgoing Consul DNS TCP traffic to other datacenters"
}

resource "aws_security_group_rule" "consul_dns_wan_udp_ingress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "ingress"
    from_port         = 8600
    to_port           = 8600
    protocol          = "udp"
    cidr_blocks       = var.consul_dns_wan_udp_ingress_cidrs
    description       = "Allow incoming Consul DNS UDP traffic from other datacenters"
}

resource "aws_security_group_rule" "consul_dns_wan_udp_egress" {
    count             = var.enable_wan_federation ? 1 : 0
    security_group_id = aws_security_group.consul.id
    type              = "egress"
    from_port         = 8600
    to_port           = 8600
    protocol          = "udp"
    cidr_blocks       = var.consul_dns_wan_udp_egress_cidrs
    description       = "Allow outgoing Consul DNS UDP traffic to other datacenters"
}

// This rule allows Consul Serf UDP.
resource "aws_security_group_rule" "wp_to_consul_serf_udp" {
    security_group_id       = aws_security_group.wp_client.id
    type                    = "ingress"
    from_port               = 8301
    to_port                 = 8302
    protocol                = "udp"
    cidr_blocks             = var.consul_subnets
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "wp_to_consul_dns_tcp" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8600
    to_port                  = 8600
    protocol                 = "tcp"
    source_security_group_id = aws_security_group.wp_client.id
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "wp_to_consul_dns_udp" {
    security_group_id        = aws_security_group.consul.id
    type                     = "ingress"
    from_port                = 8600
    to_port                  = 8600
    protocol                 = "udp"
    source_security_group_id = aws_security_group.wp_client.id
}

################################################################################
#            WordPress Rules                                                   #
################################################################################

resource "aws_security_group" "wp_client" {
    name                    = "${random_id.environment_name.hex}-wp-canary-sg"
    description             = "Consul servers"
    vpc_id                  = var.vpc_id
}

resource "aws_security_group_rule" "wp_consul_icmp_igr" {
    security_group_id       = aws_security_group.wp_client.id
    type                    = "ingress"
    from_port               = -1
    to_port                 = -1
    protocol                = "icmp"
    cidr_blocks             = var.wp_consul_icmp_igr_cidrs
}

resource "aws_security_group_rule" "wp_consul_ssh_igr" {
    security_group_id       = aws_security_group.wp_client.id
    type                    = "ingress"
    from_port               = 22
    to_port                 = 22
    protocol                = "tcp"
    cidr_blocks             = var.consul_subnets
}

resource "aws_security_group_rule" "wp_consul_external_egress_all" {
    security_group_id       = aws_security_group.wp_client.id
    type                    = "egress"
    from_port               = 0
    to_port                 = 0
    protocol                = "-1"
    cidr_blocks             = var.wp_consul_external_egress_all_cidrs
}

// This rule allows Consul RPC.
resource "aws_security_group_rule" "wp_consul_rpc" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 8300
    to_port                     = 8300
    protocol                    = "tcp"
    cidr_blocks                 = var.consul_subnets
}

// This rule allows Consul Serf TCP.
resource "aws_security_group_rule" "wp_consul_serf_tcp" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 8301
    to_port                     = 8302
    protocol                    = "tcp"
    cidr_blocks                 = var.consul_subnets
}

// This rule exposes the Consul API for traffic from the same CIDR block as approved SSH.
resource "aws_security_group_rule" "wp_consul_ui_ingress" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 8500
    to_port                     = 8500
    protocol                    = "tcp"
    cidr_blocks                 = var.consul_subnets
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "wp_consul_dns_tcp" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 8600
    to_port                     = 8600
    protocol                    = "tcp"
    cidr_blocks                 = var.consul_subnets
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "wp_consul_dns_udp" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 8600
    to_port                     = 8600
    protocol                    = "udp"
    cidr_blocks                 = var.consul_subnets
}

# rule to allow ingress from alb port 443 to instances 443 
resource "aws_security_group_rule" "wp_client_external_egress_https" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 443
    to_port                     = 443
    protocol                    = "tcp"
    cidr_blocks                 = var.wp_client_external_ingress_https_cidrs
}

# rule to allow ingress from alb port 80 to instances 80 
resource "aws_security_group_rule" "wp_client_external_egress_http" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 80
    to_port                     = 80
    protocol                    = "tcp"
    cidr_blocks                 = var.wp_client_external_ingress_http_cidrs
}

# rule to allow efs ingress
resource "aws_security_group_rule" "wp_to_efs_tcp" {
    security_group_id           = aws_security_group.wp_client.id
    type                        = "ingress"
    from_port                   = 2049
    to_port                     = 2049
    protocol                    = "tcp"
    cidr_blocks                 = var.wp_subnets
}
