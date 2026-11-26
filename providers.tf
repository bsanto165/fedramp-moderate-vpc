provider "aws" {
  region = var.region

  # SC-13: route all AWS API calls through FIPS 140 validated endpoints.
  use_fips_endpoint = var.use_fips_endpoint

  # Guard against applying to the wrong account.
  allowed_account_ids = var.allowed_account_ids

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
