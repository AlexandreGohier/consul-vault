variable "container_names" {
  default = {
    "0" = "client0"
    "1" = "client1"
  }
}

variable "container_ips" {
  default = {
    "0" = "10.1.42.150"
    "1" = "10.1.42.151"
  }
}

variable "container_ports" {
  default = {
    "0" = "22050"
    "1" = "22051"
  }
}

resource "lxd_container" "clients" {
  count = 2
  name      = "${lookup(var.container_names, count.index)}"
  image     = "ubuntu:18.04"
  ephemeral = false
  profiles  = ["default", "${lxd_profile.client_config.name}"]

  config {
    boot.autostart = true
#    user.user-data = "${file("cloud-init_${lookup(var.container_names, count.index)}_user-data.conf")}"
  }

  device {
    name = "eth0"
    type = "nic"
    properties {
      nictype = "bridged"
      parent = "lxdbr0"
      ipv4.address = "${lookup(var.container_ips, count.index)}" 
    }
}

#  provisioner "file" {
#    source      = "./trusted-user-ca-keys.pem"
#    destination = "/etc/ssh/trusted-user-ca-keys.pem"
#  }

  provisioner "local-exec" {
    command ="lxc config device add ${self.name} myport22 proxy listen=tcp:0.0.0.0:${lookup(var.container_ports, count.index)} connect=tcp:localhost:22"
  }

}

