import { createHash } from "node:crypto";

const HASH = /^0x[a-f0-9]{64}$/;
const ADDRESS = /^0x[a-f0-9]{40}$/;
const NUMBER_HEX = /^0x(?:0|[1-9a-f][0-9a-f]*)$/;
const GITHUB_SAFE_NUMBER = /^(0|[1-9][0-9]*)$/;

export class ChainObservationError extends Error {
  constructor(
    public readonly reason:
      | "UNAPPROVED_CHAIN"
      | "MALFORMED_RPC"
      | "PROVIDER_UNAVAILABLE"
      | "REORG"
      | "UNAPPROVED_CONTRACT",
    message: string,
  ) {
    super(message);
    this.name = "ChainObservationError";
  }
}

export interface EvmObservationConfigV1 {
  rpcHttpsUrl: string;
  approvedChainId: string;
  approvedGenesisHash: string;
  contractAddresses: string[];
  eventTopic0: string[];
}

export interface ObservedEvmLogV1 {
  transactionHash: string;
  blockHash: string;
  blockNumber: string;
  logIndex: string;
  address: string;
  topic0: string;
  dataSha256: string;
}

export interface ObservedEvmBlockV1 {
  chainId: string;
  blockNumber: string;
  blockHash: string;
  parentHash: string;
  observedHead: string;
  logs: ObservedEvmLogV1[];
}

/**
 * EVM-compatible JSON-RPC observer only. NOT proof that Portaldot supports
 * these RPC methods. Runtime approval, contract ABI, genesis and address
 * allowlists must be obtained independently by an operator.
 */
export class ReadOnlyEvmObserverV1 {
  private readonly addressSet: Set<string>;
  private readonly topicSet: Set<string>;
  private readonly url: string;

  constructor(
    private readonly config: EvmObservationConfigV1,
    private readonly request: typeof fetch = fetch,
  ) {
    const url = new URL(config.rpcHttpsUrl);
    if (
      url.protocol !== "https:" ||
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      !GITHUB_SAFE_NUMBER.test(config.approvedChainId) ||
      config.approvedChainId === "0" ||
      !HASH.test(config.approvedGenesisHash) ||
      config.contractAddresses.length < 1 ||
      config.eventTopic0.length < 1 ||
      !config.contractAddresses.every((value) => ADDRESS.test(value)) ||
      !config.eventTopic0.every((value) => HASH.test(value))
    ) {
      throw new ChainObservationError(
        "UNAPPROVED_CHAIN",
        "Missing approved chain/contract/RPC identity",
      );
    }
    this.url = url.href;
    this.addressSet = new Set(config.contractAddresses);
    this.topicSet = new Set(config.eventTopic0);
  }

  private async rpc(method: string, params: unknown[] = []): Promise<unknown> {
    let reply: Response;
    try {
      reply = await this.request(this.url, {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(10000),
      });
    } catch {
      throw new ChainObservationError(
        "PROVIDER_UNAVAILABLE",
        "EVM provider unavailable",
      );
    }
    if (!reply.ok)
      throw new ChainObservationError(
        "PROVIDER_UNAVAILABLE",
        "EVM provider rejected request",
      );
    let result: unknown;
    try {
      result = await reply.json();
    } catch {
      throw new ChainObservationError("MALFORMED_RPC", "Malformed RPC JSON");
    }
    if (
      !result ||
      typeof result !== "object" ||
      !("jsonrpc" in result) ||
      result.jsonrpc !== "2.0" ||
      !("id" in result) ||
      result.id !== 1 ||
      !("result" in result) ||
      "error" in result
    ) {
      throw new ChainObservationError(
        "MALFORMED_RPC",
        "Malformed RPC envelope",
      );
    }
    return result.result;
  }

