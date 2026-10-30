# Headlamp web UI

The role installs [Headlamp](https://headlamp.dev/), a web UI for managing
workloads and inspecting the cluster. It replaces the Kubernetes Dashboard,
which was archived in January 2026 and no longer gets security fixes;
Headlamp is maintained under Kubernetes SIG UI.

Headlamp is enabled by default (`kubernetes_headlamp_enabled`) and installed
with Helm from the pinned chart `kubernetes_headlamp_version` into the
`headlamp` namespace. Apply changes with the `headlamp` tag (also part of
`observability`):

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags headlamp --ask-vault-pass
```

## Security model

- The Headlamp pod has **no cluster permissions of its own**. The role turns
  off the chart's default cluster-admin binding, so every user signs in with
  a token, and Headlamp acts with that token's RBAC permissions.
- The container runs as a non-root user with a read-only root filesystem,
  no capabilities, and the `RuntimeDefault` seccomp profile, which meets the
  `restricted` Pod Security Standard.
- The service is `ClusterIP` by default, so Headlamp is reachable only
  through `kubectl port-forward`. Headlamp serves plain HTTP; tokens sent to
  a `NodePort` service cross the network unencrypted.

## Open Headlamp

From a controller, or any machine with a kubeconfig for the cluster:

```sh
kubectl -n headlamp port-forward service/headlamp 8080:80
```

Open <http://localhost:8080>. When you run the command on a controller over
SSH, forward the port as well: `ssh -L 8080:localhost:8080 <controller>`.

## Sign in

With `kubernetes_headlamp_admin_account_enabled: true` (the default) the role
creates the `headlamp-admin` ServiceAccount, bound to `cluster-admin`. Create
a short-lived token for it and paste it into the sign-in page:

```sh
kubectl -n headlamp create token headlamp-admin --duration=8h
```

Anyone with the token has full control of the cluster until it expires.
For day-to-day use, prefer accounts with narrower roles. For a read-only
account:

```sh
kubectl -n headlamp create serviceaccount viewer
kubectl create clusterrolebinding headlamp-viewer \
  --clusterrole=view --serviceaccount=headlamp:viewer
kubectl -n headlamp create token viewer --duration=8h
```

Setting `kubernetes_headlamp_admin_account_enabled: false` removes the
`headlamp-admin` account on the next run.

## Expose Headlamp on the network

To reach Headlamp without a port-forward, publish it on every node:

```yaml
kubernetes_headlamp_service_type: NodePort
kubernetes_headlamp_node_port: 30443
```

Headlamp is then available at `http://<any node>:30443`. Because the
connection is not encrypted, use this only on a trusted management network,
and limit the source addresses with `kubernetes_firewall_nodeport_networks`
(see [Host firewall](firewall.md)). For anything wider, put Headlamp behind
an ingress or load balancer that terminates TLS.

## Offline installations

The `offline_stage` tag saves the Headlamp chart on the controllers and its
image in the bundle, so offline mode installs Headlamp from there.

## Remove Headlamp

Set `kubernetes_headlamp_enabled: false`. The role then stops managing
Headlamp but does not uninstall it; remove it by hand:

```sh
helm -n headlamp uninstall headlamp
kubectl delete clusterrolebinding headlamp-admin
kubectl delete namespace headlamp
```
