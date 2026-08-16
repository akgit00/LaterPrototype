// Supabase Edge Function: send-push
//
// Sends APNs alert notifications to the device tokens of the given app users.
// Called by the iOS app after user actions (new message, friend request,
// shared memory, new comment). The caller must be a signed-in app user.
//
// Required function secrets (Dashboard -> Edge Functions -> send-push -> Secrets):
//   APNS_AUTH_KEY  - full contents of the .p8 APNs auth key from Apple
//   APNS_KEY_ID    - the 10-character key id shown next to that key
//   APNS_TEAM_ID   - your Apple Developer team id (e.g. NEHAJYAD3L)
//   APNS_TOPIC     - optional, defaults to app.laterprototype (the bundle id)

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
// Secrets pasted through the dashboard sometimes arrive with literal "\n".
const APNS_AUTH_KEY = (Deno.env.get("APNS_AUTH_KEY") ?? "").replace(/\\n/g, "\n");
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_TOPIC = Deno.env.get("APNS_TOPIC") ?? "app.laterprototype";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface PushRequest {
  recipients: string[];
  title: string;
  body: string;
  threadId?: string;
}

interface TokenRow {
  user_id: string;
  device_token: string;
}

// --- APNs provider JWT (ES256), reused for 40 minutes ---

let cachedJWT: { value: string; issuedAt: number } | null = null;

function base64URL(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function apnsJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 40 * 60) return cachedJWT.value;

  const pem = APNS_AUTH_KEY
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const enc = new TextEncoder();
  const header = base64URL(enc.encode(JSON.stringify({ alg: "ES256", kid: APNS_KEY_ID })));
  const payload = base64URL(enc.encode(JSON.stringify({ iss: APNS_TEAM_ID, iat: now })));
  const unsigned = `${header}.${payload}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    enc.encode(unsigned),
  );
  const jwt = `${unsigned}.${base64URL(new Uint8Array(signature))}`;
  cachedJWT = { value: jwt, issuedAt: now };
  return jwt;
}

// --- push_tokens table access (service role, bypasses RLS) ---

async function fetchTokens(userIDs: string[]): Promise<TokenRow[]> {
  const list = userIDs.join(",");
  const url = `${SUPABASE_URL}/rest/v1/push_tokens?user_id=in.(${list})&select=user_id,device_token`;
  const res = await fetch(url, {
    headers: { apikey: SERVICE_ROLE_KEY, authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
  if (!res.ok) throw new Error(`token lookup failed (${res.status})`);
  return await res.json();
}

/** Removes a token APNs reported as permanently dead. */
async function deleteToken(token: string): Promise<void> {
  const url = `${SUPABASE_URL}/rest/v1/push_tokens?device_token=eq.${encodeURIComponent(token)}`;
  await fetch(url, {
    method: "DELETE",
    headers: { apikey: SERVICE_ROLE_KEY, authorization: `Bearer ${SERVICE_ROLE_KEY}` },
  });
}

// --- APNs delivery ---

/**
 * Sends one alert to one device. TestFlight/App Store tokens live on the
 * production host; tokens minted by Xcode debug builds only work against the
 * sandbox host, so BadDeviceToken on production falls through to sandbox.
 */
async function sendToDevice(
  token: string,
  title: string,
  body: string,
  threadId: string | undefined,
  jwt: string,
): Promise<"sent" | "failed"> {
  const payload = {
    aps: {
      alert: { title, body },
      sound: "default",
      ...(threadId ? { "thread-id": threadId } : {}),
    },
    ...(threadId ? { threadId } : {}),
  };

  for (const host of ["api.push.apple.com", "api.sandbox.push.apple.com"]) {
    const res = await fetch(`https://${host}/3/device/${token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": APNS_TOPIC,
        "apns-push-type": "alert",
        "apns-priority": "10",
      },
      body: JSON.stringify(payload),
    });

    if (res.ok) return "sent";

    const text = await res.text();
    let reason = "";
    try {
      reason = JSON.parse(text).reason ?? "";
    } catch {
      // not JSON, keep raw text for logging
    }

    if (res.status === 410 || reason === "Unregistered") {
      await deleteToken(token);
      return "failed";
    }
    if (reason === "BadDeviceToken") continue; // wrong environment, try sandbox

    console.error(`APNs ${res.status} (${reason || text}) via ${host}`);
    return "failed";
  }
  return "failed";
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return Response.json({ error: "POST only" }, { status: 405 });
  }
  if (!APNS_AUTH_KEY || !APNS_KEY_ID || !APNS_TEAM_ID) {
    return Response.json(
      { error: "APNs secrets not configured (APNS_AUTH_KEY / APNS_KEY_ID / APNS_TEAM_ID)" },
      { status: 500 },
    );
  }

  // Only signed-in app users may trigger pushes.
  const authHeader = req.headers.get("authorization") ?? "";
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, authorization: authHeader },
  });
  if (!userRes.ok) {
    return Response.json({ error: "not authenticated" }, { status: 401 });
  }
  const caller: { id: string } = await userRes.json();

  let body: PushRequest;
  try {
    body = await req.json();
  } catch {
    return Response.json({ error: "invalid JSON" }, { status: 400 });
  }

  // Normalize, dedupe, drop the caller themselves, and cap the fan-out.
  const recipients = [
    ...new Set(
      (body.recipients ?? [])
        .map((r) => String(r).toLowerCase().trim())
        .filter((r) => UUID_RE.test(r) && r !== caller.id),
    ),
  ].slice(0, 100);
  const title = String(body.title ?? "").slice(0, 120);
  const text = String(body.body ?? "").slice(0, 500);
  const threadId = body.threadId ? String(body.threadId).toLowerCase() : undefined;

  if (recipients.length === 0 || !title || !text) {
    return Response.json({ sent: 0, failed: 0, note: "nothing to send" });
  }

  const rows = await fetchTokens(recipients);
  if (rows.length === 0) {
    return Response.json({ sent: 0, failed: 0, note: "no registered devices" });
  }

  const jwt = await apnsJWT();
  const results = await Promise.all(
    rows.map((row) => sendToDevice(row.device_token, title, text, threadId, jwt)),
  );
  const sent = results.filter((r) => r === "sent").length;
  return Response.json({ sent, failed: results.length - sent });
});
