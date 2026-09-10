"use client";

import type { ReactNode } from "react";
import { usePathname } from "next/navigation";
import { Providers } from "@/app/providers";
import { BackgroundEffects } from "@/components/background-effects";
import { ConsentGate } from "@/components/consent-gate";

/** Only these exact design routes are non-transactional and mount no wallet provider. */
export function SiteRuntime({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  if (pathname === "/preview" || pathname === "/preview/landing") return <>{children}</>;
  return (
    <>
      {pathname !== "/" && pathname !== "/app" && !pathname.startsWith("/app/") && <BackgroundEffects />}
      <div id="site-content"><Providers>{children}</Providers></div>
      <ConsentGate />
    </>
  );
}
