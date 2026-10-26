import Link from "next/link";

const STATES = ["funded", "assigned", "submitted", "verifying", "review", "disputed", "payable", "settled", "refunded"] as const;
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const AMOUNT = /^(0|[1-9][0-9]*)$/;
const REPO = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const PER_PAGE = 12;

type Params = { state?: string | string[]; repo?: string | string[]; page?: string | string[] };
interface PublishedOpportunity {
  bountyId: string;
  repositoryFullName: string;
  rewardAtoms: string;
  state: string;
  manifestDigest: string;
  chainId: string;
  verificationProven: false;
}
type Feed =
  | { kind: "invalid" }
  | { kind: "unavailable" }
  | { kind: "available"; items: PublishedOpportunity[]; page: number; next: boolean };

function canonical(params: Params): { state?: string; repo?: string; page: number } | null {
  if (
    Array.isArray(params.state) || Array.isArray(params.repo) ||
    Array.isArray(params.page) ||
    (params.state !== undefined && !STATES.includes(params.state as (typeof STATES)[number])) ||
    (params.repo !== undefined && !REPO.test(params.repo)) ||
    (params.page !== undefined && !/^(0|[1-9][0-9]{0,2})$/.test(params.page))
  ) return null;
  const page = Number(params.page ?? "0");
  if (page > 100) return null;
  return { state: params.state, repo: params.repo, page };
}

function isOpportunity(value: unknown): value is PublishedOpportunity {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const v = value as Record<string, unknown>;
  return typeof v.bountyId === "string" && UUID.test(v.bountyId) &&
    typeof v.repositoryFullName === "string" && REPO.test(v.repositoryFullName) &&
    typeof v.rewardAtoms === "string" && AMOUNT.test(v.rewardAtoms) &&
    typeof v.state === "string" && STATES.includes(v.state as (typeof STATES)[number]) &&
    typeof v.manifestDigest === "string" && DIGEST.test(v.manifestDigest) &&
    typeof v.chainId === "string" && AMOUNT.test(v.chainId) &&
    v.verificationProven === false;
}

