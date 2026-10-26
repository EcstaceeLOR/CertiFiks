export default function HistoryLoading() {
  return (
    <main className="container onboarding-main" aria-busy="true">
      <div className="market-state" role="status" aria-live="polite" aria-atomic="true">
        <div>
          <h1>Retrieving published history…</h1>
          <p>Records are loading directly from the public index. Cached balances and placeholder totals are not shown.</p>
        </div>
      </div>
    </main>
  );
}
