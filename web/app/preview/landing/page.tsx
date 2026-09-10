import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LandingPreview } from "@/components/preview/landing-preview";

export const dynamic = "force-dynamic";
export const metadata: Metadata = {
  title: "The next chapter — landing preview",
  description: "Explore the NexaFlow landing-page design. This is a non-transactional preview, not a live V6 launch.",
  robots: { index: false, follow: false },
  openGraph: { title: "NexaFlow — design preview", description: "A non-transactional landing-page preview.", images: [] },
  twitter: { title: "NexaFlow — design preview", description: "A non-transactional landing-page preview.", images: [] },
};

export default function LandingPreviewPage() {
  if (process.env.NODE_ENV !== "development" && process.env.NEXAFLOW_DESIGN_PREVIEW !== "true") notFound();
  return <LandingPreview />;
}
