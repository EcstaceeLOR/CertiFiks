import Link from "next/link";

interface PublishedBounty {
  bountyId: string;
  repositoryFullName: string;
  manifestDigest: string;
  rewardAtoms: string;
  state: string;
  verificationProven: false;
}

type SponsorPublicView =
  | { kind: "unavailable" }
  | { kind: "available"; items: PublishedBounty[] };

const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;
const DIGEST = /^0x[a-f0-9]{64}$/;
const ATOMS = /^(0|[1-9][0-9]*)$/;

/**
 * Published, server-redacted bounty metadata ONLY. A sponsor's private
 * workspace must not be inferred from these public rows. Authenticated
 * draft/application/billing access is disabled until #23/#26 are live.
 */
async function loadPublishedBounties(): Promise<SponsorPublicView> {
  const configured = process.env.CERTIFIKS_API_BASE_URL;
  if (!configured) return { kind: "unavailable" };
  let api: URL;
  try {
    api = new URL(configured);
    const localDev =
      process.env.NODE_ENV !== "production" &&
      api.protocol === "http:" &&
      ["localhost", "127.0.0.1"].includes(api.hostname);
    if (
      (!localDev && api.protocol !== "https:") ||
      api.username ||
      api.password ||
      api.search ||
      api.hash
    )
      return { kind: "unavailable" };
  } catch {
    return { kind: "unavailable" };
  }
  const endpoint = new URL("/v1/bounties?limit=12&offset=0", api);
  try {
    const response = await fetch(endpoint, {
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(5000),
    });
    if (!response.ok) return { kind: "unavailable" };
    const body: unknown = await response.json();
    if (
      !body ||
      typeof body !== "object" ||
      !("items" in body) ||
      !Array.isArray(body.items) ||
      body.items.length > 12
    ) {
      return { kind: "unavailable" };
    }
    const items = body.items;
    if (
      !items.every(
        (item: unknown) =>
          item !== null &&
          typeof item === "object" &&
          "bountyId" in item &&
          typeof item.bountyId === "string" &&
          UUID.test(item.bountyId) &&
          "repositoryFullName" in item &&
          typeof item.repositoryFullName === "string" &&
          /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(item.repositoryFullName) &&
          "manifestDigest" in item &&
          typeof item.manifestDigest === "string" &&
          DIGEST.test(item.manifestDigest) &&
          "rewardAtoms" in item &&
          typeof item.rewardAtoms === "string" &&
          ATOMS.test(item.rewardAtoms) &&
          "state" in item &&
          typeof item.state === "string" &&
          "verificationProven" in item &&
          item.verificationProven === false,
      )
    )
      return { kind: "unavailable" };
    return { kind: "available", items: items as PublishedBounty[] };
  } catch {
    return { kind: "unavailable" };
  }
}

const steps = [
  [
    "Repository access",
    "Explicit GitHub App installation and maintainer consent are required. These are not live yet.",
  ],
  [
    "Frozen acceptance terms",
    "Baseline commit, image, regression plan and verifier policy must be fixed before a transaction.",
  ],
  [
    "Approved chain and escrow",
    "The actual runtime, contract address, asset, amount, gas and refund rules must be independently verified.",
  ],
  [
    "Wallet transaction",
    "A sponsor must personally approve the exact transaction in a secure wallet; no background auto-funding.",
  ],
  [
    "Finality and audit trail",
    "Only confirmed, indexed, non-orphaned transfers may be shown as funded.",
  ],
] as const;

export default async function SponsorPage() {
  const published = await loadPublishedBounties();
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
            <Link href="/">Home</Link>
            <Link href="/onboarding">Role guide</Link>
            <a href="https://github.com/EcstaceeLOR/CertiFiks/issues/32">
              Development status ↗
            </a>
          </nav>
        </div>
      </header>
      <main id="main-content">
        <div className="container onboarding-main">
          <div className="onboarding-intro">
            <p className="eyebrow">SPONSOR WORKSPACE / PUBLIC PREVIEW</p>
            <h1>
              Reward a repair.
              <br />
              <em>Only after proof.</em>
            </h1>
            <p>
              Browse real public bounty records and understand the required
              on-chain funding safeguards. Private sponsor data is not
              accessible until wallet, GitHub and organization authorization is
              available.
            </p>
            <div className="availability-alert" role="status">
              <span aria-hidden="true">!</span>
              <div>
                <strong>
                  Funding and private sponsor management are disabled.
                </strong>
                <span>
                  No verified custody deployment or secure sponsor session is
                  connected. Do not send money or treat public records as your
                  personal workspace.
                </span>
              </div>
            </div>
          </div>
          <section aria-labelledby="setup-title" className="journey-section">
            <div className="section-head">
              <p className="eyebrow">FUNDING INTEGRITY</p>
              <h2 id="setup-title">
                Every bounty needs a <em>real foundation.</em>
              </h2>
              <p>
                These are hard release requirements, not completed steps or
                clickable transaction controls.
              </p>
            </div>
            <div className="journey-grid">
              {steps.map(([title, description], i) => (
                <article className="journey-card" key={title}>
                  <div className="journey-card-top">
                    <span className="large-number">
                      {String(i + 1).padStart(2, "0")}
                    </span>
                    <span className="mono">REQUIRES VERIFICATION</span>
                  </div>
                  <h3>{title}</h3>
                  <p>{description}</p>
                  <span className="availability-pill">NOT YET AVAILABLE</span>
                </article>
              ))}
            </div>
          </section>
          <section className="marketplace" aria-labelledby="published-title">
            <div className="section-head">
              <p className="eyebrow">PUBLIC RECORDS ONLY</p>
              <h2 id="published-title">
                Published <em>bounties.</em>
              </h2>
              <p>
                No inferred sponsor ownership, placeholder amounts or fabricated
                balances.
              </p>
            </div>
            {published.kind === "unavailable" ? (
              <div className="market-state" role="status">
                <div>
                  <h3>Public backend unavailable</h3>
                  <p>No published records can be verified at this time.</p>
                </div>
                <span className="state-badge">NOT CONNECTED</span>
              </div>
            ) : published.items.length === 0 ? (
              <div className="market-state" role="status">
                <div>
                  <h3>No published bounties</h3>
                  <p>The live backend has no public items to show.</p>
                </div>
                <span className="state-badge">0 PUBLISHED</span>
              </div>
            ) : (
              <div className="listing-grid">
                {published.items.map((item) => (
                  <article className="listing-card" key={item.bountyId}>
                    <span className="mono">{item.state.toUpperCase()}</span>
                    <h3>{item.repositoryFullName}</h3>
                    <p>{item.rewardAtoms} atomic reward units</p>
                    <small>Manifest: {item.manifestDigest}</small>
                    <p className="verification-warning">
                      Independent fix verification not proven.
                    </p>
                  </article>
                ))}
              </div>
            )}
            <p className="market-fineprint">
              Publishing does not prove escrow ownership, availability of funds,
              a valid fix, or withdrawal rights.
            </p>
          </section>
        </div>
      </main>
      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">
            certi<span className="brand-accent">fiks</span>
            <span className="brand-dot">.</span>
          </span>
          <p>
            Live sponsor funding is unavailable until external acceptance gates
            pass.
          </p>
          <Link href="/">Back to home ↗</Link>
        </div>
      </footer>
    </div>
  );
}
