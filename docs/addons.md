# Optional add-ons

The role can install three common cluster add-ons with Helm. All are off by
default; turn on the ones you need. Each is pinned to a chart version in
`defaults/main.yml` (Renovate proposes updates), installed from the first
controller, and kept in sync on every run: the release is upgraded when the
chart version or the values change.

| Add-on | Switch | Chart version variable | Namespace |
| --- | --- | --- | --- |
| [Traefik](https://traefik.io/traefik/) ingress controller (Ingress and Gateway API) | `kubernetes_ingress_enabled` | `kubernetes_traefik_version` | `traefik` |
| [cert-manager](https://cert-manager.io/) with its CRDs | `kubernetes_cert_manager_enabled` | `kubernetes_cert_manager_version` | `cert-manager` |
| [Argo CD](https://argo-cd.readthedocs.io/) for GitOps | `kubernetes_argocd_enabled` | `kubernetes_argocd_version` | `argocd` |

```yaml
kubernetes_ingress_enabled: true
kubernetes_cert_manager_enabled: true
kubernetes_argocd_enabled: true
```

Install or update only the add-ons on an existing cluster with the `addons`
tag (it also installs Helm on the controllers if needed):

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml --tags addons
```

Turning a switch off later does not uninstall the add-on; remove it with
`helm uninstall <name> --namespace <namespace>` (`traefik`, `cert-manager`,
`argocd`).

## Traefik

The role installs Traefik instead of ingress-nginx, which is retired upstream,
and instead of Cilium's ingress, which needs `kubeProxyReplacement=true` while
the role runs Cilium with kube-proxy.

- `kubernetes_ingress_service_type: NodePort` (default) exposes HTTP on
  `kubernetes_ingress_http_node_port` (30080) and HTTPS on
  `kubernetes_ingress_https_node_port` (30444) on every node. Put an external
  load balancer or DNS round-robin in front of the nodes.
- `LoadBalancer` needs a load-balancer implementation, for example Cilium LB
  IPAM with L2 Announcements (see
  [deploy-nginx-cilium-loadbalancer.md](deploy-nginx-cilium-loadbalancer.md)).
- Traefik is the default IngressClass unless
  `kubernetes_ingress_default_class: false`.

Example Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: web
spec:
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: web
                port:
                  number: 80
```

## cert-manager

cert-manager is installed with its CRDs (kept when the release is removed).
With `kubernetes_cert_manager_selfsigned_issuer: true` (default) the role
creates a `ClusterIssuer` named `selfsigned` for lab certificates:

```yaml
metadata:
  annotations:
    cert-manager.io/cluster-issuer: selfsigned
spec:
  tls:
    - hosts: [web.lab.local]
      secretName: web-tls
```

For trusted certificates, create your own issuer (ACME needs internet access;
an internal CA works offline). The startup API check Job is turned off because
its image is not part of the offline bundle.

## Argo CD

Argo CD is installed without Dex (SSO). Sign in as `admin` with the generated
password:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n argocd port-forward service/argocd-server 8443:443
```

Then open <https://localhost:8443>. With
`kubernetes_argocd_service_type: NodePort` the UI is reachable on every node
at `kubernetes_argocd_https_node_port` (30943) without a port-forward. Change
the admin password and delete the initial secret afterwards.

## NodePorts

The role checks that the NodePorts of the registry (30500), Headlamp (30443
with a NodePort service), Traefik and Argo CD are between 30000 and 32767 and
unique.

## Offline installation

When an add-on is enabled while the offline bundle is staged
(`--tags offline_stage`), its chart is saved in `manifests/` on the
controllers and the images of its running pods are saved with the other
images. Stage with the same switches you install with. The add-on versions
must be pinned; `latest` is not supported for them.
