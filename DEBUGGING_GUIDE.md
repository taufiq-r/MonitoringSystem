# Panduan Debugging Sistem Monitoring

Panduan ini membantu Anda troubleshoot masalah pada sistem alerting dan monitoring Prometheus + Alertmanager + Discord.

---

## 1. Cek Status Service

### Lihat semua container yang running
```bash
docker compose ps
```

**Expected output:** Semua service UP
```
NAME                STATUS
prometheus          Up X minutes
alertmanager        Up X minutes
incident-webhook    Up X minutes
grafana             Up X minutes
blackbox-exporter   Up X minutes
```

### Jika ada yang DOWN, restart semua
```bash
docker compose down
docker compose up -d --build
```

---

## 2. Debugging Prometheus

### Cek logs Prometheus
```bash
docker compose logs prometheus
```

### Error yang sering:
- **"No such file or directory prometheus.yml"** → Mounting tidak bekerja
  ```bash
  # Solusi: Pastikan mount path di docker-compose.yml benar
  docker compose exec prometheus ls -la /etc/prometheus/
  ```

- **"alert_rules.yml: no such file"** → alert_rules.yml tidak ada
  ```bash
  # Solusi: Buat file
  ls -la prometheus/alert_rules.yml
  # Jika tidak ada, buat dari template yang ada
  ```

### Verifikasi konfigurasi Prometheus valid
```bash
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
```

### Verifikasi alert rules valid
```bash
docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml
```

### Akses Prometheus UI
```
http://<IP-server>:9090
```
- Tab **Alerts** → lihat rule status (PENDING/FIRING)
- Tab **Targets** → lihat scrape status per job
- Tab **Graph** → test metrics query

### Debug metric collection
```bash
# Cek apakah metrics dari target diterima
curl http://localhost:9090/api/v1/query?query=up
```

---

## 3. Debugging Alert Rules

### Cek apakah alert rule terbaca
Buka Prometheus UI → Alerts tab → lihat apakah rules muncul

### Test expression langsung di Prometheus
1. Buka http://192.168.50.108:9090
2. Search bar → Ketik expression, misal:
   ```
   probe_success{job="blackbox"}
   ```
3. Execute dan lihat hasilnya

### Debug InstanceDown alert
```bash
# Query apakah metric up tersedia
curl http://192.168.50.108:9090/api/v1/query?query=up{job="Monitored%20Server"}
```

**Expected response:** metric dengan value 1 atau 0

Jika tidak ada metrik, berarti:
- Server target tidak bisa di-reach
- Nama job salah di rule
- Port node_exporter salah

---

## 4. Debugging Alertmanager

### Cek logs Alertmanager
```bash
docker compose logs alertmanager
```

### Akses Alertmanager UI
```
http://<IP-server>:9093
```

- Tab **Alerts** → lihat alert yang currently firing
- Tab **Status** → config file info

### Verifikasi config Alertmanager valid
```bash
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml
```

### Error yang sering:
- **"lookup incident-webhook on 127.0.0.11:53: no such host"** → Docker DNS resolve gagal
  ```bash
  # Solusi: Cek apakah incident-webhook container running
  docker compose ps incident-webhook
  
  # Jika running, reload Alertmanager
  docker compose restart alertmanager
  ```

- **"connection refused"** → Webhook service tidak listening
  ```bash
  # Solusi: Cek incident-webhook logs
  docker compose logs incident-webhook
  docker compose ps incident-webhook
  ```

### Trigger alert manual untuk testing
```bash
# Kirim alert test ke Alertmanager
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {"alertname": "TestAlert", "severity": "critical"},
    "annotations": {"summary": "Test alert", "description": "This is a test"},
    "generatorURL": "http://localhost:9090/graph"
  }]'
```

Cek UI Alertmanager apakah alert muncul.

---

## 5. Debugging Webhook Incident

### Cek logs webhook
```bash
docker compose logs -f incident-webhook
```

