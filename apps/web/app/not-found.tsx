import Link from "next/link";

export default function NotFound() {
  return (
    <main id="main-content" className="container onboarding-main">
      <div className="market-state">
        <div>
          <p className="eyebrow">NOT FOUND / 404</p>
          <h1>This page does not exist.</h1>
          <p>Check the link or return to the verified public overview. No private records are exposed by an invalid URL.</p>
          <Link href="/" className="button button-outline">Return home</Link>
        </div>
      </div>
    </main>
  );
}
