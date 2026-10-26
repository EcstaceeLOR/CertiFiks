import {
  ReadOnlyEvmObserverV1,
  type EvmObservationConfigV1,
} from "./evm-observer.js";

/**
 * Safe, one-block-at-a-time DB-integrated poll step. It cannot authorize a
 * bounty, a verification verdict or money movement. Runtime and deployed ABI
 * approval MUST precede actual use in any environment.
 */
export class ChainIndexerBlockedError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ChainIndexerBlockedError";
  }
}

export class DurableEvmIndexStepV1 {
  private readonly endpoint: URL;
  private readonly observer: ReadOnlyEvmObserverV1;

  constructor(
    private readonly config: EvmObservationConfigV1,
    supabaseUrl: string,
    private readonly serviceKey: string,
    rpcFetch: typeof fetch = fetch,
    private readonly databaseFetch: typeof fetch = fetch,
  ) {
    const url = new URL(supabaseUrl);
    if (
      url.protocol !== "https:" ||
      !url.hostname.endsWith(".supabase.co") ||
      url.search || url.hash || url.username || url.password ||
      typeof serviceKey !== "string" || serviceKey.length < 16
    ) throw new ChainIndexerBlockedError("Approved server-side database not configured");
    this.endpoint = new URL("/rest/v1/", url);
    this.observer = new ReadOnlyEvmObserverV1(config, rpcFetch);
  }

  private async readOrWrite(path: string, args?: object): Promise<unknown> {
    const url = new URL(path, this.endpoint);
    let response: Response;
    try {
      response = await this.databaseFetch(url.href, {
        method: args ? "POST" : "GET",
        redirect: "error",
        cache: "no-store",
        headers: {
          "content-type": "application/json",
          apikey: this.serviceKey,
          Authorization: `Bearer ${this.serviceKey}`,
          Accept: "application/json",
        },
        ...(args ? { body: JSON.stringify(args) } : {}),
        signal: AbortSignal.timeout(8000),
      });
    } catch {
      throw new ChainIndexerBlockedError("Database unavailable; no chain observation acknowledged");
    }
    if (!response.ok) throw new ChainIndexerBlockedError("Database rejected chain observation");
    try {
      return await response.json();
    } catch {
      throw new ChainIndexerBlockedError("Database response could not be independently validated");
    }
  }

  async pollOnce(): Promise<"accepted" | "duplicate"> {
    const query = new URLSearchParams({
      select: "genesis_hash,last_scanned,last_hash,halted,confirmation_depth",
      chain_id: `eq.${this.config.approvedChainId}`,
      limit: "1",
    });
    const cursor = await this.readOrWrite(
      `certifiks_chain_indexer_heads?${query.toString()}`,
    );
    if (!Array.isArray(cursor) || cursor.length !== 1 ||
      typeof cursor[0] !== "object" || cursor[0] === null) {
      throw new ChainIndexerBlockedError("Chain indexer cursor not provisioned");
    }
    const row = cursor[0] as Record<string, unknown>;
    const height = Number(row.last_scanned);
    if (
      row.halted !== false ||
      row.genesis_hash !== this.config.approvedGenesisHash ||
      typeof row.last_hash !== "string" ||
      !/^0x[a-f0-9]{64}$/.test(row.last_hash) ||
      !Number.isSafeInteger(height) || height < 0
    ) throw new ChainIndexerBlockedError("Chain cursor inconsistent or halted");
    const block = await this.observer.observeBlock(height + 1);
    if (block.parentHash !== row.last_hash) {
      // DO NOT resolve this automatically: finality and accounting history
      // must be examined before choosing an authorized rewind ancestor.
      throw new ChainIndexerBlockedError("REORG_OR_GAP: operator reconciliation required");
    }
    const result = await this.readOrWrite(
      "rpc/certifiks_commit_evm_observation",
      {
        p_chain_id: block.chainId,
        p_number: block.blockNumber,
        p_hash: block.blockHash,
        p_parent: block.parentHash,
        p_observed_head: block.observedHead,
        p_logs: block.logs,
      },
    );
    if (result !== "accepted" && result !== "duplicate") {
      throw new ChainIndexerBlockedError("Database did not confirm exact committed block");
    }
    return result;
  }
}
