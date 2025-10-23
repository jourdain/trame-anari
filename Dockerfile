#############################################
# Stage 1: VisRTX and ANARI build
#############################################
FROM nvidia/cuda:12.2.0-devel-ubuntu22.04 AS visrtxbuilder

ARG ANARI_VERSION=0.14.1
ARG ANARI_PREFIX=/opt/anari
ARG VISRTX_PREFIX=/opt/visrtx
ARG VISRTX_VERSION=0.12.0

# Install dev tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    git cmake ninja-build build-essential pkg-config \
    curl ca-certificates wget unzip xz-utils \
    python3 python3-pip \
    libegl1 \
    libegl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

# Build ANARI
RUN mkdir -p ${ANARI_PREFIX} \
    && git clone --branch v${ANARI_VERSION} https://github.com/KhronosGroup/ANARI-SDK.git ${ANARI_PREFIX}/src \
    && cmake -S ${ANARI_PREFIX}/src/ -B ${ANARI_PREFIX}/build -G Ninja \
        -DCMAKE_INSTALL_PREFIX=${ANARI_PREFIX}/install \
        -DBUILD_VIEWER:BOOL=OFF \
        -DBUILD_TESTING:BOOL=OFF \
        -DBUILD_REMOTE_DEVICE:BOOL=OFF \
    && cmake --build ${ANARI_PREFIX}/build \
    && cmake --install ${ANARI_PREFIX}/build

# Build VisRTX
ENV CUDA_HOME=/usr/local/cuda-12.2
ENV CUDAToolkit_ROOT=${CUDA_HOME}
ENV PATH=${CUDA_HOME}/bin:${PATH}

# Make CUDA stubs available for the build
# The real libcuda.so.1 lives on the host driver and gets injected only at runtime via --gpus all. 
# During build, you should link against the CUDA stub library that ships with the toolkit.
ARG LIBCUDA_STUBS=${CUDA_HOME}/lib64/stubs
ENV LD_LIBRARY_PATH=${LIBCUDA_STUBS}:${CUDA_HOME}/lib64:${LD_LIBRARY_PATH}

RUN ln -s ${CUDA_HOME}/lib64/stubs/libcuda.so ${CUDA_HOME}/lib64/stubs/libcuda.so.1
RUN ln -s ${CUDA_HOME}/lib64/stubs/libnvidia-ml.so ${CUDA_HOME}/lib64/stubs/libnvidia-ml.so.1

RUN mkdir -p ${VISRTX_PREFIX} \
    && git clone --branch v${VISRTX_VERSION} https://github.com/NVIDIA/VisRTX.git ${VISRTX_PREFIX}/src \
    && cmake \
        -S ${VISRTX_PREFIX}/src \
        -B ${VISRTX_PREFIX}/build \
        -G Ninja \
        -DCMAKE_INSTALL_PREFIX=${VISRTX_PREFIX}/install \
        -Danari_DIR:PATH=${ANARI_PREFIX}/install/lib/cmake/anari-${ANARI_VERSION} \
        -DCUDAToolkit_ROOT=${CUDAToolkit_ROOT} \
        -DCMAKE_CUDA_COMPILER=${CUDA_HOME}/bin/nvcc \
        -DCMAKE_EXE_LINKER_FLAGS="-L${LIBCUDA_STUBS}" \
        -DCMAKE_SHARED_LINKER_FLAGS="-L${LIBCUDA_STUBS}" \
    && cmake --build ${VISRTX_PREFIX}/build \
    && cmake --install ${VISRTX_PREFIX}/build

RUN sed -i '/\/usr\/local\/cuda-12\.2\/lib64\/stubs/d' /etc/environment || true
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

#############################################
# Stage 2: Pan3D/VTK environment
#############################################
FROM kitware/trame:uv-12.2.0-cuda-runtime-ubuntu22.04

# Install dev tools
RUN apt-get update \
    && apt-get install -y \
        libxrender1 \
        build-essential \
        cmake \
        ninja-build \
        git \
        curl \
        nvidia-cuda-toolkit-gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy VisRTX and ANARI from previous stage
ARG ANARI_PREFIX=/opt/anari
ARG VISRTX_PREFIX=/opt/visrtx

COPY --from=visrtxbuilder ${ANARI_PREFIX} ${ANARI_PREFIX}
COPY --from=visrtxbuilder ${VISRTX_PREFIX} ${VISRTX_PREFIX}

