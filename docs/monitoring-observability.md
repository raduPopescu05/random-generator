# Monitoring and Observability for DevOps

This guide introduces monitoring and observability, explains how Prometheus and Grafana fit into a DevOps workflow, and shows how the tools run alongside this repository's Docker Compose stack. It is written for readers who know the basics of applications and containers but are new to these tools.

> **Current repository status:** the API exposes internal Prometheus metrics, and the default Docker Compose stack includes Prometheus and Grafana with three provisioned dashboards. Follow [the monitoring README](../monitoring/README.md) to start it and generate sample traffic.

## 1. Monitoring and observability

**Monitoring** is the ongoing collection and review of signals that tell a team whether a system is healthy and meeting expectations. A monitor can detect that the API is returning errors, the database is unreachable, or response times have risen. Dashboards and alerts make those signals easier to act on.

**Observability** is the ability to understand a system's internal condition from the information it produces. When an unfamiliar failure occurs, useful telemetry helps an engineer investigate what happened and narrow down why. Monitoring asks, “Is something wrong?” Observability helps answer, “What is happening, and why?” The terms overlap in everyday use; observability is not a product that can be switched on by itself. It depends on useful instrumentation, telemetry, and investigation practices.

The common telemetry signals are:

- **Metrics:** numeric measurements recorded over time, such as request counts, error rates, latency, memory use, or database connections. They are efficient for dashboards, trends, and alert conditions.
- **Logs:** timestamped records of individual events. A log entry can explain the details of one failed request, but searching huge volumes of logs for broad trends can be expensive.
- **Traces:** records of a request's path across services and operations. A distributed trace can show that an API request spent most of its time waiting for a database query.
- **Events and profiles:** other useful signals include deployment events and CPU or memory profiles. Which signals to collect depends on the system and the questions the team needs to answer.

Metrics, logs, and traces complement one another. A metric can reveal a spike in errors, a log can provide the detail for a particular failure, and a trace can show which service or dependency contributed to its latency. Prometheus primarily handles metrics. Grafana can visualize data from many systems, including metrics, logs, and traces when the corresponding data sources are configured; installing Grafana alone does not collect those signals.

### Why DevOps teams use monitoring

DevOps teams need feedback from development, deployment, and production. Monitoring provides that feedback so a team can:

1. **Detect incidents:** notice failing health checks, rising error rates, or depleted disk space before a user report is the first signal.
2. **Triage faster:** see whether a problem is limited to one endpoint, all API requests, the database, or the host.
3. **Check changes:** compare service behavior before and after a release, and identify regressions.
4. **Plan capacity:** use trends in request volume, resource use, and saturation to decide when to tune or scale a service.
5. **Improve reliability:** define service expectations, measure them, and learn from incidents instead of relying on guesses.

Useful monitoring starts with questions, not with a large collection of graphs. For an HTTP API, a practical starting set is request volume, error rate, and latency. Add resource and dependency metrics such as CPU, memory, database availability, and connection pool use when they help explain user impact. A dashboard should help answer a real operational question.

### Health checks are useful but are not metrics

A health check returns a simple status, often success or failure. A **liveness** check asks whether a process is running and should continue. A **readiness** check asks whether it can currently serve requests, including whether required dependencies are reachable. A container orchestrator can use these checks to restart or route traffic around an unhealthy service.

Health checks are snapshots: they do not show how often requests fail, how long they take, or how behavior changes through the day. Metrics provide that history and detail. A probe exporter can check an HTTP health endpoint and expose the result as metrics. Prometheus cannot directly interpret a JSON health response as metric exposition.

In this repository, `GET /health/live` indicates that the API process is running, and `GET /health/ready` checks whether the API can connect to MySQL. Docker Compose uses the ready endpoint for the API health check, and the web service waits for that check to pass. These endpoints support service health decisions; application metrics are exposed separately at `/metrics`.

## 2. Prometheus

**Prometheus** is an open-source monitoring and alerting toolkit. It collects numeric measurements and stores them as time series: sequences of timestamped values. A series is identified by a metric name and optional key/value **labels**. For example, an HTTP request counter could have labels for method, route, and response code.

Prometheus is designed around a **pull model**. At configured intervals, the Prometheus server requests a metrics page from each target, commonly an HTTP endpoint such as `/metrics`. An application can expose its own metrics using a client library, or an **exporter** can translate metrics from a system that does not expose Prometheus format directly. The target must be reachable from Prometheus over the network.

The basic flow looks like this:

```text
Application or exporter  -- exposes metrics -->  Prometheus  -- query -->  Grafana
                                               stores time series
```

### What problem Prometheus solves

Without a metrics system, an engineer may have to inspect machines one by one or infer service behavior from scattered logs. Prometheus provides one place to scrape configured targets, retain time-stamped measurements, query them over a time window, and evaluate alerting rules. Its built-in target status also helps distinguish “the service is down” from “the service is running but reporting bad application metrics.”

