#!/usr/bin/env node
/**
 * Read-only HTTP JSON-RPC capability probe for Portaldot V3 EVM endpoints.
 * IMPORTANT: It does not deploy anything or establish that the RPC is approved.
 * Node.js >=22; run with PORTALDOT_EVM_RPC=https://approved-v3-evm-rpc ...
 */
const candidate = process.env.PORTALDOT_EVM_RPC;
if (!candidate) {
  console.error('Set PORTALDOT_EVM_RPC to an organizer-confirmed V3 HTTP(S) EVM RPC.');
  process.exit(2);
}
const url = new URL(candidate);
const local = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password || url.search || url.hash) {
  console.error('Public RPC must use HTTPS and cannot include secrets, query params or fragments.');
  process.exit(2);
}

const timeoutMs = Math.min(30000, Math.max(2000, Number(process.env.RPC_TIMEOUT_MS || 12000)));
const methods = [
  ['web3_clientVersion', []],
  ['eth_chainId', []],
  ['eth_blockNumber', []],
  ['eth_getBlockByNumber', ['latest', false]],
  ['net_version', []]
];
const report = {
  schema_version: 1,
  timestamp_utc: new Date().toISOString(),
  rpc_endpoint: url.origin + url.pathname,
  read_only: true,
  methods: {},
  warnings: [
    'eth_chainId alone is not proof of Portaldot or contract deployability.',
    'No fee estimate, contract bytecode deployment, wallet balance transfer, or signature is performed.',
    'Confirm genesis/block hash, chain ID and endpoint ownership with event organizers before accepting RPC as Portaldot V3.',
    'A local/dev Ethereum RPC returning success does not qualify as a Portaldot deployment.'
  ]
};

for (let i = 0; i < methods.length; i++) {
  const [method, params] = methods[i];
  try {
    const response = await fetch(candidate, {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(timeoutMs),
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ jsonrpc: '2.0', id: i + 1, method, params })
    });
    if (!response.ok) throw new Error('HTTP ' + response.status);
    const payload = await response.json();
    if (payload.error) {
      report.methods[method] = { status: payload.error.code === -32601 ? 'unsupported' : 'rpc_error', code: payload.error.code, message: String(payload.error.message || '').slice(0, 160) };
    } else {
      let result = payload.result;
      if (method === 'eth_getBlockByNumber' && result) {
        result = { hash: result.hash, number: result.number, timestamp: result.timestamp, parentHash: result.parentHash, transactionsCount: Array.isArray(result.transactions) ? result.transactions.length : null };
      }
      report.methods[method] = { status: 'ok', result };
    }
  } catch (err) {
    report.methods[method] = { status: 'failed', error: String(err.message || err).slice(0, 160) };
  }
}
console.log(JSON.stringify(report, null, 2));
if (report.methods.eth_chainId.status !== 'ok' || report.methods.eth_blockNumber.status !== 'ok') process.exitCode = 1;
