"use client";

import { motion, useReducedMotion, type Variants } from "framer-motion";
import {
  useEffect,
  useRef,
  useState,
  type ReactNode,
  type RefObject,
} from "react";

const EASE = [0.22, 1, 0.36, 1] as const;

/**
 * Scroll reveal that FAILS OPEN.
 *
 * Content must never depend on IntersectionObserver to become visible. If the
 * observer is throttled, blocked, or simply never fires (some embedded and
 * headless browsers do exactly this), an IO-gated element stays at opacity 0
 * forever and the page renders blank. That is a content bug, not an animation
 * bug, and it also hurts SEO and accessibility.
 *
 * So: IO is the fast path, a manual rect check on scroll is the fallback, and
 * a short timer reveals anything still hidden no matter what.
 */
function useRevealed(ref: RefObject<Element>) {
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let done = false;

    const reveal = () => {
      if (done) return;
      done = true;
      setShown(true);
      cleanup();
    };

    const nearViewport = () => {
      const r = el.getBoundingClientRect();
      return r.top < window.innerHeight - 60 && r.bottom > 0;
    };

    let io: IntersectionObserver | undefined;
    if (typeof IntersectionObserver !== "undefined") {
      io = new IntersectionObserver(
        (entries) => entries.some((e) => e.isIntersecting) && reveal(),
        { rootMargin: "0px 0px -60px 0px" }
      );
      io.observe(el);
    }

    const onScroll = () => nearViewport() && reveal();
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });

    // Above-the-fold content reveals immediately on the next frame.
    const raf = requestAnimationFrame(onScroll);

    // Last resort. If nothing above worked, show the content anyway.
    const timer = window.setTimeout(reveal, 1200);

    function cleanup() {
      io?.disconnect();
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", onScroll);
      cancelAnimationFrame(raf);
      window.clearTimeout(timer);
    }

    return cleanup;
  }, [ref]);

  return shown;
}

export function Reveal({
  children,
  delay = 0,
  y = 18,
  className,
}: {
  children: ReactNode;
  delay?: number;
  y?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const shown = useRevealed(ref);
  const reduce = useReducedMotion();

  if (reduce) return <div className={className}>{children}</div>;

  return (
    <motion.div
      ref={ref}
      className={className}
      initial={{ opacity: 0, y }}
      animate={shown ? { opacity: 1, y: 0 } : undefined}
      transition={{ duration: 0.7, delay, ease: EASE }}
    >
      {children}
    </motion.div>
  );
}

const containerVariants: Variants = {
  hidden: {},
  show: { transition: { staggerChildren: 0.08 } },
};

const itemVariants: Variants = {
  hidden: { opacity: 0, y: 20 },
  show: { opacity: 1, y: 0, transition: { duration: 0.65, ease: EASE } },
};

export function Stagger({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const shown = useRevealed(ref);
  const reduce = useReducedMotion();

  if (reduce) return <div className={className}>{children}</div>;

  return (
    <motion.div
      ref={ref}
      className={className}
      variants={containerVariants}
      initial="hidden"
      animate={shown ? "show" : "hidden"}
    >
      {children}
    </motion.div>
  );
}

/**
 * Must be its own named export, not a static property on `Stagger`.
 * The RSC bundler resolves client components by module export, so a
 * `Stagger.Item` reference from a server component fails to resolve
 * ("Could not find the module ...#Stagger#Item in the React Client Manifest").
 */
export function StaggerItem({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <motion.div variants={itemVariants} className={className}>
      {children}
    </motion.div>
  );
}
