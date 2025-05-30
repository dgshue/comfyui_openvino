################################################################################
# Dockerfile that builds 'dgshue/comfyui-openvino'
# A runtime environment for https://github.com/comfyanonymous/ComfyUI
# Running on XPU (Intel GPU) and OpenVINO.
# Using PyTorch built by Intel.
################################################################################
FROM ubuntu:24.04 AS ov_base

LABEL description="This is the dev image for Intel(R) Distribution of OpenVINO(TM) toolkit on Ubuntu 24.04 LTS"
LABEL vendor="Intel Corporation"

USER root
WORKDIR /

SHELL ["/bin/bash", "-xo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# Creating user openvino and adding it to groups "video" and "users" to use GPU and VPU
RUN sed -ri -e 's@^UMASK[[:space:]]+[[:digit:]]+@UMASK 000@g' /etc/login.defs && \
	grep -E "^UMASK" /etc/login.defs && useradd -ms /bin/bash -G video,users openvino && \
    chown openvino -R /home/openvino

RUN mkdir /opt/intel

ENV INTEL_OPENVINO_DIR /opt/intel/openvino

COPY --from=base /opt/intel/ /opt/intel/

WORKDIR /thirdparty

ARG INSTALL_SOURCES="no"

ARG DEPS="tzdata \
          curl"

ARG LGPL_DEPS="g++ \
               gcc \
               libc6-dev"
ARG INSTALL_PACKAGES="-c=python -c=core -c=dev"


# hadolint ignore=DL3008
RUN apt-get update && apt-get upgrade -y && \
    dpkg --get-selections | grep -v deinstall | awk '{print $1}' > base_packages.txt  && \
    apt-get install -y --no-install-recommends ${DEPS} && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get reinstall -y ca-certificates && rm -rf /var/lib/apt/lists/* && update-ca-certificates

# hadolint ignore=DL3008, SC2012
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3-venv ${LGPL_DEPS} && \
    ${INTEL_OPENVINO_DIR}/install_dependencies/install_openvino_dependencies.sh -y ${INSTALL_PACKAGES} && \
    if [ "$INSTALL_SOURCES" = "yes" ]; then \
      sed -Ei 's/# deb-src /deb-src /' /etc/apt/sources.list && \
      apt-get update && \
	  dpkg --get-selections | grep -v deinstall | awk '{print $1}' > all_packages.txt && \
	  grep -v -f base_packages.txt all_packages.txt | while read line; do \
	  package=$(echo $line); \
	  name=(${package//:/ }); \
      grep -l GPL /usr/share/doc/${name[0]}/copyright; \
      exit_status=$?; \
	  if [ $exit_status -eq 0 ]; then \
	    apt-get source -q --download-only $package;  \
	  fi \
      done && \
      echo "Download source for $(ls | wc -l) third-party packages: $(du -sh)"; fi && \
    rm /usr/lib/python3.*/lib-dynload/readline.cpython-3*-gnu.so && rm -rf /var/lib/apt/lists/*

RUN curl -L -O  https://github.com/oneapi-src/oneTBB/releases/download/v2021.9.0/oneapi-tbb-2021.9.0-lin.tgz && \
    tar -xzf  oneapi-tbb-2021.9.0-lin.tgz&& \
    cp oneapi-tbb-2021.9.0/lib/intel64/gcc4.8/libtbb.so* /opt/intel/openvino/runtime/lib/intel64/ && \
    rm -Rf oneapi-tbb-2021.9.0*

WORKDIR ${INTEL_OPENVINO_DIR}/licensing
RUN if [ "$INSTALL_SOURCES" = "no" ]; then \
        echo "This image doesn't contain source for 3d party components under LGPL/GPL licenses. They are stored in https://storage.openvinotoolkit.org/repositories/openvino/ci_dependencies/container_gpl_sources/." > DockerImage_readme.txt ; \
    fi


ENV InferenceEngine_DIR=/opt/intel/openvino/runtime/cmake
ENV LD_LIBRARY_PATH=/opt/intel/openvino/runtime/3rdparty/hddl/lib:/opt/intel/openvino/runtime/3rdparty/tbb/lib:/opt/intel/openvino/runtime/lib/intel64:/opt/intel/openvino/tools/compile_tool:/opt/intel/openvino/extras/opencv/lib
ENV OpenCV_DIR=/opt/intel/openvino/extras/opencv/cmake
ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV PYTHONPATH=/opt/intel/openvino/python:/opt/intel/openvino/python/python3:/opt/intel/openvino/extras/opencv/python
ENV TBB_DIR=/opt/intel/openvino/runtime/3rdparty/tbb/cmake
ENV ngraph_DIR=/opt/intel/openvino/runtime/cmake
ENV OpenVINO_DIR=/opt/intel/openvino/runtime/cmake
ENV INTEL_OPENVINO_DIR=/opt/intel/openvino
ENV OV_TOKENIZER_PREBUILD_EXTENSION_PATH=/opt/intel/openvino/runtime/lib/intel64/libopenvino_tokenizers.so
ENV PKG_CONFIG_PATH=/opt/intel/openvino/runtime/lib/intel64/pkgconfig

# setup python

ENV VIRTUAL_ENV=/opt/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH=$VIRTUAL_ENV/bin:$PATH

# hadolint ignore=DL3013
RUN python3 -m pip install  --no-cache-dir --upgrade pip

# dev package
WORKDIR ${INTEL_OPENVINO_DIR}
ARG OPENVINO_WHEELS_VERSION=2025.1.0
ARG OPENVINO_WHEELS_URL
# hadolint ignore=SC2102
RUN apt-get update && apt-get install -y --no-install-recommends cmake make git && rm -rf /var/lib/apt/lists/* && \
    python3 -m pip install --no-cache-dir openvino=="${OPENVINO_WHEELS_VERSION}" && \
    python3 -m pip install --no-cache-dir openvino-tokenizers=="${OPENVINO_WHEELS_VERSION}" && \
    python3 -m pip install --no-cache-dir openvino-genai=="${OPENVINO_WHEELS_VERSION}"

WORKDIR ${INTEL_OPENVINO_DIR}/licensing
# Please use `third-party-programs-docker-dev.txt` short path to 3d party file if you use the Dockerfile directly from docker_ci/dockerfiles repo folder
COPY third-party-programs-docker-dev.txt ${INTEL_OPENVINO_DIR}/licensing
COPY third-party-programs-docker-runtime.txt ${INTEL_OPENVINO_DIR}/licensing

COPY --from=opencv /opt/repo/opencv/build/install ${INTEL_OPENVINO_DIR}/extras/opencv
RUN  echo "export OpenCV_DIR=${INTEL_OPENVINO_DIR}/extras/opencv/cmake" | tee -a "${INTEL_OPENVINO_DIR}/extras/opencv/setupvars.sh"; \
     echo "export LD_LIBRARY_PATH=${INTEL_OPENVINO_DIR}/extras/opencv/lib:\$LD_LIBRARY_PATH" | tee -a "${INTEL_OPENVINO_DIR}/extras/opencv/setupvars.sh"

# Install dependencies for OV::RemoteTensor
RUN apt-get update && apt-get install -y --no-install-recommends opencl-headers ocl-icd-opencl-dev && rm -rf /var/lib/apt/lists/* && rm -rf /tmp/*

# build samples into ${INTEL_OPENVINO_DIR}/samples/cpp/samples_bin
WORKDIR ${INTEL_OPENVINO_DIR}/samples/cpp
RUN ./build_samples.sh -b /tmp/build -i ${INTEL_OPENVINO_DIR}/samples/cpp/samples_bin && \
    rm -Rf /tmp/build

# add Model API package
# hadolint ignore=DL3013
RUN git clone https://github.com/openvinotoolkit/open_model_zoo && \
    sed -i '/opencv-python/d' open_model_zoo/demos/common/python/requirements.txt && \
    pip3 --no-cache-dir install open_model_zoo/demos/common/python/ && \
    rm -Rf open_model_zoo && \
    python3 -c "from model_zoo import model_api"

# Intel® NPU drivers (optional)
RUN apt-get update && \
    apt-get install -y --no-install-recommends libtbb12 && \
    apt-get clean
RUN mkdir /tmp/npu_deps && cd /tmp/npu_deps && \
    curl -L -O https://github.com/intel/linux-npu-driver/releases/download/v1.17.0/intel-driver-compiler-npu_1.17.0.20250508-14912879441_ubuntu24.04_amd64.deb && \
    curl -L -O https://github.com/intel/linux-npu-driver/releases/download/v1.17.0/intel-fw-npu_1.17.0.20250508-14912879441_ubuntu24.04_amd64.deb && \
    curl -L -O https://github.com/intel/linux-npu-driver/releases/download/v1.17.0/intel-level-zero-npu_1.17.0.20250508-14912879441_ubuntu24.04_amd64.deb && \
    dpkg -i ./*.deb && rm -Rf /tmp/npu_deps

# for GPU
RUN apt-get update && \
    apt-get install -y --no-install-recommends ocl-icd-libopencl1 && \
    apt-get clean ; \
    rm -rf /var/lib/apt/lists/* && rm -rf /tmp/*
# hadolint ignore=DL3003
RUN mkdir /tmp/gpu_deps && cd /tmp/gpu_deps && \
    curl -L -O https://github.com/intel/intel-graphics-compiler/releases/download/v2.11.7/intel-igc-core-2_2.11.7+19146_amd64.deb && \
    curl -L -O https://github.com/intel/intel-graphics-compiler/releases/download/v2.11.7/intel-igc-opencl-2_2.11.7+19146_amd64.deb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/intel-ocloc-dbgsym_25.18.33578.6-0_amd64.ddeb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/intel-ocloc_25.18.33578.6-0_amd64.deb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/intel-opencl-icd-dbgsym_25.18.33578.6-0_amd64.ddeb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/intel-opencl-icd_25.18.33578.6-0_amd64.deb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/libigdgmm12_22.7.0_amd64.deb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/libze-intel-gpu1-dbgsym_25.18.33578.6-0_amd64.ddeb && \
    curl -L -O https://github.com/intel/compute-runtime/releases/download/25.18.33578.6/libze-intel-gpu1_25.18.33578.6-0_amd64.deb && \
    curl -L -O https://github.com/oneapi-src/level-zero/releases/download/v1.21.9/level-zero_1.21.9+u24.04_amd64.deb && \
    dpkg -i ./*.deb && rm -Rf /tmp/gpu_deps


# Post-installation cleanup and setting up OpenVINO environment variables
ENV LIBVA_DRIVER_NAME=iHD
ENV GST_VAAPI_ALL_DRIVERS=1
ENV LIBVA_DRIVERS_PATH=/usr/lib/x86_64-linux-gnu/dri

RUN apt-get update && \
    apt-get autoremove -y gfortran && \
    rm -rf /var/lib/apt/lists/*

USER openvino
WORKDIR ${INTEL_OPENVINO_DIR}
ENV DEBIAN_FRONTEND=noninteractive

CMD ["/bin/bash"]

# Setup custom layers below
FROM ov_base as comfyui

USER root
RUN set -eu

# See http://bugs.python.org/issue19846

RUN if [ -f /etc/apt/apt.conf.d/proxy.conf ]; then rm /etc/apt/apt.conf.d/proxy.conf; fi && \
    if [ ! -z ${HTTP_PROXY} ]; then echo "Acquire::http::Proxy \"${HTTP_PROXY}\";" >> /etc/apt/apt.conf.d/proxy.conf; fi && \
    if [ ! -z ${HTTPS_PROXY} ]; then echo "Acquire::https::Proxy \"${HTTPS_PROXY}\";" >> /etc/apt/apt.conf.d/proxy.conf; fi
RUN apt-get update -y && \
    apt-get full-upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
build-essential \
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
