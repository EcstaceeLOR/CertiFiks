"use client";

import Link from "next/link";
import { useEffect } from "react";

export default function PageError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    // Avoid sending sensitive response bodies, wallet addresses or artifacts to
    // analytics. Production error tracking requires explicit secure opt-in.
    void error.digest;
  }, [error]);

  return (
    <main id="main-content" className="container recovery-page" role="main">
      <p className="eyebrow">SERVICE RESPONSE / CANNOT VERIFY</p>
      <h1>That page didn't load.</h1>
      <p role="alert" aria-live="assertive">
        The request was interrupted. No transaction, payout, or verification
        result has been confirmed by this page.
      </p>
      <div className="recovery-actions">
        <button className="button button-primary" type="button" onClick={reset}>
          Retry the request
        </button>
        <Link className="button button-outline" href="/">
          Return to overview
        </Link>
      </div>
      <p className="recovery-note">
        If you were using a wallet, check the independently verified chain
        receipt before attempting any payment again.
      </p>
    </main>
  );
}
