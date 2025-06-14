# Data source to get the Consul server instances
data "aws_instances" "consul_servers" {
  filter {
    name   = "tag:Name"
    values = ["${var.name_prefix}-consul-server"]
  }
  
  instance_state_names = ["running"]
  depends_on           = [aws_autoscaling_group.consul_servers]
}

output "wp_asg_id" {
    value       = aws_autoscaling_group.lb_servers.id
}

output "consul_server_autoscaling_group_id" {
    value       = aws_autoscaling_group.consul_servers.id
    description = "Consul server autoscaling group ID"
}

output "consul_server_instance_ids" {
    value       = data.aws_instances.consul_servers.ids
    description = "Consul server instance IDs"
}

output "consul_server_private_ips" {
    description = "Private IP addresses of the Consul servers"
    value       = flatten(data.aws_instances.consul_servers[*].private_ips)
    depends_on  = [aws_autoscaling_group.consul_servers]
}

output "consul_gossip_encryption_key" {
    value       = local.gossip_encryption_key
    description = "Consul gossip encryption key"
    sensitive   = false
}
