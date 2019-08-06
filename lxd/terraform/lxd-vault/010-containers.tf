variable "container_names" {
  default = {
    "0" = "haproxys1"
    "1" = "haproxys2"
    "2" = "consuls1"
    "3" = "consuls2"
    "4" = "consuls3"
    "5" = "consuls4"
    "6" = "consuls5"
    "7" = "vaults1"
    "8" = "vaults2"
    "9" = "vaults3"
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
  count     = 10
  name      = var.container_names[count.index]
  image     = "ubuntu:18.04"
  ephemeral = false
  profiles  = ["default", lxd_profile.vault_config.name]

  config = {
    "boot.autostart" = true
  }

  #    user.user-data = "${file("cloud-init_${lookup(var.container_names, count.index)}_user-data.conf")}"

  device {
    name = "eth0"
    type = "nic"
    properties = {
      nictype      = "bridged"
      parent       = "lxdbr0"
      "ipv4.address" = var.container_ips[count.index]
    }
  }

  provisioner "local-exec" {
    command = "lxc config device add ${self.name} myport22 proxy listen=tcp:0.0.0.0:${var.container_ports[count.index]} connect=tcp:localhost:22"
  }
}

