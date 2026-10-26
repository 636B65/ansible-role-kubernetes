# API server hardening

With `kubernetes_hardening_enabled: true` (the default) the role configures
three API server features on every controller:

| Feature | Setting | Files on each controller |
| --- | --- | --- |
| Audit logging | `kubernetes_audit_log_enabled` | `/etc/kubernetes/hardening/audit-policy.yaml`, logs in `/var/log/kubernetes/audit/` |
| Encryption of Secrets at rest | `kubernetes_secrets_encryption_enabled` | `/etc/kubernetes/hardening/encryption-config.yaml` |
| Pod Security admission defaults | `kubernetes_pod_security_enabled` | `/etc/kubernetes/hardening/admission-config.yaml` |

The files are mounted into the kube-apiserver static pods through the kubeadm
configuration. New clusters get the settings at `kubeadm init`, and
controllers that join later inherit them.

## Audit logging

The policy records metadata (who did what, when, and with which result) for
every request, and request bodies for changes. It never records the contents
of Secrets, ConfigMaps, or tokens. Health checks, events, leases, and routine
node status updates are not logged. The API server rotates the log by size
(`kubernetes_audit_log_maxsize`, in MB) and keeps
`kubernetes_audit_log_maxbackup` files for at most
`kubernetes_audit_log_maxage` days.

```sh
sudo tail -f /var/log/kubernetes/audit/audit.log | jq .
```

## Encryption of Secrets at rest

Secrets are encrypted with the `secretbox` provider and a 32-byte key. When
`kubernetes_secrets_encryption_key` is empty, the role generates a key on the
first controller and copies it to the others. Later runs read the key back
from the first controller, so it stays stable.

The key is stored in plain text in `encryption-config.yaml` (mode `0600`).
Anyone with root access to a controller or a copy of its backups can decrypt
the Secrets. The etcd backup archive includes the key because a snapshot
cannot be restored without it; protect the backups accordingly.

To manage the key yourself, store it in Ansible Vault:

```sh
python3 -c 'import base64, os; print(base64.b64encode(os.urandom(32)).decode())'
```

```yaml
kubernetes_secrets_encryption_key: !vault |
  ...
```

The role refuses to replace a key that is already in use, because Secrets
encrypted with the old key would become unreadable. Key rotation is not
automated: it needs a second key with a new name next to the old one, a
rewrite of every Secret, and then removal of the old key. Follow the upstream
[key rotation procedure](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/#rotating-a-decryption-key)
and do not run the `hardening` tag while you edit the files by hand.

## Pod Security admission

The cluster-wide defaults enforce the `baseline` Pod Security Standard and
warn and audit against `restricted`. Namespaces that need privileged pods are
exempt: `kube-system` (Cilium, kube-proxy), `longhorn-system`, the registry
namespace (its one-time migration job uses a hostPath volume), and the
monitoring namespace. Add your own with
`kubernetes_pod_security_exempt_namespaces`, or label a single namespace:

```sh
kubectl label namespace my-namespace \
  pod-security.kubernetes.io/enforce=privileged
```

Namespace labels always take precedence over the defaults.

## Roll the settings out to an existing cluster

Clusters created before this feature run their API servers without these
flags. The upgrade flow adds them: it updates the `kubeadm-config` ConfigMap
on the first controller and then re-renders each controller's API server
manifest with `kubeadm upgrade apply` or `kubeadm upgrade node`, one
controller at a time. Workloads keep running; each API server restarts once.

Encryption needs two passes on a cluster with several controllers. If the
first restarted API server started writing encrypted Secrets right away, the
API servers that have not restarted yet could not read them.

1. Check which running pods would violate the `baseline` standard:

   ```sh
   kubectl label --dry-run=server --overwrite namespace --all \
     pod-security.kubernetes.io/enforce=baseline
   ```

   Exempt or relabel namespaces that report warnings before you continue.
   Pods that are already running are not evicted, but new pods that violate
   the standard are rejected.

2. Teach every API server to read encrypted Secrets, while still writing
   them unencrypted:

   ```sh
   ansible-playbook -i examples/inventory.yml examples/upgrade.yml \
     -e kubernetes_secrets_encryption_stage=prepare --ask-vault-pass
   ```

3. Switch to writing encrypted Secrets. The API servers reload the
   encryption file automatically within about a minute:

   ```sh
   ansible-playbook -i examples/inventory.yml examples/site.yml \
     --tags hardening --ask-vault-pass
   ```

4. Rewrite the existing Secrets so they are stored encrypted:

   ```sh
   kubectl get secrets --all-namespaces --output json \
     | kubectl replace --filename -
   ```

5. Verify that a Secret is encrypted in etcd. The value should start with
   `k8s:enc:secretbox:v1:key1:`:

   ```sh
   sudo crictl exec "$(sudo crictl ps --name '^etcd$' --quiet)" etcdctl \
     --endpoints=https://127.0.0.1:2379 \
     --cacert=/etc/kubernetes/pki/etcd/ca.crt \
     --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
     --key=/etc/kubernetes/pki/etcd/healthcheck-client.key \
     get /registry/secrets/local-registry/kubernetes-image-registry-http \
     | head -c 64 | od -c
   ```

Single-controller clusters can skip step 2 and run the upgrade playbook with
the default `active` stage.

## Turn a feature off

The role only adds API server flags; it does not remove them. To turn a
feature off:

1. For encryption, first set `kubernetes_secrets_encryption_stage: prepare`,
   run the `hardening` tag, and rewrite all Secrets (step 4 above) so they are
   stored unencrypted again.
2. Set the feature flag to `false` in your variables.
3. Remove the matching `extraArgs` entries from the `ClusterConfiguration` in
   the `kubeadm-config` ConfigMap:

   ```sh
   kubectl -n kube-system edit configmap kubeadm-config
   ```

4. Re-render the API server manifest one controller at a time, with
   `sudo kubeadm upgrade apply --yes v<current version>` on the first
   controller and `sudo kubeadm upgrade node` on the others.
