FROM alpine:3.8

RUN apk update && \
    apk add git && \
    apk add curl

WORKDIR /workspace
 
RUN chgrp -R 0 /workspace && \
    chmod -R g=u /workspace


USER 1001

ENTRYPOINT ["tail", "-f", "/dev/null"]

# Image already updated into QUAY: 
# Build and push:
# podman build -t git-utils -f  workshop-environment/gitea/Dockerfile
# podman tag git-utils quay.io/skoussou/git-utils:1.0.0
# podman login quay.io
# podm/an push quay.io/skoussou/git-utils:1.0.0
# Run:
# podman run  --name git -d git-utils
# podman exec -it git sh
