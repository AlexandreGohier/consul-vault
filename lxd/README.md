# Using a LXD backend instead of VMs / Instances

## This is intended for testing purposes, not for managing real secrets
**This setup is unsafe - with the current configuration memlock is disabled, which means your secrets will sooner or later be available in plaintext in the container's memory which can be read by the host and can be dumped on disk.**  

---
## Why bother?  
- This is only useful for testing purposes, you get a nice HAProxy + Consul + Vault setup to play with which is functionally much closer to a real production environment than the dev mode of both Consul and Vault
- The footprint of LXD containers is smaller than full instances - _check host specs in the prerequisites below_
- Fully automated backend container setup using Terraform and cloud-init
- Fully automated vault-managed clients (with SSH signer) using Terraform and cloud-init - _very useful to start experimenting with Vault_
- Snapshot / restore functionalities are a lot faster, especially when using a btrfs or zfs LXD storage pool

---
## What works, how does it differ from the original code?
|Component|What works?|What differs?|
|:---:|---|---|
|Consul|Fully functional|Nothing, code is the same|
|Vault|Fully functional from user's perspective|Unsafe (memlock disabled) - updated to Vault v1.1.2 - uses python3-pip|
|HAProxy|Both HAProxy containers are fully functional|Updated to HAProxy v1.8.19|
|Keepalived|Doesn't work - VIP can't be used on LXD networking - probably a multicast problem|Nothing, code is the same|

---
## Tested OS
- LXD 3.0.3 host running on Ubuntu 18.04.2 LTS (amd64)
- LXD containers for consul-vault project running on Ubuntu 18.04.2 LTS (amd64)
- LXD containers for vault-managed clients (SSH signer) running on Ubuntu 18.04.2 LTS (amd64)

