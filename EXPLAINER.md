# How the Cloudflare Prometheus Exporter Works

> **One-pager for engineers.** Why it is a Worker, why it lives at the edge, and why "just run a container" is not the move.

---

## 1. Where the data comes from

Every request that hits Cloudflare (DNS, HTTP, WAF, Load Balancer, Workers, Magic Transit, etc.) is ingested by Cloudflare's global network.

On top of this raw traffic, Cloudflare exposes two APIs:

| API | What it gives | How we use it |
|-----|---------------|---------------|
| **Analytics GraphQL** | Aggregated metrics in 1-minute buckets (requests, bandwidth, errors, firewall events, health checks, …) | Primary data source for Prometheus metrics |
| **REST API** | Structured resources (zones, SSL certs, firewall rules, account list, load-balancer pools, …) | Discovery ("which zones should I monitor?") |

These APIs are **not** in Prometheus format.
They speak **GraphQL** and **JSON**.

> Prometheus = `pull` model + `text/plain` exposition format (`HELP`, `TYPE`, `counter`, `gauge`).
> Cloudflare APIs = `push/query` model + `application/json`.
> **So we need a translator in the middle.**

---

## 2. What the Exporter does


    ┌──────────────────────────────────────────────────────────────────┐
    │                       YOUR INFRA / CLIENT                        │
    │                                                                  │
    │   ┌──────────────┐  GET /metrics   ┌──────────────────────────┐  │
    │   │  Prometheus  │ ───────────────►│ Cloudflare Prometheus    │  │
    │   │  (scraper)   │  every 60s      │ Exporter                 │  │
    │   └──────────────┘                 │ (Worker)                 │  │
    └────────────────────────────────────┴──────────────────────────┴──┘
                                         │
     ┌───────────────────────────────────┴──────────────────────────────┐
     │                    CLOUDFLARE NETWORK (Edge)                   │
     │                                                                │
     │  ┌──────────────────┐         ┌─────────────────────────────┐  │
     │  │ Durable Objects  │ ◄────── │ GraphQL + REST APIs         │  │
     │  │ (stateful cache) │ refresh │ (Analytics, Zones, Cert, …) │  │
     │  └──────────────────┘  every  └─────────────────────────────┘  │
     │           │                60s                                 │
     │           │                                                    │
     │           ▼                                                    │
     │  ┌──────────────────┐  alarm: update ctx.storage               │
     │  │ MetricExporter   │  per-query counters (monotonic)           │
     │  │ AccountMetric    │                                           │
     │  │ Coordinator      │                                           │
     │  └──────────────────┘                                           │
     └─────────────────────────────────────────────────────────────────┘


### The scrape is fast because we pre-fetch

- **Background** → Durable Objects run `alarm()` every 60 seconds, query Cloudflare APIs, accumulate counters, and persist state.
- **Scrape** → Prometheus hits `/metrics`. The Worker returns **already cached data** from the DOs. **Zero calls to Cloudflare APIs during the scrape.**

Result: a Prometheus scrape that returns in **milliseconds** even though the underlying data pipeline is complex.

---

## 3. Why not a VM?

| Problem | Explanation |
|---------|-------------|
| **Cost** | A modest cloud VM = €20–€50/month **fixed cost**, 24/7. The Worker is billed by request + CPU-ms. For a 60s scrape interval, it is orders of magnitude cheaper. |
| **Ops overhead** | OS patching, dependency management, log rotation, monitoring the monitor. None of this exists with a Worker. |
| **Scaling** | If the account grows from 6 zones to 600 zones, a VM needs a bigger instance or horizontal scaling. The Worker auto-scales across 300+ PoPs within the same pricing model. |
| **Cold start** | VM boot = seconds. Container boot = hundreds of ms. Worker isolate cold start = **~0 ms**. |

> A VM is overkill for a service that is woken up **once per minute** to do a few API calls and serialize text.

---

## 4. Why not self-hosted (Docker)?

The upstream repo includes a `Dockerfile` and `docker-compose.yml`, but they are **only for local Prometheus** (so you can test scraping locally). They do **not** run the exporter itself.

You could technically wrap the code in a Node.js container, but you would lose:

| Feature | Worker (native) | Self-hosted container |
|---------|----------------|----------------------|
| **Stateful persistence** | Durable Objects (`ctx.storage`, SQLite-backed, replicated) | You need Redis or an external DB |
| **Background scheduling** | Native `alarm()` API with jitter and recovery | External cron (`systemd`, `node-cron`) — single point of failure |
| **Distributed rate-limiting** | Native `RateLimit` binding (200 req/10s, shared across all DO instances) | Custom rate-limiter, race conditions |
| **Retry / backoff** | Built into the DO alarm + exponential backoff | Re-implement |
| **Global availability** | 300+ edge locations, traffic routed to the closest one | Single region unless you run a cluster |
| **Zero maintenance** | No OS, no patching, no container runtime | Full ownership of the stack |

