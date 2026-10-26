"use client";

import { useEffect, useState } from "react";

/**
 * Connectivity state is informational only. navigator.onLine is not proof
 * of backend or blockchain availability. Refresh is explicit: balances and
 * transaction finality must always come from a new verified server/chain read.
 */
export function ConnectivityNotice() {
  const [state, setState] = useState<"unknown" | "offline" | "restored">("unknown");

  useEffect(() => {
    const goOffline = () => setState("offline");
    const goOnline = () => setState((previous) => (previous === "offline" ? "restored" : "unknown"));
    if (!navigator.onLine) goOffline();
    window.addEventListener("offline", goOffline);
    window.addEventListener("online", goOnline);
    return () => {
      window.removeEventListener("offline", goOffline);
      window.removeEventListener("online", goOnline);
    };
  }, []);

  if (state === "unknown") return null;
  return (
    <div
      className="connectivity-notice"
      role={state === "offline" ? "alert" : "status"}
      aria-live={state === "offline" ? "assertive" : "polite"}
      data-connection-state={state}
    >
      <div className="container connectivity-notice__inner">
        <div>
          <strong>{state === "offline" ? "Your device appears offline." : "Network connection returned."}</strong>{" "}
          <span>
            {state === "offline"
              ? "Published listings and transaction states may be unavailable or outdated. Do not assume a payment succeeded."
              : "This does not confirm API or chain recovery. Refresh to request the latest verified information."}
          </span>
        </div>
        {state === "restored" ? (
          <button
            className="connectivity-notice__action"
            type="button"
            onClick={() => window.location.reload()}
          >
            Refresh verified data
          </button>
        ) : null}
      </div>
    </div>
  );
}
