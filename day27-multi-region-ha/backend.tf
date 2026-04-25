terraform {
  backend "s3" {
    bucket         = "felix-terraform-remote-state-2026"
    key            = "day27/multi-region-ha/prod/terraform.tfstate"
    region         = "eu-north-1"
    dynamodb_table = "felix-terraform-lock"
    encrypt        = true
  }
}

