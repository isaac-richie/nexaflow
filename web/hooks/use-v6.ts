"use client";

import { useRef, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useAccount, usePublicClient, useWalletClient } from "wagmi";
import { decodeEventLog, erc20Abi, zeroAddress, type Address, type Hash, type PublicClient } from "viem";
import { ACTIVE_CHAIN, IS_DEPLOYED, IS_V6, MEMBERSHIP_ADDRESS, PAYMENT_TOKEN_ADDRESS, V6_RUNTIME_HASH } from "@/lib/contracts/config";
import { BINARY_MEMBERSHIP_V6_ABI as abi } from "@/lib/contracts/binaryMembershipV6Abi";
import { checkV6Purchase, readV6Snapshot, type V6Deployment } from "@/lib/v6";
import { NO_BACKGROUND_RPC, RPC_CACHE_MS, RPC_POLLING_INTERVAL_MS } from "@/lib/rpc-policy";

export const v6Deployment: V6Deployment = { chainId: ACTIVE_CHAIN.id, address: MEMBERSHIP_ADDRESS, token: PAYMENT_TOKEN_ADDRESS, runtimeHash: V6_RUNTIME_HASH };
export const v6Scope = ["membership-v6", ACTIVE_CHAIN.id, MEMBERSHIP_ADDRESS.toLowerCase(), PAYMENT_TOKEN_ADDRESS.toLowerCase(), V6_RUNTIME_HASH] as const;

export function useV6Snapshot() {
  const account = useAccount();
  const client = usePublicClient({ chainId: ACTIVE_CHAIN.id });
  const query = useQuery({
    queryKey: [...v6Scope, "snapshot", account.address?.toLowerCase()],
    queryFn: () => readV6Snapshot(client as PublicClient, v6Deployment, account.address!),
    enabled: IS_V6 && IS_DEPLOYED && Boolean(client && account.address) && account.chainId === ACTIVE_CHAIN.id,
    staleTime: RPC_CACHE_MS.board, retry: 1, ...NO_BACKGROUND_RPC,
  });
  return { ...query, client: client as PublicClient | undefined, account };
}

export function v6Error(error: unknown): string {
  const text = error instanceof Error ? error.message : String(error);
  if (/User rejected|User denied|rejected the request/i.test(text)) return "Cancelled in your wallet. No new transaction was submitted by this action.";
  if (/UnknownSponsor/.test(text)) return "That sponsor has not joined V6. Use a V6 member’s address or leave it blank.";
  if (/PlacementUnavailable/.test(text)) return "No placement is available yet. Try again after pending re-entries are processed.";
  if (/EmergencyRecoveryActive|EnforcedPause/.test(text)) return "The protocol is paused. Do not send funds manually.";
  if (/insufficient funds/i.test(text)) return "Your wallet needs enough USDT for entry and BNB for network fees.";
  if (/reverted/i.test(text)) return "The transaction did not complete. Check its receipt before trying again; network fees may apply.";
  if (/HTTP|RPC|fetch|timeout|rate limit/i.test(text)) return "The network could not confirm this request. Check any submitted transaction before retrying.";
  return text.split("\n")[0].slice(0, 240);
}

