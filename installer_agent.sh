\#!/bin/bash

set -e

echo "================================================================="
echo "  INSTALLER Agent: Node Exporter, Process Exporter Prometheus,  Promtail & Loki"
echo "================================================================="
sleep 1

# Detect Architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
  ARCH_DL="amd64"
elif [[ "$ARCH" == "aarch64" ]]; then
  ARCH_DL="arm64"
else
  echo "Unsupported architecture: $ARCH"
  exit 1
fi

INSTALL_DIR="/opt/monitoring"
mkdir -p $INSTALL_DIR

###################################
# NODE EXPORTER INSTALLATION
###################################
install_node_exporter() {
  echo "[1/4] Installing Node Exporter..."

  cd $INSTALL_DIR
  VERSION="1.8.1"
  FILE="node_exporter-${VERSION}.linux-${ARCH_DL}.tar.gz"

  wget --show-progress https://github.com/prometheus/node_exporter/releases/download/v${VERSION}/${FILE}
  tar -xzf $FILE
  mv node_exporter-${VERSION}.linux-${ARCH_DL}/node_exporter /usr/local/bin/
  rm -rf node_exporter-${VERSION}.linux-${ARCH_DL} $FILE


  echo "Create user node_exporter..."
  useradd --no-create-home --shell /sbin/nologin node_exporter 2>/dev/null || true

  echo "Create node_exporter.service ..."
  cat <<EOF >/etc/systemd/system/node_exporter.service
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

  systemctl daemon-reload
  systemctl enable --now node_exporter

  echo "Node Exporter installed & running on port 9100"
}

install_process_exporter(){
  echo "[2/5] Installing Process Exporter...."
  cd $INSTALL_DIR

  VERSION="0.8.7"
  FILE="process-exporter-${VERSION}.linux-${ARCH_DL}.tar.gz"
  echo $FILE
  wget --show-progress https://github.com/ncabatoff/process-exporter/releases/download/v${VERSION}/${FILE}
  tar xzf ${FILE}
  sudo mv process-exporter-${VERSION}.linux-${ARCH_DL}/process-exporter /usr/local/bin/
  sudo chmod +x /usr/local/bin/process-exporter

  cat <<EOF >/etc/process-exporter.yml
process_names:
  - name: "{{.Comm}}"
    cmdline:
      - ".+"
  - name: "nginx"
    cmdline:
      - "nginx"
  - name: "mysql"
    cmdline:
      - "mysqld"


EOF

  cat <<EOF >/etc/systemd/system/process_exporter.service
[Unit]
Description=Prometheus Process Exporter
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/process-exporter --config.path=/etc/process-exporter.yml

[Install]
WantedBy=multi-user.target

EOF

  systemctl daemon-reload
  systemctl enable --now process_exporter
  systemctl status process_exporter
  echo "Succes Create process_exporter.service"

  echo "Test endpoint Process Exporter..."
  curl http://localhost:9256/metrics
  echo "Success install Process Exporter, run on PORT: 9256.."

}
###################################
# LOKI INSTALLATION
###################################
install_loki() {
  echo "[3/5] Installing Loki..."

  cd $INSTALL_DIR
  VERSION="3.1.1"
  FILE="loki-linux-${ARCH_DL}.zip"

  wget --show-progress https://github.com/grafana/loki/releases/download/v${VERSION}/${FILE}
  unzip --show-progress $FILE
  mv loki-linux-${ARCH_DL} /usr/local/bin/loki
  rm $FILE

  mkdir -p /etc/loki /var/lib/loki
  useradd --no-create-home --shell /sbin/nologin loki 2>/dev/null || true

  cat <<EOF >/etc/loki/loki-config.yml
auth_enabled: false
server:
  http_listen_port: 3100

ingester:
  wal:
    enabled: true
    dir: /var/lib/loki/wal
  max_transfer_retries: 0

schema_config:
  configs:
    - from: 2020-10-24
      store: boltdb-shipper
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /var/lib/loki/index
    shared_store: filesystem
    cache_location: /var/lib/loki/cache
  filesystem:
    directory: /var/lib/loki/chunks

limits_config:
  allow_structured_metadata: false

table_manager:
  retention_deletes_enabled: true
  retention_period: 168h
EOF

  cat <<EOF >/etc/systemd/system/loki.service
[Unit]
Description=Loki Log Aggregation System
After=network.target

[Service]
Type=simple
User=loki
ExecStart=/usr/local/bin/loki --config.file=/etc/loki/loki-config.yml

[Install]
WantedBy=multi-user.target
EOF

  chown -R loki:loki /etc/loki /var/lib/loki

  systemctl daemon-reload
  systemctl enable --now loki

  echo "Loki installed & running on port 3100"
}

