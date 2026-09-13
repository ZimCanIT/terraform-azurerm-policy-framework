terraform {
  # The source adapters rely on nullable validation guards and validation
  # short-circuiting available from Terraform 1.12.0.
  required_version = ">= 1.12.0"
}
