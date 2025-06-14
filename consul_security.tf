resource "random_uuid" "consul_master_token" {}
resource "random_uuid" "consul_agent_server_token" {}
resource "random_uuid" "consul_snapshot_token" {}

resource "random_id" "consul_gossip_encryption_key" {
    byte_length = 32
}

locals {
    # Use the shared gossip key if provided and WAN federation is enabled, otherwise use the random key
    gossip_encryption_key = var.enable_wan_federation && var.shared_gossip_key != "" ? var.shared_gossip_key : random_id.consul_gossip_encryption_key.b64_std
}
