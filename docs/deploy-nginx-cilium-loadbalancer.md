# Deploy NGINX with a Cilium LoadBalancer

This guide deploys the `nginx:stable` image staged in the cluster's local
registry and exposes it through a Kubernetes `Service` of type `LoadBalancer`.
It uses Cilium LB IPAM to allocate a service IP and Cilium L2 Announcements to
advertise that IP on the local network. It is intended for a bare-metal/on-premises
cluster where the nodes and clients share a Layer 2 network.

## Before you start

- The cluster is installed and `kubectl` works with the cluster.
- The role has completed its `registry_images` tasks while internet access was
  available. It stages the installed Cilium chart and all images rendered from
  the active Cilium Helm values on each controller, and copies those images to
  the internal registry.
- Cilium is healthy. The role installs Cilium for pod networking, but its
  current bootstrap configuration sets `kubeProxyReplacement=false` and does
  not enable L2 Announcements. Cilium L2 Announcements require kube-proxy
  replacement.
- Choose one or more unused IP addresses on the same LAN/subnet as the nodes.
  Reserve them outside your DHCP pool and make sure they do not overlap the
  Kubernetes API virtual IP, node addresses, or any other address pool.
- The client accessing NGINX can reach that LAN, and network/host firewalls
  permit ARP and TCP port 80 to the cluster nodes.

L2 Announcements respond to ARP/NDP on the local network; they do not route
the LoadBalancer IP across a router. For routed networks, use a Cilium BGP
Control Plane setup or another suitable load-balancer integration instead.
L2 Announcements are a Cilium beta feature.

## Enable Cilium L2 Announcements

On an existing cluster, changing the Cilium service datapath can interrupt
existing connections. Schedule this change as cluster maintenance and follow
the Cilium upgrade/migration guidance for the installed version. Do not remove
the kube-proxy DaemonSet as an ad hoc step.

The offline assets are stored under `/opt/kubernetes-offline` on each
controller. The role installs Helm and saves the chart archive there. Find the
staged chart version on a control-plane node:

```sh
ls -1 /opt/kubernetes-offline/cilium/
```

Set `API_VIP` to the configured `kubernetes_api_vip`. The API VIP listens on
port `8443` in the role's example configuration. The commands below read the
Cilium and Envoy versions from the running DaemonSets. They use only the local
chart and local registry; they do not access a Helm repository or upstream
image registry.

```sh
export KUBECONFIG=/etc/kubernetes/admin.conf
API_VIP=192.168.1.100
REGISTRY=registry.k8s.local:30500
CILIUM_IMAGE="$(kubectl --namespace kube-system get daemonset cilium \
  --output=jsonpath='{.spec.template.spec.containers[0].image}')"
CILIUM_IMAGE="${CILIUM_IMAGE%%@*}"
CILIUM_VERSION="${CILIUM_IMAGE##*:}"
ENVOY_IMAGE="$(kubectl --namespace kube-system get daemonset cilium-envoy \
  --output=jsonpath='{.spec.template.spec.containers[0].image}')"
ENVOY_IMAGE="${ENVOY_IMAGE%%@*}"
ENVOY_TAG="${ENVOY_IMAGE##*:}"

helm upgrade cilium \
  "/opt/kubernetes-offline/cilium/cilium-${CILIUM_VERSION}.tgz" \
  --namespace kube-system \
  --reuse-values \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost="${API_VIP}" \
  --set k8sServicePort=8443 \
  --set l2announcements.enabled=true \
  --set k8sClientRateLimit.qps=20 \
  --set k8sClientRateLimit.burst=100 \
  --set image.override="${REGISTRY}/cilium/cilium:${CILIUM_VERSION}" \
  --set operator.image.override="${REGISTRY}/cilium/operator-generic:${CILIUM_VERSION}" \
  --set envoy.image.override="${REGISTRY}/cilium/cilium-envoy:${ENVOY_TAG}"
```

