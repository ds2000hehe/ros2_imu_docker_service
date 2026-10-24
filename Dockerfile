FROM ros:humble-ros-base

SHELL ["/bin/bash", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends \
        qtbase5-dev \
        libqt5serialport5-dev \
        libboost-dev \
        ros-humble-tf2-geometry-msgs \
        ros-humble-nav-msgs \
        ros-humble-rmw-cyclonedds-cpp \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /ros2_ws
# This repo is the workspace; src/witmotion_ros is a submodule (clone with --recursive)
COPY src src
RUN test -n "$(ls src/witmotion_ros/witmotion-uart-qt)" \
    || (echo "witmotion-uart-qt is empty: run 'git submodule update --init --recursive'" && exit 1)

RUN source /opt/ros/humble/setup.bash \
    && colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ros2", "run", "witmotion_ros", "witmotion_ros_node", "--ros-args", "--params-file", "/config/wt901.yml"]
