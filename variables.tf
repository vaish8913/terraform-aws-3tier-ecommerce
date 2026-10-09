variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "project" {
  type    = string
  default = "threetier"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 4
}

variable "requests_per_target" {
  description = "Scale out when avg requests per instance (per minute) exceeds this"
  type        = number
  default     = 100
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "dbadmin"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "domain_name" {
  description = "Site hostname, e.g. shop.example.com. Leave empty for HTTP only on the ALB DNS name."
  type        = string
  default     = ""
}

variable "hosted_zone_name" {
  description = "Existing Route 53 public hosted zone, e.g. example.com (needed only when domain_name is set)"
  type        = string
  default     = ""
}
