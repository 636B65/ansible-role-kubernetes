# Import your own images

Use this guide when someone has already built a container image, for example
from a copy of the [skeletons](building-images.md), and you want it in the
internal registry at `registry.k8s.local:30500`. Once it is there, every node
can pull it without credentials.

Pick the method that matches what you have:

| You have | Method |
| --- | --- |
| A Dockerfile and its build files | [Let the role build it](#from-a-dockerfile) |
| An image in another registry (Docker Hub, GHCR, a company registry) | [Let the role copy it](#from-another-registry) |
| An image file (`.tar`) from `docker save`, `podman save`, or a USB stick | [Import the file](#from-an-image-file) |
| The image locally in Docker or Podman, on a machine that can reach the nodes | [Push it directly](#push-from-a-workstation) |

Whichever method you use, pick a repository name in lowercase (for example
`team/my-app`) and a version tag such as `1.0.0`. Avoid `latest`: nodes cache
images by tag and do not notice that a tag changed.

## From a Dockerfile

Give the role the build context and it builds and pushes the image on every
run where something changed:

```yaml
kubernetes_registry_builds:
  - name: team/my-app
    tag: "1.0.0"
    context: "{{ playbook_dir }}/images/my-app"
```

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags registry_builds --ask-vault-pass
```

See [Build your own images](building-images.md) for the details, including
how to keep the default skeletons in the list.

## From another registry

If the image can be pulled from a registry that the registry node can reach,
add it to `kubernetes_registry_images` and run the `registry_images` tag:

```yaml
kubernetes_registry_images:
  # Keep the defaults you still need, for example the skeleton base images:
  - source: docker.io/library/ubuntu:26.04
    destination: ubuntu:26.04
  - source: docker.io/library/nginx:1.30.6
    destination: nginx:1.30.6
  # Your image:
  - source: ghcr.io/example/my-app:1.0.0
    destination: team/my-app:1.0.0
```

```sh
ansible-playbook -i examples/inventory.yml examples/site.yml \
  --tags registry_images --ask-vault-pass
```

The role copies every architecture of the image and skips images whose
destination tag already exists. For a private source registry, log in on the
registry node first: `sudo skopeo login ghcr.io`.

## From an image file

This works without internet access, for example on an offline cluster.

1. **Save the image to a file** on the machine where it was built:

   ```sh
   docker save --output my-app.tar my-app:1.0.0
   # or
   podman save --output my-app.tar localhost/my-app:1.0.0
   ```

2. **Copy the file to the registry node.** That is the first control-plane
   node unless you changed `kubernetes_registry_node`:

   ```sh
   scp my-app.tar kube-cp01:/tmp/
   ```

3. **Push it into the registry** on that node. Skopeo is installed there by
   the role:

   ```sh
   sudo skopeo copy --dest-tls-verify=false \
     docker-archive:/tmp/my-app.tar \
     docker://registry.k8s.local:30500/team/my-app:1.0.0
   ```

   For an OCI archive (`podman save --format oci-archive`), use
   `oci-archive:/tmp/my-app.tar` as the source instead.

4. **Remove the file:** `rm /tmp/my-app.tar`.

The image keeps the CPU architecture it was built for. Build it for the
nodes' architecture (usually `linux/amd64`), for example with
`docker build --platform linux/amd64`.

## Push from a workstation

You can push straight from Docker or Podman when your machine reaches TCP
`30500` on a node. The registry uses plain HTTP, so the client has to allow
that.

1. Map the registry name to any node's address in your `/etc/hosts`:

   ```text
   192.0.2.11 registry.k8s.local
   ```

2. Push the image.

   **Podman:**

   ```sh
   podman tag localhost/my-app:1.0.0 registry.k8s.local:30500/team/my-app:1.0.0
   podman push --tls-verify=false registry.k8s.local:30500/team/my-app:1.0.0
   ```

   **Docker:** add the registry to `/etc/docker/daemon.json`, then restart
   Docker (`sudo systemctl restart docker`):

   ```json
   {
     "insecure-registries": ["registry.k8s.local:30500"]
   }
   ```

   ```sh
   docker tag my-app:1.0.0 registry.k8s.local:30500/team/my-app:1.0.0
   docker push registry.k8s.local:30500/team/my-app:1.0.0
   ```

With the [host firewall](firewall.md) enabled, your network must be in
`kubernetes_firewall_nodeport_networks`.

## Check the import

```sh
curl http://registry.k8s.local:30500/v2/_catalog
curl http://registry.k8s.local:30500/v2/team/my-app/tags/list
```

Run the image on the cluster:

```sh
kubectl run my-app --image=registry.k8s.local:30500/team/my-app:1.0.0
kubectl get pod my-app
```

If the pod is rejected by Pod Security admission, the image or the pod needs
fewer privileges, for example a non-root user like the `ubuntu-base`
skeleton. See [Troubleshooting](troubleshooting.md#pods-are-rejected-by-pod-security-admission).

## Things to keep in mind

- Anyone who can reach the registry can pull every image in it. Do not put
  passwords, keys, or other secrets into images; give them to pods as
  Kubernetes Secrets.
- Images pushed by hand are not tracked by the role. Note them somewhere, or
  prefer the [Dockerfile](#from-a-dockerfile) or
  [registry](#from-another-registry) methods, which keep the list in your
  variables.
- To roll out a change, push a new tag and update your workloads to use it.
