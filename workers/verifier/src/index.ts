/** Intentionally closed by default. Never execute contributor code without #21's isolated sandbox. */
export function runUntrustedCode(): never {
  throw new Error(
    "VERIFIER_DISABLED: secure runner is not implemented; see issue #21",
  );
}
export const verifierAvailable = false as const;