Prometheus does not automatically know what your application is doing. The application or an exporter must expose useful measurements, and the server must be configured to scrape them. It is also not a long-term, horizontally distributed metrics warehouse by default; retention, scale, and high availability require an appropriate architecture as needs grow.

### Metrics and labels

Prometheus supports four common metric types:

- **Counter:** only increases (or resets when the process restarts), such as total requests or total failures. Use `rate()` or `increase()` to understand change over a time window.
- **Gauge:** can increase or decrease, such as memory in use, active requests, or queue depth.
- **Histogram:** records observations in configurable buckets and provides a count and sum. It is commonly used for latency distributions and percentile calculations.
- **Summary:** calculates quantiles in the instrumented process. Summaries can be difficult to aggregate across replicas, so histograms are often more flexible for service-wide latency views.

Labels let one metric describe bounded dimensions. For example, `http_requests_total{method="GET", route="/number", status="200"}` distinguishes methods, routes, and status codes. Every distinct combination of labels creates a separate time series. Avoid labels with unbounded values, such as user IDs, email addresses, request IDs, or full URLs containing arbitrary identifiers. High cardinality can consume substantial memory and storage and make queries slower. Prefer stable route templates like `/items/:id` over individual paths like `/items/391`.

Metric names should describe one quantity and use a consistent unit. For example, use seconds for duration and bytes for size. If the application has a request-duration histogram, name it so the unit is clear, such as `http_request_duration_seconds`.

### A Prometheus scrape configuration

Prometheus is configured with a YAML file. The repository uses the following scrape jobs. The instrumented API exposes `/metrics`; the executable configuration lives in `monitoring/prometheus.yml`.

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["prometheus:9090"]

  - job_name: "random-generator-api"
    metrics_path: /metrics
    static_configs:
      - targets: ["api:3000"]
```

`global.scrape_interval` sets the default interval between collection requests. A `scrape_config` defines one job, a logical group of targets. `static_configs` lists targets directly; service discovery can replace that list in larger or changing environments. `metrics_path` defaults to `/metrics`, so the line is shown to make the intended endpoint explicit. The target uses `api:3000` because containers in the same Compose network reach each other by service name and container port, not by the host's published port.

Validate configuration with Prometheus's `promtool check config prometheus.yml` when `promtool` is available. After starting Prometheus, open its web UI (port 9090 in the example setup) and check **Status → Targets**. A target should show as `UP`. `DOWN` usually means a bad target name or port, a missing endpoint, a network problem, or an application that is not running. The Prometheus expression browser can be used to query a metric directly before building a dashboard.

### PromQL examples

PromQL is Prometheus's query language. The metric names below are exposed by this repository. The provisioned dashboards additionally scope queries to the API job and filter unavailable targets.

```promql
# Total request rate per route over the last five minutes
sum by (route) (rate(http_requests_total[5m]))

# Error percentage over the last five minutes (assuming status labels)
100 * sum(rate(http_requests_total{status=~"5.."}[5m]))
    / sum(rate(http_requests_total[5m]))

# 95th percentile request latency from a histogram
histogram_quantile(
  0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket[5m]))
)

# Is the configured scrape target reachable?
up{job="random-generator-api"}
```

`rate(counter[5m])` estimates a per-second increase over the selected range and accounts for counter resets. `sum by (...)` aggregates series while retaining the chosen labels. `histogram_quantile` estimates a percentile from histogram buckets. A ratio query should handle a zero request rate if it is used for a production dashboard or alert; otherwise an empty period can produce no meaningful ratio.

### Alerting

Prometheus can evaluate alerting rules such as “the API error rate has stayed above a threshold for several minutes.” Rules can use a `for` duration to avoid firing on a brief blip. Prometheus can show pending and firing alerts; in a typical production design, Alertmanager groups, routes, and delivers notifications to configured channels. Alerts should focus on actionable symptoms and user impact. A chart that is interesting is not automatically a reason to wake someone up.

## 3. Grafana

**Grafana** is an open-source platform for querying, visualizing, and sharing operational data. It connects to one or more **data sources**; Prometheus is one common metrics source. Grafana sends queries to the configured source and displays their results in dashboards. It generally does not replace the source's storage: Prometheus stores the metrics in this setup, while Grafana stores dashboard and application configuration.

### What problem Grafana solves

Prometheus has a query and graph interface, but teams often need a shared view that puts important signals together. Grafana turns queries into **panels** (graphs, stat values, tables, and other visualizations) and organizes panels into dashboards. A service dashboard might show request rate, error percentage, latency, CPU, memory, database connectivity, and deployment markers in one place. Grafana's Explore view is also useful for trying a query before saving it to a dashboard.

Grafana supports alerting features too, but alert delivery depends on configuring contact points and notification policies. Prometheus alert rules and Grafana-managed alert rules are different ways to define alerts; a small learning stack does not need to use both. For a first setup, keep alerting simple and focus on dashboards, then choose one alerting path when there is a concrete need.

### Connect Grafana to Prometheus and build a dashboard

For a local setup, first start Prometheus and verify that its target is `UP`. Then:

This repository already provisions the data source and dashboards. The steps below
explain the manual workflow for creating additional dashboards or another Grafana instance.

1. Open Grafana at the host port selected for the Compose service (port `3001` below).
2. Sign in using credentials configured for the local environment. A disposable local setup may use documented defaults, but change defaults and use secrets before exposing Grafana to other machines.
3. Add a **Prometheus** data source. Set its URL to `http://prometheus:9090` when Grafana and Prometheus are services on the same Compose network. Do not use `localhost:9090` from inside Grafana's container: there, `localhost` means the Grafana container itself.
4. Save and test the data source. A connection test confirms Grafana can reach Prometheus; it does not prove the API target is healthy or that the API has metrics.
5. Create a dashboard, add a time-series panel, and enter a PromQL query. Start with a useful question, such as request rate by route or latency over time.
6. Set an informative title, unit, and legend. Save the dashboard and choose a time range that makes changes easy to see.