### Test webhook endpoint
```bash
# Test GET (health check)
curl http://192.168.50.108:5000/
# Expected: {"status":"ok","service":"incident-webhook"}

# Test POST (alert)
curl -X POST -H "Content-Type: application/json" \
  -d '{"alerts":[{"labels":{"alertname":"TestAlert","severity":"critical","instance":"test-host"},"annotations":{"summary":"Test alert","description":"Test description"},"status":"firing","startsAt":"2025-12-01T00:00:00Z"}]}' \
  http://192.168.50.108:5000/alert
# Expected: {"status":"ok"}
```

### Debug Discord webhook
```bash
# Cek apakah DISCORD_WEBHOOK_URL benar
docker compose exec incident-webhook env | grep DISCORD

# Test Discord webhook langsung (replace dengan URL Anda)
curl -X POST -H "Content-Type: application/json" \
  -d '{"content":"Test dari webhook"}' \
  https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN
```

### Error yang sering:
- **"Failed to send to Discord: 401"** → Token/webhook URL salah
  ```bash
  # Solusi: Update DISCORD_WEBHOOK_URL di docker-compose.yml dengan URL yang benar
  docker compose up -d --build incident-webhook
  ```

- **"Webhook rejected"** → Webhook URL sudah expired atau didelete
  ```bash
  # Solusi: Generate webhook baru di Discord dan update di docker-compose.yml
  ```

### Cek alert logs yang tersimpan
```bash
docker compose exec incident-webhook cat /var/log/alerts/alerts.log
```

---

## 6. Debugging Blackbox Exporter

### Cek logs blackbox
```bash
docker compose logs blackbox_exporter
```

### Test probe langsung
```bash
# Test HTTP probe
curl "http://localhost:9115/probe?target=https://seamolec.org/&module=http_2xx"
```

### Debug VLAN probe
- Pastikan di `prometheus.yml` blackbox targets punya label `vlan`
- Contoh:
```yaml
- targets:
  - "192.168.10.1"
  labels:
    vlan: "vlan10"
```

---

## 7. Debugging Prometheus + Alertmanager Integration

### Cek apakah Prometheus bisa reach Alertmanager
```bash
docker compose exec prometheus curl -v http://alertmanager:9093/-/healthy
```

**Expected:** HTTP 200

### Cek konfigurasi alerting di Prometheus
```bash
curl http://192.168.50.108:9090/api/v1/status
# Lihat field "alertingRules" dan "alertmanagers"
```

### Simulasi alert firing hingga Discord

**Step 1:** Cek Prometheus metrics
```bash
curl http://192.168.50.108:9090/api/v1/query?query=probe_success{job="blackbox"}
```

**Step 2:** Trigger rule (misal: buat target unreachable)
```bash
# Stop sementara salah satu blackbox target atau down-kan server
# Tunggu rule evaluate (biasanya 5-15 menit tergantung `for:` di rule)
```

**Step 3:** Cek Prometheus Alerts UI
```
http://192.168.50.108:9090/alerts
# Status berubah jadi FIRING?
```

**Step 4:** Cek Alertmanager
```
http://192.168.50.108:9093
# Alert muncul di sini?
```

**Step 5:** Cek Discord
- Alert message masuk di channel?

**Step 6:** Cek webhook logs
```bash
docker compose logs incident-webhook
# Ada log "Sent alert to Discord webhook"?
```

---

## 8. Checklist Debugging Umum

### Ketika alert tidak firing:
- [ ] Prometheus running? `docker compose ps prometheus`
- [ ] Alert rules valid? `docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml`
- [ ] Metrics ada? `curl http://192.168.50.108:9090/api/v1/query?query=up`
- [ ] Expression di rule benar? Test di Prometheus Graph
- [ ] Threshold tepat? Misal: >90% atau <1?
- [ ] `for:` duration cukup? Misal: 5m atau 2m?

### Ketika alert tidak masuk Alertmanager:
- [ ] Prometheus → Alertmanager connection OK? `docker compose exec prometheus curl http://alertmanager:9093/-/healthy`
- [ ] Alertmanager running? `docker compose ps alertmanager`
- [ ] Alertmanager config valid? `docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml`
- [ ] Route rule cocok? Cek `matchers` di alertmanager.yml

