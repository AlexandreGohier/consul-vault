resource "lxd_profile" "client_config" {
  name = "client_config"

  config {
    limits.cpu = 2
#    user.user-data = "${file("cloud-init-user.conf")}"
    user.vendor-data = "${file("cloud-init-vendor.conf")}"
  }

  device {
    name = "shared"
    type = "disk"

    properties {
      source = "/tmp-shared"
      path   = "/tmp-shared"
    }
  }

#  device {
#    type = "disk"
#    name = "root"

#    properties {
#      pool = "default"
#      path = "/"
#    }
#  }
}

