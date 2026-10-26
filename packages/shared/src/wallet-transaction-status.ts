/**
 * Display-only wallet state contract. NO wallet connector, no signing keys,
 * fund movement, chain approval or automatic payout authorization.
 * Approved Portaldot runtime / connector must be independently verified first.
 */
const HEX_40 = /^0x[a-f0-9]{40}$/i;
const HEX_64 = /^0x[a-f0-9]{64}$/i;
const UINT = /^(0|[1-9][0-9]*)$/;

export type WalletObservation =
  | "wallet_disconnected"
  | "wrong_network"
  | "different_account"
  | "signature_required"
  | "user_rejected"
  | "broadcast"
  | "pending_finality"
  | "transaction_replaced"
  | "transaction_reverted"
  | "provider_unavailable"
  | "canonical_receipt_observed"
  | "configuration_blocked";

export interface WalletConnectionV1 {
  protocol: "evm" | "substrate";
  chainId: string;
  account: string;
}

export interface WalletTxObservationInputV1 {
  approvedProtocol: "evm" | "substrate" | null;
  approvedChainId: string | null;
  /** Operator-approved chain genesis; not a proof by itself. */
  approvedGenesisHash: string | null;
  originalAccount: string | null;
  currentWallet: WalletConnectionV1 | null;
  txHash: string | null;
  replacementHash?: string | null;
  signatureRejected?: boolean;
  providerUnavailable?: boolean;
  receipt?: {
    transactionHash: string;
    canonical: boolean;
    finalized: boolean;
    success: boolean;
  } | null;
}

export interface WalletTxSafetyViewV1 {
  status: WalletObservation;
  userMessage: string;
  evidenceTxHash: string | null;
  /** Intentionally impossible to grant from a UI/client RPC observation. */
  custodyVerified: false;
  payoutVerified: false;
  allowTransfer: false;
}

function result(
  status: WalletObservation,
  userMessage: string,
  evidenceTxHash: string | null = null,
): WalletTxSafetyViewV1 {
  return {
    status,
    userMessage,
    evidenceTxHash,
    custodyVerified: false,
    payoutVerified: false,
    allowTransfer: false,
  };
}

function validAccount(value: string | null): boolean {
  return typeof value === "string" && HEX_40.test(value);
}

/**
 * A strict status classifier for EVM account/hash *observations*. Substrate
 * account encoding differs, so it remains disabled until approved runtime and
 * wallet support are implemented. Never convert this result into a payout.
 */
export function assessWalletTransactionV1(
  input: WalletTxObservationInputV1,
): WalletTxSafetyViewV1 {
  if (
    input.approvedProtocol !== "evm" ||
    input.approvedChainId === null ||
    !UINT.test(input.approvedChainId) ||
    input.approvedChainId === "0" ||
    !input.approvedGenesisHash ||
    !HEX_64.test(input.approvedGenesisHash) ||
    !validAccount(input.originalAccount)
  ) {
    return result(
      "configuration_blocked",
      "This chain and wallet combination is not independently approved for money movement.",
    );
  }
  const wallet = input.currentWallet;
  if (!wallet) {
    return result("wallet_disconnected", "Connect the original wallet to inspect this transaction.");
  }
  if (
    wallet.protocol !== "evm" ||
    wallet.chainId !== input.approvedChainId
  ) {
    return result(
      "wrong_network",
      "The connected wallet uses the wrong network. No transaction is authorized.",
    );
  }
  if (!validAccount(wallet.account) ||
      wallet.account.toLowerCase() !== input.originalAccount?.toLowerCase()) {
    return result(
      "different_account",
      "The connected account has changed. Prior transaction details remain private.",
    );
  }
  if (input.signatureRejected === true) {
    return result("user_rejected", "The wallet signature was declined. No transfer was submitted.");
  }
  if (input.providerUnavailable === true) {
    return result(
      "provider_unavailable",
      "The blockchain provider is unavailable; payment state cannot be verified.",
    );
  }
  const txHash = input.txHash;
  if (!txHash) {
    return result("signature_required", "No signed, broadcast transaction has been observed.");
  }
  if (!HEX_64.test(txHash)) {
    return result("configuration_blocked", "The transaction identifier is malformed.");
  }
  const replaced = input.replacementHash;
  if (replaced !== undefined && replaced !== null) {
    if (!HEX_64.test(replaced) || replaced.toLowerCase() === txHash.toLowerCase()) {
      return result("configuration_blocked", "The replacement transaction cannot be trusted.");
    }
    return result(
      "transaction_replaced",
      "The original transaction was replaced; inspect the replacement before assuming finality.",
      replaced.toLowerCase(),
    );
  }
  const receipt = input.receipt;
  if (!receipt) {
    return result(
      "broadcast",
      "Transaction submitted. Receipt and chain finality have not been verified.",
      txHash.toLowerCase(),
    );
  }
  if (
    !HEX_64.test(receipt.transactionHash) ||
    receipt.transactionHash.toLowerCase() !== txHash.toLowerCase()
  ) {
    return result("configuration_blocked", "Receipt identity does not match the submitted transaction.");
  }
  if (receipt.success === false) {
    return result("transaction_reverted", "The transaction reverted. No successful payment is claimed.", txHash.toLowerCase());
  }
  if (!receipt.canonical || !receipt.finalized) {
    return result(
      "pending_finality",
      "The transaction is pending canonical chain finality; funds are not confirmed.",
      txHash.toLowerCase(),
    );
  }
  return result(
    "canonical_receipt_observed",
    "A canonical successful receipt was observed; independent escrow accounting is still required.",
    txHash.toLowerCase(),
  );
}
