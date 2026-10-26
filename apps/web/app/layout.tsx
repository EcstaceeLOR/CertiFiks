import type { Metadata } from "next";
import { ConnectivityNotice } from "./connectivity-notice";
import "./globals.css";
export const metadata: Metadata = {
  title: "CertiFiks — Prove the Fix. Release the Reward.",
  description:
    "Build independently reproducible software repairs with transparent proof. CertiFiks is under development; no live funding or payouts are available.",
};
export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>
        <ConnectivityNotice />
        {children}
      </body>
    </html>
  );
}
