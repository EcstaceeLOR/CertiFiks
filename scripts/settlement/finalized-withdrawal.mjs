#!/usr/bin/env node
/**
 * Issue #16: read-only finality-bound witness for a native payout event.
 * A green result witnesses a particular event on a configured chain, NOT
 * an audit, authorization for funding, or a claim of production readiness.
 */
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";

export const WITHDRAWN_TOPIC =
  "0x5dda4341e6ecb0fe9f51e8db7179eb1638b5fcabee55fb0e2255252354bf6bda";

const HEX_32 = /^0x[0-9a-f]{64}$/;
const ADDRESS = /^0x[0-9a-f]{40}$/;
const QUANTITY = /^0x(?:0|[1-9a-f][0-9a-f]*)$/;
const UINT256 = (1n << 256n) - 1n;
const OUTPUT_KEYS = [
  "chainId", "genesisHash", "escrowAddress", "escrowCodeSha256",
  "transactionHash", "logIndex", "bountyId", "beneficiary",
  "recipient", "amountAtoms", "remainingAtoms", "rpcOrigin",
];

export class PayoutProofError extends Error {
  constructor() {
    super("PAYOUT_PROOF_BLOCKED");
    this.name = "PayoutProofError";
  }
}

function insist(condition) {
  if (!condition) throw new PayoutProofError();
}

function uint(value, allowZero = false) {
  insist(typeof value === "string" && /^(0|[1-9][0-9]*)$/.test(value));
  const parsed = BigInt(value);
  insist(parsed <= UINT256 && (allowZero || parsed > 0n));
  return parsed;
}

function hexQuantity(value) {
  insist(typeof value === "string" && QUANTITY.test(value));
  return BigInt(value);
}

function cleanAddress(value) {
  insist(typeof value === "string" && ADDRESS.test(value));
  return value;
}

export function parsePayoutProofConfig(input) {
  insist(input !== null && typeof input === "object" && !Array.isArray(input));
  insist(Object.keys(input).sort().join("|") === [...OUTPUT_KEYS].sort().join("|"));
  let url;
  try {
    url = new URL(input.rpcOrigin);
  } catch {
    throw new PayoutProofError();
  }
  insist(
    url.protocol === "https:" &&
    url.origin === url.href.replace(/\/$/, "") &&
    url.pathname === "/" &&
    !url.username && !url.password && !url.search && !url.hash &&
    !["localhost", "127.0.0.1", "[::1]"].includes(url.hostname),
  );
  insist(typeof input.genesisHash === "string" && HEX_32.test(input.genesisHash));
  insist(typeof input.transactionHash === "string" && HEX_32.test(input.transactionHash));
  insist(typeof input.escrowCodeSha256 === "string" &&
    /^[a-f0-9]{64}$/.test(input.escrowCodeSha256));
  insist(typeof input.logIndex === "string" && QUANTITY.test(input.logIndex));
  cleanAddress(input.escrowAddress);
  cleanAddress(input.beneficiary);
  cleanAddress(input.recipient);
  uint(input.chainId);
  uint(input.bountyId);
  uint(input.amountAtoms);
  uint(input.remainingAtoms, true);
  return Object.freeze({ ...input });
}

async function rpc(config, request, id, method, params) {
  let data;
  try {
    const response = await request(config.rpcOrigin, {
      method: "POST",
      redirect: "error",
      cache: "no-store",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
      signal: AbortSignal.timeout(8000),
    });
    insist(response.ok && !response.redirected);
    const body = await response.text();
    insist(Buffer.byteLength(body) <= 1024 * 1024);
    data = JSON.parse(body);
  } catch {
    throw new PayoutProofError();
  }
  insist(
    data?.jsonrpc === "2.0" && data.id === id &&
    !Object.hasOwn(data, "error") && Object.hasOwn(data, "result"),
  );
  return data.result;
}

function addressTopic(address) {
  return "0x" + "0".repeat(24) + address.slice(2);
}

