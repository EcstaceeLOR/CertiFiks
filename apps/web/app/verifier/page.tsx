import Link from "next/link";
import styles from "./verifier.module.css";

const duties = [
  {
    number: "01",
    title: "Confirm your role",
    description:
      "An enrolled reviewer identity, active organization membership and conflict-of-interest screening are required before private evidence can be revealed.",
  },
  {
    number: "02",
    title: "Read pinned evidence",
    description:
      "Compare the exact baseline and candidate commits, committed test plan, runner image digest and independently retained test artifacts.",
  },
  {
    number: "03",
    title: "Make an independent decision",
    description:
      "A claimed passing run is not an accepted fix. An explicit reason, signed commitment, expiry and independent quorum are needed before any on-chain attestation.",
  },
] as const;

export default function VerifierPage() {
  return (
    <main id="main-content" className={styles.page}>
      <a href="#review-requirements" className={styles.skip}>Skip to review requirements</a>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <Link href="/" className={styles.wordmark} aria-label="CertiFiks home">
            certi<span>fiks</span>.
          </Link>
          <nav aria-label="Verifier navigation" className={styles.nav}>
            <Link href="/">Overview</Link>
            <Link href="/onboarding">How verification works</Link>
          </nav>
        </div>
      </header>
      <div className={styles.body}>
        <p className={styles.eyebrow}>INDEPENDENT VERIFICATION / ROLE ACCESS</p>
        <h1>Evidence before <em>approval.</em></h1>
        <p className={styles.lead}>
          An actual verification decision needs independently reproducible test outcomes,
          trusted reviewer identity and report signatures tied to an immutable commit.
          Nothing is approved just because a runner completed.
        </p>
        <div className={styles.warning} role="status" aria-live="polite">
          <strong>Live reviewer sessions are not enabled.</strong>
          <p>
            This screen will not display private cases or allow signatures until secure
            wallet/GitHub authentication, reviewer enrollment and evidence access are connected.
            No attestation or payout is performed here.
          </p>
        </div>
        <section id="review-requirements" aria-labelledby="requirements-title">
          <div className={styles.sectionIntro}>
            <p className={styles.eyebrow}>REVIEWER WORKFLOW</p>
            <h2 id="requirements-title">Three gates before a verdict</h2>
          </div>
          <div className={styles.grid}>
            {duties.map((step) => (
              <article key={step.number} className={styles.card}>
                <span className={styles.number}>{step.number}</span>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </article>
            ))}
          </div>
        </section>
        <section aria-labelledby="queue-title" className={styles.queue}>
          <div>
            <p className={styles.eyebrow}>PROTECTED REVIEW QUEUE</p>
            <h2 id="queue-title">No authenticated cases available here</h2>
            <p>
              The server-side preflight checks tenant scope and excludes a bounty's sponsor
              or contributing developer. Public browsers are not given private artifact URLs,
              review votes or a fabricated approval queue.
            </p>
          </div>
          <div className={styles.queueStatus}>
            <span>SESSION REQUIRED</span>
            <strong>Review disabled</strong>
          </div>
        </section>
        <section aria-labelledby="integrity-title" className={styles.footerNote}>
          <h2 id="integrity-title">Nothing is signed automatically.</h2>
          <p>
            On-chain attestation, reviewer separation, report retention, appeal windows
            and escrow settlement require additional independent checks and an explicit,
            authenticated user action. They are not yet available.
          </p>
          <Link href="/onboarding" className={styles.link}>View role requirements ↗</Link>
          <a href="https://github.com/EcstaceeLOR/CertiFiks/issues/34"
            rel="noreferrer" target="_blank" className={styles.secondaryLink}>
            Follow verifier implementation ↗
          </a>
        </section>
      </div>
    </main>
  );
}
