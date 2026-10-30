# Skeleton image: NGINX serving the static files in html/.
# The role builds it on the registry node and pushes it to
# registry.k8s.local:30500/nginx-static:<tag>. Replace html/ with your site,
# or copy this directory to start another image.
ARG REGISTRY=registry.k8s.local:30500
FROM ${REGISTRY}/nginx:1.30.6

COPY html/ /usr/share/nginx/html/

EXPOSE 80
