import type { Config } from "tailwindcss";

/** NexaFlow tokens. BNB gold on Binance near-black. */
const config: Config = {
  darkMode: ["class"],
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    screens: {
      xs: "400px",
      sm: "640px",
      md: "768px",
      lg: "1024px",
      xl: "1280px",
      "2xl": "1536px",
    },
    extend: {
      fontFamily: {
        sans: ["var(--font-sans)", "system-ui", "sans-serif"],
        display: ["var(--font-display)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      colors: {
        bg: "hsl(var(--bg))",
        surface: {
          1: "hsl(var(--surface-1))",
          2: "hsl(var(--surface-2))",
          3: "hsl(var(--surface-3))",
        },
        gold: "hsl(var(--gold))",
        goldHi: "hsl(var(--gold-hi))",
        goldDim: "hsl(var(--gold-dim))",
        ink: "hsl(var(--ink))",
        muted: "hsl(var(--muted))",
        faint: "hsl(var(--faint))",
        line: "hsl(var(--line))",
        up: "hsl(var(--up))",
        down: "hsl(var(--down))",
      },
      borderRadius: { lg: "0.75rem", xl: "1rem", "2xl": "1.25rem", "3xl": "1.75rem" },
      boxShadow: {
        gold: "0 0 0 1px hsl(var(--gold) / 0.25), 0 12px 40px -12px hsl(var(--gold) / 0.35)",
        lift: "0 24px 64px -20px rgba(0,0,0,0.85)",
      },
      keyframes: {
        flowUp: {
          "0%": { strokeDashoffset: "26", opacity: "0" },
          "20%,80%": { opacity: "1" },
          "100%": { strokeDashoffset: "0", opacity: "0" },
        },
        float: {
          "0%,100%": { transform: "translateY(0)" },
          "50%": { transform: "translateY(-6px)" },
        },
        marquee: {
          from: { transform: "translateX(0)" },
          to: { transform: "translateX(-50%)" },
        },
      },
      animation: {
        flowUp: "flowUp 2.6s cubic-bezier(.4,0,.2,1) infinite",
        float: "float 6s ease-in-out infinite",
        marquee: "marquee 32s linear infinite",
      },
    },
  },
  plugins: [],
};

export default config;
