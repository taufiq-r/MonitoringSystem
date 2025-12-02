# Panduan Konfigurasi Monitoring

Dokumentasi cepat untuk mengubah konfigurasi sistem monitoring Prometheus + Alertmanager + Discord.

---

## File Konfigurasi Utama

| File | Fungsi | Perlu Restart? |
|------|--------|----------------|
| `prometheus/prometheus.yml` | Main Prometheus config | Reload (curl POST /-/reload) |
| `prometheus/alert_rules.yml` | Alert rules | Reload (curl POST /-/reload) |
| `alertmanager/alertmanager.yml` | Alert routing & receivers | Restart ✓ |
| `docker-compose.yml` | Docker services | Restart ✓ |
| `incident-webhook/app.py` | Webhook handler | Rebuild ✓ |

---

## Skenario Perubahan Konfigurasi

### 1. Menambah Server Baru untuk Monitoring

**Target:** Tambah server `192.168.50.114:9100` (node_exporter)

**File:** `prometheus/prometheus.yml`

```yaml
scrape_configs:
  - job_name: Monitored Server
    static_configs:
      - targets: 
        - "192.168.50.113:9100"
        - "192.168.50.112:9100"
        - "192.168.50.114:9100"  # ← Tambah baris ini
```

**Reload:**
```bash
curl -X POST http://192.168.50.108:9090/-/reload
```

**Verify:**
- Prometheus UI → Targets → Lihat `192.168.50.114:9100` muncul
- Status: UP dalam 1-2 menit

---

### 2. Mengubah Threshold Alert (CPU > 85% instead of 90%)

**File:** `prometheus/alert_rules.yml`

```yaml
- alert: HighCPUUsage
  expr: 100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85  # ← Ubah dari 90 ke 85
  for: 5m
```

**Reload:**
```bash
docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml
curl -X POST http://192.168.50.108:9090/-/reload
```

**Verify:** Prometheus UI → Alerts → Cek threshold berubah

---

### 3. Mengubah VLAN Monitoring

**Skenario:** Tambah VLAN 30 gateway `192.168.30.1`

**File:** `prometheus/prometheus.yml`

```yaml
- job_name: "blackbox"
  ...
  static_configs:
    - targets:
        - "https://seamolec.org/"
        - "https://maganghub.kemnaker.go.id"
        - "https://siapkerja.kemnaker.go.id/app/home"
      labels:
        vlan: "internet"
    - targets:
        - "192.168.10.1"
      labels:
        vlan: "vlan10"
    - targets:
        - "192.168.20.1"
      labels:
        vlan: "vlan20"
    - targets:
        - "192.168.30.1"  # ← Tambah blok baru
      labels:
        vlan: "vlan30"
```

**Reload:**
```bash
curl -X POST http://192.168.50.108:9090/-/reload
```

**Alert akan otomatis terdeteksi per VLAN.**

---

### 4. Mengubah Discord Webhook

**Skenario:** Ganti webhook URL karena yang lama expired

**File:** `docker-compose.yml`

```yaml
incident-webhook:
  ...
  environment:
    - DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/NEW_ID/NEW_TOKEN  # ← Ganti URL
```

**Restart:**
```bash
docker compose up -d --build incident-webhook
```

**Verify:**
```bash
curl http://192.168.50.108:5000/  # Seharusnya 200 OK
```

---

### 5. Tambah Alert Severity (Warning vs Critical)

**Skenario:** Tambah alert WARNING untuk high memory (>80%) dan CRITICAL untuk >95%

**File:** `prometheus/alert_rules.yml`

```yaml
- alert: HighMemoryUsageWarning
  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
  for: 5m
  labels:
    severity: warning  # ← Warning level
  annotations:
    summary: "High memory usage warning on {{ $labels.instance }}"
    description: "Memory > 80% on {{ $labels.instance }}"

- alert: HighMemoryUsageCritical
  expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 95
  for: 2m
  labels:
    severity: critical  # ← Critical level
  annotations:
    summary: "Critical memory usage on {{ $labels.instance }}"
    description: "Memory > 95% on {{ $labels.instance }}"
```

**Update Alertmanager** (`alertmanager/alertmanager.yml`):

```yaml
routes:
  - matchers:
      - severity="critical"
    receiver: webhook_incident
    continue: true
  
  - matchers:
      - severity="warning"
    receiver: team-X-mails  # ← Kirim warning ke email saja
    continue: true
```

**Restart Alertmanager:**
```bash
docker compose restart alertmanager
```

---

### 6. Menambah Receiver Email (selain Discord)

**File:** `alertmanager/alertmanager.yml`

