import Link from "next/link";
import styles from "./help.module.css";

const roles = [
  {
    id: "maintainers",
    title: "Maintainers and sponsors",
    detail:
      "Select a real repository and reproduce a defect; agree on a fixed acceptance manifest, reviewer independence, and a deadline before considering funding.",
    blocked:
      "GitHub installation, funding, bounty publication, and account onboarding are not available.",
  },
  {
    id: "contributors",
    title: "Developers and contributors",
    detail:
      "Review the exact test rules, repository commit, challenge window, and payout requirements. Keep your patch at an immutable Git commit.",
    blocked:
      "Applying, submitting for verification, and withdrawing earned rewards are not available.",
  },
  {
    id: "reviewers",
    title: "Verifiers and arbitrators",
    detail:
      "Use independent identities, approved isolation, signed evidence, and bounded dispute rules; approval of a test result alone must not move funds.",
    blocked:
      "Reviewer enrollment, private evidence access, and live adjudication are not available.",
  },
] as const;

const questions = [
  {
    title: "Can I deposit money or connect my wallet?",
    answer:
      "No. No supported Portaldot runtime, verified escrow deployment, or production wallet flow is available. Do not send funds to any address claiming to be CertiFiks.",
  },
  {
    title: "How is a fix judged?",
    answer:
      "The intended rule is a precommitted failing baseline, a candidate commit, regression checks, and independent signed review. Tests can miss bugs; a passing test or GitHub check is not a guarantee of correctness.",
  },
  {
    title: "When are refunds, disputes, and payouts possible?",
    answer:
      "Not yet. Future settlement must follow immutable bounty rules, independent review, a defined challenge window, verified chain finality, and an authorized wallet withdrawal. Refunds cannot be promised until live contract terms and deployment are independently confirmed.",
  },
  {
    title: "What are the fees, gas costs, and response times?",
    answer:
      "No binding fees, token prices, gas quote, support SLA, or payout timelines have been published. Any future transaction must disclose network and platform charges before you sign.",
  },
  {
    title: "What information can reviewers see?",
    answer:
      "The design restricts evidence to authorized parties and assigns private artifacts limited retention. A production privacy/retention policy, deletion guarantees, and live storage access controls are not yet independently verified. Never upload secrets or confidential source code today.",
  },
  {
    title: "Does CertiFiks have an independent security audit?",
    answer:
      "No. Automated tests and signature-verification code are not an independent audit. Real-fund launch is blocked until review, retests, and release sign-off are completed.",
  },
] as const;

export default function HelpPage() {
  return (
    <div className="site">
      <a className="skip-link" href="#main-content">
        Skip to content
      </a>
      <header className="site-header">
        <div className="container header-inner">
          <Link href="/" className="brand" aria-label="CertiFiks home">
            certi<span className="brand-accent">fiks</span>
            <span className="brand-dot">.</span>
          </Link>
          <nav className="main-nav" aria-label="Help navigation">
            <Link href="/">Home</Link>
            <Link href="/onboarding">Onboarding</Link>
            <Link href="/wallet">Wallet safety</Link>
          </nav>
        </div>
      </header>

      <main id="main-content" className={styles.main}>
        <section className="container" aria-labelledby="help-heading">
          <p className="eyebrow">CERTIFIKS / HELP AND TRUST</p>
          <h1 id="help-heading" className={styles.heading}>
            Evidence first. <em>Questions welcome.</em>
          </h1>
          <p className={styles.lead}>
            A guide to the planned fix-verification process, its limitations,
            and safe ways to get engineering help. This is not an active
            financial or customer-support service.
          </p>
          <div className={styles.warning} role="status">
            <strong>No live escrow is available.</strong>
            <p>
              Do not send funds, upload credentials, install a purported
              CertiFiks GitHub App, or trust an unverified contract address.
              There are no authenticated money-moving actions on this site.
            </p>
          </div>
          <nav className={styles.jumpLinks} aria-label="Help topics">
            <a href="#roles">Role guides</a>
            <a href="#faq">Questions</a>
            <a href="#support">Support and incident reporting</a>
          </nav>
        </section>

        <section id="roles" className="container" aria-labelledby="roles-title">
          <h2 id="roles-title" className={styles.sectionTitle}>Start with your role</h2>
          <div className={styles.grid}>
            {roles.map((role) => (
              <article key={role.id} className={styles.card}>
                <h3>{role.title}</h3>
                <p>{role.detail}</p>
                <p className={styles.blocked}>
                  <strong>Currently unavailable:</strong> {role.blocked}
                </p>
              </article>
            ))}
          </div>
          <Link href="/onboarding" className={styles.link}>
            Read complete role prerequisites ↗
          </Link>
        </section>

        <section id="faq" className="container" aria-labelledby="faq-title">
          <h2 id="faq-title" className={styles.sectionTitle}>Frequently asked questions</h2>
          <div className={styles.faq}>
            {questions.map((question) => (
              <details key={question.title}>
                <summary>{question.title}</summary>
                <p>{question.answer}</p>
              </details>
            ))}
          </div>
          <div className={styles.contextLinks}>
            <Link href="/wallet">Wallet and finality guide ↗</Link>
            <Link href="/disputes">Dispute safeguards ↗</Link>
            <a href="https://github.com/EcstaceeLOR/CertiFiks/blob/main/SECURITY.md" target="_blank" rel="noreferrer">
              Security disclosure policy ↗
            </a>
          </div>
        </section>

        <section id="support" className="container" aria-labelledby="support-title">
          <h2 id="support-title" className={styles.sectionTitle}>Support, abuse, and security</h2>
          <div className={styles.supportGrid}>
            <div className={styles.card}>
              <h3>Public product problem</h3>
              <p>
                Report a reproducible non-sensitive bug in the public issue
                tracker. Include the public URL, expected result, browser, and
                redacted steps. Do not include private repository content,
                passwords, recovery phrases, wallet keys, tokens, or personal data.
              </p>
              <a className={styles.link} href="https://github.com/EcstaceeLOR/CertiFiks/issues/new/choose" target="_blank" rel="noreferrer">
                Open GitHub issue tracker ↗
              </a>
            </div>
            <div className={styles.card}>
              <h3>Security vulnerability or abuse</h3>
              <p>
                Do not disclose exploit details in public issues. Follow the
                repository security policy and use GitHub private
                vulnerability reporting if enabled, or agree on a private
                channel with the maintainer. No staffed incident hotline or
                guaranteed response time has been established.
              </p>
              <a className={styles.link} href="https://github.com/EcstaceeLOR/CertiFiks/security/policy" target="_blank" rel="noreferrer">
                Read security reporting instructions ↗
              </a>
            </div>
          </div>
          <p className={styles.disclosure}>
            This website does not grant legal, financial, security, or custody
            guarantees. The complete production terms, privacy disclosures,
            sanctions and jurisdictional review, and third-party support
            obligations require professional approval before any real-value
            service launches.
          </p>
        </section>
      </main>

      <footer className="site-footer">
        <div className="container footer-content">
          <span className="brand footer-brand">certifiks.</span>
          <p>In development. No live payments, audited escrow, or service SLA.</p>
          <Link href="/">Home ↗</Link>
        </div>
      </footer>
    </div>
  );
}
