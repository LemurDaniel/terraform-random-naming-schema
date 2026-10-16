
output "random" {
  description = "Outputs a random source for unique naming ids."
  value = {
    uuid = random_uuid.id.result
  }
}

output "index_modifier" {
  description = "Output the index modifier"
  value       = coalesce(local.custom.index_modifier, local.default_naming.index_modifier)
}

output "enforce_lower_case" {
  description = "Output lowercase settings."
  value       = local.enforce_lower_case
}

output "abbreviations" {
  description = "Output the resources part of the schema."
  value       = local.abbreviations
}

output "mappings" {
  description = "Output the mappings for resources."
  value       = local.mappings
}

output "patterns" {
  description = "Output the patterns part of the schema."
  value       = local.patterns
}

output "default_parameters" {
  description = "Output the default parameters for the schema."
  value = merge(
    coalesce(local.default_naming.default_parameters, {}),
    local.custom.default_parameters,
    var.parameters,
  )
}