### Ketika alert tidak masuk Discord:
- [ ] Webhook service running? `docker compose ps incident-webhook`
- [ ] Webhook bisa di-reach? `curl http://192.168.50.108:5000/alert -X POST ...`
- [ ] Discord webhook URL valid? Cek di docker-compose.yml
- [ ] Discord webhook belum expired? Buat baru jika diperlukan
- [ ] Webhook logs OK? `docker compose logs incident-webhook`

---

## 9. Update Konfigurasi & Reload

### Update prometheus.yml (tanpa restart container)
```bash
# Edit file
nano prometheus/prometheus.yml

# Validate syntax
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml

# Reload Prometheus (tanpa downtime)
curl -X POST http://192.168.50.108:9090/-/reload
```

### Update alert_rules.yml
```bash
# Edit file
nano prometheus/alert_rules.yml

# Validate syntax
docker compose exec prometheus promtool check rules /etc/prometheus/alert_rules.yml

# Reload Prometheus
curl -X POST http://192.168.50.108:9090/-/reload
```

### Update alertmanager.yml (perlu restart)
```bash
# Edit file
nano alertmanager/alertmanager.yml

# Validate syntax
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml

# Restart Alertmanager
docker compose restart alertmanager
```

### Update incident-webhook (perlu rebuild)
```bash
# Edit incident-webhook/app.py
nano incident-webhook/app.py

# Rebuild dan restart
docker compose up -d --build incident-webhook
```

---

## 10. Useful Commands

### View real-time logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f prometheus
docker compose logs -f alertmanager
docker compose logs -f incident-webhook
```

### Check service health
```bash
docker compose exec prometheus curl -s http://localhost:9090/-/healthy
docker compose exec alertmanager curl -s http://localhost:9093/-/healthy
curl -s http://192.168.50.108:5000/
```

### Inspect container
```bash
docker compose exec <service> /bin/bash
# Atau
docker exec <container-name> /bin/bash
```

### Check disk usage (Prometheus data)
```bash
docker exec prometheus du -sh /prometheus
```

### Backup Prometheus data
```bash
docker cp prometheus:/prometheus ./prometheus-backup-$(date +%Y%m%d)
```

### Clean up (hapus semua container + volume)
```bash
docker compose down -v
```

---

## 11. Performance Tuning

### Jika Prometheus slow:
```bash
# Edit prometheus.yml, kurangi `scrape_interval` jika terlalu tinggi
# Atau increase `evaluation_interval` jika alert evaluation terlalu sering

# Check Prometheus resource usage
docker stats prometheus
```

### Jika alert delay:
```bash
# Check Alertmanager config:
# - group_wait: tunggu sebelum send (default 30s)
# - group_interval: batch alert baru (default 5m)
# - repeat_interval: resend alert (default 3h)

# Reduce values untuk alert lebih cepat
```

---

## 12. Emergency Troubleshooting

### Semua service down, harus restart semuanya
```bash
cd /home/monitoring/server-monitoring
docker compose down
docker compose up -d --build
```

### Container keeps restarting
```bash
# Cek logs
docker compose logs <service>

# Cek config validity (lihat step 3-5 di atas)

# Rebuild image
docker compose up -d --build <service>
```

### Storage issue (disk penuh)
```bash
# Check disk
df -h

# Clear old Prometheus data
docker exec prometheus promtool tsdb clean-tombstones /prometheus

# Or reduce retention
# Edit prometheus.yml: command: --storage.tsdb.retention.time=7d
```

---

## Referensi

- **Prometheus Docs:** https://prometheus.io/docs/
- **Alertmanager Docs:** https://prometheus.io/docs/alerting/latest/
- **Blackbox Exporter:** https://github.com/prometheus/blackbox_exporter
- **Discord Webhook:** https://discord.com/developers/docs/resources/webhook

---

**Last Updated:** 2025-12-01

Jika masih ada masalah, cek logs dulu dengan step-by-step debugging checklist di atas.
