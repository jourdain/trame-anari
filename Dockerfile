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

# Build ANARI
RUN mkdir -p /opt/anari/ \
    && git clone https://github.com/KhronosGroup/ANARI-SDK.git /opt/anari/src \
    && cmake -S /opt/anari/src/ -B /opt/anari/build -G Ninja -DCMAKE_INSTALL_PREFIX=/opt/anari/install \
    && cmake --build /opt/anari/build \
    && cmake --install /opt/anari/build

# Build VisRTX
RUN mkdir -p /opt/VisRTX/ \
    && git clone https://github.com/NVIDIA/VisRTX.git /opt/VisRTX/src \
    && cmake -S /opt/anari/src -B /opt/VisRTX/build -G Ninja -DCMAKE_INSTALL_PREFIX=/opt/VisRTX/install \
    && cmake --build /opt/VisRTX/build \
    && cmake --install /opt/VisRTX/build

RUN mkdir -p /deploy/setup \
    && echo "pan3d[all]" > /deploy/setup/requirements.txt \
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
        -D anari_DIR=/opt/VisRTX/install/lib/cmake/anari-0.15.0 \
        -D Python3_EXECUTABLE=/deploy/server/venv/bin/python \
    && cmake --build /opt/vtk/build \
    && cmake --install /opt/vtk/build

# Patched version of pan3d - to test
COPY --chown=trame-user:trame-user app /app

# Update venv (vtk+pan3d)
RUN . /deploy/server/venv/bin/activate \
    && uv pip uninstall vtk \
    && uv pip install setuptools \
    && cd /opt/vtk/build \
    && python setup.py bdist_wheel \
    && uv pip install /opt/vtk/build/dist/vtk-*.whl \
    && uv pip install /app

# Anari runtime env
ENV ANARI_LIBRARY=vizrtx
ENV LD_LIBRARY_PATH=/opt/VisRTX/install/lib/