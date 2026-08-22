"use client";

import { useCallback, useMemo, useState } from "react";
import {
  useAccount,
  useReadContract,
  useWaitForTransactionReceipt,
  useWriteContract,
} from "wagmi";
import { erc20Abi, maxUint256 } from "viem";
import { BINARY_MEMBERSHIP_ABI } from "@/lib/contracts/binaryMembershipAbi";
import {
  IS_DEPLOYED,
  MEMBERSHIP_ADDRESS,
  PAYMENT_TOKEN_ADDRESS,
} from "@/lib/contracts/config";
import {
  NO_BACKGROUND_RPC,
  RPC_CACHE_MS,
  RPC_POLLING_INTERVAL_MS,
} from "@/lib/rpc-policy";

export type JoinStep = "idle" | "approving" | "joining" | "done";
export type JoinAction = "approve" | "register" | "joinStage";

/**
 * The two-transaction join flow: approve the payment token, then enter a
 * selected stage.
 *
 * Deliberately does NOT approve `maxUint256` by default. An unlimited approval
 * to any contract is a standing permission that survives long after the user
 * stops using the app; approving the exact fee means a compromised or upgraded
 * spender cannot drain a wallet later. The unlimited option is exposed for
 * members climbing several stages who would otherwise sign a fresh approval
 * each time, but it has to be chosen.
 */
export function useJoin() {
  const { address } = useAccount();
  const [action, setAction] = useState<JoinAction>();

  const {
    writeContractAsync,
    data: hash,
    isPending: isSigning,
    error: writeError,
    reset,
  } = useWriteContract();

  const { isLoading: isConfirming, isSuccess: isConfirmed } =
    useWaitForTransactionReceipt({
      hash,
      // Receipt polling exists only while a submitted transaction is pending.
      // Six seconds is responsive enough for BSC without checking every block.
      pollingInterval: RPC_POLLING_INTERVAL_MS,
    });

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: PAYMENT_TOKEN_ADDRESS,
    abi: erc20Abi,
    functionName: "allowance",
    args: address ? [address, MEMBERSHIP_ADDRESS] : undefined,
    query: {
      enabled: IS_DEPLOYED && Boolean(address),
      staleTime: RPC_CACHE_MS.wallet,
      ...NO_BACKGROUND_RPC,
    },
  });

  const { data: balance } = useReadContract({
    address: PAYMENT_TOKEN_ADDRESS,
    abi: erc20Abi,
    functionName: "balanceOf",
    args: address ? [address] : undefined,
    query: {
      enabled: IS_DEPLOYED && Boolean(address),
      staleTime: RPC_CACHE_MS.wallet,
      ...NO_BACKGROUND_RPC,
    },
  });

  /** Read the token's own decimals; never assume 18 or 6. */
  const { data: decimals } = useReadContract({
    address: PAYMENT_TOKEN_ADDRESS,
    abi: erc20Abi,
    functionName: "decimals",
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.tokenMetadata,
      ...NO_BACKGROUND_RPC,
    },
  });

  const { data: symbol } = useReadContract({
    address: PAYMENT_TOKEN_ADDRESS,
    abi: erc20Abi,
    functionName: "symbol",
    query: {
      enabled: IS_DEPLOYED,
      staleTime: RPC_CACHE_MS.tokenMetadata,
      ...NO_BACKGROUND_RPC,
    },
  });

  const approve = useCallback(
    async (amount: bigint, unlimited = false) => {
      setAction("approve");
      return writeContractAsync({
        address: PAYMENT_TOKEN_ADDRESS,
        abi: erc20Abi,
        functionName: "approve",
        args: [MEMBERSHIP_ADDRESS, unlimited ? maxUint256 : amount],
      });
    },
    [writeContractAsync],
  );

  const registerAtStage = useCallback(
    async (
      stageId: number,
      sponsor: `0x${string}`,
      parent: `0x${string}`,
      side: number,
      maximumPayment: bigint,
    ) => {
      setAction("register");
      return writeContractAsync({
        address: MEMBERSHIP_ADDRESS,
        abi: BINARY_MEMBERSHIP_ABI,
        functionName: "registerAtStageWithMaxPayment",
        args: [
          BigInt(stageId),
          sponsor,
          parent,
          side,
          maximumPayment,
          BigInt(Math.floor(Date.now() / 1000) + 20 * 60),
        ],
      });
    },
    [writeContractAsync],
  );

  const joinStage = useCallback(
    async (
      stageId: number,
      parent: `0x${string}`,
      side: number,
      maximumPayment: bigint,
    ) => {
      setAction("joinStage");
      return writeContractAsync({
        address: MEMBERSHIP_ADDRESS,
        abi: BINARY_MEMBERSHIP_ABI,
        functionName: "joinAnyStageWithMaxPayment",
        args: [
          BigInt(stageId),
          parent,
          side,
          maximumPayment,
          BigInt(Math.floor(Date.now() / 1000) + 20 * 60),
        ],
      });
    },
    [writeContractAsync],
  );

  const needsApproval = useCallback(
    (fee: bigint) => allowance === undefined || allowance < fee,
    [allowance],
  );

  const hasBalance = useCallback(
    (fee: bigint) => balance !== undefined && balance >= fee,
    [balance],
  );

  const step: JoinStep = useMemo(() => {
    if (isConfirmed) return "done";
    if (isConfirming || isSigning) {
      return action === "approve" ? "approving" : "joining";
    }
    return "idle";
  }, [action, isSigning, isConfirming, isConfirmed]);

  const resetJoin = useCallback(() => {
    setAction(undefined);
    reset();
  }, [reset]);

  return {
    approve,
    registerAtStage,
    joinStage,
    needsApproval,
    hasBalance,
    refetchAllowance,
    allowance,
    balance,
    decimals: decimals ?? 18,
    symbol: symbol ?? "RWAAN",
    hash,
    action,
    step,
    isSigning,
    isConfirming,
    isConfirmed,
    error: writeError,
    reset: resetJoin,
  };
}
