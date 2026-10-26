import Link from "next/link";

interface PublicBounty {
  bountyId: string;
  repositoryFullName: string;
  rewardAtoms: string;
  state: string;
  manifestDigest: string;
  verificationProven: false;
}
type Listings =
  | { kind: "unavailable" }
  | { kind: "available"; items: PublicBounty[] };

async function loadPublishedBounties(): Promise<Listings> {
  const configured = process.env.CERTIFIKS_API_BASE_URL;
  if (!configured) return { kind: "unavailable" };
  let origin: URL;
  try {
    origin = new URL(configured);
    if (
      (origin.protocol !== "https:" &&
        !(
          process.env.NODE_ENV !== "production" &&
          origin.protocol === "http:" &&
          ["localhost", "127.0.0.1"].includes(origin.hostname)
        )) ||
      origin.username ||
      origin.password ||
      origin.search ||
      origin.hash
    )
      return { kind: "unavailable" };
  } catch {
    return { kind: "unavailable" };
  }
  try {
    const url = new URL("/v1/bounties?limit=3&offset=0", origin);
    const response = await fetch(url, {
      method: "GET",
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return { kind: "unavailable" };
    const data: unknown = await response.json();
    if (
      !data ||
      typeof data !== "object" ||
      !("items" in data) ||
      !Array.isArray(data.items) ||
      !data.items.every(
        (item: unknown) =>
          item !== null &&
          typeof item === "object" &&
          "bountyId" in item &&
          typeof item.bountyId === "string" &&
          "repositoryFullName" in item &&
          typeof item.repositoryFullName === "string" &&
          "rewardAtoms" in item &&
          typeof item.rewardAtoms === "string" &&
          "state" in item &&
          typeof item.state === "string" &&
          "manifestDigest" in item &&
          typeof item.manifestDigest === "string" &&
          "verificationProven" in item &&
          item.verificationProven === false,
      )
    ) {
      return { kind: "unavailable" };
    }
    return { kind: "available", items: data.items as PublicBounty[] };
  } catch {
    return { kind: "unavailable" };
  }
}

const pathways = [
  {
    number: "01",
    kicker: "FOR MAINTAINERS",
    title: "Define the bug.",
    copy: "Pin the failing revision, approval rules and test evidence before a contributor starts. Published terms are designed to be immutable.",
    badge: "Funding not available",
  },
  {
    number: "02",
    kicker: "FOR CONTRIBUTORS",
    title: "Submit a repair.",
    copy: "Make the change against an exact commit and let a sandbox independently replay the original failure and candidate tests.",
    badge: "Live submission not available",
  },
  {
    number: "03",
    kicker: "FOR REVIEWERS",
    title: "Verify the proof.",
    copy: "Inspect signed reports and independently assess reproducibility. A status label cannot replace real artifacts or verifier independence.",
    badge: "Live reviewer access not available",
  },
] as const;

export default async function HomePage() {
  const listings = await loadPublishedBounties();
  return (
    <div className="site">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <header className="site-header">
        <div className="container header-inner">
          <Link href="/" className="brand" aria-label="CertiFiks home">
            <span className="brand-symbol" aria-hidden="true">
              <span />
            </span>
            <span>
              certi<span className="brand-accent">fiks</span>
              <span className="brand-dot">.</span>
            </span>
          </Link>
          <nav className="main-nav" aria-label="Primary navigation">
            <a href="#how-it-works">How it works</a>
            <a href="#marketplace">Bounties</a>
            <Link href="/onboarding">
              Get oriented <span aria-hidden="true">↗</span>
            </Link>
          </nav>
        </div>
      </header>

      <main id="main-content">
        <section className="hero container" aria-labelledby="hero-title">
          <div className="hero-copy">
            <div className="eyebrow">
              <span className="pulse" aria-hidden="true" /> PROTOCOL IN
              DEVELOPMENT
            </div>
            <h1 id="hero-title">
              Don't just
              <br />
              merge the fix.
              <br />
              <em>Prove it.</em>
            </h1>
            <p className="hero-description">
              An open-source bug bounty should end with something stronger than
              a green checkmark. CertiFiks is building independently
              reproducible software repairs and evidence-bound escrow.
            </p>
            <div className="hero-actions">
              <Link href="/onboarding" className="button button-primary">
                Understand the process <span aria-hidden="true">↗</span>
              </Link>
              <a className="button button-outline" href="#marketplace">
                Explore public bounties <span aria-hidden="true">↓</span>
              </a>
            </div>
            <p className="hero-disclosure">
              No live deposits, funded rewards or automated payouts are
              available through this website. Do not send funds.
            </p>
          </div>
          <aside
            className="proof-panel"
            aria-label="Illustrative verification sequence, not live activity"
          >
            <div className="proof-top">
              <span className="mono">CERTIFIKS / PROOF PIPELINE</span>
              <span className="illustration-label">CONCEPT ONLY</span>
            </div>
            <div className="proof-steps">
              <div className="proof-step">
                <span className="step-indicator">01</span>
                <div>
                  <strong>Commit pinned</strong>
                  <span>Exact repository &amp; baseline</span>
                </div>
                <span className="step-decor" aria-hidden="true">
                  ◇
                </span>
              </div>
              <div className="proof-connector" aria-hidden="true" />
              <div className="proof-step">
                <span className="step-indicator">02</span>
                <div>
                  <strong>Fix reproduced</strong>
                  <span>Fail-before / pass-after</span>
                </div>
                <span className="step-decor" aria-hidden="true">
                  ◇
                </span>
              </div>
              <div className="proof-connector" aria-hidden="true" />
              <div className="proof-step">
                <span className="step-indicator">03</span>
                <div>
                  <strong>Report independently signed</strong>
                  <span>Artifacts, reviewers &amp; policy</span>
                </div>
                <span className="step-decor" aria-hidden="true">
                  ◇
                </span>
              </div>
            </div>
            <div className="proof-bottom">
              <span className="mono">TRUST IS EARNED, NOT IMPLIED.</span>
              <span aria-hidden="true">✳</span>
            </div>
          </aside>
        </section>

        <section
          className="status-band"
          aria-label="Current service availability"
        >
          <div className="container status-grid">
            <div>
              <span className="status-label">PROTOCOL</span>
              <strong>Under active construction</strong>
            </div>
            <div>
              <span className="status-label">GITHUB CONNECTION</span>
              <strong>Live onboarding unavailable</strong>
            </div>
            <div>
              <span className="status-label">ESCROW</span>
              <strong>Funding disabled</strong>
            </div>
            <div>
              <span className="status-label">CHAIN RELEASE</span>
              <strong>Deployment not verified</strong>
            </div>
          </div>
        </section>

        <section
          id="how-it-works"
          className="container journey-section"
          aria-labelledby="journey-title"
        >
          <div className="section-head">
            <p className="eyebrow">THE WORKFLOW / 001</p>
            <h2 id="journey-title">
              A clear path from <em>bug to proof.</em>
            </h2>
            <p>
              Different roles. Shared evidence. No shortcuts around
              verification.
            </p>
          </div>
          <div className="journey-grid">
            {pathways.map((pathway) => (
              <article className="journey-card" key={pathway.number}>
                <div className="journey-card-top">
                  <span className="large-number">{pathway.number}</span>
                  <span className="mono">{pathway.kicker}</span>
                </div>
                <h3>{pathway.title}</h3>
                <p>{pathway.copy}</p>
                <span className="availability-pill">{pathway.badge}</span>
              </article>
            ))}
          </div>
        </section>

        <section className="trust-section" aria-labelledby="trust-title">
          <div className="container trust-grid">
            <div className="trust-intro">
              <p className="eyebrow">WHY EVIDENCE MATTERS</p>
              <h2 id="trust-title">
                Proof, not
                <br />
                <em>promises.</em>
              </h2>
              <p>
                Each claim has to survive independent scrutiny. Passing CI alone
                is not proof of a correct fix or permission to release a reward.
              </p>
            </div>
            <div className="trust-list">
              <div className="trust-item">
                <span aria-hidden="true">↗</span>
                <div>
                  <h3>Immutable terms</h3>
                  <p>
                    A clear baseline, acceptance plan and funding policy pinned
                    before submission.
                  </p>
                </div>
              </div>
              <div className="trust-item">
                <span aria-hidden="true">↗</span>
                <div>
                  <h3>Reproducible evidence</h3>
                  <p>
                    Before-and-after outcomes, environment hashes, and
                    reviewable artifacts.
                  </p>
                </div>
              </div>
              <div className="trust-item">
                <span aria-hidden="true">↗</span>
                <div>
                  <h3>Independent review</h3>
                  <p>
                    Signed decisions, bounded disputes and explicit limits to
                    what a test proves.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section
          id="marketplace"
          className="container marketplace"
          aria-labelledby="market-title"
        >
          <div className="section-head section-head-inline">
            <div>
              <p className="eyebrow">PUBLIC BOUNTIES / LIVE SOURCE ONLY</p>
              <h2 id="market-title">
                Published <em>opportunities.</em>
              </h2>
            </div>
            <p>
              Listings appear only when the backend returns actual published
              chain-indexed records.
            </p>
          </div>
          {listings.kind === "unavailable" ? (
            <div className="market-state" role="status">
              <span className="state-glyph" aria-hidden="true">
                ◌
              </span>
              <div>
                <h3>Live listings are unavailable</h3>
                <p>
                  The public bounty API is not connected or did not respond. No
                  sample rewards or simulated activity are displayed.
                </p>
              </div>
              <span className="state-badge">NOT CONNECTED</span>
            </div>
          ) : listings.items.length === 0 ? (
            <div className="market-state" role="status">
              <span className="state-glyph" aria-hidden="true">
                —
              </span>
              <div>
                <h3>No published bounties</h3>
                <p>
                  The live public index currently contains no bounties available
                  for display.
                </p>
              </div>
              <span className="state-badge">0 PUBLISHED</span>
            </div>
          ) : (
            <div className="listing-grid">
              {listings.items.map((listing) => (
                <article key={listing.bountyId} className="listing-card">
                  <span className="mono">
                    PUBLISHED / {listing.state.toUpperCase()}
                  </span>
                  <h3>{listing.repositoryFullName}</h3>
                  <p>Reward: {listing.rewardAtoms} atomic units</p>
                  <small>
                    Manifest: {listing.manifestDigest.slice(0, 12)}…
                  </small>
                  <p className="verification-warning">
                    Fix verification has not been established.
                  </p>
                </article>
              ))}
            </div>
          )}
          <p className="market-fineprint">
            Publication is not independent proof of completed verification, safe
            custody, or payment.
          </p>
        </section>

        <section className="last-cta">
          <div className="container last-cta-inner">
            <div>
              <p className="eyebrow">BUILDING IN PUBLIC</p>
              <h2>
                Trust starts with <em>clarity.</em>
              </h2>
              <p>
                See the requirements and known blockers before connecting an
                account or considering a reward.
              </p>
            </div>
            <div className="cta-end">
              <Link href="/onboarding" className="button button-primary">
                Read onboarding <span aria-hidden="true">↗</span>
              </Link>
              <a
                href="https://github.com/EcstaceeLOR/CertiFiks/issues"
                target="_blank"
                rel="noreferrer"
              >
                View open engineering issues ↗
              </a>
            </div>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">
            certi<span className="brand-accent">fiks</span>
            <span className="brand-dot">.</span>
          </span>
          <p>
            Verified repair protocol in development. No custody or payment
            service is operational.
          </p>
          <a
            href="https://github.com/EcstaceeLOR/CertiFiks"
            target="_blank"
            rel="noreferrer"
          >
            Source on GitHub ↗
          </a>
        </div>
      </footer>
    </div>
  );
}
