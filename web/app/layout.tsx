import type { Metadata, Viewport } from "next";
import "./globals.css";
import { SiteRuntime } from "@/components/site-runtime";

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://nexaflow.app",
  ),
  title: {
    default: "NexaFlow | Move forward. Together.",
    template: "%s · NexaFlow",
  },
  description:
    "Explore six membership stages on BNB Smart Chain. Track your boards, stage progress and referral network with NexaFlow.",
  applicationName: "NexaFlow",
  manifest: "/site.webmanifest",
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/favicon.svg", type: "image/svg+xml" },
      { url: "/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/apple-touch-icon.png", sizes: "180x180", type: "image/png" }],
  },
  openGraph: {
    title: "NexaFlow",
    description:
      "When someone fills a slot on your board, you get paid in the same transaction.",
    type: "website",
    url: "/",
    siteName: "NexaFlow",
    images: [{ url: "/og-image.png", width: 1200, height: 630, alt: "NexaFlow" }],
  },
  twitter: {
    card: "summary_large_image",
    title: "NexaFlow",
    description: "Every position pays you back. BNB Smart Chain.",
    images: ["/og-image.png"],
  },
  robots: { index: true, follow: true },
};

export const viewport: Viewport = {
  themeColor: "#0B0E11",
  width: "device-width",
  initialScale: 1,
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="min-h-screen antialiased">
        <SiteRuntime>{children}</SiteRuntime>
      </body>
    </html>
  );
}
