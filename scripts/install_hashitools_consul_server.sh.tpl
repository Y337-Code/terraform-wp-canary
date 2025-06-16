#!/usr/bin/env bash

yum -y update
yum -y upgrade

yum install -y curl wget unzip yum-utils shadow-utils tuned
yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
yum -y install consul jq

echo "Configuring system time"
timedatectl set-timezone UTC

echo "Starting deployment from AMI: ${ami}"
INSTANCE_ID=`curl -s http://169.254.169.254/latest/meta-data/instance-id`
AVAILABILITY_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
LOCAL_IPV4=`curl -s http://169.254.169.254/latest/meta-data/local-ipv4`

cat << EOF > /etc/consul.d/consul.hcl
datacenter          = "${datacenter}"
server              = true
bootstrap_expect    = ${bootstrap_expect}
data_dir            = "/opt/consul/data"
advertise_addr      = "$${LOCAL_IPV4}"
client_addr         = "0.0.0.0"
log_level           = "INFO"
ui                  = true

# AWS cloud join
retry_join          = ["provider=aws tag_key=Environment-Name tag_value=${environment_name}"]

# Max connections for the HTTP API
limits {
  http_max_conns_per_client = 128
}
performance {
    raft_multiplier = 1
}

# acl {
#   enabled        = true
#   %{ if acl_bootstrap_bool }default_policy = "allow"%{ else }default_policy = "deny"%{ endif }
#   enable_token_persistence = true
#   tokens {
#     master = "${master_token}"%{ if !acl_bootstrap_bool }
#     agent  = "${agent_server_token}"%{ endif }
#   }
# }

encrypt = "${gossip_key}"
EOF

cat << EOF > /etc/consul.d/autopilot.hcl
autopilot {
  upgrade_version_tag = "consul_cluster_version"
}
EOF

cat << EOF > /etc/consul.d/cluster_version.hcl
node_meta = {
    consul_cluster_version = "${consul_cluster_version}"
}
EOF

%{ if enable_connect }
cat << EOF > /etc/consul.d/connect.hcl
connect {
  enabled = true
}
EOF
%{ endif }

%{ if consul_config != {} }
cat << EOF > /etc/consul.d/zz-override.json
${jsonencode(consul_config)}
EOF
%{ endif }

%{ if enable_wan_federation }
# WAN federation configuration
cat << EOF > /etc/consul.d/wan_federation.hcl
retry_join_wan = ["provider=aws tag_key=Environment-Name tag_value=${peer_environment_name}-consul region=${peer_datacenter_region}"]
translate_wan_addrs = true
EOF
%{ endif }


%{ if acl_bootstrap_bool }
cat << EOF > /tmp/bootstrap_tokens.sh
#!/bin/bash
# export CONSUL_HTTP_TOKEN=${master_token}
# echo "Creating Consul ACL policies......"
# if ! consul kv get acl_bootstrap 2>/dev/null; then
#   consul kv put  acl_bootstrap 1

#   echo '
#   node_prefix "" {
#     policy = "write"
#   }
#   service_prefix "" {
#     policy = "read"
#   }
#   service "consul" {
#     policy = "write"
#   }
#   agent_prefix "" {
#     policy = "write"
#   }' | consul acl policy create -name consul-agent-server -rules -

#   # echo '
#   # acl = "write"
#   # key "consul-snapshot/lock" {
#   # policy = "write"
#   # }
#   # session_prefix "" {
#   # policy = "write"
#   # }
#   # service "consul-snapshot" {
#   # policy = "write"
#   # }' | consul acl policy create -name snapshot_agent -rules -

#   echo '
#   node_prefix "" {
#     policy = "read"
#   }
#   service_prefix "" {
#     policy = "read"
#   }
#   session_prefix "" {
#     policy = "read"
#   }
#   agent_prefix "" {
#     policy = "read"
#   }
#   query_prefix "" {
#     policy = "read"
#   }
#   operator = "read"' |  consul acl policy create -name anonymous -rules -

#   consul acl token create -description "consul agent server token" -policy-name consul-agent-server -secret "${agent_server_token}" 1>/dev/null
#   # consul acl token create -description "consul snapshot agent" -policy-name snapshot_agent -secret "${snapshot_token}" 1>/dev/null
#   consul acl token update -id anonymous -policy-name anonymous 1>/dev/null
# else
#   echo "Bootstrap already completed"
# fi
EOF

