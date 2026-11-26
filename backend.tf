# Partial backend: values come from env/<name>.s3.tfbackend via
#   terraform init -backend-config=env/prod.s3.tfbackend
terraform {
  backend "s3" {}
}