The API VIP and port let Cilium reach the Kubernetes API while it configures
service handling. The QPS and burst values are starting values for a small
cluster; monitor Cilium and API-server logs for throttling and tune them for
your cluster. If the Cilium Helm `devices` option is explicitly configured,
make sure it includes the node interface connected to the client LAN.
The Envoy tag changes independently of the Cilium version; the commands above
read it from the running Envoy DaemonSet. The role mirrors every image in the
currently installed chart rendering, including any components enabled in its
Helm values.

The role’s first-time Kubernetes and Cilium bootstrap still downloads OS
packages, the Cilium CLI, and initial cluster images from upstream. The local
registry is inside Kubernetes and cannot bootstrap an empty cluster. Run the
role with internet access and wait for registry image staging to finish before
exporting the VMs. Export all six VMs, including the worker disks holding the
Longhorn registry replicas, as one cluster. After importing, bring up the full
cluster so the replicated registry volume is available; the chart, Helm, and
Cilium CLI are also retained on every controller.

Wait for Cilium to recover and confirm its status before continuing:

```sh
cilium status --wait
kubectl get pods --namespace kube-system --selector k8s-app=cilium
```

## Create an address pool and announcement policy

Save the following as `cilium-nginx-lb.yaml`. Replace the sample range with
unused addresses from your own node LAN. Do not use the documentation example
range as-is unless it is actually free and routed on your network.

```yaml
apiVersion: cilium.io/v2
kind: CiliumLoadBalancerIPPool
metadata:
  name: lan-pool
spec:
  blocks:
    - start: 192.168.1.240
      stop: 192.168.1.249
  serviceSelector:
    matchLabels:
      app: nginx
---
apiVersion: cilium.io/v2alpha1
kind: CiliumL2AnnouncementPolicy
metadata:
  name: nginx-lan
spec:
  serviceSelector:
    matchLabels:
      app: nginx
  loadBalancerIPs: true
```

The policy allows any node eligible to run Cilium to announce selected
services. If you need to restrict eligible nodes or network interfaces, add a
`nodeSelector` and/or `interfaces` that match your cluster; verify the
interface is enabled in Cilium's `devices` setting if that setting is
explicitly configured.

Apply the pool and policy:

```sh
kubectl apply -f cilium-nginx-lb.yaml
kubectl get ciliumloadbalancerippools
kubectl get ciliuml2announcementpolicies
```

## Deploy NGINX

Save this manifest as `nginx.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
        - name: nginx
          image: registry.k8s.local:30500/nginx:stable
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          readinessProbe:
            httpGet:
              path: /
              port: http
          livenessProbe:
            httpGet:
              path: /
              port: http
---
apiVersion: v1
kind: Service
metadata:
  name: nginx
  labels:
    app: nginx
spec:
  type: LoadBalancer
  externalTrafficPolicy: Cluster
  selector:
    app: nginx
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

Apply it and wait for both pods:

```sh
kubectl apply -f nginx.yaml
kubectl rollout status deployment/nginx
kubectl get pods --selector app=nginx -o wide
kubectl get service nginx
```

The service's `EXTERNAL-IP` should be allocated from `lan-pool`. Open
`http://<EXTERNAL-IP>/` from a client on the LAN; the NGINX welcome page should
appear. The service uses `externalTrafficPolicy: Cluster`, which is required
for this example because Cilium L2 Announcements does not support
`externalTrafficPolicy: Local`.

If the IP remains pending, check the pool's conflict/availability status,
confirm the service label is `app: nginx`, and inspect Cilium agent logs and
the L2 policy status:

```sh
kubectl describe ciliumloadbalancerippool lan-pool
kubectl describe ciliuml2announcementpolicy nginx-lan
kubectl get service nginx
kubectl -n kube-system get pods -l k8s-app=cilium
```

To remove the example:

```sh
kubectl delete -f nginx.yaml
kubectl delete -f cilium-nginx-lb.yaml
```

## References

- [Cilium LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/)
- [Cilium L2 Announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
- [Cilium kube-proxy replacement](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/)
