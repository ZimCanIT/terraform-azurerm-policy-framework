output "definitions" {
  description = "Canonical definition objects keyed by catalogue key. Read by the role-grant and assignment states."
  value       = module.content.definitions
}

output "initiatives" {
  description = "Canonical initiative objects keyed by catalogue key. Read by the role-grant and assignment states."
  value       = module.content.initiatives
}