# Setup trame app configuration for pan3d
RUN mkdir -p /deploy/setup \
    && echo "pan3d[all]>=1.2" > /deploy/setup/requirements.txt \
    && echo "trame:" > /deploy/setup/apps.yml \
    && echo "  www_modules:" >> /deploy/setup/apps.yml \
    && echo "  - pan3d.ui.css.base" >> /deploy/setup/apps.yml \
    && echo "  - pan3d.ui.css.preview" >> /deploy/setup/apps.yml \
    && echo "  - pan3d.ui.css.vtk_view" >> /deploy/setup/apps.yml \
    && echo "  cmd:" >> /deploy/setup/apps.yml \
    && echo "  - xr-globe" >> /deploy/setup/apps.yml \
    && echo "  - --host" >> /deploy/setup/apps.yml \
    && echo "  - \${host}" >> /deploy/setup/apps.yml \
    && echo "  - --port" >> /deploy/setup/apps.yml \
    && echo "  - \${port}" >> /deploy/setup/apps.yml \
    && echo "  - --authKey" >> /deploy/setup/apps.yml \
    && echo "  - \${secret}" >> /deploy/setup/apps.yml \
    && echo "  - --server" >> /deploy/setup/apps.yml \
    && echo "  - --anari" >> /deploy/setup/apps.yml \
    && chown trame-user:trame-user -R /deploy/setup

# Trame setup
ENV TRAME_PYTHON=3.12
RUN /opt/trame/entrypoint.sh build

# Build VTK
RUN mkdir -p /opt/vtk/src \
    && cd /opt/vtk/src \
    && curl -L https://vtk.org/files/release/9.5/VTK-9.5.2.tar.gz | tar --strip-components=1 -xzv \
    && cmake \
        -S /opt/vtk/src \
        -B /opt/vtk/build \
        -G Ninja \
        -D CMAKE_INSTALL_PREFIX:PATH=/opt/vtk/install \
        -D CMAKE_BUILD_TYPE:STRING=Release \
        -D VTK_LEGACY_REMOVE=ON \
        -D VTK_BUILD_TESTING=OFF \
        -D VTK_ALL_NEW_OBJECT_FACTORY=ON \
        -D VTK_GROUP_ENABLE_Imaging:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_MPI:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Qt:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Rendering:STRING=DONT_WANT \
        -D VTK_GROUP_ENABLE_Web:STRING=YES \
        -D VTK_ENABLE_WRAPPING=ON \
        -D VTK_WRAP_PYTHON=ON \
        -D VTK_WRAP_SERIALIZATION=ON \
        -D VTK_PYTHON_VERSION=3 \
        -D VTK_WHEEL_BUILD=ON \
        -D VTK_MODULE_ENABLE_VTK_CommonCore:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersFlowPaths:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersHybrid:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersModeling:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersPython:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersVerdict:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_GeovisCore:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_IOEnSight:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_IOGeometry:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_IOLegacy:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_IOPLY:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_IOXML:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_InteractionStyle:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingAnnotation:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingFreeType:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingOpenGL2:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingVolumeOpenGL2:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_libxml2:STRING=YES \
        -D VTK_ENABLE_REMOTE_MODULES:BOOL=OFF \
        -D VTK_MODULE_ENABLE_VTK_jsoncpp:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_ViewsCore:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_exodusII:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_octree:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_InfovisLayout:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_ioss:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingVtkJS:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_DomainsChemistry:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_SerializationManager:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_RenderingAnari:STRING=YES \
        -D VTK_MODULE_ENABLE_VTK_FiltersTexture:STRING=YES \
        -D anari_DIR:PATH=/opt/anari/install/lib/cmake/anari-0.14.1 \
        -D Python3_EXECUTABLE=/deploy/server/venv/bin/python \
    && cmake --build /opt/vtk/build \
    && cmake --install /opt/vtk/build

# Update venv - install custom vtk build
RUN . /deploy/server/venv/bin/activate \
    && uv pip uninstall vtk \
    && uv pip install setuptools \
    && cd /opt/vtk/build \
    && python setup.py bdist_wheel \
    && uv pip install /opt/vtk/build/dist/vtk-*.whl 

# Anari runtime env
# ENV ANARI_LIBRARY=helide
# ENV ANARI_LIBRARY=visgl
ENV ANARI_LIBRARY=visrtx
ENV LD_LIBRARY_PATH=${VISRTX_PREFIX}/install/lib/:${ANARI_PREFIX}/install/lib/:$LD_LIBRARY_PATH