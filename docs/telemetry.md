# Anonymous usage telemetry

Fretwork has one optional telemetry signal: an `active_day` pulse, sent at
most once per UTC day and only after the player enables **Share anonymous usage
data** in Settings.

The app sends the current app version and three locally-derived, rotating
anonymous tokens. The Worker records:

| Stored field | Why |
| --- | --- |
| Timestamp | Daily trend |
| Daily token | Daily active installations |
| Weekly token | Weekly active installations |
| Monthly token | Monthly active installations |
| App version/build | Adoption of an update |
| Two-letter country code | Coarse regional demand |

The rotating tokens are SHA-256 hashes of a random local secret plus a UTC
calendar period. The secret never leaves the Mac. The analytics dataset never
records a durable installation ID, IP address, city, or coordinates. It
receives no microphone audio, detected notes/chords, practice history, device
IDs/names, or account data.

## Deployment

The app endpoint is `https://telemetry.fretwork.org/v1/active`. Before a
release offers the toggle, create a proxied `telemetry.fretwork.org` DNS record
in the existing Cloudflare zone, then deploy the Worker:

```bash
cd Telemetry
npx wrangler deploy --route 'telemetry.fretwork.org/v1/*'
```

`wrangler.toml` binds the Worker to a Workers Analytics Engine dataset named
`fretwork_usage`. The dataset is created on its first accepted pulse. Test the
endpoint after deployment with a malformed request first (it must return 400),
then a valid synthetic payload (it must return 204). Do not use a production
app's actual token in manual tests. The supplied report excludes the one
`synthetic-test (1)` validation event used during setup.

Add this plain-language disclosure to the website privacy policy before
release:

> If you choose to share anonymous usage data, Fretwork sends at most one
> activity record per day. It contains the app version and an approximate
> country inferred at our network edge. It never includes your audio, notes,
> practice history, audio-device information, identity, IP address, precise
> location, or a persistent installation identifier. You can turn this off at
> any time in Settings.

## Viewing the data

Create a Cloudflare API token restricted to **Account Analytics: Read**. Keep
it in the local shell only, then run:

```bash
export CF_ACCOUNT_ID='your Cloudflare account ID'
export CF_ANALYTICS_TOKEN='a read-only token'
./scripts/telemetry-report.sh
```

The script calls the Workers Analytics Engine SQL API and prints today, this
week, and this month, a 30-day daily trend, and current-month version and
country breakdowns. It does not change Cloudflare state. Analytics Engine keeps
these records for three months, so save only aggregate monthly totals elsewhere
if a longer trend is needed.
