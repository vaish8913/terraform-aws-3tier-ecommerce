# Remote state: the Jenkins workspace is temporary, so state must live outside it.
# bucket and region are passed by the pipeline: terraform init -backend-config="bucket=..." -backend-config="region=..."
terraform {
  backend "s3" {
    key          = "ecommerce-3tier/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # S3 native locking, needs Terraform >= 1.10
  }
}