async function load(params: Params): Promise<Feed> {
  const filter = canonical(params);
  if (!filter) return { kind: "invalid" };
  const base = process.env.CERTIFIKS_API_BASE_URL;
  if (!base) return { kind: "unavailable" };
  let endpoint: URL;
  try {
    const url = new URL(base);
    const devLocal = process.env.NODE_ENV !== "production" &&
      url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname);
    if ((!devLocal && url.protocol !== "https:") || url.username || url.password ||
      url.search || url.hash) return { kind: "unavailable" };
    endpoint = new URL("/v1/bounties", url);
  } catch {
    return { kind: "unavailable" };
  }
  endpoint.searchParams.set("limit", String(PER_PAGE));
  endpoint.searchParams.set("offset", String(filter.page * PER_PAGE));
  if (filter.state) endpoint.searchParams.set("state", filter.state);
  if (filter.repo) endpoint.searchParams.set("repo", filter.repo);
  try {
    const response = await fetch(endpoint, {
      method: "GET", redirect: "error", cache: "no-store",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return { kind: "unavailable" };
    const value: unknown = await response.json();
    if (!value || typeof value !== "object" || !("items" in value) ||
      !Array.isArray(value.items) || value.items.length > PER_PAGE ||
      !value.items.every(isOpportunity)) {
      return { kind: "unavailable" };
    }
    const items = value.items as PublishedOpportunity[];
    return { kind: "available", items, page: filter.page, next: items.length === PER_PAGE };
  } catch {
    return { kind: "unavailable" };
  }
}

function filterLink(params: { state?: string; repo?: string; page: number }, page: number): string {
  const query = new URLSearchParams({ page: String(page) });
  if (params.state) query.set("state", params.state);
  if (params.repo) query.set("repo", params.repo);
  return `/opportunities?${query.toString()}`;
}

export default async function DeveloperDiscovery({
  searchParams,
}: {
  searchParams: Promise<Params>;
}) {
  const provided = await searchParams;
  const parsed = canonical(provided);
  const result = await load(provided);
  return (
    <div className="site">
      <a href="#main-content" className="skip-link">Skip to content</a>
      <header className="site-header">
        <div className="container header-inner">
          <Link href="/" className="brand" aria-label="CertiFiks home">
            <span className="brand-symbol" aria-hidden="true"><span /></span>
            <span>certi<span className="brand-accent">fiks</span><span className="brand-dot">.</span></span>
          </Link>
          <nav className="main-nav" aria-label="Primary navigation">
            <Link href="/">Home</Link>
            <Link href="/sponsor">For sponsors</Link>
            <Link href="/onboarding">Role guide</Link>
          </nav>
        </div>
      </header>
      <main id="main-content" className="container onboarding-main">
        <section className="onboarding-intro" aria-labelledby="browse-title">
          <p className="eyebrow">FOR DEVELOPERS / PUBLISHED RECORDS ONLY</p>
          <h1 id="browse-title">Find real work.<br /><em>Check the proof.</em></h1>
          <p>Only publicly published, chain-indexed records returned by the live API appear here. These are not guaranteed open assignments or claimable rewards. No application, submission or withdrawal service is available yet.</p>
          <div className="availability-alert" role="status">
            <span aria-hidden="true">!</span>
            <div><strong>Contributor applications and earnings are not enabled.</strong>
              <span>Authentication, assignment approvals, independent verification and real wallet payouts must be operational before anyone can apply or claim funds.</span>
            </div>
          </div>
        </section>
        <section className="marketplace" aria-labelledby="public-search-title">
          <div className="section-head">
            <p className="eyebrow">FILTERS / LIVE PUBLIC DATA</p>
            <h2 id="public-search-title">Browse <em>opportunities.</em></h2>
            <p>Search by exact repository and current state. Filters apply at the live backend, before pagination.</p>
          </div>
          <form className="opportunity-filters" method="get" action="/opportunities" aria-label="Filter published bounties">
            <div><label htmlFor="repository">Repository (owner/name)</label>
              <input id="repository" name="repo" type="text" autoComplete="off"
                placeholder="organization/repository" defaultValue={parsed?.repo ?? ""} maxLength={200} />
            </div>
            <div><label htmlFor="state">Public state</label>
              <select id="state" name="state" defaultValue={parsed?.state ?? ""}>
                <option value="">All published states</option>
                {STATES.map((state) => <option value={state} key={state}>{state.replaceAll("_", " ")}</option>)}
              </select>
            </div>
            <button className="button button-primary" type="submit">Apply filters ↗</button>
            <Link href="/opportunities" className="button button-outline">Clear</Link>
          </form>
          {result.kind === "invalid" ? (
            <div className="market-state" role="alert"><div><h3>Check your filter values</h3><p>Use a repository in owner/name format and one supported public state. No backend request was made.</p></div></div>
          ) : result.kind === "unavailable" ? (
            <div className="market-state" role="status"><div><h3>Live opportunity data unavailable</h3><p>The approved public bounty API is unconfigured or unavailable. No simulated rewards or results are shown.</p></div><span className="state-badge">NOT CONNECTED</span></div>
          ) : result.items.length === 0 ? (
            <div className="market-state" role="status"><div><h3>No matching published bounties</h3><p>The live API returned no public records for these filters and page.</p></div><span className="state-badge">EMPTY</span></div>
          ) : (
            <div className="listing-grid" aria-live="polite">
              {result.items.map((item) => (
                <article className="listing-card" key={item.bountyId}>
                  <span className="mono">{item.state.toUpperCase()} · CHAIN {item.chainId}</span>
                  <h3>{item.repositoryFullName}</h3>
                  <p>Advertised reward: {item.rewardAtoms} atomic units</p>
                  <small>Funded terms digest: {item.manifestDigest}</small>
                  <p className="verification-warning">Fix verification, eligibility and actual withdrawal rights have not been established.</p>
                  <span className="availability-pill">APPLICATION UNAVAILABLE</span>
                </article>
              ))}
            </div>
          )}
          {result.kind === "available" && parsed && (
            <nav aria-label="Bounty result pages" className="opportunity-pages">
              {result.page > 0 && <Link href={filterLink(parsed, result.page - 1)}>← Previous page</Link>}
              <span>Page {result.page + 1}</span>
              {result.next && result.page < 100 && <Link href={filterLink(parsed, result.page + 1)}>Next page →</Link>}
            </nav>
          )}
          <p className="market-fineprint">Published funding metadata is not an audited escrow receipt, verified fix, acceptance of an application, or permission to move funds.</p>
        </section>
      </main>
      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">certi<span className="brand-accent">fiks</span><span className="brand-dot">.</span></span>
          <p>Never connect your wallet to unverified copies or send funds to unapproved contracts.</p>
          <Link href="/">Home ↗</Link>
        </div>
      </footer>
    </div>
  );
}
