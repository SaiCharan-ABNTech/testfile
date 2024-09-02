variable "region" {
  description = "The AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "VpcId of your existing Virtual Private Cloud (VPC)"
  type        = string
}

variable "subnets" {
  description = "The list of SubnetIds in your Virtual Private Cloud (VPC)"
  type        = list(string)
}

variable "instance_type" {
  description = "WebServer EC2 instance type"
  type        = string
  default     = "t2.micro"
}

variable "operator_email" {
  description = "EMail address to notify if there are any scaling operations"
  type        = string
}

variable "key_name" {
  description = "The EC2 Key Pair to allow SSH access to the instances"
  type        = string
}

variable "ssh_location" {
  description = "The IP address range that can be used to SSH to the EC2 instances"
  type        = string
}

