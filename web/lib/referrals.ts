import { bytesToHex, getAddress, hexToBytes, keccak256 } from "viem";

/**
 * Referral links are deliberately self-contained. The code encodes the
 * sponsor address plus a checksum, so resolving a link never depends on a
 * database, an API request, or a code record that can be overwritten.
 */
const PREFIX = "NF";
const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
const ALPHABET_INDEX = new Map([...ALPHABET].map((char, i) => [char, i]));
const ADDRESS_BYTES = 20;
const CHECKSUM_BYTES = 4;

function encodeBase58(bytes: Uint8Array): string {
  let value = 0n;
  for (const byte of bytes) value = value * 256n + BigInt(byte);

  let encoded = "";
  while (value > 0n) {
    const remainder = Number(value % 58n);
    encoded = ALPHABET[remainder] + encoded;
    value /= 58n;
  }

  let leadingZeroes = 0;
  while (leadingZeroes < bytes.length && bytes[leadingZeroes] === 0) {
    leadingZeroes += 1;
  }
  return "1".repeat(leadingZeroes) + (encoded || "");
}

function decodeBase58(value: string): Uint8Array | undefined {
  if (!value) return undefined;

  let decoded = 0n;
  for (const char of value) {
    const digit = ALPHABET_INDEX.get(char);
    if (digit === undefined) return undefined;
    decoded = decoded * 58n + BigInt(digit);
  }

  const hex = decoded.toString(16);
  const body = hex.length % 2 === 0 ? hex : `0${hex}`;
  const leadingZeroes = value.match(/^1+/)?.[0].length ?? 0;
  const result = new Uint8Array(leadingZeroes + body.length / 2);

  for (let i = 0; i < body.length; i += 2) {
    result[leadingZeroes + i / 2] = Number.parseInt(body.slice(i, i + 2), 16);
  }
  return result;
}

function equalBytes(a: Uint8Array, b: Uint8Array): boolean {
  return a.length === b.length && a.every((byte, i) => byte === b[i]);
}

/** A deterministic, checksummed code for a wallet address. */
export function referralCodeForAddress(address: string): string {
  const normalized = getAddress(address);
  const addressBytes = hexToBytes(normalized);
  const checksum = hexToBytes(keccak256(addressBytes)).slice(0, CHECKSUM_BYTES);
  const payload = new Uint8Array(addressBytes.length + checksum.length);
  payload.set(addressBytes);
  payload.set(checksum, addressBytes.length);
  return `${PREFIX}${encodeBase58(payload)}`;
}

/** Resolve and checksum-validate a referral code without any network call. */
export function addressForReferralCode(code: string): `0x${string}` | undefined {
  if (!code.startsWith(PREFIX)) return undefined;

  const payload = decodeBase58(code.slice(PREFIX.length));
  if (!payload || payload.length !== ADDRESS_BYTES + CHECKSUM_BYTES) return undefined;

  const addressBytes = payload.slice(0, ADDRESS_BYTES);
  const suppliedChecksum = payload.slice(ADDRESS_BYTES);
  const expectedChecksum = hexToBytes(keccak256(addressBytes)).slice(0, CHECKSUM_BYTES);
  if (!equalBytes(suppliedChecksum, expectedChecksum)) return undefined;

  return getAddress(bytesToHex(addressBytes));
}

export function referralPathForAddress(address: string): string {
  return `/r/${referralCodeForAddress(address)}`;
}

export function directReferralPathForAddress(address: string): string {
  return `/app/join?ref=${encodeURIComponent(getAddress(address))}`;
}
