# k3s + NVIDIA container runtime.
#
# k3d nodes are containers. `gpuRequest: all` passes the device through, but
# k3s also needs containerd wired to the nvidia runtime, which rancher/k3s
# does not ship.
#
# Build:  make k3s-cuda-image
# Verify: docker run --rm --gpus all nullnode/k3s-cuda:v1.31.2-k3s1 nvidia-smi
ARG K3S_TAG=v1.31.2-k3s1
FROM rancher/k3s:${K3S_TAG} AS k3s
FROM nvidia/cuda:12.6.2-base-ubuntu24.04

ARG NVIDIA_CONTAINER_TOOLKIT_VERSION=1.17.0

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# curl and gnupg are transient build deps used only to add the NVIDIA repo and
# removed with the apt lists below; pinning them breaks on every base refresh.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates=20230311 curl gnupg \
 && curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
      | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg \
 && curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
      | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
      > /etc/apt/sources.list.d/nvidia-container-toolkit.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      "nvidia-container-toolkit-base=${NVIDIA_CONTAINER_TOOLKIT_VERSION}-1" \
      "libnvidia-container-tools=${NVIDIA_CONTAINER_TOOLKIT_VERSION}-1" \
 && rm -rf /var/lib/apt/lists/*

# k3s expects an exact layout; copy it wholesale.
COPY --from=k3s / /tmp/
COPY --from=k3s /bin /tmp/bin/
RUN cp -a /tmp/* / && rm -rf /tmp/*

# k3s detects the runtime at startup and registers RuntimeClass "nvidia".
RUN mkdir -p /etc/nvidia-container-runtime \
 && echo 'accept-nvidia-visible-devices-as-volume-mounts = true' >> /etc/nvidia-container-runtime/config.toml

VOLUME /var/lib/kubelet
VOLUME /var/lib/rancher/k3s
VOLUME /var/lib/cni
VOLUME /var/log

ENV PATH="$PATH:/bin/aux"
ENTRYPOINT ["/bin/k3s"]
CMD ["agent"]
