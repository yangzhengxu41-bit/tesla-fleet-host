#!/bin/bash
# One-time setup: TeslaMate state exporter + tailnet-only HTTP service.
# Run as root on the Tencent server (82.156.53.116).
set -x

mkdir -p /opt/teslamate/state

cat > /opt/teslamate/export-state.sh <<'EOS'
#!/bin/bash
OUT=/opt/teslamate/state/state.json
SQL="SELECT json_build_object('exported_at', now(), 'car', (SELECT json_build_object('name', name, 'model', model) FROM cars ORDER BY id LIMIT 1), 'state', (SELECT json_build_object('state', state, 'since', start_date) FROM states WHERE end_date IS NULL ORDER BY start_date DESC LIMIT 1), 'position', (SELECT json_build_object('date', date, 'battery_level', battery_level, 'usable_battery_level', usable_battery_level, 'rated_range_km', rated_battery_range_km, 'est_range_km', est_battery_range_km, 'odometer_km', odometer, 'latitude', latitude, 'longitude', longitude, 'outside_temp', outside_temp, 'inside_temp', inside_temp, 'climate_on', is_climate_on) FROM positions ORDER BY date DESC LIMIT 1), 'charging', (SELECT json_build_object('start', start_date, 'end', end_date, 'energy_added_kwh', charge_energy_added, 'cost', cost) FROM charging_processes ORDER BY start_date DESC LIMIT 1), 'last_drive', (SELECT json_build_object('start', d.start_date, 'end', d.end_date, 'distance_km', d.distance, 'duration_min', d.duration_min, 'from', sa.display_name, 'to', ea.display_name) FROM drives d LEFT JOIN addresses sa ON sa.id = d.start_address_id LEFT JOIN addresses ea ON ea.id = d.end_address_id ORDER BY d.start_date DESC LIMIT 1))"
docker exec teslamate-database-1 psql -U teslamate -d teslamate -t -A -c "$SQL" > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
EOS
chmod +x /opt/teslamate/export-state.sh

cat > /etc/systemd/system/teslamate-state.service <<'EOS'
[Unit]
Description=TeslaMate state export HTTP (tailnet only)
After=network-online.target tailscaled.service
Wants=network-online.target

[Service]
ExecStart=/usr/bin/python3 -m http.server 8446 --bind 100.110.17.118 --directory /opt/teslamate/state
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOS

echo '* * * * * root /opt/teslamate/export-state.sh >/dev/null 2>&1' > /etc/cron.d/teslamate-state

/opt/teslamate/export-state.sh
systemctl daemon-reload
systemctl enable --now teslamate-state.service
sleep 3
echo '--- state.json ---'
cat /opt/teslamate/state/state.json
echo
echo '--- self test via tailnet IP ---'
curl -s --max-time 10 http://100.110.17.118:8446/state.json
echo
echo SETUP_DONE
