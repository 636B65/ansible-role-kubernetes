# ansible-role-kubernetes

An Ansible role for installing a Kubernetes cluster with containerd, Cilium,
HAProxy and Keepalived on the control-plane nodes, plus an internal Docker
Distribution registry backed by replicated Longhorn storage. Component
versions are pinned for reproducible installs, and the role includes rolling
upgrades, scheduled etcd backups, API server hardening, an optional host
firewall, observability add-ons, node removal, and an offline installation
mode.

> **Before you run this role:** replace all `changeme` values, configure your
> inventory and API virtual IP, review the network requirements, and keep
> credentials in Ansible Vault. Do not commit real passwords or vault secrets.

## Requirements

- Ansible Core 2.16 or newer on the Ansible controller.
- Debian-family managed hosts with `apt`, Python, SSH access, and privilege
  escalation to root.
- At least one control-plane node and one worker node. The default registry
  configuration needs at least three worker nodes for its three Longhorn
  replicas; use three control-plane nodes for a highly available control plane.
- All nodes must be able to reach each other and the required package/image
  repositories. Longhorn additionally requires iSCSI and NFSv4 client support
  and sufficient local disk space under `/var/lib/longhorn` on at least three
  worker nodes. Permit Longhorn's node-to-node storage traffic through host
  firewalls as described in its [network requirements](https://longhorn.io/docs/latest/deploy/important-notes/#networking).
- A free virtual IP address on the control-plane network for Keepalived.

## System requirements and sizing

The current six-node cluster uses the following size on **each** node:

| Resource | Current per-node size | Notes |
| --- | ---: | --- |
| CPU | 2 vCPU | Baseline for this small cluster; leave CPU headroom for workloads. |
| Memory | 4 GB RAM | Small-lab baseline; can become constrained under Kubernetes, Cilium, Longhorn, and application workloads. |
| Disk | 60 GB | Total disk, not all available to Longhorn. OS, container images, logs, and Kubernetes data use part of it. |

With three controllers and three workers, that is 12 vCPU, 24 GB RAM, and
360 GB of raw disk across the cluster. These totals are not pooled: each node
must independently meet its requirements. The current size is a practical
small-cluster baseline, not a production capacity guarantee. For a growing or
production workload, a reasonable starting target is 4 vCPU and 8 GB RAM per
node (not a role-enforced minimum), then size disk for the operating system,
image cache, logs, workload data, and expected growth.

Longhorn stores three copies of the default 8 GiB registry volume, requiring
about 24 GiB of raw capacity in total and at least 8 GiB of schedulable free
space on each of three worker disks, plus headroom for Longhorn's disk
reservations and rebuilds. Longhorn replica capacity is separate from usable
application storage: every extra GiB in the registry claim consumes roughly
three GiB across the workers at the default replica count. Keep iSCSI and NFSv4
client support enabled on every node.

The role targets Debian-family systems with `apt`, Python, SSH, and root
privilege escalation. The control-plane nodes need at least 2 CPU cores for
the kubeadm setup. Initial installation requires internet access to configured
package and image repositories. To prepare for later offline use, the role
also installs Helm and the Cilium CLI on each controller, saves their release
archives and the installed Cilium chart under `/opt/kubernetes-offline`, and
mirrors every image rendered from the active Cilium Helm values into the local
registry. The registry also receives the pinned NGINX image used by the
LoadBalancer guide. Complete registry staging before exporting the VMs as
OVAs. To install an empty cluster without internet access, stage a full
offline bundle with packages and bootstrap images as described in
[Offline installation](docs/offline.md). All nodes need
connectivity to one another for Kubernetes/Cilium/Longhorn traffic and
synchronized clocks.

## Architecture

![High-availability Kubernetes cluster architecture](docs/architecture.svg)

The editable diagrams.net source is [docs/architecture.drawio](docs/architecture.drawio).
The API virtual IP is active on one controller at a time; HAProxy on that
controller distributes new TCP connections round-robin across healthy API
servers. Cilium provides pod networking across the cluster.
Keepalived is ordered after systemd-networkd wait-online so the API VIP is
assigned only after the controller network interface is available at boot.

For an example NGINX workload exposed through a Cilium-managed
`LoadBalancer` service, see the
[NGINX and Cilium LoadBalancer guide](docs/deploy-nginx-cilium-loadbalancer.md).
To run an interactive Ubuntu pod from the image in the local registry, see the
[Ubuntu pod guide](docs/deploy-ubuntu-pod.md).

## Operations guides

| Guide | Covers |
| --- | --- |
| [Upgrade Kubernetes](docs/upgrade.md) | Rolling upgrades with `examples/upgrade.yml`, Cilium and Longhorn upgrades |
| [API server hardening](docs/hardening.md) | Audit logging, encryption of Secrets at rest, Pod Security admission, rollout to existing clusters |
| [etcd backup and restore](docs/etcd-backup-restore.md) | Scheduled snapshots and a full restore procedure |
| [Host firewall](docs/firewall.md) | Optional nftables input filter |
| [Add and remove nodes](docs/scaling.md) | Scale-out, `examples/remove-node.yml`, replacing failed nodes |
| [Offline installation](docs/offline.md) | Staging a package and image bundle, installing without internet access |
| [Troubleshooting](docs/troubleshooting.md) | VIP, etcd, joins, Longhorn, registry, Pod Security, upgrades |

## Observability

The role installs [metrics-server](https://github.com/kubernetes-sigs/metrics-server)
(`kubectl top`) and enables Cilium [Hubble](https://docs.cilium.io/en/stable/observability/hubble/)
Relay and UI by default. Open the Hubble UI from a controller with
`cilium hubble ui`. Set `kubernetes_prometheus_stack_enabled: true` and a
`kubernetes_grafana_admin_password` of at least 12 characters (from Vault) to
also install kube-prometheus-stack in the `monitoring` namespace; it needs
internet access. Run the `observability` tag to apply changes.

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
   restrict it to trusted administrator networks. The role can manage these
   rules with nftables; see [Host firewall](docs/firewall.md).

The registry uses a Longhorn `ReadWriteMany` volume with three replicas by
default, and runs two registry pods. The default claim size is 8 GiB; with
three replicas, allow about 24 GiB of raw capacity across the storage nodes.
Set `kubernetes_longhorn_replica_count` and
`kubernetes_registry_storage_size` to match your capacity and durability
requirements. Longhorn CSI, manager, and engine-image components run on
controllers so workloads there can mount and attach volumes, but controller
disks are excluded from replica placement. Replicas stay on separate workers.
Two registry pods are scheduled on different nodes. A single controller failure
does not lose the registry volume, provided the Longhorn prerequisites are met
and healthy replicas exist on surviving nodes; volume/share-manager
reattachment can cause a brief interruption while Kubernetes and Longhorn
recover.

On an existing cluster, the first registry deployment with Longhorn detects
the old hostPath deployment, briefly scales it down, and copies its data from
the first control-plane node to the replicated volume before switching the
registry to two pods. Run this migration while that controller and its old
registry data are available; the old copy is left untouched. If that host or
its disk is already lost, data that existed only there cannot be recovered by
this migration.

The registry is exposed as a plain-HTTP NodePort (`30500`) without
authentication. Do not expose it outside a trusted network.

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

Use tags to run only the relevant part of the role. `registry_deploy` includes
Longhorn installation and the one-time data migration from the old hostPath
registry; run it while the first control-plane node is available:

| Tag | Tasks |
| --- | --- |
| `prerequisites` | OS preparation, containerd and Kubernetes packages |
| `loadbalancer` | HAProxy and Keepalived configuration on control-plane nodes |
| `bootstrap` | Initialize the first controller and install Cilium |
| `join` | Join additional control-plane and worker nodes |
| `longhorn` | Install Longhorn and prepare replicated storage prerequisites |
| `registry_deploy` | Install Longhorn, migrate existing data if needed, and deploy two registry replicas |
| `registry_runtime` | Configure containerd for the registry |
| `registry_images` | Copy configured, NGINX, and active Cilium chart images into the registry; stage the chart and tools on controllers |
| `cilium_offline` | Stage the active Cilium chart and rendered images, plus Helm and Cilium CLI, for offline use |
| `registry` | Run Longhorn installation and all registry tasks |
| `firewall` | Configure or remove the nftables host firewall |
| `hardening` | Write the API server audit, encryption, and Pod Security files on controllers |
| `etcd_backup` | Install the scheduled etcd backup on controllers |
| `observability` | Install metrics-server, enable Hubble, and optionally kube-prometheus-stack |
| `offline_stage` | Stage the offline package and image bundle (only runs when requested) |
| `upgrade` | Rolling upgrade; needs `serial: 1`, see `examples/upgrade.yml` (only runs when requested) |
| `remove_node` | Remove `kubernetes_remove_nodes`; see `examples/remove-node.yml` (only runs when requested) |

Example:

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags loadbalancer --ask-vault-pass
```

## Versioning and releases

### Component versions

All components are pinned in `defaults/main.yml`:

| Variable | Default |
| --- | --- |
| `kubernetes_version` | `1.36.5` |
| `kubernetes_cilium_version` | `1.20.4` |
| `kubernetes_cilium_cli_version` | `v0.20.1` |
| `kubernetes_helm_version` | `v3.22.1` |
| `kubernetes_longhorn_version` | `1.13.0` |
| `kubernetes_metrics_server_version` | `v0.9.0` |
| `kubernetes_prometheus_stack_version` | `92.14.0` |

Set a value to `latest` to resolve the newest stable release at runtime
instead; this is not reproducible and is refused in offline mode. apt holds
`kubelet`, `kubeadm`, and `kubectl` (`kubernetes_held_packages`), and the role
never changes installed Kubernetes packages outside the
[upgrade flow](docs/upgrade.md). [Renovate](https://docs.renovatebot.com/)
proposes updates of the pinned versions (`renovate.json`; it needs the
Renovate GitHub app), and Dependabot updates the GitHub Actions.

### Role releases

The role follows [Semantic Versioning](https://semver.org/):

- **Major** (`v2.0.0`): changes that need action from users, such as renamed
  or removed variables, changed defaults that alter a running cluster, or a
  new minimum Ansible or OS version.
- **Minor** (`v1.1.0`): new features and new variables with backwards
  compatible defaults, and Kubernetes minor version bumps of the pinned
  defaults.
- **Patch** (`v1.0.1`): bug fixes, documentation, and patch releases of
  pinned components.

Record every change under `Unreleased` in [CHANGELOG.md](CHANGELOG.md). To
release, move those entries under a new version heading, then push a version
tag such as `v1.0.0` to run the CI checks and publish a GitHub Release. The
release workflow requires the repository's standard `GITHUB_TOKEN`
permission to create releases.

### Tests

CI runs `ansible-lint`, syntax checks of the role and example playbooks,
template rendering tests (`tests/render.yml`, `tests/operations.yml`),
`nft --check` on the rendered firewall, and `shellcheck` on the generated
scripts. To check idempotence against a real lab cluster, run the site
playbook twice and require no changes on the second run:

```sh
tests/idempotence.sh -i examples/inventory.yml examples/site.yml --ask-vault-pass
```
