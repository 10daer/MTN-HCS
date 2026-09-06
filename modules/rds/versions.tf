terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcs = {
      source  = "huaweicloud/hcs"
      version = "~> 2.4.0"
    }
    # Used only for the post-create settle window before database/account jobs.
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9"
    }
  }
}
