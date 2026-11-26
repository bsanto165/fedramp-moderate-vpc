################################################################################
# VPC and default-resource lockdown (SC-7, CM-7)
################################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  instance_tenancy     = "default"

  tags = { Name = "${local.name_prefix}-vpc" }

  lifecycle {
    precondition {
      condition     = length(data.aws_availability_zones.available.names) >= var.az_count
      error_message = "Region does not have ${var.az_count} available AZs."
    }
  }
}

# Strip every rule from the default security group so nothing can use it by accident.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-default-sg-DO-NOT-USE" }
}

# Default NACL with no rules = deny all. Every subnet below gets its own NACL.
resource "aws_default_network_acl" "this" {
  default_network_acl_id = aws_vpc.this.default_network_acl_id
  tags                   = { Name = "${local.name_prefix}-default-nacl-DENY" }

  lifecycle {
    ignore_changes = [subnet_ids]
  }
}

# Default route table with no routes beyond local.
resource "aws_default_route_table" "this" {
  default_route_table_id = aws_vpc.this.default_route_table_id
  route                  = []
  tags                   = { Name = "${local.name_prefix}-default-rt-UNUSED" }
}

################################################################################
# Subnets (no public IPs are ever auto-assigned)
################################################################################

resource "aws_subnet" "public" {
  count = local.create_public ? var.az_count : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-public-${local.azs[count.index]}", Tier = "public" }
}

resource "aws_subnet" "app" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.app_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-app-${local.azs[count.index]}", Tier = "app" }
}

resource "aws_subnet" "data" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.data_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-data-${local.azs[count.index]}", Tier = "data" }
}

resource "aws_subnet" "tgw" {
  count = local.create_tgw ? var.az_count : 0

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.tgw_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${local.name_prefix}-tgw-${local.azs[count.index]}", Tier = "tgw" }
}

################################################################################
# Egress: NAT mode (standalone VPC)
################################################################################

resource "aws_internet_gateway" "this" {
  count  = local.create_public ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-igw" }
}

resource "aws_eip" "nat" {
  count  = local.create_public ? var.az_count : 0
  domain = "vpc"
  tags   = { Name = "${local.name_prefix}-nat-${local.azs[count.index]}" }
}

# One NAT per AZ so an AZ failure does not cut egress for the others.
resource "aws_nat_gateway" "this" {
  count = local.create_public ? var.az_count : 0

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "${local.name_prefix}-nat-${local.azs[count.index]}" }

  depends_on = [aws_internet_gateway.this]
}

################################################################################
# Egress: TGW mode (hub-and-spoke with centralized inspection)
################################################################################

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = local.create_tgw ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = aws_subnet.tgw[*].id
  dns_support        = "enable"

  tags = { Name = "${local.name_prefix}-tgw-attach" }
}

################################################################################
# Route tables
################################################################################

resource "aws_route_table" "public" {
  count  = local.create_public ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-public-rt" }
}

resource "aws_route" "public_igw" {
  count = local.create_public ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  count          = local.create_public ? var.az_count : 0
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# App tier: one route table per AZ (keeps NAT traffic in-AZ).
resource "aws_route_table" "app" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-app-rt-${local.azs[count.index]}" }
}

resource "aws_route" "app_nat" {
  count = local.create_public ? var.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route" "app_tgw" {
  count = local.create_tgw ? var.az_count : 0

  route_table_id         = aws_route_table.app[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "app" {
  count          = var.az_count
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index].id
}

# Data tier: local + gateway endpoints only, unless data_tier_egress = true.
resource "aws_route_table" "data" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-data-rt-${local.azs[count.index]}" }
}

resource "aws_route" "data_nat" {
  count = local.create_public && var.data_tier_egress ? var.az_count : 0

  route_table_id         = aws_route_table.data[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route" "data_tgw" {
  count = local.create_tgw && var.data_tier_egress ? var.az_count : 0

  route_table_id         = aws_route_table.data[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}

resource "aws_route_table_association" "data" {
  count          = var.az_count
  subnet_id      = aws_subnet.data[count.index].id
  route_table_id = aws_route_table.data[count.index].id
}

# TGW attachment subnets: local routes only.
resource "aws_route_table" "tgw" {
  count  = local.create_tgw ? 1 : 0
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${local.name_prefix}-tgw-rt" }
}

resource "aws_route_table_association" "tgw" {
  count          = local.create_tgw ? var.az_count : 0
  subnet_id      = aws_subnet.tgw[count.index].id
  route_table_id = aws_route_table.tgw[0].id
}
