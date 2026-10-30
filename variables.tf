variable "yourname" {
  description = "Your name — makes resource names unique."
  type        = string
}
variable "location" {
  type    = string
  default = "eastus"
}
variable "admin_username" {
  type    = string
  default = "labadmin"
}
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "tags" {
  type    = map(string)
  default = { lab = "network-security" }
}