_Since I use cloud-init functionalities to setup the LXD containers, it was easier to use the Ubuntu LXD images with cloud-init preinstalled. You can probably use any other OS that is compatible with the original project as long as you customize your images first to include cloud-init. More information on this here:_ [Are there any plans to add cloud-init to the images provided at images.linuxcontainers.org?](https://discuss.linuxcontainers.org/t/are-there-any-plans-to-add-cloud-init-to-the-images-provided-at-images-linuxcontainers-org/3271)

---
## Prerequisites
### Minimal host specs for backend containers
- amd64 host running Ubuntu 18.04
- 2 CPU cores (1 might work, 4 will make the setup process faster)
- 2GB RAM minimum (might swap a little during initial setup) - 4GB is more comfortable during setup but once installed the host + the backend containers will require less than 1.5GB RAM (in total for all of them), everything else will be available for your client containers
- ~60GB disk space (host + images + backend containers + snapshots + client containers)

### LXD
You need to install and initialize LXD prior to using Terraform to create the backend containers. I am using LXD v3.0.3 (latest LTS version as of this writing).

__The LXD installation and initialisation process can be automated using Ansible. See [this role](https://github.com/WilliamCocker/terraform/tree/master/roles/ansible-role-lxd-init) for an example on how to do that.__

### Terraform & LXD provider

You need to install [Terraform](https://www.terraform.io/downloads.html) on the host along with the [LXD provider](https://github.com/sl1pm4t/terraform-provider-lxd/releases). 

- This is a community provider for Terraform and as such it must be downloaded separately
- Unzip & Copy to $PATH or the ~/.terraform.d/plugins directory so Terraform can find it

__The Terraform and LXD provider installation can be automated using Ansible. See [this playbook](https://github.com/WilliamCocker/terraform) for an example on how to do that.__

---
## Create the backend containers

**Short version:** go to lxd/terraform/lxd-vault folder, add your SSH public key to `cloud-init-vendor.conf` & run `terraform init` & `terraform apply`!  

**Detailed version:** There are five files in this folder you can customize

- 000-provider.tf  

This file contains the [LXD provider configuration](https://github.com/sl1pm4t/terraform-provider-lxd/tree/master/docs). Although the provider supports LXD remotes, you should avoid it since we will also be using the Terraform "local-exec" provider which runs locally to the Terraform context to configure the containers. If you are familiar with LXD you can go around this by installing LXD locally to manage a LXD remote (you'll also need to modify the lxc config commands in the next file).

- 010-containers.tf  

This file is where we create all 10 containers, you can customize it to your liking.  
For instance, you can set whether the container will autostart on host boot or set a host-specific cloud-init userdata file (can be in cloud-config or bash format).  

If you uncomment the user.user-data file, it will expect 10 files in the same folder, one for each host (_cloud-init_haproxy-s1_user-data.conf_, _cloud-init_haproxy-s2_user-data.conf_, etc).
```
config {
    boot.autostart = true
#    user.user-data = "${file("cloud-init_${lookup(var.container_names, count.index)}_user-data.conf")}"
  }
```

This is also where we create the proxy device to forward the incoming SSH connections on container-specific ports to each container (no iptables on host required).     
  
Connections to HOST:22011 will be forwarded to 10.1.42.11:22  
Connections to HOST:22012 will be forwarded to 10.1.42.12:22  
and so on...

```
  provisioner "local-exec" {
    command ="lxc config device add ${self.name} myport22 proxy listen=tcp:0.0.0.0:${lookup(var.container_ports, count.index)} connect=tcp:localhost:22"
  }
```

You can later check the proxy devices using the `lxc config show container_name` command.

Ex:

```
lxc config show consul-s1
  
[...]
devices:
  eth0:
    ipv4.address: 10.1.42.101
    nictype: bridged
    parent: lxdbr0
    type: nic
  myport22:
    connect: tcp:localhost:22
    listen: tcp:0.0.0.0:22101
    type: proxy
ephemeral: false
[...]
```

- 020-profile.tf

This file contains an additional LXD profile that will be applied to each backend container (as in addition to the default profile). We will mostly use it to apply a common cloud-init vendor-data cloud-config file to all containers but there are many other things you can use it for.  

We can set some CPU limits, set a common cloud-init user-data file (bash or cloud-config format), set a common cloud-init vendor-date file (bash or cloud-config format). _Even though you can override cloud-init settings between containers and profiles, it's probably easier to stick to one approach, for instance using common vendor-data on the profile and specific user-data on the container_.

```
  config {
    limits.cpu = 2
#    user.user-data = "${file("cloud-init-user.conf")}"
    user.vendor-data = "${file("cloud-init-vendor.conf")}"
  }
```

You can also set additional container devices. Here we set a shared disk that will be available on the host and each container (useful if we need to share data). _Note: /tmp-shared/ must be created on the host prior to running Terraform apply and available in RWX to everyone_  

```
  device {
    name = "shared"
    type = "disk"

    properties {
      source = "/tmp-shared"
      path   = "/tmp-shared"
    }
  }
```

- cloud-init-vendor.conf

This is the common cloud-init vendor-data file we use in the additional profile we created in the `020-profile.tf` file. This file is in cloud-config format but it could be a bash script as well.  

We use it to update / upgrade the image, install some required packages, set the timezone and create a "deploy" user.

You can customize this but **at a minimum, you must update this file with the SSH public key you will be using to deploy the consul-vault project with ansible later on**

```
#cloud-config
  users:
    - name: deploy
      ssh-authorized-keys:
        ssh-rsa AAAA...add..your..SSH..public..key..here.. user@domain
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      groups: sudo
      shell: /bin/bash
```

- cloud-init_haproxy-s1_user-data.conf

This is a sample cloud-init used-data file we could customize and rename for each container. This example is a bash script but it could be a cloud-config as well. At the moment this file is unused, it's just there as an example.   

Now all you have to do is run `terraform init` and `terraform apply` to create all the containers. You can check the result with `lxc ls` and you should get something similar to this:

```
+------------+---------+--------------------+------+------------+-----------+
|    NAME    |  STATE  |        IPV4        | IPV6 |    TYPE    | SNAPSHOTS |
+------------+---------+--------------------+------+------------+-----------+
| consul-s1  | RUNNING | 10.1.42.101 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s2  | RUNNING | 10.1.42.102 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s3  | RUNNING | 10.1.42.103 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s4  | RUNNING | 10.1.42.104 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s5  | RUNNING | 10.1.42.105 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| haproxy-s1 | RUNNING | 10.1.42.11 (eth0)  |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| haproxy-s2 | RUNNING | 10.1.42.12 (eth0)  |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s1   | RUNNING | 10.1.42.201 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s2   | RUNNING | 10.1.42.202 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s3   | RUNNING | 10.1.42.203 (eth0) |      | PERSISTENT | 0         |
+------------+---------+--------------------+------+------------+-----------+
```
---
## Snapshot the containers

Even though you can easily `terraform destroy` & `terraform apply` to start over, snapshotting and restoring LXD containers is much faster. So I would recommend you create at least one snapshot of your containers before starting to deploy anything with ansible. To do so, I have included a new `lxd.yml` playbook in the playbooks folder. You can use it with the main `deploy.sh` script:

`./deploy.sh -s lxd -t snapshot`

The playbook will stop all containers, create a snapshot for each one and restart them once it's done. If you `lxc ls` again, you will see the snapshots counter has incremented:

```
+------------+---------+--------------------+------+------------+-----------+
|    NAME    |  STATE  |        IPV4        | IPV6 |    TYPE    | SNAPSHOTS |
+------------+---------+--------------------+------+------------+-----------+
| consul-s1  | RUNNING | 10.1.42.101 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s2  | RUNNING | 10.1.42.102 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s3  | RUNNING | 10.1.42.103 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s4  | RUNNING | 10.1.42.104 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| consul-s5  | RUNNING | 10.1.42.105 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| haproxy-s1 | RUNNING | 10.1.42.11 (eth0)  |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| haproxy-s2 | RUNNING | 10.1.42.12 (eth0)  |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s1   | RUNNING | 10.1.42.201 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s2   | RUNNING | 10.1.42.202 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
| vault-s3   | RUNNING | 10.1.42.203 (eth0) |      | PERSISTENT | 1         |
+------------+---------+--------------------+------+------------+-----------+
```
---
## Restore the containers

If you need to go back to this snapshot for all your containers, you can simply run:

`./deploy.sh -s lxd -t restore`

The playbook will stop all containers, restore each container's `snap0` snapshot and restart the containers. **Note that if you run the snapshot command more than once, new snapshots will be named snap1, snap2 and so on but the restore command will always restore snap0. If you need to restore another snapshot, modify the snapshot name in the playbooks/lxd.yml file.**

---
## Install consul-vault

Once your containers are up and running, you can simply run `./deploy.sh` - refer to the original documentation for further information.

---
## VIP not working - need to bind each HAProxy on its own IP address

Since I did not get the VIP to work, the default HAProxy configuration has to be modified. I'm still hoping for a solution to the VIP problem so I won't be updating the Ansible playbooks.

On both haproxy servers, just update the file `/etc/haproxy/haproxy.cfg`

For haproxy-s1:

```
frontend vault
  bind 10.1.42.11:8200
```

For haproxy-s2:

```
frontend vault
  bind 10.1.42.12:8200
```

Then restart both containers. This way you can still simulate interacting with vault through HAProxy --> Consul --> Vault. The only limitation is the missing load balancing features and VIP, you need to address each HAProxy server directly.

---
## Start using Vault & create client containers

Please see additional documentation in lxd/docs folder (work in-progress).
