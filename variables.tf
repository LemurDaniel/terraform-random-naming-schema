
variable "convention" {
  nullable    = false
  description = "(Required) The naming convention to use."
  type        = string
  default     = "default"

  # Must match a file at convention/<name>.naming.yaml - extend this list when
  # adding one. "other" used to be allowed here but no such file exists, so it
  # passed validation and then failed on the file read.
  validation {
    condition     = contains(["default"], var.convention)
    error_message = "The naming convention '${var.convention}' was not found!"
  }
}

variable "naming" {
  nullable    = true
  description = "(Optional) The default patterns to use for the schema."
  type = object({
    index_modifier     = optional(number)
    enforce_lower_case = optional(any)

    mappings      = optional(map(map(string)))
    patterns      = optional(any)
    abbreviations = optional(any)

    default_parameters = optional(map(any))
  })
  default = null
}

variable "parameters" {
  nullable    = false
  description = "(Required) The default parameters to use for the schema."
  type        = map(any)
  default     = {}
}