chmod 700 /tmp/bootstrap_tokens.sh

%{ endif }

chown -R consul:consul /etc/consul.d
chmod -R 640 /etc/consul.d/*

systemctl daemon-reload
systemctl enable consul
systemctl start consul

# Wait for consul-kv to come online
while true; do
    curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -e . && break
    sleep 5
done

# Wait until all new node versions are online
until [[ $TOTAL_NEW -ge ${total_nodes} ]]; do
    TOTAL_NEW=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version == "${consul_cluster_version}")) | length'`
    sleep 5
    echo "Current New Node Count: $TOTAL_NEW"
done

# Wait for a leader
until [[ $LEADER -eq 1 ]]; do
    let LEADER=0
    echo "Fetching new node ID's"
    NEW_NODE_IDS=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -r 'map(select(.NodeMeta.consul_cluster_version == "${consul_cluster_version}")) | .[].ID'`
    # Wait until all new nodes are voting
    until [[ $VOTERS -eq ${bootstrap_expect} ]]; do
        let VOTERS=0
        for ID in $NEW_NODE_IDS; do
            echo "Checking $ID"
            curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -e ".Servers[] | select(.ID == \"$ID\" and .Voter == true)" && let "VOTERS+=1" && echo "Current Voters: $VOTERS"
            sleep 2
        done
    done
    echo "Checking Old Nodes"
    OLD_NODES=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | length'`
    echo "Current Old Node Count: $OLD_NODES"
    # Wait for old nodes to drop from voting
    until [[ $OLD_NODES -eq 0 ]]; do
        OLD_NODES=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | length'`
        OLD_NODE_IDS=`curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -r 'map(select(.NodeMeta.consul_cluster_version != "${consul_cluster_version}")) | .[].ID'`
        for ID in $OLD_NODE_IDS; do
            echo "Checking Old $ID"
            curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -e ".Servers[] | select(.ID == \"$ID\" and .Voter == false)" && let "OLD_NODES-=1" && echo "Checking Old Nodes for Voters: $OLD_NODES"
            sleep 2
        done
    done
    # Check if there is a leader running the newest version
    LEADER_ID=`curl -s http://127.0.0.1:8500/v1/operator/autopilot/health | jq -er ".Servers[] | select(.Leader == true) | .ID"`
    curl -s http://127.0.0.1:8500/v1/catalog/service/consul | jq -er ".[] | select(.ID == \"$LEADER_ID\" and .NodeMeta.consul_cluster_version == \"${consul_cluster_version}\")" && let "LEADER+=1" && echo "New Leader: $LEADER_ID"
    sleep 2
done

%{ if acl_bootstrap_bool }/tmp/bootstrap_tokens.sh%{ endif }
echo "$INSTANCE_ID determined all nodes to be healthy and ready to go <3"

# Set required Consul KV pairs if they don't already exist
echo "Setting required Consul KV pairs..."

# Set canary flag
if ! consul kv get canary &>/dev/null; then
  echo "Setting canary=false"
  consul kv put canary false
else
  echo "canary key already exists, skipping"
fi

# Set canary IP pattern replace 8.8.8.8 with canary IP ranges
if ! consul kv get canary_ip &>/dev/null; then
  echo "Setting canary IP"
  consul kv put canary_ip "8.8.8.8 1;"
else
  echo "canary/ips key already exists, skipping"
fi

# Set peer datacenter name if WAN federation is enabled
if [[ "${enable_wan_federation}" == "true" ]]; then
  if ! consul kv get peer_datacenter_name &>/dev/null; then
    echo "Setting peer_datacenter_name=${peer_datacenter_name}"
    consul kv put peer_datacenter_name "${peer_datacenter_name}"
  else
    echo "peer_datacenter_name key already exists, skipping"
  fi
fi

%{ if enable_wan_federation }
# Create WAN join and cleanup script
cat << EOF > /usr/local/bin/consul-wan-join.sh
#!/bin/bash

set -euo pipefail

TARGET_REGION="${peer_datacenter_region}"
TARGET_DATACENTER="${peer_datacenter_name}"
CONSUL_TAG_VALUE="${peer_environment_name}-consul-server"
JOIN_PORT="8302"

# Attempt WAN join to peer datacenter
attempt_wan_join() {
  if consul catalog datacenters | grep -q "\$TARGET_DATACENTER"; then
    echo "WAN federation already established with \$TARGET_DATACENTER"
    return 0
  fi

  echo "Querying EC2 for Consul servers in \$TARGET_REGION with tag Name=\$CONSUL_TAG_VALUE..."
  SERVER_IPS=\$(aws ec2 describe-instances --region "\$TARGET_REGION" \\
    --filters "Name=tag:Name,Values=\$CONSUL_TAG_VALUE" \\
              "Name=instance-state-name,Values=running" \\
    --query "Reservations[].Instances[].PrivateIpAddress" \\
    --output text)

  if [[ -z "\$SERVER_IPS" ]]; then
    echo "No running Consul servers found with tag \$CONSUL_TAG_VALUE in \$TARGET_REGION"
    return 1
  fi

  echo "Discovered Consul server IPs: \$SERVER_IPS"

  for IP in \$SERVER_IPS; do
    echo "Attempting WAN join to \$IP..."
    if consul join -wan "\$IP:\$JOIN_PORT"; then
      echo "Successfully joined \$IP"
      return 0
    else
      echo "Failed to join \$IP, continuing..."
    fi
  done

  echo "Could not join any Consul servers in \$TARGET_REGION"
  return 1
}

# Clean up failed WAN members
cleanup_failed_nodes() {
  FAILED_NODES=\$(consul members -wan | awk '/failed/ {print \$1}')
  for NODE in \$FAILED_NODES; do
    echo "Removing failed WAN node: \$NODE"
    consul force-leave -wan "\$NODE"
  done
}

# Loop every 5 minutes
while true; do
  attempt_wan_join
  cleanup_failed_nodes
  sleep 300
done
EOF

chmod +x /usr/local/bin/consul-wan-join.sh

# Create systemd service for WAN join
cat << EOF > /etc/systemd/system/consul-wan-join.service
[Unit]
Description=Consul WAN Federation Service
After=consul.service
Requires=consul.service

[Service]
Type=simple
ExecStart=/usr/local/bin/consul-wan-join.sh
Restart=always
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable consul-wan-join.service
systemctl start consul-wan-join.service
%{ endif }

cat <<EOL >> /etc/sysctl.conf
net.core.somaxconn = 4096
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_wmem = 4096 12582912 16777216
net.ipv4.tcp_rmem = 4096 12582912 16777216
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_syn_backlog = 20480
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_max_syn_backlog = 1280
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.tcp_timestamps = 0
fs.file-max = 70000
fs.suid_dumpable = 0
kernel.exec-shield = 1
kernel.randomize_va_space = 2
EOL

sysctl -p

cat <<EOL >> /etc/sysconfig/network
NETWORKING_IPV6=no
IPV6INIT=no
EOL

sudo sed -i '/udp6\s\+tpi_clts\s\+v\s\+inet6\s\+udp\s\+-\s\+-/ s/^/#/' /etc/netconfig
sudo sed -i '/tcp6\s\+tpi_cots_ord\s\+v\s\+inet6\s\+tcp\s\+-\s\+-/ s/^/#/' /etc/netconfig

echo "install dccp /bin/false" > /etc/modprobe.d/dccp.conf
echo "install sctp /bin/false" > /etc/modprobe.d/sctp.conf
echo "install rds /bin/false" > /etc/modprobe.d/rds.conf
echo "install tipc /bin/false" > /etc/modprobe.d/tipc.conf
echo "install cramfs /bin/false" > /etc/modprobe.d/cramfs.conf
echo "install freevxfs /bin/false" > /etc/modprobe.d/freevxfs.conf
echo "install jffs2 /bin/false" > /etc/modprobe.d/jffs2.conf
echo "install hfs /bin/false" > /etc/modprobe.d/hfs.conf
echo "install hfsplus /bin/false" > /etc/modprobe.d/hfsplus.conf
echo "install squashfs /bin/false" > /etc/modprobe.d/squashfs.conf
echo "install udf /bin/false" > /etc/modprobe.d/udf.conf

sudo systemctl enable tuned
sudo tuned-adm profile aws

systemctl reboot
