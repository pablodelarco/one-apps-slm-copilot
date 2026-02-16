variable "appliance_name" {
  type    = string
  default = "slm-copilot"
}

variable "input_dir" {
  type        = string
  description = "Directory containing base OS image (ubuntu2404.qcow2)"
}

variable "output_dir" {
  type        = string
  description = "Directory for output QCOW2 image"
}

variable "headless" {
  type    = bool
  default = true
}

variable "version" {
  type    = string
  default = "1.0.0"
}

variable "one_apps_dir" {
  type        = string
  description = "Path to one-apps repository checkout"
}

variable "distro" {
  type    = string
  default = ""
}
