import Link from "next/link";

const roles = [
  {
    id: "sponsor",
    index: "01",
    label: "Sponsor / Maintainer",
    title: "Define an auditable bug bounty.",
    summary:
      "The intended flow captures repository access, a frozen acceptance manifest, independently verified chain funding and clear dispute terms.",
    requirements: [
      "GitHub App installation authorized for the exact repository.",
      "Wallet identity and supported chain approved before funding.",
      "Acceptance tests, reviewer policy and immutable manifest approved.",
      "Escrow contract and chain transactions independently verified.",
    ],
    status: "Live publishing and funding are unavailable.",
  },
  {
    id: "contributor",
    index: "02",
    label: "Developer / Contributor",
    title: "Repair a pinned revision.",
    summary:
      "The planned contributor flow binds each application and submitted patch to an immutable GitHub commit and independently reproducible test evidence.",
    requirements: [
      "A GitHub account linked to a secure, verified session.",
      "An eligible repository and a visible, real published opportunity.",
      "An assignment and unmodified baseline/candidate acceptance tests.",
      "A signed verification report before any payout decision.",
    ],
    status: "Live applications, submissions and payouts are unavailable.",
  },
  {
    id: "reviewer",
    index: "03",
    label: "Verifier / Arbitrator",
    title: "Evaluate evidence, not marketing.",
    summary:
      "Independent reviewers need enrolled identities, private artifact access restricted by role, and a real signed adjudication trail.",
    requirements: [
      "Independently approved verifier or arbitrator credentials.",
      "Role-scoped artifact retrieval and trusted signature policy.",
      "Replayable result hashes, logs and before/after test outcomes.",
      "Bounded appeals and quorum checks that cannot bypass custody safeguards.",
    ],
    status: "Live reviewer enrollment and dispute operations are unavailable.",
  },
] as const;

export default function OnboardingPage() {
  return (
    <div className="site onboarding-page">
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
            <Link href="/opportunities">Bounties</Link>
            <Link href="/help">Help and trust</Link>
            <a
              href="https://github.com/EcstaceeLOR/CertiFiks/issues"
              target="_blank"
              rel="noreferrer"
            >
              Engineering status ↗
            </a>
          </nav>
        </div>
      </header>

      <main id="main-content" className="container onboarding-main">
        <div className="onboarding-intro">
          <p className="eyebrow">YOUR FIRST STEPS / NO FAKE CONNECTIONS</p>
          <h1>
            Know what you're
            <br />
            <em>signing up for.</em>
          </h1>
          <p>
            CertiFiks is under active development. This guide explains the
            intended roles and permissions, not a functioning sign-in or custody
            workflow. No wallet connection or GitHub installation is performed
            here.
          </p>
          <div className="availability-alert" role="status">
            <span aria-hidden="true">!</span>
            <div>
              <strong>Onboarding is not enabled yet.</strong>
              <span>
                Do not send funds or install an unverified third-party app
                claiming to represent CertiFiks.
              </span>
            </div>
          </div>
          <nav aria-label="Choose your role" className="role-tabs">
            {roles.map((role) => (
              <a href={`#${role.id}`} key={role.id}>
                {role.label} <span aria-hidden="true">↓</span>
              </a>
            ))}
          </nav>
        </div>

        <div className="roles-list">
          {roles.map((role) => (
            <section
              key={role.id}
              id={role.id}
              className="role-section"
              aria-labelledby={`${role.id}-title`}
            >
              <div className="role-left">
                <p className="mono">
                  {role.index} / {role.label.toUpperCase()}
                </p>
                <h2 id={`${role.id}-title`}>{role.title}</h2>
                <p>{role.summary}</p>
              </div>
              <div className="role-right">
                <h3>Requirements before this role is available</h3>
                <ul>
                  {role.requirements.map((requirement) => (
                    <li key={requirement}>{requirement}</li>
                  ))}
                </ul>
                <div className="role-unavailable" role="note">
                  {role.status}
                </div>
              </div>
            </section>
          ))}
        </div>

        <section className="onboarding-last" aria-labelledby="next-title">
          <p className="eyebrow">CURRENT TRUTH</p>
          <h2 id="next-title">
            Your security shouldn't depend on a placeholder button.
          </h2>
          <p>
            Until the product can prove live GitHub authorization, supported
            chain identity, protected private artifacts and real transaction
            finality, registration and payment actions will remain unavailable.
          </p>
          <Link href="/" className="button button-outline">
            Return to overview ↗
          </Link>
          <Link href="/sponsor" className="text-link">
            Explore public sponsor view ↗
          </Link>
          <a
            href="https://github.com/EcstaceeLOR/CertiFiks/issues"
            target="_blank"
            rel="noreferrer"
            className="text-link"
          >
            Inspect release blockers ↗
          </a>
        </section>
      </main>
      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">
            certi<span className="brand-accent">fiks</span>
            <span className="brand-dot">.</span>
          </span>
          <p>Verification before rewards. No live escrow is available.</p>
          <Link href="/">Home ↗</Link>
        </div>
      </footer>
    </div>
  );
}
