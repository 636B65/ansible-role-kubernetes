# Troubleshooting

Run the commands on a controller unless stated otherwise. `kubectl` uses
`/etc/kubernetes/admin.conf` there (`export KUBECONFIG=/etc/kubernetes/admin.conf`
when you run it with `sudo`).

## The API virtual IP does not respond or does not move

Find the controller that holds the VIP:

```sh
ansible k8s_control_plane -b -m ansible.builtin.command \
  -a "ip -brief address show" | grep -B1 192.0.2.10
```

On each controller:

```sh
sudo systemctl status keepalived haproxy
sudo journalctl -u keepalived -n 50
curl -k https://192.0.2.10:8443/readyz
```

Common causes:

- **No controller holds the VIP.** Keepalived failed to start, usually
  because the interface in `kubernetes_api_vip_interface` does not exist or
  the network was not up yet at boot. The role orders Keepalived after
  `systemd-networkd-wait-online`; on hosts without systemd-networkd, check
  that the interface is up before Keepalived starts.
- **Two controllers hold the VIP (split brain).** The controllers cannot
  exchange VRRP packets. They use unicast; check that they can reach each
  other, that `kubernetes_keepalived_auth_pass` and
  `kubernetes_api_vip_router_id` match on all of them, and that no other
  VRRP instance on the network uses the same router ID.
- **The VIP stays on a controller with a broken API server.** Keepalived
  moves the VIP when a controller fails, not when only its API server does.
  HAProxy on the VIP holder still sends traffic to the healthy API servers.
  Check the backend state on the statistics page:
  `http://<controller>:8404/stats`.

## HAProxy shows API server backends as down

```sh
sudo crictl ps --name kube-apiserver
sudo crictl logs "$(sudo crictl ps --name kube-apiserver --quiet)" 2>&1 | tail -50
curl -k https://127.0.0.1:6443/readyz?verbose
```

A failing API server usually means etcd is unhealthy (next section), a
certificate expired (`sudo kubeadm certs check-expiration`), or a hardening
file is missing from `/etc/kubernetes/hardening`.

## etcd is unhealthy

```sh
ETCDCTL="sudo crictl exec $(sudo crictl ps --name '^etcd$' --quiet) etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key"
$ETCDCTL endpoint health --cluster
$ETCDCTL endpoint status --cluster --write-out=table
$ETCDCTL member list --write-out=table
```

etcd needs a majority of its members: two of three controllers. If one member
is permanently gone, remove it (see [Scaling](scaling.md#replace-a-failed-node)).
If quorum is lost, restore from a snapshot (see
[etcd backup and restore](etcd-backup-restore.md)).

## A node fails to join

The role prints the kubeadm error with the token and certificate key
redacted. Common causes:

- **The token or certificate key expired.** Join tokens created by the role
  are valid for one hour, and uploaded control-plane certificates for two
  hours. Run the site playbook again; it creates new credentials for nodes
  that have not joined yet.
- **A previous join attempt left state behind.** Reset the node and retry:
  `sudo kubeadm reset --force && sudo rm -rf /etc/cni/net.d`.
- **The node cannot reach the API VIP on port 8443** or, for a controller,
  the other controllers on 2379-2380. Check routes and firewalls.
- **Preflight errors** such as swap enabled or missing kernel modules. Run
  the `prerequisites` tag on the node first.

Running only `--tags join` also creates join credentials, so it works after
a failed join.

## Nodes are NotReady or pods cannot reach each other

```sh
kubectl get nodes -o wide
cilium status
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
cilium connectivity test   # creates test workloads in a cilium-test namespace; delete it afterwards
```

Check `journalctl -u kubelet` on the node. A node with a stopped or
crash-looping Cilium agent stays `NotReady`.

## Longhorn volumes are degraded or faulted

```sh
kubectl -n longhorn-system get volumes.longhorn.io
kubectl -n longhorn-system get replicas.longhorn.io -o wide
kubectl -n longhorn-system get nodes.longhorn.io
```

- **Degraded:** fewer healthy replicas than configured. Longhorn rebuilds
  them automatically when a worker with enough free space is schedulable.
  Check that at least `kubernetes_longhorn_replica_count` workers are
  `Ready`, have schedulable disks, and have free space.
- **Faulted:** no healthy replica is left. Find the newest replica in the
  Longhorn UI and salvage it, or restore from a Longhorn backup.
- **Volumes do not attach:** check that `iscsid` runs and `open-iscsi` and
  `nfs-common` are installed on every node (the `longhorn` tag installs
  them), and that node-to-node traffic is allowed.

The Longhorn UI is not exposed by default:

```sh
kubectl -n longhorn-system port-forward service/longhorn-frontend 8080:80
```

## Pods cannot pull from the internal registry

```sh
curl http://registry.k8s.local:30500/v2/_catalog
kubectl -n local-registry get pods,pvc -o wide
grep registry.k8s.local /etc/hosts
cat /etc/containerd/certs.d/registry.k8s.local:30500/hosts.toml
```

Every node resolves `registry.k8s.local` to itself and reaches the registry
through the NodePort. If the registry pods are not `Running`, check the
Longhorn volume behind the `registry-data` claim. Run the `registry_runtime`
tag if a node is missing its containerd registry configuration.

## Pods are rejected by Pod Security admission

An error such as `violates PodSecurity "baseline:latest"` means the pod needs
more privileges than the namespace allows. Fix the pod's security context,
or exempt the namespace (see [API server hardening](hardening.md#pod-security-admission)).

## The upgrade stops at the drain step

`kubectl drain` waits for PodDisruptionBudgets. Find the blocking pods:

```sh
kubectl get pdb --all-namespaces
kubectl get pods --all-namespaces --field-selector spec.nodeName=<node>
```

Longhorn blocks a drain while the node holds the last healthy replica of a
volume. Wait until the volume is healthy, then rerun the upgrade playbook.
The node stays cordoned until the upgrade completes.

## apt refuses to upgrade Kubernetes packages

`kubelet`, `kubeadm`, and `kubectl` are held on purpose
(`apt-mark showhold`). Use the [upgrade flow](upgrade.md) instead of
`apt upgrade`. To release a hold manually: `sudo apt-mark unhold kubeadm`.

## SSH stops working after enabling the firewall

See [Host firewall](firewall.md#recover-from-a-lockout).

## metrics-server reports no metrics

```sh
kubectl top nodes
kubectl -n kube-system logs deployment/metrics-server
```

`x509: cannot validate certificate` errors mean metrics-server does not trust
the kubelet serving certificates. Keep
`kubernetes_metrics_server_kubelet_insecure_tls: true`, or enable kubelet
serving certificate rotation and approve the kubelet CSRs.

## Where to find logs

| Component | Command |
| --- | --- |
| kubelet, containerd | `journalctl -u kubelet`, `journalctl -u containerd` |
| HAProxy, Keepalived | `journalctl -u haproxy`, `journalctl -u keepalived` |
| Control-plane pods | `sudo crictl logs <container>` or `kubectl -n kube-system logs <pod>` |
| API audit log | `/var/log/kubernetes/audit/audit.log` |
| etcd backups | `journalctl -u kubernetes-etcd-backup.service` |
| Host firewall | `journalctl -u kubernetes-firewall.service`, `sudo nft list table inet kubernetes_host_firewall` |
