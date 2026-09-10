"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { useConnectWallet, useLogin, usePrivy } from "@privy-io/react-auth";
import { useAccount, useSwitchChain } from "wagmi";
import { AnimatePresence, motion } from "framer-motion";
import { ACTIVE_CHAIN } from "@/lib/contracts/config";
import { cn, shortAddress } from "@/lib/format";

/**
 * Wallet connection, via Privy.
 *
 * Privy owns the login modal, so there is no bespoke wallet picker here — it
 * lists extension wallets through EIP-6963 and handles WalletConnect itself.
 * What this component still owns is the two states Privy does not model:
 *
 *  - wrong network, which otherwise shows a member an empty dashboard and lets
 *    them conclude their money has vanished;
 *  - the connected account menu.
 */
export function ConnectButton({ className }: { className?: string }) {
  const { ready, authenticated, logout } = usePrivy();
  const { address, isConnected, chainId } = useAccount();
  const { switchChain, isPending: isSwitching } = useSwitchChain();

  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [connectionError, setConnectionError] = useState("");
  const reportConnectionError = () =>
    setConnectionError("Wallet connection was not completed. Please try again.");
  const { login } = useLogin({
    onComplete: () => setConnectionError(""),
    onError: reportConnectionError,
  });
  const { connectWallet } = useConnectWallet({
    onSuccess: () => setConnectionError(""),
    onError: reportConnectionError,
  });
  useEffect(() => setMounted(true), []);

  async function connect() {
    setConnectionError("");
    try {
      // Authentication can survive an extension disconnect or page reload.
      // Privy ignores login() for an authenticated user; reconnect instead.
      if (authenticated) await connectWallet({ walletChainType: "ethereum-only" });
      else await login();
    } catch {
      reportConnectionError();
    }
  }

  // Privy rehydrates its session asynchronously. Rendering a "Connect" button
  // during that window makes an already-connected member think they were
  // logged out, so hold a neutral placeholder until it settles.
  if (!ready) {
    return (
      <div
        className={cn(
          "h-9 w-32 animate-pulse rounded-xl border border-line bg-surface-2",
          className,
        )}
        aria-hidden
      />
    );
  }

  const wrongNetwork = isConnected && chainId !== ACTIVE_CHAIN.id;

  if (wrongNetwork) {
    return (
      <button
        onClick={() => switchChain({ chainId: ACTIVE_CHAIN.id })}
        disabled={isSwitching}
        className={cn(
          "inline-flex items-center gap-2 rounded-xl border border-down/50",
          "bg-down/10 px-4 py-2 text-sm font-medium text-down",
          "transition-colors hover:bg-down/20 disabled:opacity-60",
          className,
        )}
      >
        <span className="h-2 w-2 rounded-full bg-down" />
        {isSwitching ? "Switching…" : `Switch to ${ACTIVE_CHAIN.name}`}
      </button>
    );
  }

  if (authenticated && isConnected && address) {
    return (
      <div className={cn("relative", className)}>
        <button
          onClick={() => setOpen((v) => !v)}
          className="inline-flex items-center gap-2 rounded-xl border border-line
                     bg-surface-2 px-4 py-2 text-sm font-medium text-ink
                     transition-colors hover:border-gold/40"
        >
          <span className="h-2 w-2 rounded-full bg-up" />
          <span className="font-mono">{shortAddress(address)}</span>
        </button>

        {mounted &&
          createPortal(
            <AnimatePresence>
              {open && (
                <>
                  {/* The app header uses backdrop-blur, and backdrop-filter
                      establishes a containing block for fixed positioning — a
                      dropdown rendered inside it anchors to the header instead
                      of the viewport. Portalling escapes that. */}
                  <div
                    className="fixed inset-0 z-[60]"
                    onClick={() => setOpen(false)}
                  />
                  <motion.div
                    initial={{ opacity: 0, y: -6 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0, y: -6 }}
                    transition={{ duration: 0.15 }}
                    className="panel panel-sheen fixed right-4 top-16 z-[70] w-64 p-2 sm:right-6"
                  >
                    <div className="px-3 py-2">
                      <div className="text-[11px] uppercase tracking-wider text-faint">
                        Connected
                      </div>
                      <div className="mt-0.5 break-all font-mono text-xs text-muted">
                        {address}
                      </div>
                    </div>

                    <a
                      href={`${ACTIVE_CHAIN.blockExplorers?.default.url}/address/${address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="block rounded-lg px-3 py-2 text-sm text-muted
                                 transition-colors hover:bg-surface-3 hover:text-ink"
                    >
                      View on explorer ↗
                    </a>

                    <button
                      onClick={() => {
                        logout();
                        setOpen(false);
                      }}
                      className="w-full rounded-lg px-3 py-2 text-left text-sm
                                 text-muted transition-colors hover:bg-surface-3
                                 hover:text-ink"
                    >
                      Disconnect
                    </button>
                  </motion.div>
                </>
              )}
            </AnimatePresence>,
            document.body,
          )}
      </div>
    );
  }

  return (
    <div className="flex flex-col items-start gap-2">
      <button
        type="button"
        onClick={connect}
        className={cn("btn-gold px-5 py-2 text-sm", className)}
      >
        Connect Wallet
      </button>
      {connectionError && (
        <p role="alert" className="max-w-xs text-sm text-down">{connectionError}</p>
      )}
    </div>
  );
}
