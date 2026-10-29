name: "warc-crawler"

includes:
    - resource: true
      file: "/crawler-default.yaml"
      override: false

    - resource: false
      file: "crawler-conf.yaml"
      override: true

config:
  # use RawLocalFileSystem (instead of ChecksumFileSystem) to avoid that
  # WARC files are truncated if the topology is stopped because of a
  # delayed sync of the default ChecksumFileSystem
  warc: {"fs.file.impl": "org.apache.hadoop.fs.RawLocalFileSystem"}

components:
  - id: "WARCFileNameFormat"
    className: "org.apache.stormcrawler.warc.WARCFileNameFormat"
    configMethods:
      - name: "withPath"
        args:
          - "/data/warc"
      - name: "withPrefix"
        args:
          - "DEMO"
  - id: "WARCFileRotationPolicy"
    className: "org.apache.storm.hdfs.bolt.rotation.FileSizeRotationPolicy"
    constructorArgs:
      - 50.0
      - MB
  - id: "WARCInfo"
    className: "java.util.LinkedHashMap"
    configMethods:
      - name: "put"
        args:
         - "software"
         - "StormCrawler 4.0.0-SNAPSHOT"
      - name: "put"
        args:
         - "description"
         - "Crawling Crawling"
      - name: "put"
        args:
         - "http-header-user-agent"
         - "... Please insert your user-agent name"
      - name: "put"
        args:
         - "http-header-from"
         - "..."
      - name: "put"
        args:
         - "operator"
         - "..."
      - name: "put"
        args:
         - "robots"
         - "..."
      - name: "put"
        args:
         - "format"
         - "WARC File Format 1.1"
      - name: "put"
        args:
         - "conformsTo"
         - "https://iipc.github.io/warc-specifications/specifications/warc-format/warc-1.1/"

spouts:
  - id: "spout"
    className: "org.apache.stormcrawler.urlfrontier.Spout"
    parallelism: 1

bolts:
  - id: "partitioner"
    className: "org.apache.stormcrawler.bolt.URLPartitionerBolt"
    parallelism: 1
  - id: "fetcher"
    className: "org.apache.stormcrawler.bolt.FetcherBolt"
    parallelism: 1
  - id: "sitemap"
    className: "org.apache.stormcrawler.bolt.SiteMapParserBolt"
    parallelism: 1
  - id: "feed"
    className: "org.apache.stormcrawler.bolt.FeedParserBolt"
    parallelism: 1
  - id: "parse"
    className: "org.apache.stormcrawler.bolt.JSoupParserBolt"
    parallelism: 1
  - id: "index"
    className: "org.apache.stormcrawler.indexing.StdOutIndexer"
    parallelism: 1
  - id: "warc"
    className: "org.apache.stormcrawler.warc.WARCHdfsBolt"
    parallelism: 1
    configMethods:
      # use the "warc" config map above (RawLocalFileSystem)
      - name: "withConfigKey"
        args:
          - "warc"
      - name: "withFileNameFormat"
        args:
          - ref: "WARCFileNameFormat"
      - name: "withRotationPolicy"
        args:
          - ref: "WARCFileRotationPolicy"
      - name: "withRequestRecords"
      - name: "withHeader"
        args:
          - ref: "WARCInfo"
  - id: "status"
    className: "org.apache.stormcrawler.urlfrontier.StatusUpdaterBolt"
    parallelism: 1

streams:
  - from: "spout"
    to: "partitioner"
    grouping:
      type: SHUFFLE

  - from: "partitioner"
    to: "fetcher"
    grouping:
      type: FIELDS
      args: ["key"]

  - from: "fetcher"
    to: "sitemap"
    grouping:
      type: LOCAL_OR_SHUFFLE

  - from: "sitemap"
    to: "feed"
    grouping:
      type: LOCAL_OR_SHUFFLE

  - from: "feed"
    to: "parse"
    grouping:
      type: LOCAL_OR_SHUFFLE

  - from: "parse"
    to: "warc"
    grouping:
      type: LOCAL_OR_SHUFFLE

  - from: "fetcher"
    to: "status"
    grouping:
      type: FIELDS
      args: ["url"]
      streamId: "status"

  - from: "sitemap"
    to: "status"
    grouping:
      type: FIELDS
      args: ["url"]
      streamId: "status"
      
  - from: "feed"
    to: "status"
    grouping:
      type: FIELDS
      args: ["url"]
      streamId: "status"

  - from: "parse"
    to: "status"
    grouping:
      type: FIELDS
      args: ["url"]
      streamId: "status"
