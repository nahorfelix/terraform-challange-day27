terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "day27/multi-region-ha/prod/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
