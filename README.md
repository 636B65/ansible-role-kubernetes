# ansible-role-kubernetes

An Ansible role for installing a Kubernetes cluster with containerd, Cilium,
HAProxy and Keepalived on the control-plane nodes, plus an optional internal
Docker Distribution registry. The role resolves the latest stable Kubernetes
and Cilium releases at runtime.

> **Before you run this role:** replace all `changeme` values, configure your
> inventory and API virtual IP, review the network requirements, and keep
> credentials in Ansible Vault. Do not commit real passwords or vault secrets.

## Requirements

- Ansible Core 2.16 or newer on the Ansible controller.
- Debian-family managed hosts with `apt`, Python, SSH access, and privilege
  escalation to root.
- At least one control-plane node and one worker node. For a highly available
  control plane, use three control-plane nodes.
- All nodes must be able to reach each other and the required package/image
  repositories.
- A free virtual IP address on the control-plane network for Keepalived.

## Architecture

![High-availability Kubernetes cluster architecture](docs/architecture.svg)

The editable diagrams.net source is [docs/architecture.drawio](docs/architecture.drawio).
The API virtual IP is active on one controller at a time; HAProxy on that
controller distributes new TCP connections round-robin across healthy API
servers. Cilium provides pod networking across the cluster.

## Configure before running

1. **Inventory:** Copy `examples/inventory.yml` to your own inventory and
   replace every documentation-only address (`192.0.2.x`) with the real
   reachable IPv4 address of each host. Keep the hostnames consistent with the
   control-plane and worker groups.
2. **SSH and sudo credentials:** Copy
   `examples/group_vars/all.yml.example` to `examples/group_vars/all.yml`.
   Replace `changeme` with the SSH username and credentials for your hosts.
   Encrypt the file with Ansible Vault before storing real credentials:

   ```sh
   ansible-vault encrypt examples/group_vars/all.yml
   ```

   Use `--ask-vault-pass` when running the playbook, or configure a secure vault
   password source. Do not put real passwords directly in the playbook or
   commit unencrypted credentials.
3. **API endpoint:** In `examples/site.yml`, set
   `kubernetes_api_vip` to an unused address in your controller subnet and set
   `kubernetes_api_vip_prefix` and `kubernetes_api_vip_interface` for your
   network. The default API VIP listener port is `8443`; it forwards to each
   controller's kube-apiserver on `6443`.
4. **Keepalived:** Replace the `changeme` value for
   `kubernetes_keepalived_auth_pass` with a shared secret of at most eight
   characters. Keep it private; the default is intentionally rejected by the
   role's preflight check.
5. **Network ranges:** Review the pod and service CIDRs in
   `defaults/main.yml`. They must not overlap each other, node networks, or
   routes reachable by your cluster.
6. **Firewall and exposure:** Allow the Kubernetes control-plane and node
   traffic required by your environment, TCP `8443` to the API VIP, TCP `6443`
   to controller API servers, and Keepalived VRRP/unicast traffic between
   controllers. The HAProxy statistics page is unauthenticated on TCP `8404`;
   restrict it to trusted administrator networks.

The registry feature exposes a plain-HTTP NodePort (`30500`) without
authentication, and stores data on the first control-plane node. Do not expose
it outside a trusted network. Review or disable registry tasks if that is not
appropriate for your deployment.

## Install and run

Install the role from the public GitHub repository:

```sh
ansible-galaxy role install git+https://github.com/636B65/ansible-role-kubernetes.git
```

Copy and edit the example files as described above, then run:

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --ask-vault-pass
```

For a local checkout, install the current directory into a local roles path
first:

```sh
ansible-galaxy role install . --roles-path ./roles
ANSIBLE_ROLES_PATH=./roles ansible-playbook \
  -i examples/inventory.yml examples/site.yml --ask-vault-pass
```

The role uses privilege escalation on managed hosts. Set `become` in your
playbook and provide the appropriate become password through Vault or another
secret manager.

## Selective task tags

Use tags to run only the relevant part of the role:

| Tag | Tasks |
| --- | --- |
| `prerequisites` | OS preparation, containerd and Kubernetes packages |
| `loadbalancer` | HAProxy and Keepalived configuration on control-plane nodes |
| `bootstrap` | Initialize the first controller and install Cilium |
| `join` | Join additional control-plane and worker nodes |
| `registry_deploy` | Deploy the internal image registry |
| `registry_runtime` | Configure containerd for the registry |
| `registry_images` | Copy configured images into the registry |
| `registry` | Run all registry tasks |

Example:

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags loadbalancer --ask-vault-pass
```

## Versioning and releases

Kubernetes and Cilium stable versions are discovered at playbook runtime. This
tracks current stable releases but is not reproducible by default; pin package
and Cilium versions in a controlled environment if repeatable deployments are
required.

Push a version tag such as `v1.0.0` to run the CI checks and publish a GitHub
Release. The release workflow requires the repository's standard
`GITHUB_TOKEN` permission to create releases.