###################################
# PROMTAIL INSTALLATION
###################################
install_promtail() {
  echo "[4/5] Installing Promtail..."

  cd $INSTALL_DIR
  VERSION="3.1.1"
  FILE="promtail-linux-${ARCH_DL}.zip"

  wget --show-progress https://github.com/grafana/loki/releases/download/v${VERSION}/${FILE}
  unzip --show-progress $FILE
  mv promtail-linux-${ARCH_DL} /usr/local/bin/promtail
  rm $FILE

  mkdir -p /etc/promtail
  useradd --no-create-home --shell /sbin/nologin promtail 2>/dev/null || true

  HOSTNAME=$(hostname)

  cat <<EOF >/etc/promtail/promtail-config.yml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/log/positions.yaml

clients:
  - url: http://localhost:3100/loki/api/v1/push

scrape_configs:
  - job_name: system
    static_configs:
      - targets:
          - localhost
        labels:
          job: varlogs
          host: "${HOSTNAME}"
          __path__: /var/log/*log
EOF

  cat <<EOF >/etc/systemd/system/promtail.service
[Unit]
Description=Promtail Log Collector
After=network.target

[Service]
Type=simple
User=promtail
ExecStart=/usr/local/bin/promtail --config.file=/etc/promtail/promtail-config.yml

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now promtail

  echo "Promtail installed & sending logs to Loki"
}

##############################
#PROMETHEUS INSTALLER
#############################

install_prometheus(){
  echo "[5/5] Installer Prometheus..."

  cd $INSTALL_DIR

  VERSION="2.52.0"
  FILE="prometheus-${VERSION}.linux-${ARCH_DL}.tar.gz"

  wget --show-progress https://github.com/prometheus/prometheus/releases/download/v${VERSION}/${FILE}
  tar -xzf $FILE

  mv prometheus-${VERSION}.linux-${ARCH_DL} prometheus
  rm $FILE

  mv prometheus/prometheus /usr/local/bin/
  mv prometheus/promtool /usr/local/bin/

  mkdir -p /etc/prometheus /var/lib/prometheus

  mv prometheus/consoles /etc/prometheus/
  mv prometheus/console_libraries /etc/prometheus/

  cat <<EOF >/etc/prometheus/prometheus.yml

global:
   scrape_interval: 15s
 

scrape_configs:
   - job_name: prometheus
     static_configs:
       - targets: ["localhost:9090"]
   - job_name: node_exporter
     static_configs:
       - targets: ["localhost:9100"]
EOF

  useradd --no-create-home --shell /sbin/nologin prometheus 2>/dev/null || true
  chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

  cat <<EOF >/etc/systemd/system/prometheus.service
[Unit]
Description=Prometheus
After=network.target

[Service]
Type=simple
User=prometheus
ExecStart=/usr/local/bin/prometheus \
   --config.file=/etc/prometheus/prometheus.yml \
   --storage.tsdb.path=/var/lib/prometheus \
   --web.console.templates=/etc/prometheus/consoles \
   --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now prometheus

  echo "Prometheus Installed & running on port 9090"
}
###################################
# MENU INSTALLER
###################################

echo ""
echo "Pilih agent yang ingin di-install:"
echo "1) Install Node Exporter"
echo "2) Install Process Exporter"
echo "3) Install Loki"
echo "4) Install Promtail"
echo "5) Install Prometheus"
echo "6) Install Semua"
echo "7) Exit"
echo ""

read -p "Masukkan pilihan [1-7]: " CHOICE

case $CHOICE in
  1) install_node_exporter ;;
  2) install_process_exporter ;;
  3) install_loki ;;
  4) install_promtail ;;
  5) install_prometheus ;;
  6) install_node_exporter; install_process_exporter; install_loki; install_promtail; install_prometheus ;;
  7) exit 0 ;;
  *) echo "Input tidak valid!"; exit 1 ;;
esac

echo "==============================================="
echo " INSTALASI SELESAI!"
echo "==============================================="
