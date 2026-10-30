# Build your own images

The role builds container images from Dockerfiles on the registry node and
pushes them to the internal registry at `registry.k8s.local:30500`. Every
node can pull them from there without credentials, online or offline.

Two skeleton images in `files/images` are built by default:

| Image | Base | Use it for |
| --- | --- | --- |
| `ubuntu-base:1.0.0` | `ubuntu:26.04` | Tools, jobs, and debugging; runs as the non-root user `app` (UID 10001) |
| `nginx-static:1.0.0` | `nginx:1.30.6` | A static website from the files in `html/` |

To bring in an image that was built somewhere else, from another registry or
an image file, see [Import your own images](importing-images.md).

## How a build works

For each entry in `kubernetes_registry_builds` the `registry_builds` tag:

1. copies the build context directory from the Ansible machine to
   `/opt/kubernetes-builds/<name>` on the registry node,
2. builds the image with [Buildah](https://buildah.io/), passing
   `REGISTRY=registry.k8s.local:30500` as a build argument,
3. pushes it to `registry.k8s.local:30500/<name>:<tag>`.

An image is rebuilt only when a file in its context changed or the tag is
missing from the registry. Set `kubernetes_registry_builds_force: true` to
rebuild everything.

The skeletons start `FROM ${REGISTRY}/...`, so their base images come from
the internal registry, not from the internet. The base images must be in
`kubernetes_registry_images` (both skeleton bases are there by default), and
the `registry_images` tasks copy them in before the builds run.

## Use a built image

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: tools
spec:
  containers:
    - name: tools
      image: registry.k8s.local:30500/ubuntu-base:1.0.0
```

```sh
kubectl create deployment web --image=registry.k8s.local:30500/nginx-static:1.0.0
```

## Add your own image

1. Copy a skeleton into a directory next to your playbook, for example
   `images/my-app`, and edit its `Dockerfile`. Keep the `ARG REGISTRY` and
   `FROM ${REGISTRY}/...` lines so the base image comes from the internal
   registry.
2. Add the base image to `kubernetes_registry_images` if it is not there yet.
3. List the image in your variables. Setting `kubernetes_registry_builds`
   replaces the default list, so include the skeletons if you still want them:

   ```yaml
   kubernetes_registry_builds:
     - name: my-app
       tag: "1.0.0"
       context: "{{ playbook_dir }}/images/my-app"
       build_args:
         APP_VERSION: "1.0.0"
   ```

4. Build and push:

   ```sh
   ansible-playbook -i examples/inventory.yml examples/site.yml \
     --tags registry_builds --ask-vault-pass
   ```

Raise the tag for every change you want to roll out. The role pushes a
changed context under the same tag too, but nodes that already pulled that tag
keep their cached copy.

## Who can pull the images

The internal registry has no authentication, so every image in it is public
to anyone who can reach the registry NodePort (TCP `30500`) on a node. That
includes the images you build: do not bake passwords, keys, or other secrets
into them; pass those at runtime as Kubernetes Secrets. With the
[host firewall](firewall.md) enabled, `kubernetes_firewall_nodeport_networks`
limits which networks can reach the registry from outside the cluster.

## Offline clusters

Buildah is part of the offline package bundle, and the skeletons only use base
images from the internal registry, so builds work without internet access.
A `RUN apt-get install ...` step needs internet access or a local apt mirror
during the build; the `ubuntu-base` skeleton shows where to add it.

## Turn it off

Set `kubernetes_registry_builds_enabled: false` to skip all builds. Images
that were already pushed stay in the registry.
