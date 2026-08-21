import { fallback, http } from "wagmi";
import { bsc, bscTestnet } from "wagmi/chains";
// IMPORTANT: `createConfig` must come from @privy-io/wagmi, never from wagmi.
//
// Privy's version sets ssr:true, strips the injected connectors and lets Privy
// own the connection lifecycle. Using wagmi's own createConfig puts the two
// libraries in competition for it, which desyncs `useAccount()` on client-side
// navigation — the wallet appears to disconnect when moving between pages.
import { createConfig } from "@privy-io/wagmi";
import {
  RPC_CLIENT_CACHE_MS,
  RPC_MULTICALL_WAIT_MS,
  RPC_POLLING_INTERVAL_MS,
} from "@/lib/rpc-policy";

const rpcTransportOptions = {
  // A failed paid-provider request gets one retry, not Viem's default retry
  // fan-out. React Query separately prevents retry storms for 400/429 errors.
  retryCount: 1,
  retryDelay: 750,
  timeout: 12_000,
} as const;

/**
 * Wallet configuration for BNB Chain, managed by Privy.
 *
 * Connectors are not declared here on purpose. Privy's login modal is the sole
 * connection manager; it surfaces browser-extension wallets through EIP-6963
 * announcements (see `multiInjectedProviderDiscovery` below) and handles
 * WalletConnect itself.
 */
export const wagmiConfig = createConfig({
  chains: [bsc, bscTestnet],

  // Nearby readContract calls are encoded into one Multicall3 eth_call. This
  // reduces billable RPC methods; HTTP JSON batching alone would only reduce
  // network round trips and many providers would still bill each subrequest.
  batch: {
    multicall: {
      batchSize: 8_192,
      wait: RPC_MULTICALL_WAIT_MS,
    },
  },
  cacheTime: RPC_CLIENT_CACHE_MS,
  pollingInterval: RPC_POLLING_INTERVAL_MS,

  // EIP-6963 discovery. Privy's modal lists extension wallets (Rabby, Trust,
  // OKX, imToken…) under `detected_wallets` by listening for their
  // announcements — with discovery off, Rabby never appears at all, because it
  // only announces via EIP-6963 and has no dedicated Privy button.
  //
  // Enabling it here does NOT reintroduce the wallet-drop desync noted above:
  // that came from wagmi's createConfig adding competing injected connectors.
  // With @privy-io/wagmi's createConfig, Privy stays in charge and simply gains
  // visibility of the announced wallets.
  multiInjectedProviderDiscovery: true,

  transports: {
    [bsc.id]: bscTransport(),
    [bscTestnet.id]: http(
      process.env.NEXT_PUBLIC_BSC_TESTNET_RPC_URL,
      rpcTransportOptions,
    ),
  },
});

/**
 * BSC mainnet transport with automatic failover.
 *
 * The first entry is tried first on every request. Viem swaps to the next
 * transport in the list transparently on failure — no health check to write,
 * no polling loop to run, no state to keep. `rank: false` keeps the order
 * fixed rather than reordering endpoints by observed latency, so the paid
 * provider only serves traffic that the public one drops.
 *
 * `NEXT_PUBLIC_BSC_RPC_URL_ALCHEMY` is optional. If it is empty the config
 * silently degrades to the primary endpoint alone rather than throwing at
 * import time.
 */
function bscTransport() {
  const primary = http(process.env.NEXT_PUBLIC_BSC_RPC_URL, rpcTransportOptions);
  const alchemy = process.env.NEXT_PUBLIC_BSC_RPC_URL_ALCHEMY;
  if (!alchemy) return primary;
  return fallback([primary, http(alchemy, rpcTransportOptions)], { rank: false });
}

declare module "wagmi" {
  interface Register {
    config: typeof wagmiConfig;
  }
}
