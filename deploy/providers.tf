terraform {
  required_version = ">= 1.3.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.46.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.9"
    }
  }

  backend "gcs" {
    bucket = ""
    prefix = "infra"
  }
}

provider "google" {
  project = var.project_id
  region  = var.gcp_region
}

