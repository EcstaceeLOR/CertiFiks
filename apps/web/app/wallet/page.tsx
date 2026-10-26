import Link from "next/link";
import styles from "../verifier/verifier.module.css";

const states = [
  {
    number: "01",
    title: "Check chain identity",
    description:
      "A wallet connector must match the organizer-approved runtime, genesis and your selected account before a sensitive request is shown.",
  },
  {
    number: "02",
    title: "Get explicit wallet consent",
    description:
      "Fees, the intended contract, exact token units and signing intent must be shown before you approve a transaction in your own wallet.",
  },
  {
    number: "03",
    title: "Reconcile real finality",
    description:
      "A broadcast hash is not payment. A canonical finalized receipt, contract state and indexed escrow ledger must agree.",
  },
] as const;

export default function WalletSafetyPage() {
  return (
    <main id="main-content" className={styles.page}>
      <a className={styles.skip} href="#wallet-checks">
        Skip to wallet requirements
      </a>
      <header className={styles.header}>
        <div className={styles.headerInner}>
          <Link
            className={styles.wordmark}
            href="/"
            aria-label="CertiFiks home"
          >
            certi<span>fiks</span>.
          </Link>
          <nav aria-label="Wallet safety navigation" className={styles.nav}>
            <Link href="/">Overview</Link>
            <Link href="/onboarding">Account and chain requirements</Link>
          </nav>
        </div>
      </header>
      <div className={styles.body}>
        <p className={styles.eyebrow}>WALLET SAFETY / CHAIN VERIFICATION</p>
        <h1>
          Funds need <em>finality.</em>
        </h1>
        <p className={styles.lead}>
          Wallet approval, transaction broadcast and actual escrow funding are
          different states. CertiFiks will not call a reward paid or a bounty
          funded until independent chain evidence agrees.
        </p>
        <div className={styles.warning} role="status">
          <strong>Wallet connection and transfers are disabled.</strong>
          <p>
            Portaldot runtime compatibility, escrow deployment and supported
            wallet providers are not yet independently verified. This page does
            not connect a wallet, request a signature, accept a deposit or issue
            a payout.
          </p>
        </div>
        <section id="wallet-checks" aria-labelledby="wallet-checks-title">
          <div className={styles.sectionIntro}>
            <p className={styles.eyebrow}>REQUIRED SECURITY GATES</p>
            <h2 id="wallet-checks-title">No optimistic money states</h2>
          </div>
          <div className={styles.grid}>
            {states.map((step) => (
              <article className={styles.card} key={step.number}>
                <span className={styles.number}>{step.number}</span>
                <h3>{step.title}</h3>
                <p>{step.description}</p>
              </article>
            ))}
          </div>
        </section>
        <section className={styles.queue} aria-labelledby="wallet-state-title">
          <div>
            <p className={styles.eyebrow}>LIVE TRANSACTION RECONCILIATION</p>
            <h2 id="wallet-state-title">No supported chain connected</h2>
            <p>
              Signing rejection, RPC outages, wrong-network prompts, replaced or
              reverted transactions and unfinalized transfers will always block
              verified funding and payouts.
            </p>
          </div>
          <div className={styles.queueStatus}>
            <span>RUNTIME APPROVAL REQUIRED</span>
            <strong>Transfers blocked</strong>
          </div>
        </section>
        <section className={styles.footerNote}>
          <h2>No private keys. No silent approvals.</h2>
          <p>
            The backend must not hold customer signing keys or initiate
            money-moving wallet actions. A transfer always requires explicit
            user authorization and independent post-transaction reconciliation.
          </p>
          <Link className={styles.link} href="/onboarding">
            Review prerequisites ↗
          </Link>
          <a
            className={styles.secondaryLink}
            href="https://github.com/EcstaceeLOR/CertiFiks/issues/36"
            target="_blank"
            rel="noreferrer"
          >
            Track wallet integration ↗
          </a>
        </section>
      </div>
    </main>
  );
}
