terraform {
  required_version = ">= 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 5.0.0, < 6.0.0"
    }
  }

  # Local state keeps the reference runnable without shared storage. A pipeline
  # replaces this block, and the terraform_remote_state blocks in the roots that
  # read another state, with its own remote backend.
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
}
