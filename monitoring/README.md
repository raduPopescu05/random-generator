# Local monitoring

The default Compose stack builds the API and frontend locally and starts MySQL,
the Prometheus MySQL exporter, Prometheus, and Grafana. Four custom dashboards
and the Prometheus data source are provisioned automatically. This setup is for
local development; AWS deployment and notifications are not configured.

## Start

Install Docker Desktop with Linux containers and Docker Compose v2. Run these
commands from the repository root in PowerShell:

```powershell
Copy-Item .env.example .env
notepad .env
# Set unique Grafana and MySQL root passwords, then save.
docker compose config --quiet
docker compose up -d --build
docker compose ps
```

Do not overwrite an existing `.env`; add both `GRAFANA_ADMIN_PASSWORD` and
`MYSQL_ROOT_PASSWORD` to it. The file is ignored by Git. Compose rejects an
absent or empty password. If `mysql-data` already exists, set
`MYSQL_ROOT_PASSWORD` to the root password already stored in that database;
changing the environment variable does not change an initialized MySQL user's
password. MySQL may need a minute to initialize on its first start. No ECR
credentials are needed. Re-run `up -d --build` after changing application code.

| Service | Address | Purpose |
| --- | --- | --- |
| App | http://localhost:3000 | Generate values and view history |
| Prometheus | http://localhost:9090 | Query metrics and inspect Targets |
| Grafana | http://localhost:3001 | Sign in as `admin` with the password from `.env` |
| MySQL exporter | Internal `mysql-exporter:9104` | Exposes MySQL metrics to Prometheus only |

Monitoring ports are bound to `127.0.0.1`. Optional `APP_PORT`, `PROMETHEUS_PORT`,
and `GRAFANA_PORT` variables change the host ports. They do not change container
ports or the Grafana data source URL, which remains `http://prometheus:9090`.

The API's `/metrics` endpoint and the MySQL exporter's `:9104` endpoint are
available only within the Compose network. Nginx does not proxy either endpoint.
Running `npm start` directly instead of Compose exposes all API routes on its
listening port, so restrict network access accordingly.

## Dashboards

In Grafana, open **Dashboards → Random Generator**:

| Dashboard | What to look for |
| --- | --- |
| API Overview | Scrape availability, request rate, 5xx percentage, p50/p95 latency, routes and status codes |
| Node.js Runtime | Process uptime, CPU, resident memory, heap, event-loop delay and GC duration |
| Generation & Database Activity | Persisted generations by type and API-observed database call rates, failures and p95 latency |
| MySQL Overview | Exporter availability, current and peak connections, query and slow-query rates, InnoDB buffer-pool hit ratio and dirty pages |

Every dashboard refreshes every 15 seconds and initially shows the last hour.
Wait for at least two scrapes (roughly 30–60 seconds) before interpreting rates.
The API availability tile measures scrape success, not database readiness. Database
failure charts can rise while this tile remains UP.

Zero means measured inactivity where counters have been initialized. **No data**
can mean an unavailable target, insufficient samples, or no observations for a
latency/error-ratio calculation. For example, a latency percentile is not meaningful
before any requests. Always check availability alongside a graph. A stopped API
causes gaps rather than false zero-traffic readings.

Generation totals count successful inserts since the current process started;
they are not a query of all rows in MySQL. Counters reset when the API restarts;
Prometheus `rate()` handles those resets. CPU percentage uses one core as 100%.
Database duration includes time waiting for a connection and query execution.
These are application measurements, not host/container or MySQL server metrics.

Dashboard JSON lives in `monitoring/grafana/dashboards/`. Edit those files to
change the provisioned dashboards; Grafana reloads them within approximately
15 seconds. They have stable UIDs, so restarting does not create duplicates.
To experiment in the UI, save a copy with a different UID. Export desired changes
back to source control. Data source and provider YAML are under
`monitoring/grafana/provisioning/`; restart Grafana after editing those settings.

## Generate traffic

On macOS, run the script from the repository root:

```sh
./generate-traffic.sh
# Custom app address and number of rounds:
./generate-traffic.sh http://localhost:8080 30
```

The script checks database access through `/history`, prints each request's HTTP
status, and stops on errors. It defaults to 30 rounds, with four requests per
round and a two-second pause between rounds. It works with `sh` or Bash and
can be launched from the default macOS zsh terminal.

On PowerShell, use this one-minute sample:

```powershell
1..30 | ForEach-Object {
    Invoke-RestMethod http://localhost:3000/number | Out-Null
    Invoke-RestMethod http://localhost:3000/letter | Out-Null
    Invoke-RestMethod http://localhost:3000/rock-paper-scissors | Out-Null
    Invoke-RestMethod 'http://localhost:3000/history?limit=10' | Out-Null
    Start-Sleep -Seconds 2
}
```

This inserts 90 rows into your development database. Request and generation
charts should rise; healthy database-failure counters should stay at zero.
Static files, `/metrics`, and health endpoints are excluded from HTTP metrics.
Database readiness queries are still measured as `operation="readiness"`.
Unknown API paths share `route="unmatched"`; query strings and generated values
are never metric labels.

## Inspect and query

