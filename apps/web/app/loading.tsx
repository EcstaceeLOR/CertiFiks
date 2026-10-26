export default function AppLoading() {
  return (
    <main id="main-content" className="container onboarding-main">
      <div role="status" aria-live="polite" aria-atomic="true" className="market-state">
        <div>
          <h1>Loading the latest public information…</h1>
          <p>No bounty balance, verification or transaction is confirmed by this loading screen.</p>
        </div>
      </div>
    </main>
  );
}
