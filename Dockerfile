################################################################################
# Dockerfile that builds 'dgshue/comfyui-openvino'
# A runtime environment for https://github.com/comfyanonymous/ComfyUI
# Running on XPU (Intel GPU) and OpenVINO.
# Using PyTorch built by Intel.
################################################################################

FROM openvino/ubuntu24_runtime

USER root
RUN set -eu

# See http://bugs.python.org/issue19846

RUN if [ -f /etc/apt/apt.conf.d/proxy.conf ]; then rm /etc/apt/apt.conf.d/proxy.conf; fi && \
    if [ ! -z ${HTTP_PROXY} ]; then echo "Acquire::http::Proxy \"${HTTP_PROXY}\";" >> /etc/apt/apt.conf.d/proxy.conf; fi && \
    if [ ! -z ${HTTPS_PROXY} ]; then echo "Acquire::https::Proxy \"${HTTPS_PROXY}\";" >> /etc/apt/apt.conf.d/proxy.conf; fi
RUN apt-get update -y && \
    apt-get full-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    google-perftools \
    openssh-server \
    net-tools
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    if [ -f /etc/apt/apt.conf.d/proxy.conf ]; then rm /etc/apt/apt.conf.d/proxy.conf; fi
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 100

WORKDIR /root

ARG IPEX_VERSION=2.7.0
ARG TORCHCCL_VERSION=2.7.0
ARG PYTORCH_VERSION=2.7.0
ARG TORCHAUDIO_VERSION=2.7.0
ARG TORCHVISION_VERSION=0.22.0
RUN python -m venv venv && \
    . ./venv/bin/activate && \
    python -m pip --no-cache-dir install --upgrade \
    pip \
    setuptools \
    psutil && \
    python -m pip install --no-cache-dir \
    torch==${PYTORCH_VERSION}+cpu torchvision==${TORCHVISION_VERSION}+cpu torchaudio==${TORCHAUDIO_VERSION}+cpu --index-url https://download.pytorch.org/whl/cpu && \
    python -m pip install --no-cache-dir \
    intel_extension_for_pytorch==${IPEX_VERSION} oneccl_bind_pt==${TORCHCCL_VERSION} --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/cpu/us/ && \
    python -m pip install intel-openmp && \
    python -m pip cache purge


# Cache left by upstream
RUN rm -rf /root/.cache/pip

# Python and tools
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update \
    && apt-get install -y \
fish \
fd-find \
vim \
less \
aria2 \
git \
ninja-build \
make \
cmake \
python3-pybind11 \
libgl1 \
#libgl-mesa0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python Packages
ARG PIP_ROOT_USER_ACTION='ignore'

RUN --mount=type=cache,target=/root/.cache/pip \
    pip list \
    && pip install \
        --upgrade pip wheel setuptools

# Deps for ComfyUI & custom nodes
COPY builder-scripts/.  /builder-scripts/

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        -r /builder-scripts/pak3.txt

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        -r /builder-scripts/pak5.txt

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        -r /builder-scripts/pak7.txt

# Make sure the deps fit the needs for ComfyUI & Manager
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
        -r https://github.com/comfyanonymous/ComfyUI/raw/refs/heads/master/requirements.txt \
        -r https://github.com/ltdrdata/ComfyUI-Manager/raw/refs/heads/main/requirements.txt \
        -r https://raw.githubusercontent.com/openvino-dev-samples/comfyui_openvino/refs/heads/main/requirements.txt

# Make sure using the right version of Intel packages
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
intel-extension-for-pytorch==2.7.10+xpu \
    --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/

RUN --mount=type=cache,target=/root/.cache/pip \
    pip install \
oneccl_bind_pt==2.7.0+xpu \
    --extra-index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/us/

# Install the ComfyUI CLI
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install comfy-cli

################################################################################

RUN df -h \
    && du -ah /root \
    && find /root/ -mindepth 1 -delete

COPY runner-scripts/.  /runner-scripts/

USER root
VOLUME /root
WORKDIR /root
EXPOSE 8188
ENV CLI_ARGS="--cpu --use-pytorch-cross-attention"
CMD ["bash","/runner-scripts/entrypoint.sh"]
