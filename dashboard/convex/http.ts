import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";

const http = httpRouter();

const MISSING_AUTH = {
  status: 401,
  code: "CONVEX_AUTH_ERROR",
  body: "missing Authorization header",
};

const BAD_AUTH = {
  status: 401,
  code: "CONVEX_AUTH_ERROR",
  body: "invalid Authorization header",
};

const INVALID_JSON = {
  status: 400,
  code: "CONVEX_RESPONSE_INVALID",
  body: "invalid JSON body",
};

const INVALID_PAYLOAD = {
  status: 400,
  code: "CONVEX_RESPONSE_INVALID",
  body: "payload must be an object",
};

const VALIDATION_ERROR = {
  status: 422,
  code: "CONVEX_UPSERT_REJECTED",
  body: "status payload invalid",
};

const INTERNAL_ERROR = {
  status: 500,
  code: "HTTP_STATUS_5XX",
  body: "internal server error",
};

function parseBearer(authHeader: string | null): string | null {
  if (!authHeader) {
    return null;
  }
  const match = /^Bearer\s+(.+)$/.exec(authHeader.trim());
  return match?.[1] ?? null;
}

function asJsonResponse(payload: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function isValidationLikeError(message: string): boolean {
  const lower = message.toLowerCase();
  return (
    lower.includes("validation") ||
    lower.includes("invalid argument") ||
    lower.includes("snapshot_hash") ||
    lower.includes("schema") ||
    lower.includes("not found")
  );
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
      return asJsonResponse({ code: INVALID_JSON.code, error: INVALID_JSON.body }, INVALID_JSON.status);
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return asJsonResponse({ code: INVALID_PAYLOAD.code, error: INVALID_PAYLOAD.body }, INVALID_PAYLOAD.status);
    }

    try {
      const result = await ctx.runMutation(internal.status.upsertStatus, { payload });
      return asJsonResponse(result as Record<string, unknown>, 200);
    } catch (error) {
      const message = String(error);
      const lower = message.toLowerCase();
      if (lower.includes("authorization") || lower.includes("permission")) {
        return asJsonResponse({ code: CONVEX_AUTH_ERROR.code, error: BAD_AUTH.body }, BAD_AUTH.status);
      }

      if (isValidationLikeError(message)) {
        return asJsonResponse(
          {
            code: VALIDATION_ERROR.code,
            error: `${VALIDATION_ERROR.body}: ${message}`,
          },
          VALIDATION_ERROR.status,
        );
      }

      return asJsonResponse({ code: INTERNAL_ERROR.code, error: `${INTERNAL_ERROR.body}: ${message}` }, INTERNAL_ERROR.status);
    }
  },
});

export default http;
