variable "container_names" {
  default = {
    "0" = "haproxy-s1"
    "1" = "haproxy-s2"
    "2" = "consul-s1"
    "3" = "consul-s2"
    "4" = "consul-s3"
    "5" = "consul-s4"
    "6" = "consul-s5"
    "7" = "vault-s1"
    "8" = "vault-s2"
    "9" = "vault-s3"
  }
}

variable "container_ips" {
  default = {
    "0" = "10.1.42.11"
    "1" = "10.1.42.12"
    "2" = "10.1.42.101"
    "3" = "10.1.42.102"
    "4" = "10.1.42.103"
    "5" = "10.1.42.104"
    "6" = "10.1.42.105"
    "7" = "10.1.42.201"
    "8" = "10.1.42.202"
    "9" = "10.1.42.203"
  }
}

variable "container_ports" {
  default = {
    "0" = "22011"
    "1" = "22012"
    "2" = "22101"
    "3" = "22102"
    "4" = "22103"
    "5" = "22104"
    "6" = "22105"
    "7" = "22201"
    "8" = "22202"
    "9" = "22203"
  }
}

resource "lxd_container" "vault" {
  count = 10
  name      = "${lookup(var.container_names, count.index)}"
  image     = "ubuntu:18.04"
  ephemeral = false
  profiles  = ["default", "${lxd_profile.vault_config.name}"]

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

  provisioner "local-exec" {
    command ="lxc config device add ${self.name} myport22 proxy listen=tcp:0.0.0.0:${lookup(var.container_ports, count.index)} connect=tcp:localhost:22"
  }

}

