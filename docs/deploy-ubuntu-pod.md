# Run an Ubuntu pod

This guide runs a simple Ubuntu pod using the `ubuntu:26.04` image staged in
the cluster's internal registry. It does not require a Cilium `LoadBalancer`
service.

## Before you start

- The Kubernetes cluster is running and `kubectl` can access it.
- The role's `registry_images` tasks have copied `ubuntu:26.04` into the
  internal registry.

## Create the pod

Save this manifest as `ubuntu-pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ubuntu
spec:
  containers:
    - name: ubuntu
      image: registry.k8s.local:30500/ubuntu:26.04
      imagePullPolicy: IfNotPresent
      command: ["sleep", "infinity"]
```

Apply the manifest and wait for the pod to become ready:

```sh
kubectl apply -f ubuntu-pod.yaml
kubectl wait --for=condition=Ready pod/ubuntu --timeout=120s
kubectl get pod ubuntu -o wide
```

The `sleep` command keeps the container running so you can open a shell:

```sh
kubectl exec -it ubuntu -- bash
```

Exit the shell with `exit`. To remove the pod:

```sh
kubectl delete -f ubuntu-pod.yaml
```
