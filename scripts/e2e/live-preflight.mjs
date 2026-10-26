#!/usr/bin/env node
/**
 * Read-only Issue #40 infrastructure preflight. It deliberately cannot prove
 * funding, verification, a dispute, payout or full product release readiness.
 * No private key, installation token or request body is ever printed.
 */
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";

const HASH = /^0x[0-9a-f]{64}$/;
const ADDRESS = /^0x[0-9a-f]{40}$/;
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const TIMEOUT_MS = 10_000;
const MAX_RESPONSE_BYTES = 1024 * 1024;
const SAFE_FAILURES = new Set([
  "chain_invalid",
  "chain_mismatch",
  "genesis_mismatch",
  "finality_unavailable",
  "escrow_code_missing",
  "escrow_code_mismatch",
  "installation_scope_mismatch",
  "revision_mismatch",
  "api_not_product_ready",
  "public_api_invalid",
]);

export class PreflightConfigurationError extends Error {
  constructor(field) {
    super(`Invalid or missing configuration: ${field}`);
    this.name = "PreflightConfigurationError";
    this.field = field;
  }
}

function secureRootUrl(value, field) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new PreflightConfigurationError(field);
  }
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    url.pathname !== "/" ||
    !url.hostname ||
    ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname)
  ) {
    throw new PreflightConfigurationError(field);
  }
  return url.origin;
}

/** No assumed or guessed chain identity: all values must be independently provisioned. */
export function parseLivePreflightConfig(env) {
  const fields = {
    rpcOrigin: secureRootUrl(env.PORTALDOT_EVM_RPC, "PORTALDOT_EVM_RPC"),
    apiOrigin: secureRootUrl(
      env.CERTIFIKS_E2E_API_ORIGIN,
      "CERTIFIKS_E2E_API_ORIGIN",
    ),
    chainId: env.CERTIFIKS_E2E_CHAIN_ID,
    genesisHash: env.CERTIFIKS_E2E_GENESIS_HASH,
    escrowAddress: env.CERTIFIKS_E2E_ESCROW_ADDRESS,
    escrowCodeSha256: env.CERTIFIKS_E2E_ESCROW_CODE_SHA256,
    repository: env.CERTIFIKS_E2E_GITHUB_REPOSITORY,
    commitSha: env.CERTIFIKS_E2E_GITHUB_COMMIT_SHA,
    installationToken: env.CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN,
  };
  for (const [key, pattern] of [
    ["chainId", /^[1-9][0-9]*$/],
    ["genesisHash", HASH],
    ["escrowAddress", ADDRESS],
    ["escrowCodeSha256", /^[0-9a-f]{64}$/],
    ["repository", REPOSITORY],
    ["commitSha", /^[0-9a-f]{40}$/],
    ["installationToken", /^[A-Za-z0-9_-]{20,}$/],
  ]) {
    if (typeof fields[key] !== "string" || !pattern.test(fields[key])) {
      throw new PreflightConfigurationError(key);
    }
  }
  // Protect against numeric precision loss when comparing RPC chain IDs.
  if (BigInt(fields.chainId) > (1n << 256n) - 1n)
    throw new PreflightConfigurationError("chainId");
  if (/^0x0{40}$/.test(fields.escrowAddress))
    throw new PreflightConfigurationError("escrowAddress");
  return fields;
}

async function jsonRequest(fetchImpl, url, init) {
  const response = await fetchImpl(url, {
    ...init,
    cache: "no-store",
    redirect: "error",
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!response.ok || response.redirected) throw new Error("request_rejected");
  const body = await response.text();
  if (Buffer.byteLength(body) > MAX_RESPONSE_BYTES)
    throw new Error("response_too_large");
  return JSON.parse(body);
}

async function rpc(config, fetchImpl, id, method, params) {
  const payload = await jsonRequest(fetchImpl, config.rpcOrigin, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id, method, params }),
  });
  if (
    payload?.jsonrpc !== "2.0" ||
    payload.id !== id ||
    Object.hasOwn(payload, "error") ||
    !Object.hasOwn(payload, "result")
  ) {
    throw new Error("rpc_invalid");
  }
  return payload.result;
}

