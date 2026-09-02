#!/usr/bin/env bash
# Read-only report for Fretwork's first-party usage dataset. Create a
# Cloudflare token with Account Analytics:Read only; never put it in the app,
# Worker, git, or a GitHub Actions secret.
set -euo pipefail

: "${CF_ACCOUNT_ID:?Set CF_ACCOUNT_ID to the Cloudflare account ID}"
: "${CF_ANALYTICS_TOKEN:?Set CF_ANALYTICS_TOKEN to an Account Analytics:Read token}"

endpoint="https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/analytics_engine/sql"

query() {
  curl --fail --silent --show-error "$endpoint" \
    --header "Authorization: Bearer $CF_ANALYTICS_TOKEN" \
    --data-binary "$1" | jq -r '.data // .result // .'
}

echo "Active installs today (UTC)"
query "SELECT count(DISTINCT index1) AS active_installs
FROM fretwork_usage
WHERE timestamp >= toStartOfDay(NOW())
  AND blob1 != 'synthetic-test (1)'
FORMAT JSON"

echo
echo "Active installs this week (UTC)"
query "SELECT count(DISTINCT blob3) AS active_installs
FROM fretwork_usage
WHERE timestamp >= toStartOfWeek(NOW())
  AND blob1 != 'synthetic-test (1)'
FORMAT JSON"

echo
echo "Active installs this month (UTC)"
query "SELECT count(DISTINCT blob4) AS active_installs
FROM fretwork_usage
WHERE timestamp >= toStartOfMonth(NOW())
  AND blob1 != 'synthetic-test (1)'
FORMAT JSON"

echo
echo "30-day daily trend"
query "SELECT
  toDate(timestamp) AS day,
  count(DISTINCT index1) AS active_installs
FROM fretwork_usage
WHERE timestamp >= NOW() - INTERVAL '30' DAY
  AND blob1 != 'synthetic-test (1)'
GROUP BY day
ORDER BY day
FORMAT JSON"

echo
echo "Current-month active installs by country"
query "SELECT
  blob2 AS country,
  count(DISTINCT blob4) AS active_installs
FROM fretwork_usage
WHERE timestamp >= toStartOfMonth(NOW())
  AND blob1 != 'synthetic-test (1)'
GROUP BY country
ORDER BY active_installs DESC
FORMAT JSON"

echo
echo "Current-month active installs by version"
query "SELECT
  blob1 AS version,
  count(DISTINCT blob4) AS active_installs
FROM fretwork_usage
WHERE timestamp >= toStartOfMonth(NOW())
  AND blob1 != 'synthetic-test (1)'
GROUP BY version
ORDER BY active_installs DESC
FORMAT JSON"
