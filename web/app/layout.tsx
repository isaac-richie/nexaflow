import type { Metadata, Viewport } from "next";
import "./globals.css";
import { Providers } from "./providers";
import { BackgroundEffects } from "@/components/background-effects";

export const metadata: Metadata = {
  title: {
    default: "NexaFlow | Every position pays you back",
    template: "%s · NexaFlow",
  },
  description:
    "A binary membership protocol on BNB Chain. When someone fills a slot on your board, you get paid in the same transaction. Nothing to claim.",
  openGraph: {
    title: "NexaFlow",
    description:
      "When someone fills a slot on your board, you get paid in the same transaction.",
    type: "website",
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
        <BackgroundEffects />
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
