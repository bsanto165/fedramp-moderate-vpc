terraform {
  # 1.9+ is required for cross-variable validation (egress_mode / transit_gateway_id).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}
