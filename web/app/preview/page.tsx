import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { DashboardPreview } from "@/components/preview/dashboard-preview";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "Dashboard design preview",
  description: "An interactive NexaFlow design preview. All figures are sample data; no wallet transactions are available.",
  robots: { index: false, follow: false },
  openGraph: { title: "NexaFlow design preview", description: "Sample data. Not a live account.", images: [] },
  twitter: { title: "NexaFlow design preview", description: "Sample data. Not a live account.", images: [] },
};

export default function PreviewPage() {
  // Server-only opt-in. Shipping this source does not expose the prototype by default.
  if (process.env.NODE_ENV !== "development" && process.env.NEXAFLOW_DESIGN_PREVIEW !== "true") notFound();
  return <DashboardPreview />;
}
