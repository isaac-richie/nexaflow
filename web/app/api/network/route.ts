import { NextRequest, NextResponse } from "next/server";
import { getAddress, isAddress } from "viem";
import { summarizeNetwork } from "@/lib/network-graph";
import { getRegistrationSnapshot } from "@/lib/server/registration-index";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

function boundedInteger(
  raw: string | null,
  fallbackValue: number,
  minimum: number,
  maximum: number,
): number {
  if (!raw || !/^\d+$/.test(raw)) return fallbackValue;
  return Math.min(maximum, Math.max(minimum, Number(raw)));
}

export async function GET(request: NextRequest) {
  const contract = request.nextUrl.searchParams.get("contract");
  const version = request.nextUrl.searchParams.get("version");
  const chain = request.nextUrl.searchParams.get("chain");
  if (((process.env.NEXT_PUBLIC_MEMBERSHIP_VERSION ?? "v5") === "v6" && (!contract || !version || !chain)) ||
    (contract && contract.toLowerCase() !== process.env.NEXT_PUBLIC_MEMBERSHIP_ADDRESS?.toLowerCase()) ||
    (version && version !== (process.env.NEXT_PUBLIC_MEMBERSHIP_VERSION ?? "v5")) ||
    (chain && chain !== (process.env.NEXT_PUBLIC_CHAIN === "bsc" ? "56" : "97"))) {
    return NextResponse.json({ error: "This page uses a different deployment. Reload the website." }, { status: 409 });
  }
  const rawAddress = request.nextUrl.searchParams.get("address");
  if (!rawAddress || !isAddress(rawAddress)) {
    return NextResponse.json({ error: "A valid member address is required." }, { status: 400 });
  }

  const generation = boundedInteger(
    request.nextUrl.searchParams.get("generation"),
    1,
    1,
    256,
  );
  const offset = boundedInteger(request.nextUrl.searchParams.get("offset"), 0, 0, 1_000_000);
  const limit = boundedInteger(request.nextUrl.searchParams.get("limit"), 20, 1, 50);

  try {
    const snapshot = await getRegistrationSnapshot();
    const network = summarizeNetwork(
      snapshot.records,
      getAddress(rawAddress),
      generation,
      offset,
      limit,
    );

    return NextResponse.json(
      { ...network, syncedBlock: snapshot.syncedBlock },
      {
        headers: {
          "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300",
        },
      },
    );
  } catch (error) {
    console.error("Network index request failed", error);
    return NextResponse.json(
      { error: "Your network is temporarily unavailable. Please try again shortly." },
      { status: 503 },
    );
  }
}
