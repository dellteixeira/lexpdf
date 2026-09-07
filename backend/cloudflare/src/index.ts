export interface Env {
  ENVIRONMENT: string;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  SUPABASE_SECRET_KEY?: string;
  MAX_UPLOAD_BYTES?: string;
  DOCUMENTS: R2Bucket;
  SYNC_QUEUE?: Queue<SyncMessage>;
}

type SyncMessage = {
  userId: string;
  operation: "upload" | "replace" | "delete" | "metadata";
  key: string;
  at: string;
  requestId: string;
};

type AuthUser = { id: string; email?: string };

const DEFAULT_MAX_UPLOAD_BYTES = 250 * 1024 * 1024;
const MAX_LIST_LIMIT = 1000;

class UploadLimitExceededError extends Error {
  constructor(readonly maxBytes: number) {
    super(`Upload exceeded the configured limit of ${maxBytes} bytes.`);
    this.name = "UploadLimitExceededError";
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestId = request.headers.get("cf-ray") ?? crypto.randomUUID();
    try {
      return await route(request, env, requestId);
    } catch (error) {
      console.error("lexpdf_worker_error", { requestId, error: String(error) });
      return json({ error: "internal_error", requestId }, 500, requestId);
    }
  },

  async queue(batch: MessageBatch<SyncMessage>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      try {
        await persistBackendEvent(env, message.body);
        message.ack();
      } catch (error) {
        console.error("lexpdf_queue_error", {
          messageId: message.id,
          error: String(error),
        });
        message.retry();
      }
    }
  },
};

