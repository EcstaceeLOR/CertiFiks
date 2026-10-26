import Link from "next/link";
import styles from "../verifier/verifier.module.css";

const stages = [
  {
    number: "01",
    title: "Open a bounded case",
    description:
      "The sponsor or assigned contributor must identify the exact bounty and record a content digest of their complaint and supporting evidence.",
  },
  {
    number: "02",
    title: "Preserve both sides",
    description:
      "Each authorized party gets a private, immutable evidence timeline. Replayed updates cannot change a prior statement or escape another team's case.",
  },
  {
    number: "03",
    title: "Independent resolution",
    description:
      "Assigned arbitrators must be checked for conflicts, explain the outcome, sign the exact evidence and verify on-chain finality before any settlement.",
  },
] as const;

export default function DisputesPage() {
  return (
    <main id="main-content" className={styles.page}>
      <a className={styles.skip} href="#dispute-workflow">Skip to dispute requirements</a>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <Link className={styles.wordmark} href="/" aria-label="CertiFiks home">
            certi<span>fiks</span>.
          </Link>
          <nav aria-label="Dispute navigation" className={styles.nav}>
            <Link href="/">Overview</Link>
            <Link href="/onboarding">Roles and permissions</Link>
            <Link href="/verifier">Reviewer safety</Link>
          </nav>
        </div>
      </header>
      <div className={styles.body}>
        <p className={styles.eyebrow}>DISPUTES / TRUSTED CASE RECORDS</p>
        <h1>
          A decision needs <em>a record.</em>
        </h1>
        <p className={styles.lead}>
          A contested bug-fix bounty deserves transparent evidence and a bounded
          review process—not a support ticket that can silently move escrow funds.
          CertiFiks is building immutable, role-scoped dispute histories.
        </p>
        <div className={styles.warning} role="status">
          <strong>Live disputes and on-chain resolution are not enabled.</strong>
          <p>
            This page cannot start a case, display confidential evidence or
            authorize payouts. Secure account sessions, arbitrator assignment,
            private artifact access and verified settlement transactions are still
            required. Do not send funds.
          </p>
        </div>
        <section id="dispute-workflow" aria-labelledby="dispute-process-title">
          <div className={styles.sectionIntro}>
            <p className={styles.eyebrow}>A VERIFIABLE DISPUTE PROCESS</p>
            <h2 id="dispute-process-title">Evidence, response, resolution</h2>
          </div>
          <div className={styles.grid}>
            {stages.map((stage) => (
              <article key={stage.number} className={styles.card}>
                <span className={styles.number}>{stage.number}</span>
                <h3>{stage.title}</h3>
                <p>{stage.description}</p>
              </article>
            ))}
          </div>
        </section>
        <section className={styles.queue} aria-labelledby="case-access-title">
          <div>
            <p className={styles.eyebrow}>PRIVATE CASES</p>
            <h2 id="case-access-title">No authenticated case access</h2>
            <p>
              Case records are private to authorized participants and individually
              assigned arbitrators. No public list or fabricated dispute activity
              is presented. Ledger entries are only content-addressed metadata.
            </p>
          </div>
          <div className={styles.queueStatus}>
            <span>IDENTITY AND AUTHORIZATION REQUIRED</span>
            <strong>Dispute actions disabled</strong>
          </div>
        </section>
        <section className={styles.footerNote} aria-labelledby="case-safety-title">
          <h2 id="case-safety-title">There is no automatic verdict.</h2>
          <p>
            A case timeline cannot release or refund escrow. On-chain appeals,
            settlement and withdrawal must independently enforce the authorized
            signer policy, deadline windows and non-duplicated accounting.
          </p>
          <Link className={styles.link} href="/onboarding">Understand the roles ↗</Link>
          <a className={styles.secondaryLink}
            href="https://github.com/EcstaceeLOR/CertiFiks/issues/35"
            target="_blank" rel="noreferrer">
            Read implementation requirements ↗
          </a>
        </section>
      </div>
    </main>
  );
}
