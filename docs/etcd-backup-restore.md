# etcd backup and restore

etcd holds the entire cluster state: every Kubernetes object, including
Secrets. Longhorn volume data is **not** in etcd; back it up separately with
Longhorn backups to an NFS or S3 target.

## Scheduled backups

With `kubernetes_etcd_backup_enabled: true` (the default) every controller
runs `kubernetes-etcd-backup.timer`, daily at 02:15 plus a random delay of up
to ten minutes (`kubernetes_etcd_backup_schedule`). Each run writes two files
to `/var/backups/kubernetes-etcd` (`kubernetes_etcd_backup_directory`, mode
`0700`):

| File | Contents |
| --- | --- |
| `etcd-snapshot-<host>-<UTC time>.db` | etcd snapshot from the local member |
| `kubernetes-config-<host>-<UTC time>.tar.gz` | `/etc/kubernetes/pki` and the hardening files, including the Secret encryption key |

The snapshot is taken with `etcdctl` inside the running etcd container, so no
extra tools are needed on the host and it works offline. Files older than
`kubernetes_etcd_backup_retention_days` days are deleted. The role takes a
first snapshot when none exists, and the upgrade flow takes one before it
changes a controller.

Both files are sensitive: the archive contains the cluster CA keys and the
Secret encryption key. **Copy them off the cluster regularly**; a backup that
only lives on the controllers does not survive the loss of all controllers.
For example, from the Ansible controller:

```sh
ansible k8s_control_plane -b -m ansible.builtin.fetch \
  -a "src=/var/backups/kubernetes-etcd/<file> dest=./etcd-backups/ flat=false"
```

Run a backup by hand or check the last run:

```sh
sudo systemctl start kubernetes-etcd-backup.service
sudo journalctl -u kubernetes-etcd-backup.service -n 20
systemctl list-timers kubernetes-etcd-backup.timer
```

## Check a snapshot

```sh
ETCD_IMAGE="$(sudo awk '/image:/ {print $2}' /etc/kubernetes/manifests/etcd.yaml)"
sudo ctr -n k8s.io run --rm \
  --mount type=bind,src=/var/backups/kubernetes-etcd,dst=/backup,options=rbind:ro \
  "$ETCD_IMAGE" etcd-check \
  etcdutl snapshot status /backup/etcd-snapshot-<host>-<time>.db --write-out=table
```

## Restore the cluster from a snapshot

A restore returns the whole cluster to the state of the snapshot. Objects
created later are lost, and workloads reconcile to the restored state. Use
it only when the cluster cannot recover otherwise, for example after losing
etcd quorum. If a single controller fails while the others keep quorum,
remove and re-add that controller instead (see [Scaling](scaling.md)).

Node names and addresses below are placeholders: use the host names from
your inventory (they are also the etcd member names) and each controller's
cluster address (`kubernetes_node_ip`, or `ansible_host`). Use one
snapshot for all members.

1. **Stop the control plane on every controller.** Moving the static pod
   manifests away makes kubelet stop the API server, controller manager,
   scheduler, and etcd:

   ```sh
   sudo mkdir -p /etc/kubernetes/manifests-stopped
   sudo mv /etc/kubernetes/manifests/*.yaml /etc/kubernetes/manifests-stopped/
   # Wait until no control-plane containers are left.
   sudo crictl ps | grep -E 'etcd|kube-apiserver' || echo stopped
   ```

2. **Restore the PKI and hardening files if a controller was rebuilt.** On a
   rebuilt controller, extract the matching `kubernetes-config-*.tar.gz`
   archive: `sudo tar -xzf <archive> -C /etc/kubernetes pki` and
   `sudo tar -xzf <archive> -C / etc/kubernetes/hardening`. All controllers
   must use the same CA and the same encryption key as the snapshot.

3. **Copy the chosen snapshot to every controller**, for example to
   `/var/backups/kubernetes-etcd/restore.db`.

4. **Restore the snapshot into a new data directory on every controller.**
   Run this on each controller with its own name and address:

   ```sh
   NAME=<controller>       # this controller's inventory host name
   IP=192.0.2.11           # this controller's cluster address
   # Every controller as <inventory name>=https://<cluster address>:2380:
   CLUSTER=<controller-1>=https://192.0.2.11:2380,<controller-2>=https://192.0.2.12:2380,<controller-3>=https://192.0.2.13:2380
   ETCD_IMAGE="$(sudo awk '/image:/ {print $2}' /etc/kubernetes/manifests-stopped/etcd.yaml)"

   sudo mv /var/lib/etcd "/var/lib/etcd.before-restore-$(date +%s)"
   sudo ctr -n k8s.io run --rm \
     --mount type=bind,src=/var/lib,dst=/var/lib,options=rbind:rw \
     --mount type=bind,src=/var/backups/kubernetes-etcd,dst=/backup,options=rbind:ro \
     "$ETCD_IMAGE" etcd-restore \
     etcdutl snapshot restore /backup/restore.db \
       --name "$NAME" \
       --initial-cluster "$CLUSTER" \
       --initial-advertise-peer-urls "https://$IP:2380" \
       --data-dir /var/lib/etcd
   ```

5. **Start the control plane again on every controller:**

   ```sh
   sudo mv /etc/kubernetes/manifests-stopped/*.yaml /etc/kubernetes/manifests/
   ```

6. **Check the cluster:**

   ```sh
   sudo crictl exec "$(sudo crictl ps --name '^etcd$' --quiet)" etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
     endpoint status --cluster --write-out=table
   kubectl get nodes
   kubectl get pods --all-namespaces
   ```

   Restart kubelet on every node (`sudo systemctl restart kubelet`) if nodes
   stay `NotReady`, and restart Cilium if pods cannot reach each other:
   `kubectl -n kube-system rollout restart daemonset/cilium`.

7. Run `examples/site.yml` once more to confirm the role reports a healthy,
   converged cluster.

On a single-controller cluster, use only that controller in `--initial-cluster`.