/** Simulate immediately before each signature; cached dashboard data never authorizes spending. */
export function useV6Transaction() {
  const { address, chainId } = useAccount();
  const client = usePublicClient({ chainId: ACTIVE_CHAIN.id });
  const { data: wallet } = useWalletClient();
  const cache = useQueryClient();
  const lock = useRef(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string>();
  const [error, setError] = useState<string>();
  const [hash, setHash] = useState<Hash>();

  async function execute(action: "approve" | "purchase" | "claim" | "process", options: { stage?: number; fee?: bigint; sponsor?: Address; recipient?: Address } = {}) {
    if (lock.current) return;
    lock.current = true; setBusy(true); setMessage(undefined); setError(undefined); setHash(undefined);
    try {
      if (!IS_V6 || !IS_DEPLOYED || !client || !wallet || !address || chainId !== ACTIVE_CHAIN.id) throw new Error(`Connect your wallet to ${ACTIVE_CHAIN.name}.`);
      const checkWallet = async () => {
        if (await wallet.getChainId() !== ACTIVE_CHAIN.id || (await wallet.getAddresses())[0]?.toLowerCase() !== address.toLowerCase()) throw new Error("Wallet changed. Please refresh and review this action again.");
      };
      await checkWallet();
      setMessage("Checking the current contract state…");
      const fresh = await readV6Snapshot(client as PublicClient, v6Deployment, address);
      let submitted: Hash;
      const sponsor = options.sponsor ?? zeroAddress;
      const stage = options.stage ?? -1;
      if (action === "approve" || action === "purchase") {
        checkV6Purchase(fresh, address, sponsor, stage, options.fee ?? -1n);
        if (!fresh.registered && sponsor !== zeroAddress && !await client.readContract({ address: MEMBERSHIP_ADDRESS, abi, functionName: "registered", args: [sponsor] })) throw new Error("That sponsor has not joined V6. Leave the field blank to start under the protocol.");
      }
      const send = async (request: Parameters<typeof wallet.writeContract>[0]) => {
        await checkWallet(); setMessage("Confirm in your wallet…");
        return wallet.writeContract({ ...request, account: address, chain: ACTIVE_CHAIN });
      };
      if (action === "approve") {
        const simulated = await client.simulateContract({ address: PAYMENT_TOKEN_ADDRESS, abi: erc20Abi, functionName: "approve", args: [MEMBERSHIP_ADDRESS, options.fee!], account: address });
        submitted = await send(simulated.request);
      } else if (action === "purchase") {
        if (fresh.allowance < options.fee!) throw new Error("Approve this stage’s exact USDT fee first.");
        const simulated = fresh.registered
          ? await client.simulateContract({ address: MEMBERSHIP_ADDRESS, abi, functionName: "joinStage", args: [stage], account: address })
          : await client.simulateContract({ address: MEMBERSHIP_ADDRESS, abi, functionName: "register", args: [sponsor], account: address });
        submitted = await send(simulated.request);
      } else if (action === "claim") {
        if (fresh.claimable === 0n) throw new Error("No unpaid payout is available to claim.");
        const simulated = await client.simulateContract({ address: MEMBERSHIP_ADDRESS, abi, functionName: "claim", args: [options.recipient ?? address], account: address });
        submitted = await send(simulated.request);
      } else {
        if (fresh.recovery) throw new Error("Re-entry processing is frozen during emergency recovery.");
        if (!Number.isInteger(stage) || stage < 0 || stage > 5 || !fresh.stages[stage].latest?.queued) throw new Error("There is no queued board to process for this stage.");
        const simulated = await client.simulateContract({ address: MEMBERSHIP_ADDRESS, abi, functionName: "processReentries", args: [stage, 4n], account: address });
        submitted = await send(simulated.request);
      }
      setHash(submitted); setMessage("Submitted. Waiting for confirmation…");
      let cancelled = false;
      const receipt = await client.waitForTransactionReceipt({ hash: submitted, confirmations: 2, pollingInterval: RPC_POLLING_INTERVAL_MS, timeout: 180_000,
        onReplaced: replacement => { setHash(replacement.transactionReceipt.transactionHash); if (replacement.reason === "cancelled") cancelled = true; },
      });
      setHash(receipt.transactionHash);
      if (cancelled) throw new Error("Transaction cancelled. Your stage was not joined by this action.");
      if (receipt.status !== "success") throw new Error("Transaction reverted.");
      if (action === "purchase" || action === "claim") {
        const matched = receipt.logs.some(log => {
          if (log.address.toLowerCase() !== MEMBERSHIP_ADDRESS.toLowerCase()) return false;
          try {
            const event = decodeEventLog({ abi, data: log.data, topics: log.topics });
            if (action === "purchase") return event.eventName === "PositionOpened" && event.args.member.toLowerCase() === address.toLowerCase() && event.args.stage === stage;
            return event.eventName === "PayoutClaimed" && event.args.owner.toLowerCase() === address.toLowerCase() && event.args.recipient.toLowerCase() === (options.recipient ?? address).toLowerCase();
          } catch { return false; }
        });
        if (!matched) throw new Error("Receipt did not confirm the requested action. Check the transaction before retrying.");
      }
      if (action === "approve") {
        const allowance = await client.readContract({ address: PAYMENT_TOKEN_ADDRESS, abi: erc20Abi, functionName: "allowance", args: [address, MEMBERSHIP_ADDRESS] });
        if (allowance < options.fee!) throw new Error("The required allowance is not available. Review your token approval.");
      }
      setMessage(action === "approve" ? "Approval confirmed. Now select Join to complete your registration." : action === "purchase" ? `Stage ${stage + 1} joined successfully. View your board below or on My boards.` : action === "claim" ? "Payout claimed successfully." : "Processing transaction confirmed. Placement may still be pending; refresh to see your board.");
    } catch (failure) { setError(v6Error(failure)); setMessage(undefined); }
    finally {
      await cache.invalidateQueries({ queryKey: v6Scope });
      lock.current = false; setBusy(false);
    }
  }
  return { execute, busy, message, error, hash };
}
