# creates Consul autoscaling group for nginx load balancers
resource "aws_autoscaling_group" "lb_servers" {
    name                        = "${aws_launch_template.lb_servers.name}-asg"
    min_size                    = var.lb_servers_min
    max_size                    = var.lb_servers_max
    desired_capacity            = var.lb_servers_min
    wait_for_capacity_timeout   = "480s"
    health_check_grace_period   = 15
    health_check_type           = "EC2"
    vpc_zone_identifier         = [var.wp_client_subnets[0], var.wp_client_subnets[1]]

    launch_template {
        id      = aws_launch_template.lb_servers.id
        version = "$Latest"
    }

    depends_on = [
        aws_autoscaling_group.consul_servers,
        aws_launch_template.lb_servers
    ]

    lifecycle {
        create_before_destroy = true
    }

  dynamic "tag" {
    for_each = var.lb_extra_tags
    content {
        key                 = tag.value.key
        propagate_at_launch = tag.value.propagate_at_launch
        value               = "${var.name_prefix}-${tag.value.value}"
    }
  }
}

# provides a resource for a new autoscaling group launch template
resource "aws_launch_template" "lb_servers" {
    name_prefix   = "${random_id.environment_name.hex}-lb-clients-${var.consul_cluster_version}-"
    image_id      = var.lb_ami_id
    instance_type = var.lb_instance_type
    key_name      = var.key_name
    
    user_data = base64encode(templatefile("${path.module}/scripts/install_hashitools_consul_lb_server.sh.tpl",
        {
        ami                   = var.lb_ami_id,
        environment_name      = "${var.name_prefix}-consul",
        consul_version        = var.consul_version,
        datacenter            = data.aws_region.current.name,
        gossip_key            = local.gossip_encryption_key,
        wp_db_name            = var.wp_db_name,
        wp_mysql_user       = var.wp_mysql_user,
        wp_mysql_user_pw    = var.wp_mysql_user_pw,
        wp_mysql_root_pw    = var.wp_mysql_root_pw,
        peer_datacenter_name  = var.peer_datacenter_name,
        peer_datacenter_region = var.peer_datacenter_region,
        peer_environment_name = var.peer_environment_name,
    }))

    network_interfaces {
        associate_public_ip_address = var.public_ip
        security_groups             = [aws_security_group.wp_client.id]
        delete_on_termination       = true
    }

    iam_instance_profile {
        name = aws_iam_instance_profile.instance_profile.name
    }

    block_device_mappings {
        device_name = "/dev/sda1"
        ebs {
            volume_size = 30
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
      Name = "${terraform.workspace}-lb-server"
      Environment-Name = "${var.name_prefix}-consul"
    }
  }

    lifecycle {
        create_before_destroy = true
    }
}
