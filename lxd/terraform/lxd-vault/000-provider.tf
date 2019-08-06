provider "lxd" {
  generate_client_certificates = true
  accept_remote_certificate    = true
  version = "~> 1.2"
}

