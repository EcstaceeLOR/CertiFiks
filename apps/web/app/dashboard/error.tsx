"use client";

import Link from "next/link";

export default function HistoryError({ reset }: { error: Error; reset: () => void }) {
  return (
    <main id="main-content" className="container recovery-page">
      <p className="eyebrow">PUBLIC HISTORY / DATA UNAVAILABLE</p>
      <h1>We couldn't verify these records.</h1>
      <p role="alert" aria-live="assertive">
        No listings are shown because the public API request could not complete.
        Please don't assume previously displayed funding or verification is current.
      </p>
      <div className="recovery-actions">
        <button className="button button-primary" type="button" onClick={reset}>
          Try again
        </button>
        <Link href="/" className="button button-outline">
          Back to overview
        </Link>
      </div>
    </main>
  );
}