> **Translation:** you would spend weeks rebuilding infrastructure primitives that Cloudflare gives you for free.

---

## 5. What is a Cloudflare Worker, really?

### Not Node.js!

A Worker runs in a **V8 isolate** — the same JavaScript engine as Chrome and Node.js — but it is **not** a Node.js process.

| Node.js runtime | Cloudflare Worker runtime |
|-----------------|---------------------------|
| `require("fs")`, `require("net")` | No filesystem, no raw sockets |
| `process.env` | Yes `env` bindings (type-safe, explicit) |
| npm packages with native C++ addons | Not supported |
| `fetch`, `crypto`, `URL`, `Headers` | Yes Native Web APIs |
| `setTimeout`, `setInterval` | Limited; prefer `alarm()` for scheduling |
| Cold start | ~50–100 ms | **~0 ms** (isolates are pre-warmed) |

### The edge-native advantage

When you run `wrangler deploy`, your code is pushed to **300+ points of presence** worldwide in ~30 seconds. There is no region, no AZ, no load-balancer to configure. The closest PoP answers every request.

This is why the exporter is architected as:
- **Worker** (HTTP entry + fan-out logic) → lightweight, stateless, instant
- **Durable Objects** (stateful metric cache) → JavaScript classes that persist state across requests via `ctx.storage`

### Why Durable Objects matter here

Prometheus expects **monotonically increasing counters**. Cloudflare GraphQL gives you totals per time window.

To bridge the gap, the exporter stores partial counters in DO state, increments them per window, and exports the running total. Without stateful persistence, the counters would reset between scrapes.

DOs handle this natively because `ctx.storage` is:
- **Transactional** (read-modify-write atomic)
- **Replicated** (survives process restarts)
- **Scheduled** (`alarm()` wakes the object up automatically)

---

## 6. End-to-end data flow (60-second refresh)

```
Minute 0 (cold start)
│
├─> Worker created via `wrangler deploy`
│
├─> Prometheus configured to scrape `https://exporter.workers.dev/metrics`
│
Minute 1
│
├─> AccountMetricCoordinator DO wakes up (alarm fires)
│   ├─> Lists accounts via REST API
│   └─> Spawns one AccountMetricCoordinator DO per account
│
├─> AccountMetricCoordinator DO wakes up
│   ├─> Lists zones via REST API (cache TTL: 30 min)
│   └─> Spawns MetricExporter DOs:
│       ├─ 21 account-level exporters (workers, magic transit, stream, …)
│       └─ N zone-level exporters (1 per zone: requests, bandwidth, firewall, …)
│
├─> Each MetricExporter DO queries GraphQL for its metric
│   ├─> Accumulates counters in `ctx.storage`
│   └─> Schedules next alarm (60s + jitter)
│
├─> Prometheus scrapes `/metrics`
│   ├─> Worker reads all DOs in parallel
│   └─> Returns `text/plain` metrics instantly
│
Minute 2 (and every minute after)
│
└─> Loop repeats: DOs refresh → Prometheus scrapes — no gaps, no drift.
```

---

## 7. TL;DR for decision-makers

| Question | Answer |
|----------|--------|
| **Where does the data come from?** | Cloudflare Analytics GraphQL + REST APIs (the same APIs the dashboard uses). |
| **Why do we need an exporter?** | Because Cloudflare does not expose Prometheus natively. We translate GraphQL/JSON → Prometheus text format. |
| **Why a Worker, not a container?** | Zero ops, zero cold start, auto-scaling, orders of magnitude cheaper, and native stateful primitives (Durable Objects) that you would rebuild by hand. |
| **Can we run it on-prem?** | Technically yes, but you lose DOs, alarms, and distributed rate-limiting. The Docker files in the repo are **only** for running Prometheus locally. |
| **What does it cost?** | The Free plan covers the developer use case. For production, Workers are billed per million requests + CPU duration (fractions of a penny). |

---

## 8. Quick references

- **Deployed endpoint:** `https://your-domain.workers.dev/metrics`
- **Auth:** HTTP Basic Auth (`admin` / token rotated separately)
- **Scrape interval:** `60s` in Prometheus
- **Metric refresh:** `60s` background via DO alarms
- **Config KV:** Runtime overrides via `/config` REST API (no redeployment needed)

---

*Built with Hono, TypeScript, Durable Objects, and Cloudflare GraphQL. Deployed via Terraform + Wrangler for full reproducibility.*
