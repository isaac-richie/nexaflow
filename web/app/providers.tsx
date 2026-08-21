"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { useState, type ReactNode } from "react";
import { PrivyProvider } from "@privy-io/react-auth";
import { WagmiProvider } from "@privy-io/wagmi";
import { wagmiConfig } from "@/lib/wagmi";
import { ACTIVE_CHAIN } from "@/lib/contracts/config";
import {
  isPermanentRpcRequestError,
  isRateLimitError,
  NO_BACKGROUND_RPC,
  RPC_CACHE_MS,
} from "@/lib/rpc-policy";

const privyAppId = process.env.NEXT_PUBLIC_PRIVY_APP_ID ?? "";

export function Providers({ children }: { children: ReactNode }) {
  // Created inside state so each browser session gets its own cache and the
  // client is never shared across requests during SSR.
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // Individual hooks override staleTime according to how quickly
            // their state can change. This is the conservative fallback.
            staleTime: RPC_CACHE_MS.member,
            gcTime: RPC_CACHE_MS.garbageCollection,
            ...NO_BACKGROUND_RPC,
            // Public RPCs rate-limit. Retrying a 429 makes it worse, and a 400
            // is never going to succeed on a second attempt.
            retry: (failureCount, error) => {
              if (isRateLimitError(error) || isPermanentRpcRequestError(error)) return false;
              return failureCount < 2;
            },
            retryDelay: (attempt) => Math.min(1_000 * 2 ** attempt, 10_000),
          },
        },
      }),
  );

  // Without an app id Privy cannot mount at all. Say so rather than rendering a
  // Connect button that silently does nothing.
  if (!privyAppId) {
    return (
      <div className="mx-auto mt-16 max-w-xl rounded-2xl border border-line bg-surface-1 p-6 text-sm text-muted">
        <p className="font-medium text-ink">Wallet connection is not configured.</p>
        <p className="mt-2">
          Set <code className="text-gold">NEXT_PUBLIC_PRIVY_APP_ID</code> in{" "}
          <code className="text-gold">.env.local</code>, then restart the dev
          server. Get an app id from{" "}
          <a
            href="https://dashboard.privy.io"
            target="_blank"
            rel="noopener noreferrer"
            className="text-gold hover:underline"
          >
            dashboard.privy.io
          </a>
          .
        </p>
      </div>
    );
  }

  // Provider order matters: Privy must wrap Wagmi, and the query client sits
  // between them because @privy-io/wagmi's WagmiProvider expects one in scope.
  return (
    <PrivyProvider
      appId={privyAppId}
      config={{
        appearance: {
          theme: "dark",
          accentColor: "#F0B90B",
          showWalletLoginFirst: true,
          // Pinned in priority order so the wallets this audience actually uses
          // get their own row. `detected_wallets` surfaces any other installed
          // extension via EIP-6963; `wallet_connect` covers mobile apps by QR.
          // Rabby is listed explicitly as well as detected, so it is never
          // buried under an "Other wallets" fold.
          walletList: [
            "metamask",
            "bitget_wallet",
            "rabby_wallet",
            "detected_wallets",
            "wallet_connect",
          ],
        },
        // Wallet-only. This app moves real money on a member's own address;
        // email and social logins would create custodial-feeling accounts that
        // do not match how the protocol identifies a member.
        loginMethods: ["wallet"],
        defaultChain: ACTIVE_CHAIN,
        supportedChains: [ACTIVE_CHAIN],
        // No embedded wallets. A member's position is bound to the address they
        // register with, so generating a fresh Privy wallet on login would
        // create an address with no membership and no funds.
        embeddedWallets: {
          ethereum: { createOnLogin: "off" },
        },
      }}
    >
      <QueryClientProvider client={queryClient}>
        <WagmiProvider config={wagmiConfig}>{children}</WagmiProvider>
      </QueryClientProvider>
    </PrivyProvider>
  );
}
