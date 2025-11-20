# Allure ClickHouse Exporter

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)

A powerful tool for exporting Allure test results to ClickHouse database and visualizing test statistics through Grafana dashboards.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Grafana Dashboard](#grafana-dashboard)
- [Configuration](#configuration)
- [Examples](#examples)
- [Contributing](#contributing)

## 🎯 Overview

**Allure ClickHouse Exporter** is designed to streamline the process of collecting, storing, and analyzing test execution data. It automatically:

- Scans directories for Allure JSON result files (`*result.json`)
- Merges multiple test result files into a single dataset
- Enriches data with project metadata and upload timestamps
- Exports data to ClickHouse for efficient storage and querying
- Provides comprehensive Grafana dashboards for visualization

### Project Structure

```
allure-clickhouse-exporter/
├── README.md                    # This file
├── script/
│   └── export.sh               # Main export script
└── dashboard/
    └── allure-statistic.json    # Grafana dashboard configuration
```

## ✨ Features

- 🚀 **Efficient Export**: Uses ClickHouse HTTP API with JSONEachRow format
- 📈 **Rich Dashboards**: Pre-configured Grafana dashboards with multiple visualizations
- ⚡ **Error Handling**: Comprehensive error checking and informative messages
- 🧹 **Auto Cleanup**: Automatically removes temporary files after successful export

## 📦 Prerequisites

- **Bash**
- **ClickHouse** (accessible via HTTP)
- **curl** command-line tool
- **Grafana** (optional, for visualization)
- **[ClickHouse Grafana Plugin](https://github.com/grafana/clickhouse-datasource)**

## 🚀 Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/allure-clickhouse-exporter.git
cd allure-clickhouse-exporter
```

2. Make the script executable:
```bash
chmod +x script/export.sh
```

3. Ensure you have a ClickHouse table ready. You need to create a `test_results` table in your ClickHouse database. See the [ClickHouse Table Schema](#clickhouse-table-schema) section below for the complete SQL script to create the table.

## 💻 Usage

### Basic Usage

```bash
./script/export.sh \
  --dir /path/to/allure/results \
  --url http://localhost:8123 \
  -u clickhouse_user \
  -p clickhouse_password \
  -d default \
  --project MyProject
```

### Command-Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `--dir` | Directory containing Allure result files (`*result.json`) | ✅ |
| `--url` | ClickHouse server URL (e.g., `http://localhost:8123`) | ✅ |
| `-u` | ClickHouse username | ✅ |
| `-p` | ClickHouse password | ✅ |
| `-d` | ClickHouse database name | ✅ |
| `--project` | Project name to tag the test results | ✅ |
| `-h` | Show help message | ❌ |

**Note**: The table name is hardcoded as `test_results` in the script. Make sure you have created this table in your ClickHouse database (see [ClickHouse Table Schema](#clickhouse-table-schema)).

### Help

To see the help message:

```bash
./script/export.sh -h
```

## 📊 Grafana Dashboard

The project includes a pre-configured Grafana dashboard (`dashboard/allure-statistic.json`) that provides:

### Dashboard Features

- **Total Statistics**: Overview of all test results
  - Number of executed tests by status (passed, failed, broken, skipped, unknown)
  - Success rate percentage
  - Projects pass rate comparison

- **Project-Specific Statistics**: Detailed metrics per project
  - Test execution counts
  - Average test duration
  - Status distribution (pie charts)
  - Historical trends

- **Host-Based Analytics**: Performance metrics by execution host
  - Running tests history
  - Test duration trends

- **Advanced Filtering**:
  - Filter by project
  - Filter by test status
  - Filter by Allure tags
  - Filter by host
  - Time range selection

### Importing the Dashboard

1. Open Grafana
2. Configure your ClickHouse datasource
3. Import `dashboard/allure-statistic.json`
4. Select the datasource

### Dashboard Variables

The dashboard uses the following variables:
- `$Project` - Filter by project name
- `$Status` - Filter by test status
- `$Tag` - Filter by Allure tags
- `$Host` - Filter by execution host
- `$Datasource` - ClickHouse datasource
- `$TZ` - Timezone (default: Europe/Moscow)

## ⚙️ Configuration

Before using the exporter, you need to create a table in ClickHouse. Execute the following SQL script to create the `test_results` table:

```sql
CREATE TABLE test_results
(
    `project` String,
    `upload_time` DateTime,
    `uuid` UUID,
    `historyId` String,
    `testCaseId` String,
    `testCaseName` String,
    `fullName` String,
    `name` String,
    `status` Enum8('passed' = 1, 'failed' = 2, 'broken' = 3, 'skipped' = 4, 'unknown' = 5),
    `stage` Enum8('scheduled' = 1, 'running' = 2, 'finished' = 3, 'interrupted' = 4, 'pending' = 5),
    `description` String,
    `steps` Array(JSON),
    `start` UInt64,
    `stop` UInt64,
    `stop_datetime` DateTime MATERIALIZED toDateTime(stop / 1000),
    `links` Array(JSON),
    `labels` Array(Tuple(name String, value String)),
    `label_tag` Array(String) MATERIALIZED arrayFilter(x -> x.1 = 'tag', labels).2,
    `label_host` String MATERIALIZED arrayFirst(x -> x.1 = 'host', labels).2,
    `statusDetails` Tuple(
        flaky Nullable(Bool),
        known Nullable(Bool),
        message Nullable(String),
        muted Nullable(Bool),
        trace Nullable(String)),
    `attachments` Array(JSON),
    `parameters` Array(JSON)
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(stop_datetime)
ORDER BY (label_host, stop_datetime, project, uuid)
TTL stop_datetime + toIntervalYear(1)
SETTINGS index_granularity = 8192;
```

## 📝 Examples

### Example: Export Test Results

```bash
./script/export.sh \
  --dir ./allure-results \
  --url http://clickhouse.example.com:8123 \
  -u admin \
  -p secure_password \
  -d test_db \
  --project "E2E Tests"
```
## 🔍 How It Works

1. **File Discovery**: The script recursively searches for all files matching `*result.json` in the specified directory
2. **Data Enrichment**: Each JSON file is enriched with:
   - `project`: The project name provided via `--project`
   - `upload_time`: Current UTC timestamp
3. **Merging**: All enriched JSON objects are combined into a single temporary file
4. **Export**: The merged data is sent to ClickHouse via HTTP POST using the JSONEachRow format
5. **Cleanup**: Temporary files are automatically removed after successful export

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Allure Framework](https://github.com/allure-framework/allure2) for test reporting
- [ClickHouse](https://clickhouse.com/) for powerful analytics database
- [Grafana](https://grafana.com/) for beautiful visualizations

---