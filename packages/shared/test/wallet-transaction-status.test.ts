import assert from "node:assert/strict";
import test from "node:test";
import {
  assessWalletTransactionV1,
  type WalletTxObservationInputV1,
} from "../src/wallet-transaction-status.js";

const ADDRESS = "0x" + "a".repeat(40);
const TX = "0x" + "b".repeat(64);
const GENESIS = "0x" + "c".repeat(64);
const base: WalletTxObservationInputV1 = {
  approvedProtocol: "evm",
  approvedChainId: "11155111",
  approvedGenesisHash: GENESIS,
  originalAccount: ADDRESS,
  currentWallet: { protocol: "evm", chainId: "11155111", account: ADDRESS },
  txHash: TX,
};

test("no browser wallet status can assert escrow custody or payout", () => {
  const variations: WalletTxObservationInputV1[] = [
    base,
    { ...base, txHash: null },
    { ...base, currentWallet: null },
    { ...base, currentWallet: { ...base.currentWallet!, chainId: "1" } },
    { ...base, signatureRejected: true },
    { ...base, providerUnavailable: true },
    { ...base, replacementHash: "0x" + "d".repeat(64) },
    { ...base, receipt: { transactionHash: TX, canonical: true, finalized: true, success: true } },
    { ...base, receipt: { transactionHash: TX, canonical: false, finalized: false, success: true } },
    { ...base, receipt: { transactionHash: TX, canonical: true, finalized: true, success: false } },
  ];
  for (const input of variations) {
    const state = assessWalletTransactionV1(input);
    assert.equal(state.allowTransfer, false);
    assert.equal(state.custodyVerified, false);
    assert.equal(state.payoutVerified, false);
    assert.ok(state.userMessage.length > 10);
  }
});

test("unapproved or Substrate-only runtime never enables EVM wallet transfers", () => {
  assert.equal(
    assessWalletTransactionV1({ ...base, approvedProtocol: "substrate" }).status,
    "configuration_blocked",
  );
  assert.equal(
    assessWalletTransactionV1({ ...base, approvedGenesisHash: null }).status,
    "configuration_blocked",
  );
  assert.equal(
    assessWalletTransactionV1({ ...base, approvedChainId: "0" }).status,
    "configuration_blocked",
  );
});

test("wallet disconnect, wrong chain and account switching invalidate display assumptions", () => {
  assert.equal(
    assessWalletTransactionV1({ ...base, currentWallet: null }).status,
    "wallet_disconnected",
  );
  assert.equal(
    assessWalletTransactionV1({
      ...base, currentWallet: { protocol: "evm", chainId: "1", account: ADDRESS },
    }).status,
    "wrong_network",
  );
  const switched = assessWalletTransactionV1({
    ...base,
    currentWallet: { protocol: "evm", chainId: "11155111", account: "0x" + "e".repeat(40) },
  });
  assert.equal(switched.status, "different_account");
  assert.equal(switched.evidenceTxHash, null);
});

test("rejected, reverted, replaced and pending transactions never appear paid", () => {
  assert.equal(
    assessWalletTransactionV1({ ...base, signatureRejected: true }).status,
    "user_rejected",
  );
  assert.equal(
    assessWalletTransactionV1({
      ...base, receipt: { transactionHash: TX, canonical: true, finalized: true, success: false },
    }).status,
    "transaction_reverted",
  );
  assert.equal(
    assessWalletTransactionV1({
      ...base, replacementHash: "0x" + "d".repeat(64),
    }).status,
    "transaction_replaced",
  );
  assert.equal(
    assessWalletTransactionV1({
      ...base, receipt: { transactionHash: TX, canonical: false, finalized: false, success: true },
    }).status,
    "pending_finality",
  );
});

test("matching canonical receipt is still only an observation, not funding authorization", () => {
  const observed = assessWalletTransactionV1({
    ...base,
    receipt: { transactionHash: TX, canonical: true, finalized: true, success: true },
  });
  assert.equal(observed.status, "canonical_receipt_observed");
  assert.equal(observed.custodyVerified, false);
  assert.equal(observed.payoutVerified, false);
  assert.equal(observed.allowTransfer, false);
  assert.equal(
    assessWalletTransactionV1({
      ...base, receipt: { transactionHash: "0x" + "f".repeat(64), canonical: true, finalized: true, success: true },
    }).status,
    "configuration_blocked",
  );
});
