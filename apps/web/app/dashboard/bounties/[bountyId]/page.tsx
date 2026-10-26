import Link from "next/link";
import {
  checkPublicHistoryItem,
  safePublicApiOrigin,
  type PublicHistoryItem,
} from "../../history.js";

export const dynamic = "force-dynamic";

type Outcome = { kind: "unavailable" | "not-found" } | { kind: "record"; item: PublicHistoryItem };
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/;

async function loadPublicRecord(bountyId: string): Promise<Outcome> {
  const api = safePublicApiOrigin(process.env.CERTIFIKS_API_BASE_URL);
  if (!api) return { kind: "unavailable" };
  const path = new URL(`/v1/bounties/${bountyId}`, api);
  try {
    const response = await fetch(path.href, {
      method: "GET", cache: "no-store", redirect: "error",
      signal: AbortSignal.timeout(6000),
    });
    if (response.status === 404) return { kind: "not-found" };
    if (!response.ok) return { kind: "unavailable" };
    const item: unknown = await response.json();
    if (!checkPublicHistoryItem(item) || item.bountyId !== bountyId)
      return { kind: "unavailable" };
    return { kind: "record", item };
  } catch {
    return { kind: "unavailable" };
  }
}

export default async function PublicBountyDetail({
  params,
}: {
  params: Promise<{ bountyId: string }>;
}) {
  const { bountyId } = await params;
  const result: Outcome = UUID.test(bountyId)
    ? await loadPublicRecord(bountyId)
    : { kind: "not-found" };
  return (
    <main className="container onboarding-main" id="main-content">
      <Link href="/dashboard" className="text-link">← Back to public history</Link>
      <div className="onboarding-intro">
        <p className="eyebrow">FINALIZED PUBLIC INDEX / READ ONLY</p>
        <h1>Public bounty <em>record.</em></h1>
        <p>No private review reports, sponsor profile, unpublished acceptance tests or custody guarantees are disclosed here.</p>
      </div>
      {result.kind === "record" ? (
        <section className="role-right" aria-label="Published bounty metadata">
          <h2>{result.item.repositoryFullName}</h2>
          <dl className="public-record-list">
            <dt>Bounty ID</dt><dd>{result.item.bountyId}</dd>
            <dt>Published state</dt><dd>{result.item.state}</dd>
            <dt>Reward atomic units</dt><dd>{result.item.rewardAtoms}</dd>
            <dt>Chain ID</dt><dd>{result.item.chainId}</dd>
            <dt>On-chain reference</dt><dd>{result.item.onchainBountyId}</dd>
            <dt>Manifest commitment</dt><dd>{result.item.manifestDigest}</dd>
            <dt>Public record created at</dt><dd>{result.item.createdAt}</dd>
          </dl>
          <div role="status" className="availability-alert">
            <span aria-hidden="true">!</span>
            <div><strong>Verification and payment are not established.</strong>
              <span>This record does not prove a completed fix, independently reconciled escrow balance or payout.</span>
            </div>
          </div>
        </section>
      ) : (
        <div className="market-state" role="status">
          <div>
            <h2>{result.kind === "not-found" ? "No public record found" : "Public record unavailable"}</h2>
            <p>{result.kind === "not-found"
              ? "This identifier is not in the published finalized index."
              : "The live public API is not connected or could not return a verified record."}</p>
          </div>
        </div>
      )}
    </main>
  );
}
