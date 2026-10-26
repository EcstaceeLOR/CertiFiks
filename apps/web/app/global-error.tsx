"use client";

import { useEffect, useRef } from "react";

export default function GlobalError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus(), []);
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", margin: 0, padding: "3rem", background: "#0c1519", color: "#f1f4f1" }}>
        <main>
          <h1 ref={heading} tabIndex={-1}>CertiFiks cannot load safely.</h1>
          <p>Your transaction status is unknown. Check independently verified wallet and chain receipts before retrying a financial action.</p>
          <button type="button" onClick={reset} style={{ padding: "1rem", minHeight: 48, background: "#b7f4b8", color: "#11231a", borderRadius: 8 }}>
            Retry loading
          </button>
          <p><a href="/" style={{ color: "#b7f4b8" }}>Return to the overview</a></p>
        </main>
      </body>
    </html>
  );
}
