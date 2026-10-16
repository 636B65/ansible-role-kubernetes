# Deploy NGINX with a Cilium LoadBalancer

This guide deploys the public `nginx:stable` container image and exposes it
through a Kubernetes `Service` of type `LoadBalancer`. It uses Cilium LB IPAM
to allocate a service IP and Cilium L2 Announcements to advertise that IP on
the local network. It is intended for a bare-metal/on-premises cluster where
the nodes and clients share a Layer 2 network.

## Before you start

- The cluster is installed and `kubectl` works with the cluster.
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

On a control-plane node, use Helm (the role installs the Cilium CLI but does
not install Helm) to check the installed chart version:

```sh
helm list --namespace kube-system
```

Use the installed Cilium chart version in the upgrade command so this change
does not unintentionally upgrade Cilium. Replace `<installed-version>` with
the version shown in the `CHART` column (without the `cilium-` prefix), and
replace `<API-VIP>` with the `kubernetes_api_vip` configured for this cluster.
The API VIP listens on port `8443` in the role's example configuration.

```sh
helm repo add cilium https://helm.cilium.io/
helm repo update

helm upgrade cilium cilium/cilium \
  --version <installed-version> \
  --namespace kube-system \
  --reuse-values \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=<API-VIP> \
  --set k8sServicePort=8443 \
  --set l2announcements.enabled=true \
  --set k8sClientRateLimit.qps=20 \
  --set k8sClientRateLimit.burst=100
```

The API VIP and port let Cilium reach the Kubernetes API while it configures
service handling. The QPS and burst values are starting values for a small
cluster; monitor Cilium and API-server logs for throttling and tune them for
your cluster. If the Cilium Helm `devices` option is explicitly configured,
make sure it includes the node interface connected to the client LAN.

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
          image: nginx:stable
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
