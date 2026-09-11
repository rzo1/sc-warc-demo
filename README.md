# StormCrawler WARC Demo

A web crawler built on [Apache StormCrawler](https://stormcrawler.apache.org/) that produces [WARC (Web ARChive)](https://iipc.github.io/warc-specifications/specifications/warc-format/warc-1.1/) files. It runs on a Dockerized [Apache Storm](https://storm.apache.org/) cluster with [URLFrontier](https://github.com/crawler-commons/url-frontier) for URL management.

This project was generated using the StormCrawler Maven Archetype and serves as a starting point for building your own crawler. Review the provided code and resources and adapt them as needed for your use case.

> **Note:** This branch targets **Apache Storm 3.1.0** and **Apache StormCrawler 4.0.0-SNAPSHOT**. Until both are
> released, `pom.xml` resolves them from the ASF snapshot and Storm staging repositories, and the `storm:3.1.0`
> Docker image has to be built locally from the Storm binary distribution. Drop the `<repositories>` block from
> `pom.xml` and switch to the released StormCrawler version once both are available.

## Prerequisites

- **Java 17** (to build; the Storm 3.1.0 Docker images run on Java 25)
- **Maven** 3.x
- **Docker** and **Docker Compose**

## Quick Start

### 1. Build the project

Build a shaded uberjar containing all dependencies:

```sh
mvn clean package
```

### 2. Start the Storm cluster

```sh
docker compose up -d
```

This brings up five services:

| Service        | Description                  | Accessible at           |
|----------------|------------------------------|-------------------------|
| **Zookeeper**  | Coordination service         | internal only           |
| **Nimbus**     | Storm master node            | internal only           |
| **Supervisor** | Storm worker node            | internal only           |
| **UI**         | Storm web dashboard          | http://localhost:8080    |
| **URLFrontier**| URL queue / frontier service | localhost:7071 (gRPC)   |

> **Note:** This setup uses an **in-memory URLFrontier**. All queued URLs and crawl state will be lost when the Docker containers are stopped or restarted. For persistent storage, consult the [Apache StormCrawler documentation](https://stormcrawler.apache.org/).

### 3. Inject seed URLs

Before starting the crawl, inject seed URLs into URLFrontier using the bundled [URLFrontier client](https://github.com/crawler-commons/url-frontier/tree/master/client):

```sh
java -cp target/stormcrawler-warc-1.0-SNAPSHOT.jar \
  crawlercommons.urlfrontier.client.Client PutURLs -f seeds.txt
```

Edit `seeds.txt` to list the URLs you want to crawl (one per line).

### 4. Submit the crawl topology

Submit the Flux topology to the running Storm cluster:

```sh
docker run --network stormcrawler-warc_default -it \
  --rm \
  -v "$(pwd)/crawler-conf.yaml:/apache-storm/crawler-conf.yaml" \
  -v "$(pwd)/crawler.flux:/apache-storm/crawler.flux" \
  -v "$(pwd)/target/stormcrawler-warc-1.0-SNAPSHOT.jar:/apache-storm/stormcrawler-warc-1.0-SNAPSHOT.jar" \
  storm:3.1.0 \
  storm jar stormcrawler-warc-1.0-SNAPSHOT.jar org.apache.storm.flux.Flux --remote crawler.flux
```

> **Tip:** If you are unsure of the Docker network name, run `docker network ls` and adjust the `--network` parameter accordingly.

### 5. Monitor and collect results

- Monitor the crawl via the **Storm UI** at [http://localhost:8080](http://localhost:8080), where you can inspect the topology, check throughput, and rebalance workers.
- WARC files are written to the `./data/` directory on the host (mounted from the Storm supervisor container).

## Topology Overview

The crawl pipeline is defined declaratively in `crawler.flux` using [Storm Flux](https://storm.apache.org/releases/current/flux.html). There is no custom Java code; the topology is composed entirely of StormCrawler components:

```
URLFrontier Spout
       │
       ▼
 URLPartitioner
       │
       ▼
    Fetcher ──────────┐
       │              │ (status)
       ▼              ▼
  SiteMapParser ──► StatusUpdater ◄── (status from all parser bolts)
       │
       ▼
   FeedParser
       │
       ▼
  JSoupParser
       │
       ▼
  WARCHdfsBolt ──► ./data/  (WARC 1.1 output)
```

Status updates flow from the fetcher and each parser bolt back to the URLFrontier via the `StatusUpdaterBolt`, keeping the frontier informed about fetch outcomes and discovered URLs.

## Project Structure

| File / Directory               | Purpose                                                                 |
|--------------------------------|-------------------------------------------------------------------------|
| `crawler.flux`                 | Storm Flux topology definition (DAG, WARC output config, rotation policy) |
| `crawler-conf.yaml`            | StormCrawler configuration (fetch threads, HTTP agent, content limits, Tika) |
| `seeds.txt`                    | Seed URLs for crawling (one per line)                                   |
| `docker-compose.yml`           | Docker services: Zookeeper, Nimbus, Supervisor, UI, URLFrontier         |
| `src/main/resources/`          | Filter and normalizer configurations                                    |
| `├── urlfilters.json`          | URL filtering chain (depth, host/domain scope, regex)                   |
| `├── parsefilters.json`        | Parse filter configuration                                              |
| `├── jsoupfilters.json`        | JSoup-based HTML filter configuration                                   |
| `├── default-regex-filters.txt`| Regex patterns for URL inclusion/exclusion                              |
| `└── default-regex-normalizers.xml` | Regex-based URL normalization rules                                |
| `data/`                        | Output directory for WARC files (mounted into the supervisor container) |

## Configuration

Key settings in `crawler-conf.yaml`:

| Setting                    | Default          | Description                                            |
|----------------------------|------------------|--------------------------------------------------------|
| `fetcher.threads.number`   | 50               | Number of concurrent fetch threads                     |
| `http.content.limit`       | 65536 (64 KB)    | Max bytes per fetched page (`-1` to disable)           |
| `fetchInterval.default`    | 1440 (24h)       | Re-visit interval in minutes (`-1` to never revisit)   |
| `fetchInterval.fetch.error`| 120 (2h)         | Re-visit interval after fetch error                    |
| `fetchInterval.error`      | -1 (never)       | Re-visit interval after non-fetch error                |
| `urlfrontier.max.buckets`  | 50               | Max number of URL buckets from frontier per request     |
| `urlfrontier.max.urls.per.bucket` | 10        | Max URLs per bucket from frontier per request           |

WARC output settings in `crawler.flux`:

| Setting              | Default      | Description                                     |
|----------------------|--------------|-------------------------------------------------|
| Output path          | `/data/warc` | Directory inside the container (mapped to `./data/`) |
| File prefix          | `DEMO`       | Prefix for WARC filenames                       |
| Rotation policy      | 50 MB        | WARC files rotate when reaching this size       |

### Customizing the HTTP agent

Before using this crawler in any non-demo context, update the `http.agent.*` fields in `crawler-conf.yaml` and the WARCInfo header in `crawler.flux` with your actual contact information to comply with web crawling best practices and [RFC 9309](https://www.rfc-editor.org/rfc/rfc9309).

## Key Dependencies

| Dependency     | Version | Purpose                          |
|----------------|---------|----------------------------------|
| StormCrawler   | 4.0.0-SNAPSHOT | Core crawling framework (core, tika, urlfrontier, warc modules) |
| Apache Storm   | 3.1.0   | Distributed stream processing (`provided` scope — supplied by Docker) |
| URLFrontier    | 2.4     | URL queue management             |

## License

This project is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
