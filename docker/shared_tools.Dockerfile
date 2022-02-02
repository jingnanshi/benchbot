# Note: this Dockerfile is not meant to be used in isolation. It is used to add
# BenchBot's shared tools like ROS packages and addons to an existing Docker
# image

# Ensure our benchbot directory exists
ENV BENCHBOT_DIR="/benchbot"
RUN mkdir -p $BENCHBOT_DIR

# Build a ROS Catkin workspace
ENV ROS_WS_PATH="$BENCHBOT_DIR/ros_ws"
RUN sudo rosdep init && rosdep update && \
    mkdir -p $ROS_WS_PATH/src && source /opt/ros/melodic/setup.bash && \
    pushd $ROS_WS_PATH && catkin_make && source devel/setup.bash && popd 

# Add BenchBot's common ROS packages
ARG BENCHBOT_MSGS_GIT
ARG BENCHBOT_MSGS_HASH
ENV BENCHBOT_MSGS_PATH="$BENCHBOT_DIR/benchbot_msgs"
RUN git clone $BENCHBOT_MSGS_GIT $BENCHBOT_MSGS_PATH && \
    pushd $BENCHBOT_MSGS_PATH && git checkout $BENCHBOT_MSGS_HASH && \
    pip install -r requirements.txt && pushd $ROS_WS_PATH && \
    ln -sv $BENCHBOT_MSGS_PATH src/ && source devel/setup.bash && catkin_make

ARG BENCHBOT_CONTROLLER_GIT
ARG BENCHBOT_CONTROLLER_HASH
ENV BENCHBOT_CONTROLLER_PATH="$BENCHBOT_DIR/benchbot_robot_controller"
RUN git clone $BENCHBOT_CONTROLLER_GIT $BENCHBOT_CONTROLLER_PATH && \
    pushd $BENCHBOT_CONTROLLER_PATH && git checkout $BENCHBOT_CONTROLLER_HASH && \
    pip install -r requirements.txt && pushd $ROS_WS_PATH && \
    pushd src && git clone https://github.com/eric-wieser/ros_numpy.git && popd && \
    ln -sv $BENCHBOT_CONTROLLER_PATH src/ && source devel/setup.bash && catkin_make

# Create a place to mount our add-ons, & install manager dependencies
ARG BENCHBOT_ADDONS_PATH
ENV BENCHBOT_ADDONS_PATH="$BENCHBOT_ADDONS_PATH"
RUN mkdir -p $BENCHBOT_ADDONS_PATH && pip install pyyaml