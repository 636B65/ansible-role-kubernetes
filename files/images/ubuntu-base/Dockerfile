# Skeleton image: a non-root Ubuntu base for your own tools and jobs.
# The role builds it on the registry node and pushes it to
# registry.k8s.local:30500/ubuntu-base:<tag>. Copy this directory, rename it,
# and add it to kubernetes_registry_builds to create your own image.
ARG REGISTRY=registry.k8s.local:30500
FROM ${REGISTRY}/ubuntu:26.04

# Installing packages needs internet access or a local apt mirror during the
# build. Uncomment and extend when you have one:
# RUN apt-get update \
#     && apt-get install --yes --no-install-recommends ca-certificates curl \
#     && rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid app --create-home --shell /bin/bash app

USER 10001:10001
WORKDIR /home/app

CMD ["sleep", "infinity"]
