terraform {
  backend "s3" {
    bucket       = "vaish-terraform-state"
    key          = "ecommerce-3tier/terraform.tfstate"
    region       = "ap-south-1"
    encrypt      = true
    use_lockfile = true
  }
}