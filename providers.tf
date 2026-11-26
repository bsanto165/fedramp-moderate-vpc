provider "aws" {
  region = var.region

  # SC-13: route all AWS API calls through FIPS 140 validated endpoints.
  use_fips_endpoint = var.use_fips_endpoint

  # Guard against applying to the wrong account.
  allowed_account_ids = var.allowed_account_ids

  # Pipeline authenticates to the management account, then assumes the member
  # role (terraform-plan or terraform-apply) in the workload account.
  dynamic "assume_role" {
    for_each = var.target_account_id == null ? [] : [1]
    content {
      role_arn     = "arn:${var.partition}:iam::${var.target_account_id}:role/${var.member_role_name}"
      session_name = "fedramp-moderate-vpc"
    }
  }

  # CM-8: consistent inventory tagging on every resource.
  default_tags {
    tags = merge(
      {
        Project     = var.name
        Environment = var.environment
        ManagedBy   = "terraform"
        Compliance  = "FedRAMP-Moderate"
      },
      var.tags,
    )
  }
}
