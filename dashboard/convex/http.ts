import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";

const http = httpRouter();

const MISSING_AUTH = {
  status: 401,
  body: "missing Authorization header",
};

const BAD_AUTH = {
  status: 401,
  body: "invalid Authorization header",
};

function parseBearer(authHeader: string | null): string | null {
  if (!authHeader) {
    return null;
  }
  const match = /^Bearer\s+(.+)$/.exec(authHeader.trim());
  return match?.[1] ?? null;
}

http.route({
  path: "/status",
  method: "POST",
  handler: async (ctx: any, req: Request): Promise<Response> => {
    const expected = process.env.CONVEX_PUBLISH_SECRET;
    if (!expected) {
      return new Response("server misconfigured: missing CONVEX_PUBLISH_SECRET", { status: 500 });
    }

    const provided = parseBearer(req.headers.get("authorization"));
    if (!provided) {
      return new Response(MISSING_AUTH.body, { status: MISSING_AUTH.status });
    }
    if (provided !== expected) {
      return new Response(BAD_AUTH.body, { status: BAD_AUTH.status });
    }

    let payload: unknown;
    try {
      payload = await req.json();
    } catch {
      return new Response("invalid JSON body", { status: 400 });
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return new Response("payload must be an object", { status: 400 });
    }

    try {
      const result = await ctx.runMutation(internal.status.upsertStatus, { payload });
      return new Response(JSON.stringify(result), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    } catch (error) {
      return new Response(`failed to upsert status: ${String(error)}`, { status: 400 });
    }
  },
});

export default http;
