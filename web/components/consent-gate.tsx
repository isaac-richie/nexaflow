"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { CONSENT_VERSION } from "@/lib/consent";

const STORAGE_KEY = "nexaflow:consent";
const COOKIE_KEY = "nexaflow_consent";
const COOKIE_MAX_AGE_SECONDS = 60 * 60 * 24 * 365;
const REQUIRED_CONSENTS = [
  "age",
  "jurisdiction",
  "blockchain",
  "legal",
] as const;

type ConsentId = (typeof REQUIRED_CONSENTS)[number];
type ConsentState = Record<ConsentId, boolean>;

const EMPTY_CONSENT: ConsentState = {
  age: false,
  jurisdiction: false,
  blockchain: false,
  legal: false,
};

/**
 * First-visit acknowledgement for every public and application route. The
 * legal page itself remains readable before acceptance so the linked terms
 * are never hidden behind the consent they are meant to inform.
 *
 * The component starts in an "undetermined" state (open === null) and only
 * paints once localStorage / cookie have been read on the client. That kills
 * the flash the naive `useState(true)` approach caused every reload for
 * already-accepted users, and eliminates the SSR/CSR hydration mismatch.
 */
export function ConsentGate() {
  const pathname = usePathname();
  const bypass = pathname?.startsWith("/legal") ?? false;
  const [open, setOpen] = useState<boolean | null>(null);
  const [consents, setConsents] = useState<ConsentState>(EMPTY_CONSENT);
  const [showJurisdictions, setShowJurisdictions] = useState(false);
  const dialogRef = useRef<HTMLDivElement>(null);
  const firstCheckboxRef = useRef<HTMLInputElement>(null);
  const jurisdictionsRef = useRef<HTMLDivElement>(null);
  const returnFocusRef = useRef<Element | null>(null);

  // ------- read-persisted acceptance + cross-tab sync -----------------------

  const hasPersistedAcceptance = useCallback((): boolean => {
    try {
      const stored = window.localStorage.getItem(STORAGE_KEY);
      if (stored) {
        const record = JSON.parse(stored) as { version?: string };
        if (record?.version === CONSENT_VERSION) return true;
      }
    } catch {
      // Some privacy modes block localStorage; the cookie below is the fallback.
    }
    return document.cookie
      .split(";")
      .map((value) => value.trim())
      .some((value) => value === `${COOKIE_KEY}=${CONSENT_VERSION}`);
  }, []);

  useEffect(() => {
    if (bypass) {
      setOpen(false);
      return;
    }
    setOpen(!hasPersistedAcceptance());

    // If the user accepts in another tab, dismiss here too.
    function onStorage(event: StorageEvent) {
      if (event.key === STORAGE_KEY && hasPersistedAcceptance()) setOpen(false);
    }
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [bypass, hasPersistedAcceptance]);

  // ------- body lock + focus trap while the dialog is open -----------------

  useEffect(() => {
    if (!open) return;

    returnFocusRef.current = document.activeElement;

    const previousOverflow = document.body.style.overflow;
    const previousOverscroll = document.body.style.overscrollBehavior;
    const siteContent = document.getElementById("site-content");
    document.body.style.overflow = "hidden";
    document.body.style.overscrollBehavior = "contain";
    if (siteContent) {
      siteContent.inert = true;
      siteContent.setAttribute("aria-hidden", "true");
    }

    const focusTimer = window.setTimeout(() => {
      firstCheckboxRef.current?.focus({ preventScroll: true });
    }, 50);

    function trapFocus(event: KeyboardEvent) {
      if (event.key === "Escape") {
        // The dialog is a hard gate; Escape must not silently dismiss it.
        event.preventDefault();
        return;
      }
      if (event.key !== "Tab" || !dialogRef.current) return;

      const focusable = Array.from(
        dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), input:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
      if (focusable.length === 0) return;

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", trapFocus);
    return () => {
      window.clearTimeout(focusTimer);
      document.removeEventListener("keydown", trapFocus);
      document.body.style.overflow = previousOverflow;
      document.body.style.overscrollBehavior = previousOverscroll;
      if (siteContent) {
        siteContent.inert = false;
        siteContent.removeAttribute("aria-hidden");
      }
      // Return focus to whatever was focused before the dialog took over,
      // so screen readers and keyboard users land back in the page flow.
      const target = returnFocusRef.current;
      if (target instanceof HTMLElement) target.focus({ preventScroll: true });
    };
  }, [open]);

  // ------- reveal the restriction scope + scroll it into view on mobile ----

  useEffect(() => {
    if (!showJurisdictions) return;
    // Wait one frame so the panel has laid out before we scroll.
    const raf = window.requestAnimationFrame(() => {
      jurisdictionsRef.current?.scrollIntoView({
        behavior: "smooth",
        block: "nearest",
      });
    });
    return () => window.cancelAnimationFrame(raf);
  }, [showJurisdictions]);

  // ------- derived + handlers ----------------------------------------------

  const complete = useMemo(
    () => REQUIRED_CONSENTS.every((id) => consents[id]),
    [consents],
  );
  const confirmedCount = useMemo(
    () => REQUIRED_CONSENTS.reduce((n, id) => (consents[id] ? n + 1 : n), 0),
    [consents],
  );

  const setConsent = useCallback((id: ConsentId, checked: boolean) => {
    setConsents((current) => ({ ...current, [id]: checked }));
  }, []);

  const accept = useCallback(() => {
    if (!complete) return;
    const acceptedAt = new Date().toISOString();
    const record = {
      version: CONSENT_VERSION,
      acceptedAt,
      // Store which boxes were checked at accept-time so an audit can prove
      // the user did not click through an incomplete form due to a UI bug.
      checkboxes: REQUIRED_CONSENTS.reduce<Record<ConsentId, boolean>>(
        (acc, id) => {
          acc[id] = consents[id];
          return acc;
        },
        { age: false, jurisdiction: false, blockchain: false, legal: false },
      ),
    };
    try {
      window.localStorage.setItem(STORAGE_KEY, JSON.stringify(record));
    } catch {
      // Fall back to the cookie below.
    }
    document.cookie =
      `${COOKIE_KEY}=${CONSENT_VERSION}; Max-Age=${COOKIE_MAX_AGE_SECONDS}; ` +
      `Path=/; SameSite=Lax`;
    setOpen(false);
  }, [complete, consents]);

  const leaveWebsite = useCallback(() => {
    // `history.back()` inside our own domain would just re-open the gate on
    // the previous page. Route the user off the property unconditionally.
    try {
      window.location.replace("about:blank");
    } catch {
      window.location.href = "about:blank";
    }
  }, []);

  // ------- render ----------------------------------------------------------

  if (bypass || open === null || open === false) return null;

  return (
    <div
      className="fixed inset-0 z-[100] grid place-items-center overflow-y-auto bg-black/75 px-3 py-4 backdrop-blur-md sm:px-6 sm:py-8"
      data-testid="consent-gate"
      style={{ overscrollBehavior: "contain" }}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="consent-title"
        aria-describedby="consent-description"
        className="panel-raised panel-sheen my-auto w-full max-w-lg overflow-hidden"
        style={{
          paddingBottom: "env(safe-area-inset-bottom)",
        }}
      >
        <div className="max-h-[calc(100dvh-2rem)] overflow-y-auto p-4 sm:max-h-[88dvh] sm:p-6">
          <div className="flex items-start gap-3 pr-2">
            <ShieldIcon />
            <div>
              <div className="label text-gold">Important notice</div>
              <h1
                id="consent-title"
                className="mt-1 font-display text-xl font-bold sm:text-2xl"
              >
                Before you continue
              </h1>
              <p
                id="consent-description"
                className="mt-2 text-sm leading-relaxed text-muted"
              >
                Please confirm you understand the important conditions for using
                NexaFlow.
              </p>
            </div>
          </div>

          <div className="mt-4 space-y-2.5">
            <ConsentRow
              id="consent-age"
              checked={consents.age}
              onChange={(checked) => setConsent("age", checked)}
              inputRef={firstCheckboxRef}
            >
              I am at least 18 years old.
            </ConsentRow>

            <div className="rounded-xl border border-line bg-surface-2/70">
              <ConsentRow
                id="consent-jurisdiction"
                checked={consents.jurisdiction}
                onChange={(checked) => setConsent("jurisdiction", checked)}
                flush
              >
                I am not a US resident and I am not located in any restricted
                jurisdiction.
              </ConsentRow>
              <button
                type="button"
                aria-expanded={showJurisdictions}
                aria-controls="restricted-jurisdictions"
                onClick={() => setShowJurisdictions((value) => !value)}
                className="mb-3 ml-[3.25rem] text-left text-xs font-medium text-gold hover:underline"
              >
                {showJurisdictions
                  ? "Hide restricted countries"
                  : "View restricted countries"}
              </button>
              {showJurisdictions && (
                <div
                  id="restricted-jurisdictions"
                  ref={jurisdictionsRef}
                  className="mx-3 mb-3 rounded-lg border border-gold/15 bg-bg/45 p-3 text-xs leading-relaxed text-muted sm:mx-4"
                >
                  United States and any country or territory where NexaFlow
                  participation, blockchain membership programs, or USDT
                  transactions are legally restricted. See the full{" "}
                  <Link
                    href="/legal#jurisdictions"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-gold hover:underline"
                  >
                    jurisdiction notice
                  </Link>
                  .
                </div>
              )}
            </div>

            <ConsentRow
              id="consent-blockchain"
              checked={consents.blockchain}
              onChange={(checked) => setConsent("blockchain", checked)}
            >
              I understand that blockchain payments are generally irreversible
              and entry fees are non-refundable, except where required by law.
            </ConsentRow>

            <div className="rounded-xl border border-line bg-surface-2/70">
              <ConsentRow
                id="consent-legal"
                checked={consents.legal}
                onChange={(checked) => setConsent("legal", checked)}
                flush
              >
                I agree to the Terms, Privacy Policy, Risk Disclosure and
                Income Disclosure.
              </ConsentRow>
              <div className="mb-3 ml-[3.25rem] flex flex-wrap gap-x-3 gap-y-1 pr-3 text-xs">
                <LegalLink href="/legal#terms">Terms</LegalLink>
                <LegalLink href="/legal#privacy">Privacy Policy</LegalLink>
                <LegalLink href="/legal#risk">Risk Disclosure</LegalLink>
                <LegalLink href="/legal#risk">Income Disclosure</LegalLink>
              </div>
            </div>
          </div>

          <div
            className="mt-4 text-center text-[11px] font-medium text-faint"
            aria-live="polite"
          >
            {confirmedCount} of {REQUIRED_CONSENTS.length} confirmed
          </div>

          <div className="mt-3 grid gap-2.5 sm:grid-cols-[1fr_auto]">
            <button
              type="button"
              onClick={accept}
              disabled={!complete}
              data-testid="consent-accept"
              className="btn-gold min-h-12 w-full disabled:cursor-not-allowed disabled:opacity-40"
            >
              Accept and continue
            </button>
            <button
              type="button"
              onClick={leaveWebsite}
              className="btn-ghost min-h-12 w-full px-5 sm:w-auto"
            >
              Leave website
            </button>
          </div>

          <p className="mt-4 text-center text-[11px] leading-relaxed text-faint">
            No person is authorised to promise guaranteed income, profit,
            product delivery, or board completion.
          </p>
        </div>
      </div>
    </div>
  );
}

function ConsentRow({
  id,
  checked,
  onChange,
  children,
  inputRef,
  flush = false,
}: {
  id: string;
  checked: boolean;
  onChange: (checked: boolean) => void;
  children: React.ReactNode;
  inputRef?: React.RefObject<HTMLInputElement>;
  flush?: boolean;
}) {
  return (
    <div
      className={
        flush
          ? "flex items-start gap-3 px-3 pb-2 pt-3 sm:px-4"
          : "flex items-start gap-3 rounded-xl border border-line bg-surface-2/70 p-3 sm:p-4"
      }
    >
      <input
        ref={inputRef}
        id={id}
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.currentTarget.checked)}
        className="mt-0.5 h-5 w-5 shrink-0 cursor-pointer accent-gold"
      />
      <label
        htmlFor={id}
        className="cursor-pointer text-[13px] leading-relaxed text-ink sm:text-sm"
      >
        {children}
      </label>
    </div>
  );
}

function LegalLink({
  href,
  children,
}: {
  href: string;
  children: React.ReactNode;
}) {
  return (
    <Link
      href={href}
      target="_blank"
      rel="noopener noreferrer"
      className="text-gold hover:underline"
    >
      {children}
    </Link>
  );
}

function ShieldIcon() {
  return (
    <svg
      width="28"
      height="28"
      viewBox="0 0 24 24"
      fill="none"
      aria-hidden
      className="mt-1 shrink-0 text-gold"
    >
      <path
        d="M12 3 4 6v6c0 4.5 3.2 8 8 9 4.8-1 8-4.5 8-9V6l-8-3Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <path
        d="m8.5 12.2 2.4 2.4 4.6-5"
        stroke="currentColor"
        strokeWidth="1.8"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
