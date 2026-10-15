# Contributing

CertiFiks is building an escrow service that must earn user trust through verifiable behavior. Start from the [product specification](docs/product/PRD.md), [security model](docs/security/THREAT_MODEL.md) and [46-issue backlog](https://github.com/EcstaceeLOR/CertiFiks/issues/1).

Open one focused PR per issue with tests, negative paths and a truthful description of incomplete dependencies. Never introduce silent mock-to-production fallbacks or fake paid/verified states. Tests must not send funds on public mainnet or execute untrusted pull-request code on a privileged runner. Do not add credentials to code or CI logs.

Before requesting review: run Node and Python tests (commands in README) and any Foundry checks relevant to the contract. Link exact evidence and resolve critical findings before merge. Public contracts are unreviewed until #6 and #41 complete.
