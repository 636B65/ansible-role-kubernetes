# Changelog

All notable changes to this role are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the role uses
[Semantic Versioning](https://semver.org/) as described in the README.

## [Unreleased]

## [3.1.0] - 2026-10-31

### Added

- `kubernetes_longhorn_enabled` and `kubernetes_registry_enabled` (both `true`
  by default) turn off Longhorn and the internal registry on small hosts. The
  registry needs Longhorn, so the role refuses the registry without it. The
  switches also cover version resolution, node removal, and the offline bundle.
- A `helm` tag and `tasks/helm.yml`, which install Helm on the controllers when
  the registry or Headlamp is enabled.

### Changed

- Helm moved out of `cilium_offline.yml`, so Headlamp no longer needs the
  registry tags to find `/usr/local/bin/helm`.

### Fixed

- Start Keepalived and HAProxy on the first controller right after
  `kubeadm init`, so the API VIP answers before the Cilium install. Before,
  `cilium install` failed with "no route to host" on the VIP.
- Wait only for the Cilium agent and operator during bootstrap. Hubble Relay
  and UI cannot schedule on the tainted controller before workers join, so
  `cilium status --wait` always timed out; `observability.yml` still waits for
  the full status after the nodes have joined.
- Detect an existing Cilium installation by its DaemonSet instead of
  `cilium status`, so a re-run does not try to install it a second time.
- Install `cri-tools` so `crictl` exists, online and from the offline bundle.
  The etcd backup service failed with "crictl: command not found" because the
  `kubeadm` package no longer depends on it.
- Apply the networking sysctls when `ip_forward` is still 0, even if the file
  is already in place. After a failed run the handler never ran, and
  `kubeadm join` stopped on the preflight check.
- Wait for the `longhorn-csi-plugin` DaemonSet before patching it. Longhorn
  creates it after the manager is ready, so the patch failed with `NotFound`.

## [3.0.0] - 2026-10-30

This is a major release: the next run can rename machines and move node
services to the inventory addresses. Read the upgrade notes first.

### Added

- `kubernetes_manage_hostname` (default `true`) sets each machine's hostname
  to its inventory host name.
- `kubernetes_node_ip` sets a node's cluster address per host when it differs
  from `ansible_host`, for example when Ansible connects over a management
  network or a DNS name.
- Preflight checks that inventory names are valid node names, that cluster
  addresses are unique, and that each address is configured on its node.

### Changed

- Every component uses the node's cluster address from the inventory instead
  of the address on the default route: kubelet (`--node-ip`), the API server
  and etcd on the first and joining controllers, HAProxy backends, Keepalived
  peers, the registry host entry, and the firewall. The API VIP defaults to
  the interface that holds that address.
- etcd backup files are named after the inventory host name.
- The docs and architecture diagram no longer present `kube-cp01`-style names
  as fixed; they are examples, and the inventory decides the names.

### Upgrade notes

- On an existing cluster, check that each node's `ansible_host` (or
  `kubernetes_node_ip`) is the address the cluster already uses. If a node's
  default-route address differs, the next run moves kubelet, HAProxy, and
  Keepalived to the inventory address.
- Machine hostnames change to the inventory names on the next run. Set
  `kubernetes_manage_hostname: false` to keep the current hostnames.

## [2.1.1] - 2026-10-30

### Changed

- The architecture diagram (`docs/architecture.svg` and its draw.io source)
  shows the current role: pinned upstream sources, the offline bundle, API
  server hardening and etcd backups on the controllers, the image builds in
  the internal registry, and the cluster add-ons (metrics-server, Hubble,
  Headlamp, optional kube-prometheus-stack).

### Fixed

- The third worker in the architecture diagram is labelled `kube-wl03`
  instead of `kube-ws03`.

## [2.1.0] - 2026-10-30

### Added

- Skeleton Dockerfiles (`ubuntu-base`, `nginx-static`) that the
  `registry_builds` tag builds with Buildah on the registry node and pushes to
  the internal registry, where every node can pull them without credentials.
  Add your own images with `kubernetes_registry_builds`.
- Guide for importing images built elsewhere into the internal registry
  (`docs/importing-images.md`).

## [2.0.1] - 2026-10-30

### Added

- Quick start guide for online and offline installations
  (`docs/quickstart.md`).

### Changed

- CI uses `actions/checkout` v7 and `actions/setup-python` v7.

## [2.0.0] - 2026-10-30

This is a major release: it changes defaults that affect running clusters.
Read the upgrade notes below before running it against an existing cluster.

