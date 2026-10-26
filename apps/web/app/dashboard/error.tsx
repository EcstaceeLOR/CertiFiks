"use client";

import Link from "next/link";
import { useEffect, useRef } from "react";

export default function HistoryError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus(), []);
  return (
    <main id="main-content" className="container onboarding-main">
      <div className="market-state" role="alert">
        <div>
          <h1 ref={heading} tabIndex={-1}>Public history is unavailable.</h1>
          <p>Fresh public records could not be retrieved. No stale payout balances or inferred verification statuses are displayed.</p>
          <div className="hero-actions">
            <button type="button" className="button button-primary" onClick={reset}>Retry history</button>
            <Link href="/dashboard" className="button button-outline">Clear filters</Link>
          </div>
        </div>
      </div>
    </main>
  );
}
