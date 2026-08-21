import Link from "next/link";
import { redirect } from "next/navigation";
import { addressForReferralCode } from "@/lib/referrals";

export default function ReferralRedirect({ params }: { params: { code: string } }) {
  const sponsor = addressForReferralCode(params.code);
  if (sponsor) redirect(`/app/join?ref=${encodeURIComponent(sponsor)}`);

  return (
    <main className="flex min-h-screen items-center justify-center bg-bg px-4">
      <section className="panel panel-sheen max-w-lg p-8 text-center">
        <h1 className="font-display text-xl font-semibold">Referral link unavailable</h1>
        <p className="mt-2 text-sm leading-relaxed text-muted">
          This link is incomplete or has been changed. Ask the person who shared
          it for a fresh NexaFlow referral link.
        </p>
        <Link href="/app/join" className="btn-gold mt-5 inline-flex px-5 py-2.5 text-sm">
          Open join page
        </Link>
      </section>
    </main>
  );
}
