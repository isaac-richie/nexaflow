import { formatUnits } from "viem";
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** 0x1234…abcd */
export function shortAddress(address?: string, chars = 4): string {
  if (!address) return "";
  return `${address.slice(0, 2 + chars)}…${address.slice(-chars)}`;
}

/**
 * Token amount for display.
 *
 * Money is never rendered with floating-point maths. viem's formatUnits does
 * the base conversion exactly, and Intl handles grouping — so a balance is
 * never off by a rounding error in the last place.
 */
export function formatToken(
  value: bigint | undefined,
  decimals = 18,
  maximumFractionDigits = 2,
): string {
  if (value === undefined) return "—";
  const asString = formatUnits(value, decimals);
  return new Intl.NumberFormat("en-US", {
    maximumFractionDigits,
    minimumFractionDigits: 0,
  }).format(Number(asString));
}

/** $1,234 — for USD-denominated presets that are plain numbers, not bigints. */
export function formatUsd(value: number, maximumFractionDigits = 0): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    maximumFractionDigits,
  }).format(value);
}

export function formatCount(value: bigint | number | undefined): string {
  if (value === undefined) return "—";
  return new Intl.NumberFormat("en-US").format(Number(value));
}
