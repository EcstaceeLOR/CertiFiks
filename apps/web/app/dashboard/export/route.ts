import { NextResponse } from "next/server";
import {
  historyQuery,
  parseHistoryFilters,
  safePublicApiOrigin,
} from "../history.js";

export const dynamic = "force-dynamic";

export async function GET(request: Request): Promise<Response> {
  const search = new URL(request.url).searchParams;
  const params: Record<string, string> = {};
  for (const key of ["state", "repo", "sort", "offset"]) {
    const all = search.getAll(key);
    if (all.length > 1)
      return NextResponse.json({ error: "INVALID_FILTER" }, { status: 400 });
    if (all.length === 1) params[key] = all[0];
  }
  if (
    [...search.keys()].some(
      (key) => !["state", "repo", "sort", "offset"].includes(key),
    )
  ) {
    return NextResponse.json({ error: "INVALID_FILTER" }, { status: 400 });
  }
  const filters = parseHistoryFilters(params);
  if (!filters)
    return NextResponse.json({ error: "INVALID_FILTER" }, { status: 400 });
  const api = safePublicApiOrigin(process.env.CERTIFIKS_API_BASE_URL);
  if (!api)
    return NextResponse.json(
      { error: "PUBLIC_HISTORY_UNAVAILABLE" },
      { status: 503 },
    );
  const target = new URL("/v1/bounties/export.csv", api);
  target.search = historyQuery(filters);
  try {
    const reply = await fetch(target.href, {
      method: "GET",
      redirect: "error",
      cache: "no-store",
      signal: AbortSignal.timeout(8000),
    });
    if (
      !reply.ok ||
      !reply.headers.get("content-type")?.toLowerCase().startsWith("text/csv")
    ) {
      return NextResponse.json(
        { error: "PUBLIC_HISTORY_UNAVAILABLE" },
        { status: 503 },
      );
    }
    const bytes = await reply.arrayBuffer();
    if (bytes.byteLength > 128 * 1024) {
      return NextResponse.json(
        { error: "PUBLIC_HISTORY_UNAVAILABLE" },
        { status: 503 },
      );
    }
    return new Response(bytes, {
      headers: {
        "Content-Type": "text/csv; charset=utf-8",
        "Content-Disposition":
          'attachment; filename="certifiks-public-history.csv"',
        "Cache-Control": "private, no-store, max-age=0",
        "X-Content-Type-Options": "nosniff",
      },
    });
  } catch {
    return NextResponse.json(
      { error: "PUBLIC_HISTORY_UNAVAILABLE" },
      { status: 503 },
    );
  }
}
