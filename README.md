# WitMotion WT901C ROS 2 workspace (Docker)

ROS 2 Humble workspace for the WitMotion **WT901C-TTL** IMU on an NVIDIA Jetson, connected
directly to the 40-pin header UART (`/dev/ttyTHS1`). The driver is
[ElettraSciComp/witmotion_IMU_ros](https://github.com/ElettraSciComp/witmotion_IMU_ros)
(`ros2` branch), included as a git submodule. The container starts on boot.

```
.
├── src/witmotion_ros/   # driver (submodule, ros2 branch)
├── config/wt901.yml     # driver parameters, mounted into the container
├── Dockerfile
├── docker-compose.yml
└── entrypoint.sh
```

## Hardware

The WT901C-TTL uses **5 V logic**. The Jetson UART is **3.3 V only**, so put a level shifter
(e.g. BSS138 module) between them, or use a voltage divider on the sensor TX line.

| Sensor | Level shifter | Jetson 40-pin |
|--------|---------------|---------------|
| VCC    | HV            | Pin 2 (5 V)   |
| —      | LV            | Pin 1 (3.3 V) |
| GND    | GND           | Pin 6 (GND)   |
| TX     | HV1 ↔ LV1     | Pin 10 (RX)   |
| RX     | HV2 ↔ LV2     | Pin 8 (TX)    |

Default sensor settings: **9600 baud, 8N1**.

## Host setup (once)

```bash
# Free the UART from the serial console
sudo systemctl disable --now nvgetty

# Start Docker (and therefore this container) on boot
sudo systemctl enable docker
```

## Install and run

```bash
git clone --recursive <this-repo-url> ~/witmotion-docker
cd ~/witmotion-docker
docker compose up -d --build
docker compose logs -f
```

If you cloned without `--recursive`:

```bash
git submodule update --init --recursive
```

The container uses `restart: unless-stopped`, so it comes back after reboots and if the node
exits. Use `docker compose down` to stop it for good.

## Topics

| Topic           | Type                          | Notes |
|-----------------|-------------------------------|-------|
| `/imu`          | `sensor_msgs/Imu`             | Accel (m/s², includes gravity), gyro (rad/s), orientation |
| `/magnetometer` | `sensor_msgs/MagneticField`   | |
| `/temperature`  | `sensor_msgs/Temperature`     | |
| `/orientation`  | `geometry_msgs/Quaternion`    | Only if quaternion output is enabled on the sensor (see below) |

Check from the host:

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp   # match the container
ros2 topic echo /imu
ros2 topic hz /imu
```

Or from inside the container:

```bash
docker exec -it witmotion /entrypoint.sh bash
```

At rest, `linear_acceleration` reads about 9.81 m/s² on the vertical axis. That's gravity, and
it's normal.

## Configuration

Edit `config/wt901.yml`, then:

```bash
docker compose restart
```

No rebuild is needed. Key settings:

| Parameter                              | Value     | Notes |
|----------------------------------------|-----------|-------|
| `port`                                 | `ttyTHS1` | No `/dev/` prefix |
| `baud_rate`                            | `9600`    | Must match the sensor |
| `imu_publisher.use_native_orientation` | `false`   | `true` only if quaternion output is enabled, otherwise `/imu` never publishes |

### Enabling quaternion output (optional)

By default the WT901C sends acceleration, gyro, angle and magnetometer packets, but not
quaternions (`0x59`). Without quaternions, `/imu` still has orientation (the driver converts it
from the Euler angles), but `/orientation` is silent. To enable them, stop the container and run:

```bash
docker compose stop
python3 - <<'PY'
import serial, time
ser = serial.Serial("/dev/ttyTHS1", 9600, timeout=1)
for c in ([0xFF,0xAA,0x69,0x88,0xB5],   # unlock
          [0xFF,0xAA,0x02,0x1E,0x02],   # accel, gyro, angle, mag + quaternion
          [0xFF,0xAA,0x00,0x00,0x00]):  # save
    ser.write(bytes(c)); time.sleep(0.2)
PY
```

Check these bytes against the WT901C manual first, or set the same option in WitMotion's PC
software. Then set `use_native_orientation: true` if you want, and `docker compose start`.

At 9600 baud, keep the sensor output rate at 10 Hz or lower. Raise the baud rate on the sensor
and in the config for faster rates.

## Building without Docker

The repo root is a normal ROS 2 workspace:

```bash
sudo apt install libqt5serialport5-dev
source /opt/ros/humble/setup.bash
colcon build
source install/setup.bash
ros2 run witmotion_ros witmotion_ros_node --ros-args --params-file config/wt901.yml
```

Only one process can open the serial port, so stop the container first.

## Updating the driver

```bash
cd src/witmotion_ros
git pull origin ros2
cd ../..
git submodule update --init --recursive
git commit -am "Bump witmotion_ros"
docker compose up -d --build
```

## Troubleshooting

| Symptom | Likely cause |
|---------|--------------|
| Node exits immediately / restarts in a loop | No data: wrong `port` or `baud_rate`, wiring, or `nvgetty` still running |
| Garbage or all `0x00` bytes on the port | Baud mismatch, missing level shifter, or no common ground |
| `/imu` never publishes | `use_native_orientation: true` without quaternion output enabled |
| `/orientation` silent | Quaternion output not enabled on the sensor (see above) |
| Topics not visible on the host | Different `RMW_IMPLEMENTATION` or `ROS_DOMAIN_ID` between host and container |
| `sequence size exceeds remaining buffer` | DDS (middleware) message, not from the driver. Check that host and container use the same RMW |
| Accel x ≈ 2.7 m/s² while "flat" | Sensor is tilted, or the accelerometer needs calibrating (WitMotion PC software) |

To check the raw stream (container stopped), every packet starts with `0x55`:

```bash
python3 -c "import serial; print(serial.Serial('/dev/ttyTHS1',9600,timeout=2).read(44).hex(' '))"
```
