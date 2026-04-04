terraform {
  backend "s3" {
    bucket = "solar-system-tfstate-loogyyy"   # ← your real bucket name here
    key    = "solar-system/terraform.tfstate"
    region = "us-east-1"
  }
}