If a panel is empty, check the query in Prometheus first, then verify the Grafana data source URL, time range, and refresh interval. Empty data can also be expected when the assumed metric is not yet instrumented or there has been no traffic.

### Dashboard and access practices

Build dashboards around a service and its user-facing behavior. Use consistent units and clear labels; show a small number of meaningful signals, and add links or notes that help an on-call engineer investigate. Avoid dashboards that contain dozens of panels without an operational question.

Prometheus and Grafana interfaces can expose internal operational details. Do not publish them openly with default credentials. For a local Compose learning environment, bind ports to `127.0.0.1` where possible, use non-default credentials, and avoid putting real secrets in committed files. A production deployment needs authentication, network restrictions, TLS where appropriate, and a plan for secret management and updates.

## 4. How the tools fit this repository

The existing Compose stack contains a MySQL service, the Node.js API, and a web frontend. The API listens on port 3000 inside the Compose network. The frontend publishes host port 3000, so Grafana should use a different host port, such as 3001, and Prometheus can use 9090. The API health check calls `/health/ready`; services on its Compose network can reach the API directly; `expose` documents the port and does not publish it to the host.

The implementation uses `@prometheus-io/client`, the maintained successor to `prom-client`. API request counters and histograms record bounded method, route and status labels. The API also counts successful persisted generations and measures database operations, including failures. Node.js default collectors provide runtime metrics.

Prometheus scrapes the API and itself every 15 seconds and retains seven days of samples in a named volume. Grafana connects to `http://prometheus:9090`; its data source and three custom dashboards are provisioned from files under `monitoring/grafana/`. The dashboards cover API behavior, Node.js runtime, and generation/database activity. Database metrics describe calls made by the API rather than MySQL server internals.

The default Compose stack builds the application locally. Configure `GRAFANA_ADMIN_PASSWORD` in a root `.env` using `.env.example`, then run `docker compose up -d --build`. Open Grafana on port 3001 and Prometheus on port 9090. Both monitoring interfaces are bound to loopback. The metrics endpoint is accessible inside the Compose network and is not proxied by the frontend.

Use [the monitoring README](../monitoring/README.md) for the complete startup procedure, sample traffic, metric queries, dashboard editing, persistence and troubleshooting. Prometheus scrape availability does not imply database readiness. No-traffic ratios and latency percentiles show no data rather than a misleading healthy value. Logs and traces still require their own collection systems; this integration implements metrics without alert notifications.

## 5. Common troubleshooting checklist

- **Target is down:** check the target hostname and container port, confirm the service shares a Compose network, verify that the metrics endpoint exists, and inspect the API and Prometheus logs.
- **Target is up but the query is empty:** check that the metric name and labels match the instrumentation, send traffic if the metric is created only after an event, and widen the query time range.
- **Grafana cannot connect:** use the Prometheus Compose service name and internal port in the data source URL; confirm Prometheus is healthy and reachable from Grafana.
- **Dashboard shows odd values:** check units, counter versus gauge semantics, query aggregation, time range, and label filters. Apply `rate()` to counters when a per-second rate is intended.
- **Prometheus uses too much memory:** inspect series count and label combinations, remove unbounded labels, and review scrape interval and retention requirements.
- **Sensitive information appears in telemetry:** avoid secrets and personal data in metric labels, logs, and dashboard variables; restrict access to the monitoring network and interfaces.

## Further reading

- [Prometheus overview](https://prometheus.io/docs/introduction/overview/)
- [Prometheus configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Prometheus metric and label naming practices](https://prometheus.io/docs/practices/naming/)
- [Prometheus metric types](https://prometheus.io/docs/concepts/metric_types/)
- [Prometheus alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Grafana introduction](https://grafana.com/docs/grafana/latest/introduction/)
- [Run Grafana in Docker](https://grafana.com/docs/grafana/latest/setup-grafana/installation/docker/)
- [Grafana data sources](https://grafana.com/docs/grafana/latest/administration/data-source-management/)
- [Build your first Grafana dashboard](https://grafana.com/docs/grafana/latest/fundamentals/getting-started/first-dashboards/)
