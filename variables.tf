variable "vpc" {
  type = object({
      name = string
      cidr = string
      region = string
      private_subnets = list(string)
      public_subnets = list(string)
  })

  default = {
      name = "nomad-test"
      cidr = "172.31.0.0/16"
      region = "eu-west-3"
      private_subnets = ["172.31.1.0/24", "172.31.2.0/24", "172.31.3.0/24"]
      public_subnets = ["172.31.101.0/24", "172.31.102.0/24", "172.31.103.0/24"]
  }
}

variable "servers_asg" {
  type = object({
      name = string
      size = number
      launch_config = object({
          name = string
          description = string
          ami = string
          type = string
          volume_size = number
          key_name = string
      })
  })

  default = {
    launch_config = {
      ami = "ami-0c0f763628afa7f8b"
      description = "nomad-servers"
      name = "nomad-servers"
      type = "t3.medium"
      volume_size = 30
      key_name = "test-nomad"
    }
    name = "nomad-servers"
    size = 3
  }
}

variable "clients_asg" {
  type = object({
      name = string
      size = number
      launch_config = object({
          name = string
          description = string
          ami = string
          type = string
          volume_size = number
          key_name = string
      })
  })

  default = {
    launch_config = {
      ami = "ami-0c0f763628afa7f8b"
      description = "nomad-clients"
      name = "nomad-clients"
      type = "t3.medium"
      key_name = "test-nomad"
      volume_size = 30
    }
    name = "nomad-clients"
    size = 6
  }
}

variable "lb" {
  type = object({
      name = string
  })

  default = {
      name = "nomad-lb"
  }
}

variable "bastion" {
    type = object({
        name = string
        ami = string
        type = string
        key_name = string
    })

    default = {
      ami = "ami-0c0f763628afa7f8b"
      key_name = "test-nomad"
      name = "bastion-nomad"
      type = "t2.micro"
    }
}