async function route(request: Request, env: Env, requestId: string): Promise<Response> {
  const url = new URL(request.url);
  if (url.pathname === "/health") {
    return json({ service: "lexpdf-api", status: "ok", environment: env.ENVIRONMENT ?? "unknown", r2: Boolean(env.DOCUMENTS), queue: Boolean(env.SYNC_QUEUE) }, 200, requestId);
  }
  if (!url.pathname.startsWith("/v1/cloud/")) return json({ error: "not_found" }, 404, requestId);

  const user = await authenticate(request, env);
  if (!user) return json({ error: "unauthorized" }, 401, requestId);

  const match = url.pathname.match(/^\/v1\/cloud\/([^/]+)\/files(?:\/([^/]+))?(?:\/(content))?$/);
  if (!match) return json({ error: "not_found" }, 404, requestId);
  const provider = match[1];
  const fileId = match[2] ? safeSegment(decodeURIComponent(match[2])) : null;
  const content = match[3] === "content";

  if (provider !== "r2") {
    return json({ error: "provider_not_configured", provider, message: "OAuth credentials for this provider must be configured before the gateway can proxy it." }, 501, requestId);
  }

  const account = safeSegment(url.searchParams.get("account") ?? "default");
  const prefix = `${user.id}/${account}/`;

  if (!fileId && request.method === "GET") {
    const requestedLimit = Number.parseInt(url.searchParams.get("limit") ?? "100", 10);
    const limit = Number.isFinite(requestedLimit) ? Math.max(1, Math.min(requestedLimit, MAX_LIST_LIMIT)) : 100;
    const cursor = url.searchParams.get("cursor") ?? undefined;
    const listed = await env.DOCUMENTS.list({ prefix, limit, cursor });
    return json({
      items: listed.objects.map((object) => ({ id: object.key.substring(prefix.length), remoteId: object.key.substring(prefix.length), name: object.customMetadata?.name ?? object.key.split("/").pop(), remotePath: object.key, size: object.size, version: object.etag, uploaded: object.uploaded.toISOString() })),
      truncated: listed.truncated,
      cursor: listed.truncated ? listed.cursor : null,
    }, 200, requestId);
  }

  if (!fileId && request.method === "POST") {
    const bodyError = validateUploadRequest(request, env);
    if (bodyError) return json({ error: bodyError }, uploadErrorStatus(bodyError), requestId);
    const name = safeFileName(url.searchParams.get("name") ?? "document.pdf");
    const id = crypto.randomUUID();
    const key = `${prefix}${id}`;
    try {
      const object = await env.DOCUMENTS.put(key, boundedUploadBody(request, env), { httpMetadata: { contentType: "application/pdf" }, customMetadata: { name } });
      await enqueue(env, user.id, "upload", key, requestId);
      return json({ id, remoteId: id, name, remotePath: key, version: object?.etag }, 201, requestId);
    } catch (error) {
      if (isUploadLimitExceeded(error)) return json({ error: "payload_too_large" }, 413, requestId);
      throw error;
    }
  }

  if (!fileId) return json({ error: "method_not_allowed" }, 405, requestId);
  const key = `${prefix}${fileId}`;

  if (content && request.method === "GET") {
    const object = await env.DOCUMENTS.get(key);
    if (!object) return json({ error: "not_found" }, 404, requestId);
    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set("etag", object.httpEtag);
    headers.set("x-request-id", requestId);
    headers.set("cache-control", "private, no-store");
    return new Response(object.body, { headers });
  }

  if (content && request.method === "PUT") {
    const bodyError = validateUploadRequest(request, env);
    if (bodyError) return json({ error: bodyError }, uploadErrorStatus(bodyError), requestId);
    const current = await env.DOCUMENTS.head(key);
    if (!current) return json({ error: "not_found" }, 404, requestId);
    const expectedEtag = request.headers.get("if-match");
    if (expectedEtag && stripQuotes(expectedEtag) !== stripQuotes(current.httpEtag)) {
      return json({ error: "version_conflict", currentVersion: current.etag }, 409, requestId);
    }
    try {
      const object = await env.DOCUMENTS.put(key, boundedUploadBody(request, env), { httpMetadata: { contentType: "application/pdf" }, customMetadata: current.customMetadata });
      await enqueue(env, user.id, "replace", key, requestId);
      return json({ id: fileId, remoteId: fileId, name: current.customMetadata?.name ?? fileId, remotePath: key, version: object?.etag }, 200, requestId);
    } catch (error) {
      if (isUploadLimitExceeded(error)) return json({ error: "payload_too_large" }, 413, requestId);
      throw error;
    }
  }

  if (!content && request.method === "GET") {
    const object = await env.DOCUMENTS.head(key);
    if (!object) return json({ error: "not_found" }, 404, requestId);
    return json({ id: fileId, remoteId: fileId, name: object.customMetadata?.name ?? fileId, remotePath: key, size: object.size, version: object.etag }, 200, requestId);
  }

  if (!content && request.method === "DELETE") {
    const current = await env.DOCUMENTS.head(key);
    if (!current) return json({ error: "not_found" }, 404, requestId);
    await env.DOCUMENTS.delete(key);
    await enqueue(env, user.id, "delete", key, requestId);
    return new Response(null, { status: 204, headers: { "x-request-id": requestId } });
  }

  if (!content && request.method === "PATCH") {
    const body = (await request.json()) as { name?: string; parentId?: string };
    if (body.parentId != null && body.parentId.trim() !== "") {
      return json({ error: "folders_not_supported_for_r2" }, 400, requestId);
    }
    const current = await env.DOCUMENTS.get(key);
    if (!current) return json({ error: "not_found" }, 404, requestId);
    const name = safeFileName(body.name ?? current.customMetadata?.name ?? fileId);
    const object = await env.DOCUMENTS.put(key, current.body, { httpMetadata: current.httpMetadata, customMetadata: { ...current.customMetadata, name } });
    await enqueue(env, user.id, "metadata", key, requestId);
    return json({ id: fileId, remoteId: fileId, name, remotePath: key, version: object?.etag }, 200, requestId);
  }

  return json({ error: "method_not_allowed" }, 405, requestId);
}

async function authenticate(request: Request, env: Env): Promise<AuthUser | null> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  if (!env.SUPABASE_URL || !env.SUPABASE_PUBLISHABLE_KEY) return null;
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, { headers: { authorization, apikey: env.SUPABASE_PUBLISHABLE_KEY } });
  if (!response.ok) return null;
  const value = (await response.json()) as AuthUser;
  return value?.id ? value : null;
}

