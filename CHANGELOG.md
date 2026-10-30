# Changelog

All notable changes to this role are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the role uses
[Semantic Versioning](https://semver.org/) as described in the README.

## [Unreleased]

### Added

- Quick start guide for online and offline installations
  (`docs/quickstart.md`).

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

[Unreleased]: https://github.com/636B65/ansible-role-kubernetes/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/636B65/ansible-role-kubernetes/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/636B65/ansible-role-kubernetes/releases/tag/v1.0.0
