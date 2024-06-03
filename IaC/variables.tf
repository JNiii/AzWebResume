variable "domain" {
  type    = string
  default = "imneojay.xyz"
}

variable "cdn_application_id" {
  default = "205478c0-bd83-4e1b-a9d6-db63a3e1e1c8" # This is azure's application UUID for a CDN endpoint
}

variable "AzureResumeTag" {
  type = map(string)
  default = {
    "Project" = "AzureResume"
  }
}

variable "regions" {
  type    = string
  default = "East US"
}

variable "AdminEmail" {
  type    = string
  default = "ineojay@gmail.com"
}

variable "data-backups" {
  type = list (string)
  default = ["Backups-RG","saazurebackupfiles", "cdb-backups"]
}