Ubah SMTP config:
```yaml
global:
  smtp_smarthost: 'smtp.gmail.com:587'  # ← Change SMTP server
  smtp_from: 'alerts@example.com'
  smtp_auth_username: 'alerts@example.com'
  smtp_auth_password: 'app_password'  # ← Use app-specific password
```

Tambah receiver:
```yaml
receivers:
  - name: 'email_critical'
    email_configs:
      - to: 'ops-team@example.com'
        headers:
          Subject: '[CRITICAL] {{ .GroupLabels.alertname }}'
```

Tambah route:
```yaml
routes:
  - matchers:
      - severity="critical"
    receiver: email_critical
    continue: true
```

**Restart:**
```bash
docker compose restart alertmanager
```

---

### 7. Mengubah Alert Timing

**Skenario:** Reduce alert delay — cek lebih sering, tapi tunggu lebih singkat sebelum firing

**File:** `prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s       # Tetap sama
  evaluation_interval: 10s   # ← Ubah dari 15s ke 10s (evaluate rule lebih sering)
```

**File:** `prometheus/alert_rules.yml`

```yaml
- alert: NetworkDown
  expr: probe_success{job="blackbox"} == 0
  for: 2m  # ← Ubah dari 5m ke 2m (alert faster)
```

**File:** `alertmanager/alertmanager.yml`

```yaml
route:
  group_wait: 10s    # ← Ubah dari 30s ke 10s (send faster)
  group_interval: 2m # ← Ubah dari 5m ke 2m
```

**Reload + Restart:**
```bash
curl -X POST http://192.168.50.108:9090/-/reload
docker compose restart alertmanager
```

---

### 8. Disable Alert Sementara (untuk maintenance)

**Skenario:** Server sedang di-maintenance, jangan alert

**Option A: Inline comment di rule**
```yaml
- alert: InstanceDown
  # expr: up{job="Monitored Server"} == 0  # ← Comment out untuk disable
  expr: up{job="Monitored Server"} == 0 and on() absent(ALERTS{alertname="MaintenanceMode"})
```

**Option B: Inhibition rule**
```yaml
inhibit_rules:
  - source_matchers: [alertname="Maintenance"]
    target_matchers: [instance=~"192.168.50.113.*"]
    equal: []
```

**Reload:**
```bash
curl -X POST http://192.168.50.108:9090/-/reload
```

---

### 9. Cek Perubahan Mana yang Butuh Reload vs Restart

```
prometheus.yml          → Reload (curl POST /-/reload) ✓ Tanpa downtime
alert_rules.yml         → Reload (curl POST /-/reload) ✓ Tanpa downtime
alertmanager.yml        → Restart (docker compose restart) ✗ ~5 detik downtime
docker-compose.yml      → Restart (docker compose up -d) ✗ Service down
incident-webhook app.py → Rebuild (docker compose up -d --build) ✗ ~10 detik downtime
```

---

## Troubleshooting Perubahan Konfigurasi

### Sintaks error di YAML

```bash
# Test syntax sebelum reload
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
```

### Alert tidak firing setelah perubahan

```bash
# 1. Cek rule valid
docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml

# 2. Reload
curl -X POST http://192.168.50.108:9090/-/reload

# 3. Cek Prometheus UI Alerts tab
# 4. Test expression di Graph
```

### Discord tidak terima alert setelah perubahan

```bash
# 1. Cek webhook URL valid
docker compose exec incident-webhook env | grep DISCORD

# 2. Test webhook
curl -X POST -H "Content-Type: application/json" \
  -d '{"content":"Test"}' \
  https://discord.com/api/webhooks/YOUR_URL

# 3. Cek logs
docker compose logs -f incident-webhook
```

---

## Backup & Restore Config

### Backup konfigurasi
```bash
tar -czf monitoring-config-backup-$(date +%Y%m%d).tar.gz \
  prometheus/ alertmanager/ incident-webhook/ docker-compose.yml
```

### Restore dari backup
```bash
tar -xzf monitoring-config-backup-20251201.tar.gz
docker compose restart
```

---

## Quick Reference

### Reload Prometheus config
```bash
curl -X POST http://192.168.50.108:9090/-/reload
```

### Restart Alertmanager
```bash
docker compose restart alertmanager
```

### Restart all services
```bash
docker compose restart
```

### Rebuild incident-webhook
```bash
docker compose up -d --build incident-webhook
```

### View live logs
```bash
docker compose logs -f
```

---

**Last Updated:** 2025-12-01

Selalu test konfigurasi di dev/staging sebelum apply ke production!
