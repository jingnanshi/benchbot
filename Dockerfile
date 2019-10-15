#TODO:
# Change COPY directives to ADD (does extracting in same step)

# Use an official Python runtime as a parent image
FROM ubuntu:bionic

# Declare any expected ARGS from the host system
ARG TZ
ARG NVIDIA_DRIVER_VERSION
ARG CUDA_VERSION
ARG CUDA_VERSION_SHORT
ARG ISAAC_SDK_TGZ
ARG ISAAC_SIM_TGZ
ARG ISAAC_SIM_GITDEPS_TGZ
RUN echo "Enforcing that all required arguments are provided..." && \
    test -n "$TZ" && test -n "$NVIDIA_DRIVER_VERSION" && test -n "$CUDA_VERSION" && \
    test -n "$CUDA_VERSION_SHORT" && test -n "$ISAAC_SDK_TGZ" && \
    test -n "$ISAAC_SIM_TGZ" && test -n "$ISAAC_SIM_GITDEPS_TGZ"

# Setup a user (as Unreal for whatever wacko reason does not allow us to build
# as a root user... thanks for that...), working directory, & use bash as the
# shell
SHELL ["/bin/bash", "-c"]
RUN apt update && apt -yq install sudo wget gnupg2 software-properties-common && \
    rm -rf /var/apt/lists/*
RUN useradd --create-home --password "" benchbot && passwd -d benchbot && \
    usermod -aG sudo benchbot
WORKDIR /home/benchbot

# Configure some basics to get us up & running
RUN echo "$TZ" > /etc/timezone && \
    ln -s /usr/share/zoneinfo/"$TZ" /etc/localtime && \
    apt update && apt -y install tzdata && rm -rf /var/apt/lists/*

# Install ROS Melodic
RUN echo "deb http://packages.ros.org/ros/ubuntu bionic main" > /etc/apt/sources.list.d/ros-latest.list && \
    apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654 && \
    apt update && apt install -y ros-melodic-desktop-full && rm -rf /var/apt/lists/*

# Install Isaac (using local copies of licensed libraries)
ENV ISAAC_SDK_PATH /home/benchbot/isaac_sdk
ADD ${ISAAC_SDK_TGZ} isaac_sdk

# Install the Nvidia driver & Vulkan
# TODO what about people who have installed a driver not in the default Ubuntu repositories... hmmm...
RUN wget -qO - http://packages.lunarg.com/lunarg-signing-key-pub.asc | apt-key add - && \
    wget -qO /etc/apt/sources.list.d/lunarg-vulkan-bionic.list http://packages.lunarg.com/vulkan/lunarg-vulkan-bionic.list && \
    apt update && DEBIAN_FRONTEND=noninteractive apt install -yq vulkan-sdk \
    "nvidia-driver-$(echo "${NVIDIA_DRIVER_VERSION}" | sed 's/\(^[0-9]*\).*/\1/')=${NVIDIA_DRIVER_VERSION}*" && \
    rm -rf /var/apt/lists/*

# Install CUDA
# TODO full CUDA install seems excessive, can this be trimmed down?
RUN wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/cuda-ubuntu1804.pin && \
    mv -v cuda-ubuntu1804.pin /etc/apt/preferences.d/cuda-repository-pin-600
RUN apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub && \
    add-apt-repository "deb http://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/ /" && \
    apt update && apt install -y "cuda-${CUDA_VERSION_SHORT}=${CUDA_VERSION}" && rm -rf /var/apt/lists/* && \
    ln -sv lib /usr/local/cuda-"$(echo ${CUDA_VERSION_SHORT} | tr - .)"/targets/x86_64-linux/lib64 && \
    ln -sv /usr/local/cuda-"$(echo ${CUDA_VERSION_SHORT} | tr - .)"/targets/x86_64-linux /usr/local/cuda

# Install Unreal Engine (& Isaac Unreal Engine Sim)
# TODO make IsaacSimProject <build_number> configurable...
ADD ${ISAAC_SIM_TGZ} isaac_sim
ADD ${ISAAC_SIM_GITDEPS_TGZ} isaac_sim/Engine/Build

# TODO move these up maybe?...
ENV NVIDIA_VISIBLE_DEVICES all
ENV NVIDIA_DRIVER_CAPABILITIES compute,utility,graphics

# Install any remaining software
RUN apt update && apt install -y git python-catkin-tools python-pip \
    python-rosinstall-generator python-wstool

# Perform all user setup steps
RUN chown -R benchbot:benchbot *
USER benchbot
RUN mkdir -p ros_ws/src && source /opt/ros/melodic/setup.bash && \
    pushd ros_ws && catkin_make && source devel/setup.bash && popd && \
    pushd "$ISAAC_SDK_PATH" && \
    engine/build/scripts/install_dependencies.sh && bazel build ... && \
    rm -rf /var/apt/lists/* && popd && \
    rm isaac_sim/Engine/Build/IsaacSimProject_1.2_Core.gitdeps.xml

# TODO we CANNOT UNDER ANY CIRCUMSTANCES release this software with this line in
# it (it manually ignores a licence). I have added this line here because I was
# stuck in a situation where every time I added stuff to the DockerFile, the 
# annoying manual license accept prompt meant the entire Isaac UnrealEngine SIM
# had to rebuilt from scratch.... It was hindering development way too much...
RUN cd isaac_sim && \
    sed -i 's/\[ -f.*1\.2\.gitdeps\.xml \];/\[ 1 == 2 \] \&\& \0/' Setup.sh && \
    ./Setup.sh &&  ./GenerateProjectFiles.sh && ./GenerateTestRobotPaths.sh && \
    make && make IsaacSimProjectEditor

# Install our benchbot software
# TODO DO THIS PROPERLY WITHOUT MY SSH KEY!!!!
ADD --chown=benchbot:benchbot id_rsa .ssh/id_rsa
RUN touch .ssh/known_hosts && ssh-keyscan bitbucket.org >> .ssh/known_hosts && \
    git clone --branch develop git@bitbucket.org:acrv/benchbot_simulator && \
    pushd benchbot_simulator && git checkout be27953 && popd && rm -rf .ssh && \
    pushd benchbot_simulator && ./.isaac_patches/apply_patches && \
    source ../ros_ws/devel/setup.bash && ./build build //apps/benchbot_simulator && popd

# TODO when we get to environments we have to build all the shaders somehow & cache them...
# Command below appears to build everything then segfaults & fails... need to figure out how
# to only build for the requested environment
# ./Engine/Binaries/Linux/UE4Editor IsaacSimProject Hospital -run=DerivedDataCache -fill 

