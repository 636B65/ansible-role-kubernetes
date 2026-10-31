# Offline installation

The role can install a cluster on nodes without internet access, from a
bundle staged on a cluster that has it. The bundle lives in
`/opt/kubernetes-offline` (`kubernetes_offline_assets_directory`).

> The offline flow has not been verified end to end on an air-gapped network
> yet. Test it in a lab before you rely on it.

## What the bundle contains

| Path | Contents | Staged by |
| --- | --- | --- |
| `debs/` | Every package the role installs, with its full dependency closure, and an apt index (`Packages`) | `offline_stage` tag |
| `images/*.tar` | Container images for this node architecture: kubeadm control-plane images, the containerd sandbox image, every image used by running pods, all Longhorn images, and the registry images | `offline_stage` tag |
| `images/images.txt` | List of the staged image references | `offline_stage` tag |
| `manifests/` | Longhorn and metrics-server manifests, the Longhorn image list, and the Headlamp chart (controllers) | `offline_stage` tag |
| `cilium/`, `cilium-cli/` | Cilium Helm chart and Cilium CLI archives (only with `kubernetes_registry_enabled`) | `registry_images` / `cilium_offline` tags (controllers) |
| `helm/` | Helm archive | `helm` tag (controllers) |
| `VERSIONS` | The component versions and platform of the bundle | `offline_stage` tag |

With `kubernetes_longhorn_enabled: false` the bundle leaves out the Longhorn
manifests and images, and with `kubernetes_registry_enabled: false` it leaves
out the registry images. Stage and install with the same switch values. The
bundle also contains `cri-tools`, which provides `crictl` for the etcd backup.

## Stage a bundle

Stage on a working cluster that runs the same Debian or Ubuntu release, the
same CPU architecture, and the same pinned versions as the offline cluster.

1. Install the cluster normally with `examples/site.yml`, including the
   `registry` tags, so the Cilium assets exist on the controllers.
2. Stage the packages and images on every node:

   ```sh
   ansible-playbook -i examples/inventory.yml examples/site.yml \
     --tags offline_stage --ask-vault-pass
   ```

   The images are saved for the node's architecture only. Expect several
   gigabytes per node.

3. Copy the complete `/opt/kubernetes-offline` directory from a
   **control-plane node** (it includes the Cilium assets) into your VM
   template, or onto each new node at the same path, for example with
   `rsync -a`.

## Install offline

1. Set the same pinned versions as in the bundle's `VERSIONS` file, and turn
   on offline mode:

   ```yaml
   kubernetes_offline_mode: true
   ```

   Offline mode refuses `latest` versions.

2. Make sure `apt-get update` succeeds on the offline nodes. The role adds
   the bundle as a local repository (`/etc/apt/sources.list.d/kubernetes-offline.list`)
   but does not change your OS sources. Disable sources that the nodes cannot
   reach, or point them at a local mirror.

3. Run the site playbook as usual. In offline mode the role:

   - installs packages from the local repository,
   - imports the image archives into containerd before `kubeadm init` and
     `kubeadm join`,
   - installs the Cilium CLI from the bundle and Cilium from the staged
     chart, with tag-only image references so the imported images match,
   - applies the staged Longhorn and metrics-server manifests and installs
     Headlamp from the staged chart,
   - fills the internal registry from the image archives and builds the
     images in `kubernetes_registry_builds` from base images in it.

kube-prometheus-stack is installed from its upstream Helm repository and is
not available in offline mode.

## Upgrade an offline cluster

A bundle contains one Kubernetes release. To upgrade, stage a new bundle on an
online cluster that already runs the target versions, copy it to every
offline node, set the new versions, and run `examples/upgrade.yml` with
`kubernetes_offline_mode: true`.

## Images for later workloads

Add images your workloads need to `kubernetes_offline_extra_images` before
staging, and to `kubernetes_registry_images` to get them into the internal
registry. Pods can then use `registry.k8s.local:30500/<name>:<tag>`; see the
[Ubuntu pod guide](deploy-ubuntu-pod.md).
