# Quick start

Two paths to a running cluster:

- [Online](#online-installation): the nodes download packages and images
  from the internet.
- [Offline](#offline-installation): the nodes have no internet access and
  install from a bundle staged on a cluster that has.

## Before you start

- A machine to run Ansible from, with Ansible Core 2.16 or newer.
- Debian-family nodes with Python, SSH access, and sudo.
- At least one control-plane node and three workers: Longhorn keeps the
  registry's three replicas on separate workers. Use three controllers for a
  highly available control plane.
- A free IPv4 address on the controllers' network for the API virtual IP.

See [System requirements and sizing](../README.md#system-requirements-and-sizing)
for node sizes.

## Online installation

1. **Get the role** at a released version:

   ```sh
   git clone --branch v2.1.1 https://github.com/636B65/ansible-role-kubernetes.git
   cd ansible-role-kubernetes
   ansible-galaxy role install . --roles-path ./roles
   ```

2. **Describe your nodes** in `examples/inventory.yml`: your own host names
   in `k8s_control_plane` and `k8s_workers`, each with its IPv4 address as
   `ansible_host`. The `kube-*` names are only examples: the inventory names
   become the node names and hostnames. If Ansible connects to a host over
   another name or network, also set `kubernetes_node_ip` to the address the
   nodes use to reach each other. The first controller in the list is the
   one the cluster is built from.

3. **Add SSH and sudo credentials** and encrypt them:

   ```sh
   cp examples/group_vars/all.yml.example examples/group_vars/all.yml
   # Replace every changeme value, then:
   ansible-vault encrypt examples/group_vars/all.yml
   ```

4. **Set the cluster values** in `examples/site.yml`:

   ```yaml
   kubernetes_api_vip: 192.0.2.10              # free address for the API
   kubernetes_api_vip_prefix: 24
   kubernetes_keepalived_auth_pass: XXXXXXXX   # your own secret, max 8 characters; keep it in Vault
   ```

   The role refuses to run with the example values. Review the pod and
   service networks in `defaults/main.yml` if they overlap your network.

5. **Install the cluster:**

   ```sh
   ANSIBLE_ROLES_PATH=./roles ansible-playbook \
     -i examples/inventory.yml examples/site.yml --ask-vault-pass
   ```

6. **Check the result** on the first controller:

   ```sh
   kubectl get nodes -o wide
   sudo cilium status
   kubectl -n longhorn-system get volumes.longhorn.io
   ```

7. **Open the web UI** (see [Headlamp](headlamp.md)):

   ```sh
   kubectl -n headlamp create token headlamp-admin --duration=8h
   kubectl -n headlamp port-forward service/headlamp 8080:80
   ```

   Browse to <http://localhost:8080> and sign in with the token.

## Offline installation

The offline nodes install from a bundle in `/opt/kubernetes-offline`. You
build the bundle once on a cluster with internet access, then copy it.

> The offline flow has not been verified end to end on an air-gapped network
> yet. Test it in a lab before you rely on it.

### Stage the bundle on a cluster with internet access

The staging cluster must run the same Debian release and CPU architecture as
the offline nodes, and use the same role version and component versions.

1. Install the staging cluster with the [online steps](#online-installation).
2. Stage the packages and images on its nodes:

   ```sh
   ANSIBLE_ROLES_PATH=./roles ansible-playbook -i examples/inventory.yml \
     examples/site.yml --tags offline_stage --ask-vault-pass
   ```

3. Copy the whole `/opt/kubernetes-offline` directory from a
   **control-plane node** of the staging cluster (it also holds the Cilium,
   Helm, and Headlamp assets) to the same path on every offline node, for
   example with `rsync -a`, or bake it into your VM template. Expect several
   gigabytes.

### Install the offline cluster

1. Make sure `apt-get update` succeeds on the offline nodes: disable package
   sources they cannot reach, or point them at a local mirror. The role adds
   the bundle as a local repository but leaves your OS sources alone.
2. Prepare the inventory, credentials, and `examples/site.yml` as in online
   steps 2 to 4, and add:

   ```yaml
   kubernetes_offline_mode: true
   ```

   Keep the component versions listed in the bundle's `VERSIONS` file; offline
   mode refuses `latest`.

3. Run the site playbook as in online step 5. The Ansible machine needs no
   internet access either.
4. Check the result as in online steps 6 and 7.

kube-prometheus-stack is not available offline. To upgrade an offline
cluster, stage a new bundle with the new versions first.

## Next steps

| Task | Guide |
| --- | --- |
| Restrict network access to the nodes | [Host firewall](firewall.md) |
| Copy etcd backups off the cluster | [etcd backup and restore](etcd-backup-restore.md) |
| Upgrade Kubernetes | [Upgrade Kubernetes](upgrade.md) |
| Add or remove nodes | [Add and remove nodes](scaling.md) |
| Expose a service on the LAN | [NGINX and Cilium LoadBalancer](deploy-nginx-cilium-loadbalancer.md) |
| Something does not work | [Troubleshooting](troubleshooting.md) |
