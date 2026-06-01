variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "iot-edge"
}

variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  default     = "lab"
}

variable "region" {
  default = "us-east-1"
}

variable "vpc_id" {
  default = "vpc-08b570fbb615b2113"
}

variable "subnet_id" {
  default = "subnet-0f8edab6a61864225"
}

variable "subnet_id_2" {
  default = "subnet-097c7fd36eeeab3e2"
}

variable "ami_id" {
  default = "ami-0a59ec92177ec3fad"
}

variable "key_name" {
  default = "vockey"
}

variable "instance_type" {
  default = "t3.micro"
}