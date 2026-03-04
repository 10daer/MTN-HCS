###############################################################################
# Module: iam – Input Variables
# Note: Kept minimal — HCS provider does not support IAM resources.
#       This module accepts name_prefix to maintain interface compatibility.
###############################################################################

variable "name_prefix" {
  description = "Prefix used to name all IAM resources."
  type        = string
}