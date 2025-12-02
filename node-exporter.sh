#!/bin/bash

# -----------------------------
# Node Exporter setup script
# Flexible for WSL2 or Linux
# -----------------------------

read -p "Enter the port for Node Exporter (default: 9100): " PORT
PORT=${PORT:-9100}

# Detect WSL2 vs Linux
if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null ; then
    echo "Running in WSL2 environment"
    ROOTFS="/host"
    IGNORED_MOUNTS="^/(sys|proc|dev|run|mnt/host/wsl|tmp)"
else
    echo "Running in standard Linux environment"
    ROOTFS="/"
    IGNORED_MOUNTS="^/(sys|proc|dev|run|tmp)"
fi

# Stop existing container if exists
docker rm -f node_exporter &> /dev/null

# Run node-exporter container
docker run -d \
  --name node_exporter \
  -p "$PORT:$PORT" \
  --pid="host" \
  -v "/:$ROOTFS:ro,rslave" \
  prom/node-exporter:v1.8.2 \
  --path.rootfs=$ROOTFS \
  --web.listen-address=":$PORT" \
  --collector.filesystem.ignored-mount-points="$IGNORED_MOUNTS" \
  --collector.textfile.directory="/var/lib/node_exporter/textfile_collector"

echo "Node Exporter is running on port $PORT"
echo "Ignored mount points regex: $IGNORED_MOUNTS"



