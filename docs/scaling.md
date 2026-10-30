# Add and remove nodes

## Add a node

1. Prepare the host like the others: the same OS release, SSH access, and
   privilege escalation.
2. Add it to the inventory, in `k8s_control_plane` or `k8s_workers`, with its
   `ansible_host` address. Keep the existing first controller first.
3. Run the full site playbook against all nodes. Do not use `--limit`: the
   first controller creates the join credentials, and every node must learn
   the new node's address.

   ```sh
   ansible-playbook -i examples/inventory.yml examples/site.yml \
     --ask-vault-pass
   ```

The role detects which nodes have not joined yet, creates a join token (and,
for controllers, uploads the control-plane certificates) only for them, and
joins them. The same run updates `/etc/hosts`, HAProxy backends, Keepalived
peers, and the host firewall on every node. A new controller gets the API
server hardening files before it joins, so it starts with the same settings.
New nodes install the Kubernetes release that the first controller runs, not
necessarily `kubernetes_version`, because a kubelet must never be newer than
the API server. Upgrade the whole cluster with the upgrade flow afterwards.

Keep an odd number of controllers (1, 3, or 5) so etcd keeps quorum when one
of them fails.

## Remove a node

`examples/remove-node.yml` removes the nodes listed in
`kubernetes_remove_nodes`, one at a time:

```sh
ansible-playbook -i examples/inventory.yml examples/remove-node.yml \
  -e '{"kubernetes_remove_nodes": ["<worker name>"]}' --ask-vault-pass
```

Use the host names exactly as they appear in your inventory.

For each node it:

1. stops Longhorn from scheduling replicas there and waits until Longhorn has
   rebuilt every replica on the remaining workers
   (`kubernetes_remove_node_eviction_timeout`, 30 minutes by default),
2. drains the node,
3. on a controller, stops Keepalived and HAProxy so the API virtual IP moves
   to another controller,
4. runs `kubeadm reset`, which also removes a controller's etcd member,
5. deletes the Kubernetes and Longhorn node objects.

The playbook refuses to remove the first controller or the registry staging
node, and to leave fewer workers than the Longhorn replica count or the
registry replica count. To remove the first controller, move another
controller to the top of the `k8s_control_plane` group first, run the site
playbook once, and then remove the old one.

Afterwards, delete the host from the inventory and run `examples/site.yml`
again so the remaining nodes drop it from HAProxy, Keepalived, `/etc/hosts`,
and the firewall.

## Replace a failed node

If a node is gone for good, the drain and reset steps cannot reach it. Remove
it by hand from a controller:

```sh
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force --timeout=120s
kubectl delete node <node>
kubectl -n longhorn-system delete nodes.longhorn.io <node>
```

For a failed controller, also remove its etcd member:

```sh
ETCDCTL="sudo crictl exec $(sudo crictl ps --name '^etcd$' --quiet) etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/healthcheck-client.crt \
  --key=/etc/kubernetes/pki/etcd/healthcheck-client.key"
$ETCDCTL member list
$ETCDCTL member remove <member ID>
```

Then add the replacement host as a new node.
