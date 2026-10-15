import type { Metadata } from "next";
import "./globals.css";
export const metadata: Metadata = {
  title: "CertiFiks — Engineering in progress",
  description: "Building verifiable software repair escrows. No live rewards or transactions are available.",
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>;
}
