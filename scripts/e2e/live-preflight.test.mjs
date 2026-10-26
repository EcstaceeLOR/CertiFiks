import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import {
  parseLivePreflightConfig,
  runLivePreflight,
} from "./live-preflight.mjs";

const code = "0x6001600055";
const genesisHash = `0x${"a".repeat(64)}`;
const finalizedHash = `0x${"b".repeat(64)}`;
const commitSha = "c".repeat(40);
const configEnv = {
  PORTALDOT_EVM_RPC: "https://rpc.confirmed.invalid/",
  CERTIFIKS_E2E_API_ORIGIN: "https://api.certifiks.invalid/",
  CERTIFIKS_E2E_CHAIN_ID: "12345",
  CERTIFIKS_E2E_GENESIS_HASH: genesisHash,
  CERTIFIKS_E2E_ESCROW_ADDRESS: `0x${"d".repeat(40)}`,
  CERTIFIKS_E2E_ESCROW_CODE_SHA256: createHash("sha256")
    .update(Buffer.from(code.slice(2), "hex"))
    .digest("hex"),
  CERTIFIKS_E2E_GITHUB_REPOSITORY: "Maintainer/real-repo",
  CERTIFIKS_E2E_GITHUB_COMMIT_SHA: commitSha,
  CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN: "test_secret_never_print_this_12345",
};

function fakeProvider(overrides = {}) {
  const seen = [];
  const fetcher = async (url, options) => {
    seen.push({ url, options });
    assert.equal(options.redirect, "error");
    assert.equal(options.cache, "no-store");
    if (overrides.throwSecret) {
      throw new Error(
        `Provider leaked ${configEnv.CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN}`,
      );
    }
    if (url === new URL(configEnv.PORTALDOT_EVM_RPC).origin) {
      const { id, method } = JSON.parse(options.body);
      const replies = {
        eth_chainId: overrides.chainId ?? "0x3039",
        eth_getBlockByNumber:
          id === 2
            ? { hash: overrides.genesisHash ?? genesisHash, number: "0x0" }
            : Object.hasOwn(overrides, "finalized")
              ? overrides.finalized
              : { hash: finalizedHash, number: "0x40" },
        eth_getCode: overrides.code ?? code,
      };
      return Response.json({ jsonrpc: "2.0", id, result: replies[method] });
    }
    if (url.includes("/installation/repositories")) {
      assert.equal(
        options.headers.Authorization,
        `Bearer ${configEnv.CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN}`,
      );
      return Response.json(
        overrides.installed ?? {
          total_count: 1,
          repositories: [{ full_name: "Maintainer/real-repo" }],
        },
      );
    }
    if (url.includes("/commits/")) {
      return Response.json({ sha: overrides.commitSha ?? commitSha });
    }
    if (url.endsWith("/health")) {
      return Response.json(
        overrides.health ?? {
          status: "ok",
          service: "certifiks-api",
          productReady: true,
          webhookIngestionConfigured: true,
        },
      );
    }
    if (url.includes("/v1/bounties")) {
      return Response.json(overrides.bounties ?? { items: [] });
    }
    throw new Error("Unexpected outbound request");
  };
  return { fetcher, seen };
}

test("rejects incomplete, local or misleading live configuration", () => {
  for (const [field, value] of [
    ["PORTALDOT_EVM_RPC", "http://127.0.0.1:8545"],
    ["CERTIFIKS_E2E_API_ORIGIN", "https://user:pass@api.invalid/"],
    ["CERTIFIKS_E2E_CHAIN_ID", "0"],
    ["CERTIFIKS_E2E_CHAIN_ID", "9".repeat(100)],
    ["CERTIFIKS_E2E_GENESIS_HASH", `0x${"f".repeat(63)}`],
    ["CERTIFIKS_E2E_ESCROW_ADDRESS", `0x${"0".repeat(40)}`],
    ["CERTIFIKS_E2E_ESCROW_CODE_SHA256", "none"],
    ["CERTIFIKS_E2E_GITHUB_COMMIT_SHA", "main"],
    ["CERTIFIKS_E2E_GITHUB_INSTALLATION_TOKEN", ""],
  ]) {
    assert.throws(
      () => parseLivePreflightConfig({ ...configEnv, [field]: value }),
      {
        name: "PreflightConfigurationError",
      },
    );
  }
  assert.throws(() => parseLivePreflightConfig({}), {
    name: "PreflightConfigurationError",
  });
});

test("requires confirmed identity, scoped GitHub access and product-ready API", async () => {
  const config = parseLivePreflightConfig(configEnv);
  const { fetcher, seen } = fakeProvider();
  const result = await runLivePreflight(config, fetcher);
  assert.equal(result.infrastructureReady, true);
  assert.equal(result.completeJourneyVerified, false);
  assert.deepEqual(
    Object.values(result.checks).map((check) => check.status),
    ["passed", "passed", "passed"],
  );
  assert.equal(seen.length, 8);
  assert(!JSON.stringify(result).includes(config.installationToken));
  assert(seen.every(({ options }) => options.signal instanceof AbortSignal));
  assert(seen.every(({ options }) => options.method !== "PUT"));
});

test("rejects wrong network, genesis, finality, deployment and code identity", async () => {
  const config = parseLivePreflightConfig(configEnv);
  for (const overrides of [
    { chainId: "0x1" },
    { genesisHash: `0x${"e".repeat(64)}` },
    { finalized: null },
    { code: "0x" },
    { code: "0x6002" },
  ]) {
    const result = await runLivePreflight(
      config,
      fakeProvider(overrides).fetcher,
    );
    assert.equal(result.infrastructureReady, false);
    assert.equal(result.checks.chain.status, "blocked");
    assert.equal(result.checks.github.status, "passed");
  }
});

test("rejects broad installation, wrong revision and unavailable API", async () => {
  const config = parseLivePreflightConfig(configEnv);
  for (const overrides of [
    {
      installed: {
        total_count: 2,
        repositories: [{ full_name: config.repository }],
      },
    },
    { commitSha: "e".repeat(40) },
    { health: { status: "ok", service: "certifiks-api", productReady: false } },
    { bounties: { error: "not configured" } },
  ]) {
    const result = await runLivePreflight(
      config,
      fakeProvider(overrides).fetcher,
    );
    assert.equal(result.infrastructureReady, false);
    assert(
      Object.values(result.checks).some((check) => check.status === "blocked"),
    );
  }
});

test("never echoes provider errors or bearer credentials", async () => {
  const config = parseLivePreflightConfig(configEnv);
  const result = await runLivePreflight(
    config,
    fakeProvider({ throwSecret: true }).fetcher,
  );
  assert.equal(result.infrastructureReady, false);
  assert(!JSON.stringify(result).includes(config.installationToken));
  assert(!JSON.stringify(result).includes("Provider leaked"));
});