async function checkChain(config, fetchImpl) {
  const chainId = await rpc(config, fetchImpl, 1, "eth_chainId", []);
  if (typeof chainId !== "string" || !/^0x[0-9a-f]+$/i.test(chainId))
    throw new Error("chain_invalid");
  if (BigInt(chainId) !== BigInt(config.chainId))
    throw new Error("chain_mismatch");

  const genesis = await rpc(config, fetchImpl, 2, "eth_getBlockByNumber", [
    "0x0",
    false,
  ]);
  if (
    genesis?.number !== "0x0" ||
    genesis.hash?.toLowerCase() !== config.genesisHash
  ) {
    throw new Error("genesis_mismatch");
  }
  const finalized = await rpc(config, fetchImpl, 3, "eth_getBlockByNumber", [
    "finalized",
    false,
  ]);
  if (
    typeof finalized?.number !== "string" ||
    !/^0x[0-9a-f]+$/i.test(finalized.number) ||
    !HASH.test(finalized.hash)
  ) {
    throw new Error("finality_unavailable");
  }
  const code = await rpc(config, fetchImpl, 4, "eth_getCode", [
    config.escrowAddress,
    "finalized",
  ]);
  if (typeof code !== "string" || !/^0x(?:[0-9a-f]{2})+$/i.test(code)) {
    throw new Error("escrow_code_missing");
  }
  const digest = createHash("sha256")
    .update(Buffer.from(code.slice(2), "hex"))
    .digest("hex");
  if (digest !== config.escrowCodeSha256)
    throw new Error("escrow_code_mismatch");
  return "chain_identity_finality_and_code_match";
}

async function checkGitHub(config, fetchImpl) {
  const headers = {
    Authorization: `Bearer ${config.installationToken}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2026-03-10",
  };
  // Require a token scoped to exactly one approved repository, not a broad
  // user bearer token or a public anonymous repository listing.
  const installed = await jsonRequest(
    fetchImpl,
    "https://api.github.com/installation/repositories?per_page=100",
    { headers },
  );
  if (
    installed?.total_count !== 1 ||
    !Array.isArray(installed.repositories) ||
    installed.repositories.length !== 1 ||
    installed.repositories[0]?.full_name !== config.repository
  ) {
    throw new Error("installation_scope_mismatch");
  }
  const commit = await jsonRequest(
    fetchImpl,
    `https://api.github.com/repos/${config.repository}/commits/${config.commitSha}`,
    { headers },
  );
  if (commit?.sha !== config.commitSha) throw new Error("revision_mismatch");
  return "exact_installation_scope_and_revision_match";
}

async function checkApi(config, fetchImpl) {
  const health = await jsonRequest(fetchImpl, `${config.apiOrigin}/health`, {});
  if (
    health?.status !== "ok" ||
    health?.service !== "certifiks-api" ||
    health?.productReady !== true ||
    health?.webhookIngestionConfigured !== true
  ) {
    throw new Error("api_not_product_ready");
  }
  const publicData = await jsonRequest(
    fetchImpl,
    `${config.apiOrigin}/v1/bounties?limit=1`,
    {},
  );
  if (!Array.isArray(publicData?.items)) throw new Error("public_api_invalid");
  return "healthy_product_api_and_public_projection";
}

/** Return fixed, non-sensitive status codes even when providers fail. */
export async function runLivePreflight(config, fetchImpl = fetch) {
  const checks = {};
  for (const [name, operation] of [
    ["chain", checkChain],
    ["github", checkGitHub],
    ["api", checkApi],
  ]) {
    try {
      checks[name] = {
        status: "passed",
        proof: await operation(config, fetchImpl),
      };
    } catch (error) {
      const reason = SAFE_FAILURES.has(error?.message)
        ? error.message
        : `${name}_check_failed`;
      checks[name] = { status: "blocked", reason };
    }
  }
  const infrastructureReady = Object.values(checks).every(
    (check) => check.status === "passed",
  );
  return {
    schemaVersion: 1,
    readOnly: true,
    infrastructureReady,
    completeJourneyVerified: false,
    checks,
    note: "This preflight never verifies identity sessions, real deposits, independent tests, payout or refund. Issue #40 still requires witnessed live E2E evidence.",
  };
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  try {
    const config = parseLivePreflightConfig(process.env);
    const result = await runLivePreflight(config);
    console.log(JSON.stringify(result, null, 2));
    if (!result.infrastructureReady) process.exitCode = 1;
  } catch (error) {
    console.error(
      error instanceof PreflightConfigurationError
        ? `PREFLIGHT_BLOCKED: ${error.message}`
        : "PREFLIGHT_BLOCKED: unexpected failure",
    );
    process.exitCode = 1;
  }
}
