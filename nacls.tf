################################################################################
# Network ACLs: stateless, subnet-level defense in depth (SC-7, AC-4).
# Security groups remain the primary, stateful control for workloads.
#
# Note: NACLs cannot reference prefix lists, so S3/DynamoDB gateway endpoint
# traffic needs TCP 443 to 0.0.0.0/0. In tiers without a default route, that
# rule can only ever reach the gateway endpoints.
################################################################################

resource "aws_network_acl" "public" {
  #checkov:skip=CKV_AWS_229:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_230:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_231:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_232:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  count = local.create_public ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  # HTTPS in (load balancers)
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Return traffic for NAT and outbound connections
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Private subnets sending through NAT
  ingress {
    rule_no    = 120
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${local.name_prefix}-public-nacl" }
}

resource "aws_network_acl" "app" {
  #checkov:skip=CKV_AWS_229:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_230:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_231:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_232:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.app[*].id

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Return traffic for outbound HTTPS (TGW/NAT egress, gateway endpoints)
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  dynamic "ingress" {
    for_each = { for i, c in var.app_ingress_cidrs : tostring(i) => c }
    content {
      rule_no    = 200 + tonumber(ingress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 443
      to_port    = 443
    }
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Responses to external clients (e.g. agency users via TGW)
  egress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  tags = { Name = "${local.name_prefix}-app-nacl" }
}

resource "aws_network_acl" "data" {
  #checkov:skip=CKV_AWS_229:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_230:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_231:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_232:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.data[*].id

  # App tier -> data tier, only on approved database ports
  dynamic "ingress" {
    for_each = local.data_ingress_pairs
    content {
      rule_no    = 100 + tonumber(ingress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = ingress.value[0]
      from_port  = ingress.value[1]
      to_port    = ingress.value[1]
    }
  }

  # Data-to-data (replication, clustering)
  dynamic "ingress" {
    for_each = { for i, c in local.data_cidrs : tostring(i) => c }
    content {
      rule_no    = 200 + tonumber(ingress.key)
      protocol   = "-1"
      action     = "allow"
      cidr_block = ingress.value
      from_port  = 0
      to_port    = 0
    }
  }

  # Return traffic for outbound HTTPS to endpoints
  ingress {
    rule_no    = 300
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  # Responses back to the app tier
  dynamic "egress" {
    for_each = { for i, c in local.app_cidrs : tostring(i) => c }
    content {
      rule_no    = 100 + tonumber(egress.key)
      protocol   = "tcp"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 1024
      to_port    = 65535
    }
  }

  dynamic "egress" {
    for_each = { for i, c in local.data_cidrs : tostring(i) => c }
    content {
      rule_no    = 200 + tonumber(egress.key)
      protocol   = "-1"
      action     = "allow"
      cidr_block = egress.value
      from_port  = 0
      to_port    = 0
    }
  }

  # HTTPS to interface/gateway endpoints (and egress, if data_tier_egress = true)
  egress {
    rule_no    = 300
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  tags = { Name = "${local.name_prefix}-data-nacl" }
}

# AWS recommends open NACLs on TGW attachment subnets; filtering happens
# in the inspection VPC and on the workload subnets.
resource "aws_network_acl" "tgw" {
  #checkov:skip=CKV_AWS_229:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_230:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_231:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  #checkov:skip=CKV_AWS_232:Ephemeral/return ranges required by stateless NACLs; SGs enforce per-port access
  count = local.create_tgw ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.tgw[*].id

  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "${local.name_prefix}-tgw-nacl" }
}
