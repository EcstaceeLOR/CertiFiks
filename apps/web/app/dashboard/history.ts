export const PUBLIC_STATES = [
  "funded",
  "assigned",
  "submitted",
  "verifying",
  "review",
  "disputed",
  "payable",
  "settled",
  "refunded",
] as const;

export const PUBLIC_SORTS = ["newest", "oldest", "repository"] as const;
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;
const DECIMAL = /^(0|[1-9][0-9]*)$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;

export interface PublicHistoryItem {
  bountyId: string;
  repositoryId: string;
  repositoryFullName: string;
  chainId: string;
  onchainBountyId: string;
  rewardAtoms: string;
  manifestDigest: string;
  state: string;
  createdAt: string;
  verificationProven: false;
}

export interface HistoryFilters {
  state: string;
  repo: string;
  sort: (typeof PUBLIC_SORTS)[number];
  offset: number;
}

export type HistoryResult =
  | { kind: "invalid" }
  | { kind: "unavailable" }
  | { kind: "available"; items: PublicHistoryItem[] };

export function safePublicApiOrigin(value: string | undefined): URL | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    const local =
      process.env.NODE_ENV !== "production" &&
      url.protocol === "http:" &&
      ["localhost", "127.0.0.1"].includes(url.hostname);
    if (
      (!local && url.protocol !== "https:") ||
      url.username ||
      url.password ||
      url.search ||
      url.hash
    )
      return null;
    return url;
  } catch {
    return null;
  }
}

function stringQuery(value: string | string[] | undefined): string | null {
  return typeof value === "string" ? value : value === undefined ? "" : null;
}

export function parseHistoryFilters(
  search: Record<string, string | string[] | undefined>,
): HistoryFilters | null {
  const state = stringQuery(search.state);
  const repo = stringQuery(search.repo);
  const sort = stringQuery(search.sort) || "newest";
  const offset = stringQuery(search.offset) || "0";
  if (
    state === null ||
    repo === null ||
    (state !== "" &&
      !PUBLIC_STATES.includes(state as (typeof PUBLIC_STATES)[number])) ||
    (repo !== "" && !REPOSITORY.test(repo)) ||
    !PUBLIC_SORTS.includes(sort as (typeof PUBLIC_SORTS)[number]) ||
    !/^(0|[1-9][0-9]*)$/.test(offset) ||
    !Number.isSafeInteger(Number(offset)) ||
    Number(offset) > 10000
  )
    return null;
  return {
    state,
    repo,
    sort: sort as HistoryFilters["sort"],
    offset: Number(offset),
  };
}

export function historyQuery(
  filters: HistoryFilters,
  offset = filters.offset,
): string {
  const params = new URLSearchParams();
  if (filters.state) params.set("state", filters.state);
  if (filters.repo) params.set("repo", filters.repo);
  if (filters.sort !== "newest") params.set("sort", filters.sort);
  if (offset > 0) params.set("offset", String(offset));
  return params.toString();
}

export function checkPublicHistoryItem(
  item: unknown,
): item is PublicHistoryItem {
  if (!item || typeof item !== "object" || Array.isArray(item)) return false;
  const i = item as Record<string, unknown>;
  return (
    typeof i.bountyId === "string" &&
    UUID.test(i.bountyId) &&
    typeof i.repositoryFullName === "string" &&
    REPOSITORY.test(i.repositoryFullName) &&
    ["repositoryId", "chainId", "onchainBountyId", "rewardAtoms"].every(
      (k) => typeof i[k] === "string" && DECIMAL.test(i[k] as string),
    ) &&
    typeof i.manifestDigest === "string" &&
    DIGEST.test(i.manifestDigest) &&
    typeof i.state === "string" &&
    PUBLIC_STATES.includes(i.state as (typeof PUBLIC_STATES)[number]) &&
    typeof i.createdAt === "string" &&
    Number.isFinite(Date.parse(i.createdAt)) &&
    i.verificationProven === false
  );
}

export async function loadPublicHistory(
  filters: HistoryFilters,
  request: typeof fetch = fetch,
  configured = process.env.CERTIFIKS_API_BASE_URL,
): Promise<HistoryResult> {
  const api = safePublicApiOrigin(configured);
  if (!api) return { kind: "unavailable" };
  const params = new URLSearchParams({
    limit: "20",
    offset: String(filters.offset),
    sort: filters.sort,
  });
  if (filters.state) params.set("state", filters.state);
  if (filters.repo) params.set("repo", filters.repo);
  try {
    const url = new URL("/v1/bounties", api);
    url.search = params.toString();
    const response = await request(url.href, {
      method: "GET",
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(6000),
      headers: { accept: "application/json" },
    });
    if (!response.ok) return { kind: "unavailable" };
    const json: unknown = await response.json();
    if (
      !json ||
      typeof json !== "object" ||
      Array.isArray(json) ||
      !("items" in json) ||
      !Array.isArray(json.items) ||
      json.items.length > 20 ||
      !json.items.every(checkPublicHistoryItem)
    )
      return { kind: "unavailable" };
    return { kind: "available", items: json.items };
  } catch {
    return { kind: "unavailable" };
  }
}