### Added

- Pinned versions for Kubernetes, Cilium, the Cilium CLI, Helm, Longhorn,
  metrics-server, and kube-prometheus-stack, with `latest` as an opt-in.
- apt holds on `kubelet`, `kubeadm`, and `kubectl`.
- Rolling upgrade flow (`examples/upgrade.yml`, `upgrade` tag) with drain,
  etcd snapshot, version-skew checks, and optional Cilium upgrade.
- API server hardening: audit logging, encryption of Secrets at rest, and
  Pod Security admission defaults (`baseline` enforced), configured through a
  kubeadm configuration file. Existing clusters get it through the upgrade
  flow.
- Scheduled etcd snapshots with PKI archives on every controller, and a
  restore guide.
- Optional nftables host firewall (`kubernetes_firewall_enabled`).
- metrics-server, Hubble Relay and UI, and optional kube-prometheus-stack.
- Headlamp web UI (`headlamp` tag), the maintained successor of the archived
  Kubernetes Dashboard. It has no cluster permissions of its own, uses a
  ClusterIP service by default, and comes with an optional `headlamp-admin`
  sign-in account.
- Offline bundle staging (`offline_stage` tag) and offline installation mode
  (`kubernetes_offline_mode`).
- Node removal flow (`examples/remove-node.yml`) with Longhorn replica
  eviction.
- Role argument specifications in `meta/argument_specs.yml`.
- Renovate configuration for the pinned versions and Dependabot for GitHub
  Actions.
- Automatic release tagging: CI on `main` creates the tag and GitHub Release
  for the newest version in `CHANGELOG.md`.
- Template tests in `tests/operations.yml`, `nft` and `shellcheck` checks in
  CI, and `tests/idempotence.sh` for lab clusters.
- Guides for upgrades, hardening, etcd backup and restore, the firewall,
  scaling, offline installation, and troubleshooting.

### Changed

- `kubeadm init` now uses a generated configuration file
  (`/etc/kubernetes/kubeadm-config.yaml`) instead of command-line flags.
- Nodes that join an existing cluster install the Kubernetes release of the
  first controller, so a kubelet is never newer than the API server.
- Installed Kubernetes packages are no longer upgraded by normal runs;
  containerd and other OS packages are installed with `state: present`
  instead of `latest`.
- Join tokens and control-plane certificate uploads are created only when a
  node still needs to join. Tokens expire after one hour.
- Images already present in the internal registry are not copied again
  (`kubernetes_registry_images_force_refresh` restores the old behavior), and
  temporary manifests no longer report changes, so repeated runs are
  idempotent.
- The default registry images are pinned: `registry:2.8.3`, `ubuntu:26.04`,
  and `nginx:1.30.6` instead of `registry:2`, `ubuntu:latest`, and
  `nginx:stable`.
- The Longhorn manifest is stored in `/opt/kubernetes-offline/manifests`
  instead of `/tmp`.

### Upgrade notes

- Before running this version against an existing cluster, check that the
  pinned defaults match what runs today (`kubectl version`,
  `cilium version`, `kubectl -n longhorn-system get daemonset longhorn-manager -o wide`).
  If the cluster runs newer releases than the defaults, set the version
  variables to the running releases; Longhorn refuses downgrades.
- Hardening is applied automatically only to new clusters. Follow
  [API server hardening](docs/hardening.md#roll-the-settings-out-to-an-existing-cluster)
  to roll it out to an existing one.
- The default registry, Ubuntu, and NGINX image tags changed. Update
  workloads that use the old tags from the internal registry.
- Playbooks must still set `loginusername`; the argument specification now
  reports a missing value before any task runs.

## [1.0.0] - 2026-10-16

### Added

- Initial release: containerd, Kubernetes, and Cilium installation with
  HAProxy and Keepalived for a highly available API endpoint, and an internal
  registry on replicated Longhorn storage with offline staging of the Cilium
  chart and images.

[Unreleased]: https://github.com/636B65/ansible-role-kubernetes/compare/v3.1.0...HEAD
[3.1.0]: https://github.com/636B65/ansible-role-kubernetes/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/636B65/ansible-role-kubernetes/compare/v2.1.1...v3.0.0
[2.1.1]: https://github.com/636B65/ansible-role-kubernetes/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/636B65/ansible-role-kubernetes/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/636B65/ansible-role-kubernetes/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/636B65/ansible-role-kubernetes/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/636B65/ansible-role-kubernetes/releases/tag/v1.0.0
