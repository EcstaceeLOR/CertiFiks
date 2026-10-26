import Link from "next/link";

export default function NotFound() {
  return (
    <main id="main-content" className="container recovery-page">
      <p className="eyebrow">404 / NO MATCHING PAGE</p>
      <h1>We couldn't find that page.</h1>
      <p>
        This address may have changed. A missing page does not imply that a
        bounty, payment, or verification record exists.
      </p>
      <Link className="button button-primary" href="/">
        Return to CertiFiks
      </Link>
    </main>
  );
}
