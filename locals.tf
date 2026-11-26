data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name_prefix = "${var.name}-${var.environment}"
  partition   = data.aws_partition.current.partition # "aws-us-gov"
  dns_suffix  = data.aws_partition.current.dns_suffix
  account_id  = data.aws_caller_identity.current.account_id

  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  create_public = var.egress_mode == "nat"
  create_tgw    = var.egress_mode == "tgw"

  # Subnet plan: VPC split into 16 equal blocks.
  #   blocks 0-3   public (only when egress_mode = nat)
  #   blocks 4-7   app (private)
  #   blocks 8-11  data (private, isolated)
  #   blocks 12-14 reserved for growth
  #   block 15     carved into /28s for TGW attachment subnets
  vpc_prefix  = tonumber(split("/", var.vpc_cidr)[1])
  tgw_newbits = 28 - (local.vpc_prefix + 4)

  public_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  app_cidrs    = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, 4 + i)]
  data_cidrs   = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, 8 + i)]
  tgw_cidrs    = [for i in range(var.az_count) : cidrsubnet(cidrsubnet(var.vpc_cidr, 4, 15), local.tgw_newbits, i)]

  # Every app-CIDR x data-port pair becomes one data-tier NACL rule.
  data_ingress_pairs = { for idx, pair in setproduct(local.app_cidrs, var.data_ports) : tostring(idx) => pair }

  # Extended flow log format (v5 fields) for SI-4 / AU-3 detail.
  flow_log_fields = [
    "version", "account-id", "interface-id", "srcaddr", "dstaddr", "srcport", "dstport",
    "protocol", "packets", "bytes", "start", "end", "action", "log-status",
    "vpc-id", "subnet-id", "instance-id", "tcp-flags", "type", "pkt-srcaddr", "pkt-dstaddr",
    "region", "az-id", "flow-direction", "traffic-path",
  ]
  flow_log_format = join(" ", [for f in local.flow_log_fields : format("$${%s}", f)])
}
