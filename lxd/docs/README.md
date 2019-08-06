Using Vault SSH signer with LXD containers provisioned with Terraform & cloud-init 
==================================================================================

Summary
-------

If you provisioned a consul-vault cluster on LXD using my terraform template to setup your containers, you may have noticed the [lxd/terraform](https://github.com/WilliamCocker/consul-vault/tree/master/lxd/terraform) folder also contains a [lxd-clients](https://github.com/WilliamCocker/consul-vault/tree/master/lxd/terraform/lxd-clients) subfolder. This terraform template is an example demonstrating how to provision additional LXD containers that will trust Vault's CA to sign SSH keys to log into the containers. It creates two users (one privileged, one regular) on each container without setting passwords or authorized keys. It does however set the allowed principals for each user. Thus, in order to log in, you will need to provide a valid certificate matching one of the user's allowed principals. This is what the Vault SSH client signer was designed for!

Provisioning the containers using the Terraform template
--------------------------------------------------------

The Terraform template can be [found here](https://github.com/WilliamCocker/consul-vault/tree/master/lxd/terraform/lxd-clients).

The provisioning process is very similar to the one used to set up the consul-vault LXD containers as [described in this README file](https://github.com/WilliamCocker/consul-vault/blob/master/lxd/README.md). The only major difference is this time we will not be including static SSH keys.

+ [000-provider.tf](https://github.com/WilliamCocker/consul-vault/blob/master/lxd/terraform/lxd-clients/000-provider.tf)

This is the LXD provider configuration, no need to customize much here.

+ [010-containers.tf](https://github.com/WilliamCocker/consul-vault/blob/master/lxd/terraform/lxd-clients/010-containers.tf)

This is the main template file, customize it to fit your needs. By default it will create two Ubuntu 18.04 client containers (named "client0" and "client1").   

*We will be using cloud-init to configure the containers, so make sure you use a cloud-init enabled container image*


+ [020-profile.tf](https://github.com/WilliamCocker/consul-vault/blob/master/lxd/terraform/lxd-clients/020-profile.tf)

This is the LXD profile configuration. Make sure the `/tmp-shared` folder exists on the host if you want to share a folder between containers, otherwise remove (or comment out) the shared disk device from the profile.

+ [cloud-init-vendor.conf](https://github.com/WilliamCocker/consul-vault/blob/master/lxd/terraform/lxd-clients/cloud-init-vendor.conf)

This is where we configure cloud-init to create our users and link our containers to Vault's CA.

**Creating users**

By default, we will create two users: "support" which is a passwordless sudoer and "limited" which is a regular user.

```
  users:
    - name: support
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      groups: sudo
      shell: /bin/bash
    - name: limited
      shell: /bin/bash
```

**Configuring the SSH server**

We need to modify the `/etc/ssh/sshd_config` SSH server config file to point it to Vault's CA public key file and to each user's file containing the allowed principals.

*We will cover how to get Vault's CA public key soon after*

```
  runcmd:
    - sed -i -e '$aTrustedUserCAKeys /etc/ssh/trusted-user-ca-keys.pem' /etc/ssh/sshd_config
    - sed -i -e '$aAuthorizedPrincipalsFile /etc/ssh/auth_principals/%u' /etc/ssh/sshd_config
    - mkdir /etc/ssh/auth_principals
```

The `AuthorizedPrincipalsFile /etc/ssh/auth_principals/%u` setting means that for each user, we will require a text file under `/etc/ssh/auth_principals` that will list the allowed principals. In the current example, we will need to create `/etc/ssh/auth_principals/support` and `/etc/ssh/auth_principals/limited`.

We create those three files (*Vault's CA public key and both principal files*) using the cloud-config write_files module. The "admins" principal will open the gate to both user accounts, the "secops-team" principal will allow using the "support" account and the "regular-users" principal will allow using the "limited" account.

*Note that there is usually an implicit principal on the user name. So if your certificate contains the "support" principal, it should allow authorizing with the "support" user even if it is not explicitly defined in the principal file.* 

```
  write_files:
    - path: /etc/ssh/trusted-user-ca-keys.pem
      content: |
           ssh-rsa AAAA....insert..trusted..CA..key..here...==
    - path: /etc/ssh/auth_principals/support
      content: |  
           secops-team
           admins
    - path: /etc/ssh/auth_principals/limited
      content: |  
           regular-users
           admins
```


