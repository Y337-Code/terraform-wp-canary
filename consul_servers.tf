# data source for current (working) aws region
data "aws_region" "current" {}

# creates random UUID for the environment name
resource "random_id" "environment_name" {
    byte_length = 4
    prefix      = "${var.name_prefix}-"
}

# creates Consul autoscaling group for servers
resource "aws_autoscaling_group" "consul_servers" {
    name                      = "${aws_launch_template.consul_servers.name}-asg"
    min_size                  = var.consul_servers
    max_size                  = var.consul_servers
    desired_capacity          = var.consul_servers
    wait_for_capacity_timeout = "480s"
    health_check_grace_period = 15
    health_check_type         = "EC2"
    vpc_zone_identifier       = [var.consul_server_subnets[0], var.consul_server_subnets[1]]

    launch_template {
        id      = aws_launch_template.consul_servers.id
        version = "$Latest"
    }

    lifecycle {
        create_before_destroy = true
    }
    dynamic "tag" {
    for_each = var.consul_extra_tags
    content {
        key                 = tag.value.key
        propagate_at_launch = tag.value.propagate_at_launch
        value               = "${var.name_prefix}-${tag.value.value}"
    }
  }
}

# provides a resource for a new autoscaling group launch template
resource "aws_launch_template" "consul_servers" {
    name_prefix   = "${random_id.environment_name.hex}-consul-servers-${var.consul_cluster_version}-"
    image_id      = var.consul_ami_id
    instance_type = var.consul_instance_type
    key_name      = var.key_name
    
    user_data = base64encode(templatefile("${path.module}/scripts/install_hashitools_consul_server.sh.tpl",
        {
        ami                    = var.consul_ami_id,
        environment_name       = "${var.name_prefix}-consul",
        consul_version         = var.consul_version,
        datacenter             = data.aws_region.current.name,
        bootstrap_expect       = var.consul_servers,
        total_nodes            = var.consul_servers,
        gossip_key             = local.gossip_encryption_key,
        master_token           = random_uuid.consul_master_token.result,
        agent_server_token     = random_uuid.consul_agent_server_token.result,
        snapshot_token         = random_uuid.consul_snapshot_token.result,
        consul_cluster_version = var.consul_cluster_version,
        acl_bootstrap_bool     = var.acl_bootstrap_bool,
        enable_connect         = var.enable_connect,
        consul_config          = var.consul_config,
        enable_wan_federation  = var.enable_wan_federation,
        peer_datacenter_name   = var.peer_datacenter_name,
        peer_datacenter_region = var.peer_datacenter_region,
        peer_environment_name  = var.peer_environment_name,
    }))

    network_interfaces {
        associate_public_ip_address = var.public_ip
        security_groups             = [aws_security_group.consul.id]
        delete_on_termination       = true
    }

    iam_instance_profile {
        name = aws_iam_instance_profile.instance_profile.name
    }

    block_device_mappings {
        device_name = "/dev/sda1"
        ebs {
            volume_type = "io1"
            volume_size = 50
            iops        = 2500
            delete_on_termination = true
        }
    }

    metadata_options {
        http_endpoint               = "enabled"
        http_tokens                = "required"
        http_put_response_hop_limit = 1
        http_protocol_ipv6         = "disabled"
    }

    tag_specifications {
        resource_type = "instance"
        tags = {
            Name = "${terraform.workspace}-consul-server"
            Environment-Name = "${var.name_prefix}-consul"
        }
    }

    lifecycle {
        create_before_destroy = true
    }
}
