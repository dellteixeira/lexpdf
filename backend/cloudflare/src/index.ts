export interface Env {
  ENVIRONMENT: string;
  SUPABASE_URL: string;
  SUPABASE_PUBLISHABLE_KEY: string;
  DOCUMENTS: R2Bucket;
  SYNC_QUEUE?: Queue<SyncMessage>;
}

type SyncMessage = {
  userId: string;
  operation: string;
  key: string;
  at: string;
};

type AuthUser = { id: string; email?: string };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      return Response.json({
        service: "lexpdf-api",
        status: "ok",
        environment: env.ENVIRONMENT ?? "unknown",
      });
    }

    if (!url.pathname.startsWith("/v1/cloud/")) {
      return json({ error: "not_found" }, 404);
    }

    const user = await authenticate(request, env);
    if (!user) return json({ error: "unauthorized" }, 401);

    const match = url.pathname.match(
      /^\/v1\/cloud\/([^/]+)\/files(?:\/([^/]+))?(?:\/(content))?$/,
    );
    if (!match) return json({ error: "not_found" }, 404);
    const provider = match[1];
    const fileId = match[2] ? decodeURIComponent(match[2]) : null;
    const content = match[3] === "content";

    if (provider !== "r2") {
      return json(
        {
          error: "provider_not_configured",
          provider,
          message:
            "OAuth credentials for this provider must be configured before the gateway can proxy it.",
        },
        501,
      );
    }

    const account = url.searchParams.get("account") ?? "default";
    const prefix = `${user.id}/${safeSegment(account)}/`;

    if (!fileId && request.method === "GET") {
      const listed = await env.DOCUMENTS.list({ prefix, limit: 1000 });
      return Response.json(
        listed.objects.map((object) => ({
          id: object.key.substring(prefix.length),
          remoteId: object.key.substring(prefix.length),
          name: object.customMetadata?.name ?? object.key.split("/").pop(),
          remotePath: object.key,
          size: object.size,
          version: object.etag,
          uploaded: object.uploaded.toISOString(),
        })),
      );
    }

    if (!fileId && request.method === "POST") {
      const name = url.searchParams.get("name") ?? "document.pdf";
      const id = crypto.randomUUID();
      const key = `${prefix}${id}`;
      const object = await env.DOCUMENTS.put(key, request.body, {
        httpMetadata: { contentType: "application/pdf" },
        customMetadata: { name },
      });
      await enqueue(env, user.id, "upload", key);
      return Response.json({
        id,
        remoteId: id,
        name,
        remotePath: key,
        version: object?.etag,
      });
    }

    if (!fileId) return json({ error: "method_not_allowed" }, 405);
    const key = `${prefix}${safeSegment(fileId)}`;

    if (content && request.method === "GET") {
      const object = await env.DOCUMENTS.get(key);
      if (!object) return json({ error: "not_found" }, 404);
      const headers = new Headers();
      object.writeHttpMetadata(headers);
      headers.set("etag", object.httpEtag);
      return new Response(object.body, { headers });
    }

    if (!content && request.method === "GET") {
      const object = await env.DOCUMENTS.head(key);
      if (!object) return json({ error: "not_found" }, 404);
      return Response.json({
        id: fileId,
        remoteId: fileId,
        name: object.customMetadata?.name ?? fileId,
        remotePath: key,
        size: object.size,
        version: object.etag,
      });
    }

    if (!content && request.method === "DELETE") {
      await env.DOCUMENTS.delete(key);
      await enqueue(env, user.id, "delete", key);
      return new Response(null, { status: 204 });
    }

    if (!content && request.method === "PATCH") {
      const body = (await request.json()) as { name?: string; parentId?: string };
      const current = await env.DOCUMENTS.get(key);
      if (!current) return json({ error: "not_found" }, 404);
      const name = body.name ?? current.customMetadata?.name ?? fileId;
      await env.DOCUMENTS.put(key, current.body, {
        httpMetadata: current.httpMetadata,
        customMetadata: { ...current.customMetadata, name },
      });
      await enqueue(env, user.id, "metadata", key);
      return Response.json({ id: fileId, remoteId: fileId, name, remotePath: key });
    }

    return json({ error: "method_not_allowed" }, 405);
  },

  async queue(batch: MessageBatch<SyncMessage>): Promise<void> {
    for (const message of batch.messages) {
      // This consumer is deliberately idempotent: R2 mutations already completed
      // before enqueue. Future heavy post-processing can be added here.
      message.ack();
    }
  },
};

async function authenticate(request: Request, env: Env): Promise<AuthUser | null> {
  const authorization = request.headers.get("authorization");
  if (!authorization?.startsWith("Bearer ")) return null;
  const response = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: {
      authorization,
      apikey: env.SUPABASE_PUBLISHABLE_KEY,
    },
  });
  if (!response.ok) return null;
  const value = (await response.json()) as AuthUser;
  return value?.id ? value : null;
}

async function enqueue(
  env: Env,
  userId: string,
  operation: string,
  key: string,
): Promise<void> {
  if (!env.SYNC_QUEUE) return;
  await env.SYNC_QUEUE.send({
    userId,
    operation,
    key,
    at: new Date().toISOString(),
  });
}

function safeSegment(value: string): string {
  return value.replace(/[^A-Za-z0-9._-]+/g, "_");
}

function json(value: unknown, status = 200): Response {
  return Response.json(value, { status });
}