  async observeBlock(height: number): Promise<ObservedEvmBlockV1> {
    if (!Number.isSafeInteger(height) || height < 1) {
      throw new ChainObservationError("MALFORMED_RPC", "Invalid block height");
    }
    const chain = await this.rpc("eth_chainId");
    if (
      typeof chain !== "string" ||
      !NUMBER_HEX.test(chain) ||
      BigInt(chain).toString() !== this.config.approvedChainId
    ) {
      throw new ChainObservationError(
        "UNAPPROVED_CHAIN",
        "Wrong chain identity",
      );
    }
    const genesis = await this.rpc("eth_getBlockByNumber", ["0x0", false]);
    if (
      !genesis ||
      typeof genesis !== "object" ||
      !("hash" in genesis) ||
      genesis.hash !== this.config.approvedGenesisHash
    ) {
      throw new ChainObservationError(
        "UNAPPROVED_CHAIN",
        "Wrong chain genesis",
      );
    }
    const headValue = await this.rpc("eth_blockNumber");
    if (typeof headValue !== "string" || !NUMBER_HEX.test(headValue)) {
      throw new ChainObservationError("MALFORMED_RPC", "Invalid observed head");
    }
    const observedHead = BigInt(headValue);
    if (BigInt(height) > observedHead) {
      throw new ChainObservationError(
        "PROVIDER_UNAVAILABLE",
        "Block is not yet available",
      );
    }

    const blockTag = `0x${height.toString(16)}`;
    const block = await this.rpc("eth_getBlockByNumber", [blockTag, false]);
    if (
      !block ||
      typeof block !== "object" ||
      !("hash" in block) ||
      typeof block.hash !== "string" ||
      !HASH.test(block.hash) ||
      !("parentHash" in block) ||
      typeof block.parentHash !== "string" ||
      !HASH.test(block.parentHash) ||
      !("number" in block) ||
      block.number !== blockTag
    ) {
      throw new ChainObservationError(
        "MALFORMED_RPC",
        "Malformed block metadata",
      );
    }
    const logs = await this.rpc("eth_getLogs", [
      {
        fromBlock: blockTag,
        toBlock: blockTag,
        address: this.config.contractAddresses,
        topics: [this.config.eventTopic0],
      },
    ]);
    if (!Array.isArray(logs) || logs.length > 1000) {
      throw new ChainObservationError(
        "MALFORMED_RPC",
        "Malformed or excessive block logs",
      );
    }
    const unique = new Set<string>();
    const events: ObservedEvmLogV1[] = [];
    for (const raw of logs) {
      if (!raw || typeof raw !== "object") {
        throw new ChainObservationError(
          "MALFORMED_RPC",
          "Malformed log object",
        );
      }
      const entry = raw as Record<string, unknown>;
      if (
        entry.removed === true ||
        entry.blockHash !== block.hash ||
        entry.blockNumber !== blockTag
      )
        throw new ChainObservationError(
          "REORG",
          "Log does not belong to canonical observed block",
        );
      if (
        typeof entry.address !== "string" ||
        !this.addressSet.has(entry.address) ||
        !Array.isArray(entry.topics) ||
        typeof entry.topics[0] !== "string" ||
        !this.topicSet.has(entry.topics[0])
      )
        throw new ChainObservationError(
          "UNAPPROVED_CONTRACT",
          "Unexpected contract event",
        );
      if (
        typeof entry.transactionHash !== "string" ||
        !HASH.test(entry.transactionHash) ||
        typeof entry.logIndex !== "string" ||
        !NUMBER_HEX.test(entry.logIndex) ||
        typeof entry.data !== "string" ||
        !/^0x(?:[a-f0-9]{2})*$/.test(entry.data) ||
        BigInt(entry.logIndex) > BigInt(2147483647)
      )
        throw new ChainObservationError(
          "MALFORMED_RPC",
          "Invalid log identity",
        );
      const key = `${entry.transactionHash}:${entry.logIndex}`;
      if (unique.has(key))
        throw new ChainObservationError("MALFORMED_RPC", "Duplicate RPC log");
      unique.add(key);
      events.push({
        transactionHash: entry.transactionHash,
        blockHash: block.hash,
        blockNumber: String(height),
        logIndex: BigInt(entry.logIndex).toString(),
        address: entry.address,
        topic0: entry.topics[0],
        dataSha256:
          "0x" +
          createHash("sha256")
            .update(Buffer.from(entry.data.slice(2), "hex"))
            .digest("hex"),
      });
    }

    // Detect a reorg during the read interval, before committing any data.
    const confirmed = await this.rpc("eth_getBlockByNumber", [blockTag, false]);
    if (
      !confirmed ||
      typeof confirmed !== "object" ||
      !("hash" in confirmed) ||
      confirmed.hash !== block.hash
    ) {
      throw new ChainObservationError(
        "REORG",
        "Observed block changed during RPC scan",
      );
    }

    return {
      chainId: this.config.approvedChainId,
      blockNumber: String(height),
      blockHash: block.hash,
      parentHash: block.parentHash,
      observedHead: observedHead.toString(),
      logs: events,
    };
  }
}
