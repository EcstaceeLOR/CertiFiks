import { createPrivateKey, sign } from "node:crypto";
import type { InstalledRepositoryPermissionsV1 } from "./revision-verifier.js";

const GITHUB = "https://api.github.com";
const VERSION = "2026-03-10";

export class GitHubAppAuthError extends Error {
  constructor(
    public readonly code:
      | "MISCONFIGURED"
      | "UNAUTHORIZED"
      | "FORBIDDEN"
      | "UPSTREAM_UNAVAILABLE",
    message: string,
  ) {
    super(message);
    this.name = "GitHubAppAuthError";
  }
}

export interface GitHubAppCredentials {
  appId: number;
  privateKeyPem: string;
}

function positiveInteger(v: number): boolean {
  return Number.isSafeInteger(v) && v > 0;
}

/** App authentication JWT: server-only RS256, ten-minute maximum lifetime. */
export function issueGitHubAppJwt(
  credentials: GitHubAppCredentials,
  nowSeconds = Math.floor(Date.now() / 1000),
): string {
  if (
    !positiveInteger(credentials.appId) ||
    !Number.isSafeInteger(nowSeconds)
  ) {
    throw new GitHubAppAuthError(
      "MISCONFIGURED",
      "Invalid GitHub App identity or clock",
    );
  }
  let key: ReturnType<typeof createPrivateKey>;
  try {
    key = createPrivateKey(credentials.privateKeyPem.replace(/\\n/g, "\n"));
    if (key.asymmetricKeyType !== "rsa") throw new Error("RSA required");
  } catch {
    throw new GitHubAppAuthError(
      "MISCONFIGURED",
      "Invalid GitHub App RSA private key",
    );
  }
  const encode = (value: object) =>
    Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = [
    encode({ alg: "RS256", typ: "JWT" }),
    encode({
      iat: nowSeconds - 60,
      exp: nowSeconds + 540,
      iss: String(credentials.appId),
    }),
  ].join(".");
  return (
    unsigned +
    "." +
    sign("RSA-SHA256", Buffer.from(unsigned), key).toString("base64url")
  );
}

interface TokenReply {
  token?: unknown;
  expires_at?: unknown;
  repositories?: unknown;
  permissions?: unknown;
}

export interface ScopedInstallationToken {
  token: string;
  expiresAt: string;
  installationId: number;
  repositoryId: number;
  permissions: InstalledRepositoryPermissionsV1;
}

/**
 * Mints a narrowly scoped, ephemeral installation token. Never caches or logs
 * bearer credentials. Caller must bind requested installation/repo IDs to a
 * separately authenticated maintainer's consent record.
 */
export async function mintRepositoryInstallationToken(
  credentials: GitHubAppCredentials,
  installationId: number,
  repositoryId: number,
  request: typeof fetch = fetch,
  now = new Date(),
): Promise<ScopedInstallationToken> {
  if (!positiveInteger(installationId) || !positiveInteger(repositoryId)) {
    throw new GitHubAppAuthError(
      "UNAUTHORIZED",
      "Invalid installation or repository ID",
    );
  }
  const jwt = issueGitHubAppJwt(credentials, Math.floor(now.getTime() / 1000));
  let response: Response;
  try {
    response = await request(
      `${GITHUB}/app/installations/${installationId}/access_tokens`,
      {
        method: "POST",
        redirect: "error",
        cache: "no-store",
        headers: {
          Authorization: `***          Accept: "application/vnd.github+json",
          "X-GitHub-Api-Version": VERSION,
          "content-type": "application/json",
        },
        body: JSON.stringify({
          repository_ids: [repositoryId],
          permissions: {
            contents: "read",
            pull_requests: "read",
            metadata: "read",
          },
        }),
      },
    );
  } catch {
    throw new GitHubAppAuthError(
      "UPSTREAM_UNAVAILABLE",
      "GitHub token endpoint unavailable",
    );
  }
  if (response.status === 401)
    throw new GitHubAppAuthError(
      "UNAUTHORIZED",
      "GitHub App credentials rejected",
    );
  if (
    response.status === 403 ||
    response.status === 404 ||
    response.status === 422
  ) {
    throw new GitHubAppAuthError(
      "FORBIDDEN",
      "Installation or repository permissions unavailable",
    );
  }
  if (!response.ok)
    throw new GitHubAppAuthError(
      "UPSTREAM_UNAVAILABLE",
      "GitHub token endpoint failed",
    );
  let reply: TokenReply;
  try {
    reply = (await response.json()) as TokenReply;
  } catch {
    throw new GitHubAppAuthError(
      "UPSTREAM_UNAVAILABLE",
      "Invalid GitHub token response",
    );
  }
  if (
    typeof reply.token !== "string" ||
    reply.token.length < 16 ||
    typeof reply.expires_at !== "string" ||
    !Number.isFinite(Date.parse(reply.expires_at)) ||
    Date.parse(reply.expires_at) - now.getTime() < 60_000
  ) {
    throw new GitHubAppAuthError(
      "UNAUTHORIZED",
      "GitHub token missing or too near expiry",
    );
  }
  if (
    !Array.isArray(reply.repositories) ||
    reply.repositories.length !== 1 ||
    !reply.repositories.some(
      (repo) =>
        typeof repo === "object" &&
        repo !== null &&
        "id" in repo &&
        repo.id === repositoryId,
    )
  ) {
    throw new GitHubAppAuthError(
      "FORBIDDEN",
      "GitHub did not attest exact repository scope",
    );
  }
  const p = reply.permissions;
  if (
    typeof p !== "object" ||
    p === null ||
    !("contents" in p) ||
    !("pull_requests" in p) ||
    p.contents !== "read" ||
    p.pull_requests !== "read"
  ) {
    throw new GitHubAppAuthError(
      "FORBIDDEN",
      "GitHub did not grant required read permissions",
    );
  }
  return {
    token: reply.token,
    expiresAt: reply.expires_at,
    installationId,
    repositoryId,
    permissions: {
      installationId,
      accessibleRepositoryIds: [repositoryId],
      granted: { contents: "read", pull_requests: "read" },
    },
  };
}