function eventFields(log) {
  insist(Array.isArray(log?.topics) && log.topics.length === 4);
  insist(log.topics[0] === WITHDRAWN_TOPIC);
  insist(typeof log.data === "string" && /^0x[0-9a-f]{128}$/.test(log.data));
  for (const topic of log.topics) {
    insist(typeof topic === "string" && HEX_32.test(topic));
  }
  return {
    bountyId: BigInt(log.topics[1]),
    beneficiary: "0x" + log.topics[2].slice(26),
    recipient: "0x" + log.topics[3].slice(26),
    amountAtoms: BigInt("0x" + log.data.slice(2, 66)),
    remainingAtoms: BigInt("0x" + log.data.slice(66, 130)),
  };
}

/** All RPC data is untrusted until chain identity, canonical block and
 * exact receipt event are checked. Requires a node supporting "finalized".
 */
export async function verifyFinalizedNativeWithdrawal(rawConfig, request = fetch) {
  const config = parsePayoutProofConfig(rawConfig);
  const chain = await rpc(config, request, 1, "eth_chainId", []);
  insist(hexQuantity(chain) === uint(config.chainId));
  const genesis = await rpc(config, request, 2, "eth_getBlockByNumber", [
    "0x0", false,
  ]);
  insist(genesis?.number === "0x0" && genesis.hash === config.genesisHash);

  const receipt = await rpc(config, request, 3, "eth_getTransactionReceipt", [
    config.transactionHash,
  ]);
  insist(receipt?.transactionHash === config.transactionHash &&
    receipt.status === "0x1" &&
    receipt.to === config.escrowAddress &&
    typeof receipt.blockHash === "string" && HEX_32.test(receipt.blockHash) &&
    Array.isArray(receipt.logs) && receipt.logs.length <= 500);
  const number = hexQuantity(receipt.blockNumber);
  const finalized = await rpc(config, request, 4, "eth_getBlockByNumber", [
    "finalized", false,
  ]);
  insist(typeof finalized?.hash === "string" && HEX_32.test(finalized.hash));
  insist(hexQuantity(finalized.number) >= number);
  const canonical = await rpc(config, request, 5, "eth_getBlockByNumber", [
    receipt.blockNumber, false,
  ]);
  insist(canonical?.hash === receipt.blockHash &&
    hexQuantity(canonical.number) === number);
  const bytecode = await rpc(config, request, 6, "eth_getCode", [
    config.escrowAddress, receipt.blockNumber,
  ]);
  insist(typeof bytecode === "string" && /^0x(?:[a-f0-9]{2})+$/i.test(bytecode));
  insist(createHash("sha256").update(Buffer.from(bytecode.slice(2), "hex"))
    .digest("hex") === config.escrowCodeSha256);

  const match = receipt.logs.filter((log) =>
    log?.address === config.escrowAddress &&
    log?.transactionHash === config.transactionHash &&
    log?.blockHash === receipt.blockHash &&
    log?.blockNumber === receipt.blockNumber &&
    log?.logIndex === config.logIndex
  );
  insist(match.length === 1 && match[0].removed !== true);
  const fields = eventFields(match[0]);
  insist(
    fields.bountyId === uint(config.bountyId) &&
    fields.beneficiary === config.beneficiary &&
    fields.recipient === config.recipient &&
    fields.amountAtoms === uint(config.amountAtoms) &&
    fields.remainingAtoms === uint(config.remainingAtoms, true),
  );
  // A finalized event proves a successful on-chain transfer call emitted
  // by this bytecode. It does not prove the real-world recipient's identity.
  return {
    schemaVersion: 1,
    witness: "finalized_native_withdrawal_event",
    verifiedOnConfiguredRpc: true,
    securityAuditApproved: false,
    productReady: false,
    chainId: config.chainId,
    transactionHash: config.transactionHash,
    blockHash: receipt.blockHash,
    blockNumber: number.toString(),
    logIndex: config.logIndex,
    escrowAddress: config.escrowAddress,
    bountyId: config.bountyId,
    beneficiary: config.beneficiary,
    recipient: config.recipient,
    amountAtoms: config.amountAtoms,
    remainingAtoms: config.remainingAtoms,
  };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    insist(process.argv.length === 3);
    const { readFile } = await import("node:fs/promises");
    const config = JSON.parse(await readFile(process.argv[2], "utf8"));
    const result = await verifyFinalizedNativeWithdrawal(config);
    process.stdout.write(JSON.stringify(result, null, 2) + "\n");
  } catch {
    process.stderr.write("PAYOUT_PROOF_BLOCKED\n");
    process.exitCode = 1;
  }
}
