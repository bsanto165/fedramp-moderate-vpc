variable "region" {
  description = "AWS GovCloud region."
  type        = string
  default     = "us-gov-west-1"

  validation {
    condition     = can(regex("^us-gov-(west|east)-1$", var.region))
    error_message = "region must be us-gov-west-1 or us-gov-east-1."
  }
}

variable "name" {
  description = "Short system name used in resource names (lowercase, digits, hyphens)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 chars: lowercase letters, digits, hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment name, e.g. dev, test, prod."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{2,16}$", var.environment))
    error_message = "environment must be 2-16 chars: lowercase letters, digits, hyphens."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR, /16 to /20. Must not overlap agency or other VPC ranges (allocate from IPAM)."
  type        = string

  validation {
    condition = can(cidrhost(var.vpc_cidr, 0)) && try(
      tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 20,
      false
    )
    error_message = "vpc_cidr must be a valid IPv4 CIDR between /16 and /20."
  }
}

variable "az_count" {
  description = "Number of Availability Zones to span (CP-7/SC-5 resilience). GovCloud regions have 3."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "egress_mode" {
  description = <<-EOT
    How private subnets reach anything outside the VPC:
      tgw  - default route to a Transit Gateway (centralized inspection VPC; recommended).
      nat  - standalone VPC with public subnets, IGW and one NAT gateway per AZ.
      none - fully isolated; AWS APIs reachable only through VPC endpoints.
  EOT
  type        = string
  default     = "tgw"

  validation {
    condition     = contains(["tgw", "nat", "none"], var.egress_mode)
    error_message = "egress_mode must be tgw, nat or none."
  }
}

variable "transit_gateway_id" {
  description = "Transit Gateway ID (required when egress_mode = tgw). May be RAM-shared from a network account."
  type        = string
  default     = null

  validation {
    condition     = var.egress_mode != "tgw" || var.transit_gateway_id != null
    error_message = "transit_gateway_id is required when egress_mode = tgw."
  }
}

variable "data_tier_egress" {
  description = "Give the data tier a default route (NAT or TGW). Off by default: data tier reaches only the VPC and endpoints."
  type        = bool
  default     = false
}

variable "data_ports" {
  description = "TCP ports the app tier may use to reach the data tier (enforced in the data-tier NACL)."
  type        = list(number)
  default     = [5432, 3306, 1433]
}

variable "app_ingress_cidrs" {
  description = "External CIDRs (e.g. agency networks via TGW) allowed to reach the app tier on TCP 443."
  type        = list(string)
  default     = []
}

variable "interface_endpoints" {
  description = "Interface endpoint service suffixes (com.amazonaws.<region>.<suffix>). Verify availability in your region."
  type        = list(string)
  default = [
    "ssm",
    "ssmmessages",
    "ec2messages",
    "ec2",
    "kms",
    "logs",
    "monitoring",
    "sts",
    "secretsmanager",
    "ecr.api",
    "ecr.dkr",
  ]
}

variable "gateway_endpoints" {
  description = "Gateway endpoint services."
  type        = list(string)
  default     = ["s3", "dynamodb"]
}

variable "organization_id" {
  description = "AWS Organizations ID. When set, gateway endpoint policies only allow principals from this org (data exfiltration control)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch retention for flow and DNS logs. OMB M-21-31 calls for 12 months active storage."
  type        = number
  default     = 365

  validation {
    condition     = contains([365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a CloudWatch retention value of 365 or more."
  }
}

variable "enable_dns_query_logging" {
  description = "Log all Route 53 Resolver DNS queries from the VPC (AU-2, SI-4)."
  type        = bool
  default     = true
}

variable "kms_deletion_window_days" {
  description = "Waiting period before the log KMS key is deleted."
  type        = number
  default     = 30
}

variable "use_fips_endpoint" {
  description = "Use FIPS endpoints for all AWS API calls made by Terraform."
  type        = bool
  default     = true
}

variable "allowed_account_ids" {
  description = "Account IDs Terraform may operate in. Strongly recommended."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Extra tags for every resource (e.g. SystemId, DataClassification, Owner)."
  type        = map(string)
  default     = {}
}

variable "target_account_id" {
  description = "Workload account to deploy into via role assumption. Null = use the caller's credentials directly."
  type        = string
  default     = null
}

variable "member_role_name" {
  description = "Role assumed in the target account. The pipeline sets terraform-plan for plans and terraform-apply for applies."
  type        = string
  default     = "terraform-apply"
}

variable "partition" {
  description = "AWS partition (used to build the assume-role ARN)."
  type        = string
  default     = "aws-us-gov"
}
