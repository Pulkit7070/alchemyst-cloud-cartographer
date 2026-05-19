variable "project_id" {
  type = string
}

variable "zone" {
  type = string
}

variable "region" {
  type = string
}

variable "public_subnet_self_link" {
  type = string
}

variable "private_subnet_self_link" {
  type = string
}

variable "gateway_sa_email" {
  type = string
}

variable "inference_sa_email" {
  type = string
}

variable "gateway_machine_type" {
  type    = string
  default = "e2-small"
}

variable "inference_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "app_version" {
  type    = string
  default = "latest"
}

variable "labels" {
  type    = map(string)
  default = {}
}