Open Prometheus **Status → Targets** and confirm all three jobs are UP:
`prometheus`, `random-generator-api`, and `mysql`. The API target is
`api:3000/metrics`; the MySQL target is `mysql-exporter:9104/metrics`. The API
and exporter may remain DOWN during initial database initialization.

Try these in Prometheus's query UI or Grafana Explore:

```promql
up{job="random-generator-api"}

sum by (route) (rate(http_requests_total{job="random-generator-api"}[5m]))

sum by (type) (increase(generations_total{job="random-generator-api"}[5m]))

sum by (operation) (
  rate(database_operations_total{job="random-generator-api",outcome="failure"}[5m])
)

histogram_quantile(
  0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{job="random-generator-api"}[5m]))
)
```

`increase()` is an extrapolated estimate over the time window and may be fractional.
The dashboards filter operational measurements against current scrape availability.
The simple example queries above are useful for investigation and may retain older
samples briefly after a target goes down.

Inspect raw API and MySQL metrics and validate configuration:

```powershell
docker compose exec api node -e "fetch('http://localhost:3000/metrics').then(r => r.text()).then(console.log)"
docker compose exec prometheus promtool check config /etc/prometheus/prometheus.yml
docker compose logs --tail=100 api prometheus grafana
```

## Troubleshooting

- **Missing password:** set `GRAFANA_ADMIN_PASSWORD` in the root `.env`, not the
  tracked example. Avoid printing `docker compose config` without `--quiet`,
  because expanded configuration contains credentials.
- **Login fails after changing `.env`:** Grafana's administrator password variable
  initializes a new data volume only. For an existing volume, sign in with the old
  password and change it in Grafana, then update `.env`. If locked out, use
  `docker compose exec grafana grafana cli admin reset-admin-password '<new-password>'`.
  That recovery command includes the password in shell history.
- **Prometheus target DOWN:** check API/exporter logs, database health, and target
  error text. Targets must use Compose service names (`api:3000` and
  `mysql-exporter:9104`), not `localhost`.
- **MySQL exporter cannot connect:** confirm `MYSQL_ROOT_PASSWORD` in `.env`
  matches the root password in the initialized `mysql-data` volume, then inspect
  `docker compose logs mysql-exporter db`. Query `mysql_up` in Prometheus to
  confirm MySQL collection is succeeding.
- **Grafana data source unavailable:** its internal URL must be
  `http://prometheus:9090`. Check that Prometheus is running.
- **Empty panels:** wait for several scrapes, generate traffic, and confirm the
  time range includes it. Error percentage and latency require actual requests.
- **No dashboards:** check Grafana logs for provisioning errors and ensure the
  mounted paths exist. All three should appear without manual importing.
- **Port conflict:** configure the optional host-port variables and restart
  Compose. Use the corresponding port in your browser and sample requests.
- **Database outage:** the API can still expose metrics while database calls fail.
  The ready endpoint and business requests can return 503. Do outage experiments
  only on a disposable Compose project with its own ports and volumes.

## Persistence, stopping, and reset

```powershell
docker compose stop       # Keep containers and all volumes
docker compose start
docker compose down       # Remove containers/network; preserve named volumes
docker compose up -d --build
```

Prometheus retains seven days of samples in `prometheus-data`. This is a time
limit, not a fixed disk-size cap. Grafana stores users, settings, and saved copies
of dashboards in `grafana-data`. Provisioned dashboard definitions remain in Git.
MySQL data stays in its separate `mysql-data` volume.

To reset **only monitoring data**, first capture the exact monitoring volume names
from their containers, then remove those services and volumes:

```powershell
$promContainer = docker compose ps -aq prometheus
$grafanaContainer = docker compose ps -aq grafana
$promVolume = docker inspect $promContainer --format '{{range .Mounts}}{{if eq .Destination "/prometheus"}}{{.Name}}{{end}}{{end}}'
$grafanaVolume = docker inspect $grafanaContainer --format '{{range .Mounts}}{{if eq .Destination "/var/lib/grafana"}}{{.Name}}{{end}}{{end}}'
# Review these two names: they must end in prometheus-data and grafana-data.
$promVolume
$grafanaVolume
docker compose rm -sf prometheus grafana
docker volume rm $promVolume $grafanaVolume
docker compose up -d prometheus grafana
```

This discards metric history and Grafana's stored settings, and reinitializes the
administrator password from `.env`. Do not use `docker compose down -v` for this
purpose: it also deletes the MySQL volume and generation history.

## Configuration and scope

Prometheus scrapes every 15 seconds. Change its configuration in
`monitoring/prometheus.yml` and restart it with `docker compose restart prometheus`.
Retention is set by its Compose command. Image versions are pinned in Compose.
The Node instrumentation uses `@prometheus-io/client`, the maintained successor
to `prom-client`, and requires Node 22 or 24 (or a supported newer release).
No Alertmanager, external notifications, or host exporter is installed. The MySQL
exporter uses root credentials for this local development setup; do not reuse
these credentials for a production deployment.

See [the concepts guide](../docs/monitoring-observability.md),
[the official Node client](https://github.com/prometheus/client_js),
[Prometheus configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/),
and [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/).
