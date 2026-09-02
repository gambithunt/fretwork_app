interface Env {
  USAGE: AnalyticsEngineDataset;
}

interface ActivePayload {
  schema: 1;
  dayToken: string;
  weekToken: string;
  monthToken: string;
  version: string;
}

const tokenPattern = /^[a-f0-9]{64}$/;
const versionPattern = /^[A-Za-z0-9 .()_-]{1,80}$/;

export default {
  async fetch(request, env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/v1/active") {
      return new Response("Not found", { status: 404 });
    }
    if (Number(request.headers.get("content-length") ?? 0) > 512) {
      return new Response("Payload too large", { status: 413 });
    }

    let payload: unknown;
    try {
      payload = await request.json();
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }
    if (!isActivePayload(payload)) {
      return new Response("Invalid payload", { status: 400 });
    }

    // The client never sends a location. Cloudflare has already derived this
    // coarse country code from the connecting IP at the edge; only the code is
    // written to the analytics dataset, never the IP or a city/coordinates.
    const country = countryCode(request.cf?.country);
    env.USAGE.writeDataPoint({
      indexes: [payload.dayToken],
      blobs: [payload.version, country, payload.weekToken, payload.monthToken],
      doubles: [],
    });

    return new Response(null, {
      status: 204,
      headers: { "Cache-Control": "no-store" },
    });
  },
} satisfies ExportedHandler<Env>;

function isActivePayload(value: unknown): value is ActivePayload {
  if (typeof value !== "object" || value === null) return false;
  const payload = value as Record<string, unknown>;
  return payload.schema === 1
    && typeof payload.dayToken === "string" && tokenPattern.test(payload.dayToken)
    && typeof payload.weekToken === "string" && tokenPattern.test(payload.weekToken)
    && typeof payload.monthToken === "string" && tokenPattern.test(payload.monthToken)
    && typeof payload.version === "string" && versionPattern.test(payload.version);
}

function countryCode(value: unknown): string {
  return typeof value === "string" && /^[A-Z]{2}$/.test(value) ? value : "ZZ";
}
