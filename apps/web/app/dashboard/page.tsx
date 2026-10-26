import Link from "next/link";
import {
  historyQuery,
  loadPublicHistory,
  parseHistoryFilters,
  PUBLIC_SORTS,
  PUBLIC_STATES,
} from "./history.js";

export const dynamic = "force-dynamic";

type Search = Record<string, string | string[] | undefined>;

function label(state: string): string {
  return state.replaceAll("_", " ");
}

export default async function DashboardPage({
  searchParams,
}: {
  searchParams: Promise<Search>;
}) {
  const filters = parseHistoryFilters(await searchParams);
  const history = filters
    ? await loadPublicHistory(filters)
    : { kind: "invalid" as const };
  const canPrevious = !!filters && filters.offset > 0;
  const canNext = !!filters && history.kind === "available" && history.items.length === 20;
  return (
    <div className="site">
      <a className="skip-link" href="#main-content">Skip to content</a>
      <header className="site-header">
        <div className="container header-inner">
          <Link href="/" className="brand" aria-label="CertiFiks home">
            <span className="brand-symbol" aria-hidden="true"><span /></span>
            <span>certi<span className="brand-accent">fiks</span><span className="brand-dot">.</span></span>
          </Link>
          <nav className="main-nav" aria-label="Primary navigation">
            <Link href="/onboarding">Role guide</Link>
            <Link href="/sponsor">Sponsor overview</Link>
            <Link href="/dashboard" aria-current="page">Public history</Link>
          </nav>
        </div>
      </header>
      <main id="main-content" className="container onboarding-main">
        <div className="onboarding-intro">
          <p className="eyebrow">TRANSPARENT HISTORY / FINALIZED PUBLIC RECORDS ONLY</p>
          <h1>Find the work.<br /><em>Check the evidence.</em></h1>
          <p>
            Browse real published bounty records from the finalized-only public index.
            No invented totals, private organization records, custody balances or
            verification approvals are shown here.
          </p>
          <div className="availability-alert" role="status">
            <span aria-hidden="true">!</span>
            <div>
              <strong>Private dashboards are not available yet.</strong>
              <span>
                Sponsor commitments, your applications, verifier assignments,
                payments, disputes and operator jobs require authenticated
                tenant-scoped APIs. This view is public and cannot prove personal ownership.
              </span>
            </div>
          </div>
        </div>
        <section aria-labelledby="history-title" className="marketplace">
          <div className="section-head">
            <p className="eyebrow">PUBLIC HISTORY / NO SAMPLE ROWS</p>
            <h2 id="history-title">Published <em>records.</em></h2>
            <p>Filter on the server, paginate without losing your search, and bookmark the resulting URL.</p>
          </div>
          <form action="/dashboard" method="get" className="dashboard-search" aria-label="Public history filters">
            <div>
              <label htmlFor="dashboard-repo">Repository (exact owner/repo)</label>
              <input id="dashboard-repo" name="repo" type="text"
                placeholder="owner/repository" defaultValue={filters?.repo ?? ""}
                maxLength={150} spellCheck={false} />
            </div>
            <div>
              <label htmlFor="dashboard-state">Bounty state</label>
              <select id="dashboard-state" name="state" defaultValue={filters?.state ?? ""}>
                <option value="">All published states</option>
                {PUBLIC_STATES.map((state) => (
                  <option value={state} key={state}>{label(state)}</option>
                ))}
              </select>
            </div>
            <div>
              <label htmlFor="dashboard-sort">Sort by</label>
              <select id="dashboard-sort" name="sort" defaultValue={filters?.sort ?? "newest"}>
                {PUBLIC_SORTS.map((sort) => (
                  <option value={sort} key={sort}>
                    {sort === "newest" ? "Newest first" : sort === "oldest" ? "Oldest first" : "Repository A–Z"}
                  </option>
                ))}
              </select>
            </div>
            <button className="button button-primary" type="submit">Apply filters</button>
            <Link href="/dashboard" className="button button-outline">Clear</Link>
          </form>
          <div className="dashboard-views" aria-label="Bookmarkable public views">
            <span className="mono">QUICK VIEWS</span>
            <Link href="/dashboard?state=funded">Published &amp; funded</Link>
            <Link href="/dashboard?state=verifying">Verification in progress</Link>
            <Link href="/dashboard?state=disputed">Disputes</Link>
            <Link href="/dashboard?state=settled">Settled</Link>
          </div>
          {history.kind === "invalid" ? (
            <div role="alert" className="market-state">
              <div><h3>Invalid search parameters</h3>
                <p>Use a published state, exact repository and valid pagination values.</p></div>
            </div>
          ) : history.kind === "unavailable" ? (
            <div role="status" className="market-state">
              <div><h3>Public records are unavailable</h3>
                <p>The verified public backend is not connected or returned an invalid response. No previously cached balance or simulated records are displayed.</p></div>
              <span className="state-badge">NOT CONNECTED</span>
            </div>
          ) : history.items.length === 0 ? (
            <div role="status" className="market-state">
              <div><h3>No matching published records</h3>
                <p>This result is from the live public index. Try changing your filters.</p></div>
              <span className="state-badge">0 ON THIS PAGE</span>
            </div>
          ) : (
            <div className="dashboard-results">
              <p role="status" className="market-fineprint">
                Showing {history.items.length} records on this page. This is not a
                count of all bounties or a statement of verified escrow liabilities.
              </p>
              <div className="listing-grid">
                {history.items.map((item) => (
                  <article key={item.bountyId} className="listing-card">
                    <span className="mono">{item.state.toUpperCase()}</span>
                    <h3>{item.repositoryFullName}</h3>
                    <p>Reward: {item.rewardAtoms} atomic units, asset and live balance unverified.</p>
                    <p className="mono">Published: {new Date(item.createdAt).toLocaleDateString("en-GB", { timeZone: "UTC" })} UTC</p>
                    <p className="verification-warning">Independent fix verification is not proven.</p>
                    <Link href={`/dashboard/bounties/${item.bountyId}`} className="text-link">
                      View public record ↗
                    </Link>
                  </article>
                ))}
              </div>
            </div>
          )}
          {filters && (
            <nav aria-label="History pagination" className="dashboard-pagination">
              {canPrevious ? (
                <Link href={`/dashboard?${historyQuery(filters, Math.max(0, filters.offset - 20))}`}>
                  ← Previous page
                </Link>
              ) : <span>First page</span>}
              <span className="mono">OFFSET {filters.offset} · MAX 20 PER PAGE</span>
              {canNext && filters.offset <= 9980 ? (
                <Link href={`/dashboard?${historyQuery(filters, filters.offset + 20)}`}>
                  Next page →
                </Link>
              ) : <span>No next page confirmed</span>}
              <Link href={`/dashboard/export?${historyQuery(filters)}`}>
                Export public page (CSV)
              </Link>
            </nav>
          )}
          <p className="market-fineprint">
            Bookmarked URLs preserve public filters, not a private user session.
            Export is limited to 50 public rows. Published does not mean paid,
            independently verified, or safe to fund.
          </p>
        </section>
      </main>
      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">certi<span className="brand-accent">fiks</span><span className="brand-dot">.</span></span>
          <p>Public observation only; private dashboards and financial reconciliation are not yet available.</p>
          <Link href="/">Home ↗</Link>
        </div>
      </footer>
    </div>
  );
}
