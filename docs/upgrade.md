# Upgrade Kubernetes

The role pins every component version in `defaults/main.yml`, and apt holds
`kubelet`, `kubeadm`, and `kubectl`. A normal run of `examples/site.yml`
never changes the installed Kubernetes packages; if the installed version
differs from `kubernetes_version`, the run prints a notice and leaves the
packages alone. Upgrades go through a separate, rolling flow.

## What the upgrade flow does

`examples/upgrade.yml` runs the role's `upgrade` tasks with `serial: 1`, so
it handles one node at a time in inventory order: controllers first, then
workers. On each node it:

1. Checks that the target release is the same or the next minor release of
   the running control plane. kubeadm cannot skip minor releases or
   downgrade.
2. Takes an etcd snapshot on controllers (when etcd backups are enabled).
3. Points the Kubernetes apt repository at the target minor release.
4. Upgrades `kubeadm`, then runs `kubeadm upgrade apply` on the first
   controller or `kubeadm upgrade node` on every other node.
5. Drains the node, upgrades `kubelet` and `kubectl`, restarts kubelet, waits
   for the node to report the new version and `Ready`, and uncordons it.
6. Holds the packages again.

Nodes that already run the target version are skipped, so you can rerun the
playbook after fixing a failed node. The first controller must finish first:
the other nodes refuse to upgrade while the control plane still runs the old
version.

A failed drain or upgrade leaves the node cordoned on purpose. Fix the cause,
then rerun the playbook or run `kubectl uncordon <node>` yourself.

## Before you upgrade

- Read the Kubernetes changelog for the target release and check for removed
  APIs used by your workloads.
- Check that Cilium supports the target release. The supported versions are
  listed in the Cilium documentation under *Kubernetes compatibility*. The
  pinned defaults are tested together; Cilium 1.20 is tested with Kubernetes
  1.33 to 1.36.
- Check that Longhorn reports every volume as `healthy`:

  ```sh
  kubectl -n longhorn-system get volumes.longhorn.io
  ```

- Make sure a recent etcd snapshot exists and that you have a copy outside the
  cluster (see [etcd backup and restore](etcd-backup-restore.md)).

## Run an upgrade

1. Set the target release in your inventory or playbook variables:

   ```yaml
   kubernetes_version: "1.36.6"
   ```

   For a minor upgrade, set the next minor release only, for example from
   `1.36.x` to `1.37.y`. Repeat the procedure for each minor release.

2. Run the rolling upgrade:

   ```sh
   ansible-playbook -i examples/inventory.yml examples/upgrade.yml \
     --ask-vault-pass
   ```

   The same tasks are available through the main role as the `upgrade` tag
   (`--tags upgrade`), but they then require a play with `serial: 1`.

3. Check the result:

   ```sh
   kubectl get nodes -o wide
   kubectl version
   ```

## Upgrade Cilium

Cilium is not upgraded by default. To upgrade it to `kubernetes_cilium_version`
as part of the upgrade flow, set `kubernetes_upgrade_cilium: true`. The first
controller then runs `cilium upgrade --version <version>` after it has been
upgraded. Read the Cilium upgrade notes for the target version first, and
upgrade one Cilium minor release at a time.

Run the `registry_images` tag afterwards so the offline assets and the
internal registry contain the new Cilium chart and images.

## Upgrade Longhorn, Helm, and metrics-server

Changing `kubernetes_longhorn_version` and running the `longhorn` tag applies
the newer Longhorn manifest. Longhorn supports upgrades from the previous
minor release only and refuses downgrades. Follow the Longhorn upgrade notes
for the target version.

`kubernetes_metrics_server_version` and `kubernetes_helm_version` are applied
by the next normal run of the `observability` and `cilium_offline` tags.

## Roll out API server hardening

The upgrade flow also applies the role's API server hardening settings to an
existing cluster, even when no version changes. See
[API server hardening](hardening.md) for the steps.
