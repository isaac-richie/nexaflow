import { keeperAuthorized, queueKeeper } from "@/lib/server/queue-keeper";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export async function GET(request: Request) {
  const headers = { "Cache-Control": "no-store" };
  if (!keeperAuthorized(request.headers.get("authorization"), process.env.CRON_SECRET)) return Response.json({ status: "unauthorized" }, { status: 401, headers });
  try {
    const result = await queueKeeper();
    const alert = ["reverted", "pending_stalled", "pending_deployment_mismatch", "no_progress", "budget_or_lease_blocked", "lease_lost", "recovery_pending"].includes(result.status);
    // Never log raw provider errors, signed transactions or credentials.
    console.info("queue_keeper", JSON.stringify(result));
    return Response.json(result, { status: alert ? 503 : 200, headers });
  } catch {
    console.error("queue_keeper", "Check failed; inspect configuration, storage, pending intent and gas funding.");
    return Response.json({ status: "check_failed", message: "Keeper stopped safely. Check configuration, storage, pending transaction and gas funding before retrying." }, { status: 503, headers });
  }
}
