# Host firewall

The role can install an nftables input filter on every node. It is
**disabled by default** (`kubernetes_firewall_enabled: false`), because a
wrong network list can cut off your SSH access. Review this page and test
the settings on one cluster before you enable it everywhere.

## What it allows

The rules live in their own table, `inet kubernetes_host_firewall`, loaded by
`kubernetes-firewall.service` from `/etc/kubernetes-firewall.nft`. They never
flush or touch the rules that kube-proxy and Cilium manage. Only incoming
traffic to the node itself is filtered; forwarded pod traffic is not.

| Source | Allowed |
| --- | --- |
| Any | Established connections, loopback, ICMP/ICMPv6, DHCP replies |
| Cluster nodes (every `ansible_host` in the inventory) | Everything: kubelet, etcd, Cilium VXLAN and health checks, Longhorn, VRRP, the registry NodePort |
| Pod network (`kubernetes_pod_network_cidr`) and Cilium interfaces | Everything, for kubelet probes, metrics, and webhooks |
| `kubernetes_firewall_admin_networks` | SSH (`kubernetes_firewall_ssh_port`), and the HAProxy statistics page on controllers |
| `kubernetes_firewall_api_networks` | Kubernetes API on the virtual IP (`8443`) and on each controller (`6443`) |
| `kubernetes_firewall_nodeport_networks` | NodePort services, TCP and UDP `30000-32767` |

Everything else is dropped. Add rules to the input chain with
`kubernetes_firewall_extra_input_rules`, for example to allow HTTP from a
reverse proxy:

```yaml
kubernetes_firewall_extra_input_rules:
  - ip saddr 192.0.2.50 tcp dport { 80, 443 } accept
```

## Enable it

```yaml
kubernetes_firewall_enabled: true
kubernetes_firewall_admin_networks:
  - 192.0.2.0/24        # the network you run Ansible and SSH from
kubernetes_firewall_api_networks:
  - 192.0.2.0/24
kubernetes_firewall_nodeport_networks:
  - 192.0.2.0/24
```

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags firewall --ask-vault-pass
```

The rules are validated with `nft -c` before they are installed, and every
reload replaces the table atomically. Existing SSH sessions stay open because
established connections are accepted.

Setting `kubernetes_firewall_enabled` back to `false` and running the
`firewall` tag stops the service and removes the rules.

## Limitations

- The network lists accept IPv4 only. IPv6 traffic other than ICMPv6 is
  dropped; add IPv6 rules through `kubernetes_firewall_extra_input_rules` if
  you need them.
- Do not enable Debian's `nftables.service` with its default
  `/etc/nftables.conf`: that file starts with `flush ruleset`, which removes
  this table and the kube-proxy and Cilium rules when it starts.
- When nodes are added or removed, run the `firewall` tag (or the full site
  playbook) on all nodes so every node trusts the current node list.
- With Cilium kube-proxy replacement and L2 Announcements (see the NGINX
  guide), LoadBalancer traffic is handled by eBPF before nftables sees it.
  Restrict LoadBalancer services with Kubernetes network policies or
  `loadBalancerSourceRanges` instead.

## Recover from a lockout

From the node's console:

```sh
sudo systemctl stop kubernetes-firewall.service
```

This deletes the table. Fix the network lists and run the `firewall` tag
again.
