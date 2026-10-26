export default function DashboardLoading() {
  return (
    <main className="container recovery-page" id="main-content">
      <div role="status" aria-live="polite" aria-busy="true">
        <p className="eyebrow">PUBLIC HISTORY / REQUESTING RECORDS</p>
        <h1>Checking public records.</h1>
        <p>
          Waiting for the published, finalized-only API. Nothing shown here
          represents a confirmed balance, verified fix, or payment.
        </p>
      </div>
    </main>
  );
}