function validateUploadRequest(request: Request, env: Env): string | null {
  if (!request.body) return "empty_body";
  const max = maxUploadBytes(env);
  const rawLength = request.headers.get("content-length");
  if (rawLength) {
    const length = Number.parseInt(rawLength, 10);
    if (!Number.isFinite(length) || length < 1 || length > max) return "payload_too_large";
  }
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (contentType && !contentType.startsWith("application/pdf") && !contentType.startsWith("application/octet-stream")) return "unsupported_media_type";
  return null;
}

function maxUploadBytes(env: Env): number {
  return parsePositiveInt(env.MAX_UPLOAD_BYTES) ?? DEFAULT_MAX_UPLOAD_BYTES;
}

function boundedUploadBody(request: Request, env: Env): ReadableStream<Uint8Array> {
  const body = request.body;
  if (!body) throw new Error("Upload body is required.");
  const reader = body.getReader();
  const max = maxUploadBytes(env);
  let bytesSeen = 0;

  return new ReadableStream<Uint8Array>({
    async pull(controller) {
      try {
        const { done, value } = await reader.read();
        if (done) {
          controller.close();
          return;
        }
        const chunk = value as Uint8Array;
        bytesSeen += chunk.byteLength;
        if (bytesSeen > max) {
          await reader.cancel("payload_too_large").catch(() => undefined);
          controller.error(new UploadLimitExceededError(max));
          return;
        }
        controller.enqueue(chunk);
      } catch (error) {
        controller.error(error);
      }
    },
    async cancel(reason) {
      await reader.cancel(reason).catch(() => undefined);
    },
  });
}

function isUploadLimitExceeded(error: unknown): boolean {
  return error instanceof UploadLimitExceededError || (error instanceof Error && error.name === "UploadLimitExceededError");
}

function uploadErrorStatus(error: string): number {
  if (error === "unsupported_media_type") return 415;
  if (error === "empty_body") return 400;
  return 413;
}

async function enqueue(env: Env, userId: string, operation: SyncMessage["operation"], key: string, requestId: string): Promise<void> {
  if (!env.SYNC_QUEUE) return;
  await env.SYNC_QUEUE.send({ userId, operation, key, at: new Date().toISOString(), requestId });
}

async function persistBackendEvent(env: Env, event: SyncMessage): Promise<void> {
  const secret = env.SUPABASE_SECRET_KEY;
  if (!secret) {
    console.warn("lexpdf_queue_event_not_persisted", { reason: "SUPABASE_SECRET_KEY_not_configured", requestId: event.requestId });
    return;
  }
  const response = await fetch(`${env.SUPABASE_URL}/rest/v1/backend_events`, {
    method: "POST",
    headers: { apikey: secret, authorization: `Bearer ${secret}`, "content-type": "application/json", prefer: "return=minimal" },
    body: JSON.stringify({ user_id: event.userId, source: "cloudflare_queue", event_type: event.operation, object_key: event.key, payload: { at: event.at, requestId: event.requestId } }),
  });
  if (!response.ok) throw new Error(`Supabase backend event insert failed: ${response.status}`);
}

function safeSegment(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9._-]+/g, "_").slice(0, 180);
  return safe || "default";
}

function safeFileName(value: string): string {
  const safe = value.replace(/[\\/\u0000-\u001f]+/g, "_").trim().slice(0, 240);
  return safe || "document.pdf";
}

function stripQuotes(value: string): string {
  return value.replace(/^W\//, "").replace(/^"|"$/g, "");
}

function parsePositiveInt(value?: string): number | null {
  if (!value) return null;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

function json(value: unknown, status = 200, requestId?: string): Response {
  const headers = new Headers({ "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  if (requestId) headers.set("x-request-id", requestId);
  return new Response(JSON.stringify(value), { status, headers });
}
