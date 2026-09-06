export interface Env {
  ENVIRONMENT: string;
}

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

    return Response.json(
      { error: "not_found" },
      { status: 404 },
    );
  },
};
