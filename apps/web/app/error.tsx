"use client";

import Link from "next/link";
import { useEffect, useRef } from "react";

export default function ApplicationError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus(), []);
  return (
    <main id="main-content" className="container onboarding-main" aria-labelledby="recovery-title">
      <section className="market-state" role="alert">
        <div>
          <p className="eyebrow">SAFE RECOVERY</p>
          <h1 id="recovery-title" ref={heading} tabIndex={-1}>
            This page could not load.
          </h1>
          <p>
            Your action has not been confirmed. Recheck the real wallet,
            GitHub or chain receipt before attempting a payment or submission again.
            Error details and private data are never displayed here.
          </p>
          <div className="hero-actions">
            <button className="button button-primary" type="button" onClick={reset}>
              Retry loading this page
            </button>
            <Link href="/" className="button button-outline">Go to overview</Link>
          </div>
        </div>
      </section>
    </main>
  );
}
