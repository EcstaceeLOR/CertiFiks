import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { realpath, stat } from "node:fs/promises";
import { isAbsolute, parse, relative, sep } from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const MAX_OUTPUT_BYTES = 256 * 1024;
const MAX_ARTIFACT_BYTES = 64 * 1024 * 1024;
const MAX_TIMEOUT_MS = 10 * 60 * 1000;

export interface VerifierRunRequest {
  workspace: string;
  image: string; // Must be pinned as repository@sha256:<digest>.
  command: string[]; // Executable + arguments; shell evaluation is never used.
  timeoutMs?: number;
}

export interface VerifierRunResult {
  status: "passed" | "failed" | "timed_out" | "runner_error";
  exitCode: number | null;
  stdout: string;
  stderr: string;
  durationMs: number;
  evidenceSha256: string;
}

function boundedText(value: string): string {
  const bytes = Buffer.from(value, "utf8");
  if (bytes.length <= MAX_OUTPUT_BYTES) return value;
  return `${bytes.subarray(0, MAX_OUTPUT_BYTES).toString("utf8")}\n[output truncated]`;
}

/**
 * Only a dedicated, operator-configured checkout volume may enter a Docker
 * bind mount. A caller-controlled workspace must never mount /, home,
 * credentials, another job's checkout, or a path reached via a symlink.
 */
export async function resolveTrustedCheckoutWorkspace(
  workspace: string,
  configuredRoot: string | undefined,
): Promise<string> {
  if (!configuredRoot || !isAbsolute(configuredRoot)) {
    throw new Error("SANDBOX_CHECKOUT_ROOT_UNCONFIGURED");
  }
  let root: string;
  let resolved: string;
  try {
    root = await realpath(configuredRoot);
    resolved = await realpath(workspace);
  } catch {
    throw new Error("SANDBOX_CHECKOUT_UNAVAILABLE");
  }
  if (root === parse(root).root || !isAbsolute(resolved) || resolved === root) {
    throw new Error("SANDBOX_WORKSPACE_OUTSIDE_TRUSTED_ROOT");
  }
  const relativePath = relative(root, resolved);
  if (
    relativePath === "" ||
    relativePath === ".." ||
    relativePath.startsWith(`..${sep}`) ||
    isAbsolute(relativePath)
  ) {
    throw new Error("SANDBOX_WORKSPACE_OUTSIDE_TRUSTED_ROOT");
  }
  try {
    const [rootInfo, workspaceInfo] = await Promise.all([
      stat(root),
      stat(resolved),
    ]);
    if (!rootInfo.isDirectory() || !workspaceInfo.isDirectory()) {
      throw new Error("invalid directory");
    }
  } catch {
    throw new Error("SANDBOX_CHECKOUT_UNAVAILABLE");
  }
  return resolved;
}

/** Docker invocation errors and likely OOM/signal exits are not valid
 * acceptance-test failures. They cannot satisfy baseline failure evidence.
 */
export function classifyContainerExitCode(
  code: number,
): "failed" | "runner_error" {
  return Number.isSafeInteger(code) &&
    code > 0 &&
    ![124, 125, 126, 127, 137, 143].includes(code)
    ? "failed"
    : "runner_error";
}

function validateImage(image: string): void {
  if (!/^[a-z0-9][a-z0-9./:_-]*@sha256:[a-f0-9]{64}$/i.test(image)) {
    throw new Error("SANDBOX_IMAGE_MUST_BE_DIGEST_PINNED");
  }
}

function validateCommand(command: string[]): void {
  if (!Array.isArray(command) || command.length < 1 || command.length > 64) {
    throw new Error("SANDBOX_COMMAND_INVALID");
  }
  if (
    command.some(
      (part) =>
        typeof part !== "string" || part.length > 4096 || part.includes("\0"),
    )
  ) {
    throw new Error("SANDBOX_ARGUMENT_INVALID");
  }
  // No shell, eval, or implicit command parsing. Test images should expose a fixed entrypoint.
  const executable = command[0]
    .replace(/\\/g, "/")
    .split("/")
    .at(-1)
    ?.toLowerCase();
  if (
    [
      "sh",
      "bash",
      "zsh",
      "dash",
      "ash",
      "ksh",
      "cmd",
      "cmd.exe",
      "powershell",
      "pwsh",
      "pwsh.exe",
    ].includes(executable ?? "")
  ) {
    throw new Error("SANDBOX_SHELL_ENTRYPOINT_FORBIDDEN");
  }
}

export async function runUntrustedCode(
  request: VerifierRunRequest,
): Promise<VerifierRunResult> {
  validateImage(request.image);
  validateCommand(request.command);
  const timeoutMs = request.timeoutMs ?? 120_000;
  if (
    !Number.isSafeInteger(timeoutMs) ||
    timeoutMs < 1_000 ||
    timeoutMs > MAX_TIMEOUT_MS
  ) {
    throw new Error("SANDBOX_TIMEOUT_OUT_OF_RANGE");
  }

  const workspace = await resolveTrustedCheckoutWorkspace(
    request.workspace,
    process.env.CERTIFIKS_TRUSTED_CHECKOUT_ROOT,
  );

  // Never pass host environment variables through. No Docker socket, credentials, network, or writable host mount.
  const args = [
    "run",
    "--rm",
    "--pull=never",
    "--network=none",
    "--read-only",
    "--cap-drop=ALL",
    "--security-opt=no-new-privileges:true",
    "--pids-limit=64",
    "--ulimit=core=0:0",
    "--ulimit=nproc=64:64",
    "--log-driver=none",
    "--ipc=none",
    "--memory=512m",
    "--memory-swap=512m",
    "--cpus=1",
    "--ulimit=nofile=256:256",
    "--ulimit=fsize=67108864:67108864",
    "--user=65532:65532",
    "--hostname=certifiks-sandbox",
    "--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=64m",
    "--mount",
    `type=bind,src=${workspace},dst=/workspace,readonly`,
    "--workdir=/workspace",
    "--env=HOME=/tmp",
    "--env=LANG=C.UTF-8",
    request.image,
    ...request.command,
  ];

  const start = Date.now();
  let status: VerifierRunResult["status"] = "runner_error";
  let exitCode: number | null = null;
  let stdout = "";
  let stderr = "";

  try {
    const result = await execFileAsync("docker", args, {
      timeout: timeoutMs,
      maxBuffer: MAX_OUTPUT_BYTES * 2,
      windowsHide: true,
      env: { PATH: process.env.PATH ?? "/usr/bin:/bin" },
    });
    status = "passed";
    exitCode = 0;
    stdout = result.stdout;
    stderr = result.stderr;
  } catch (error) {
    const e = error as NodeJS.ErrnoException & {
      code?: number | string;
      stdout?: string;
      stderr?: string;
      killed?: boolean;
      signal?: string;
    };
    stdout = e.stdout ?? "";
    stderr = e.stderr ?? "";
    if (e.killed || e.code === "ETIMEDOUT" || e.signal === "SIGTERM") {
      status = "timed_out";
    } else if (typeof e.code === "number") {
      status = classifyContainerExitCode(e.code);
      exitCode = e.code;
    } else {
      status = "runner_error";
    }
  }

  const durationMs = Date.now() - start;
  const safeStdout = boundedText(stdout);
  const safeStderr = boundedText(stderr);
  const evidenceSha256 = createHash("sha256")
    .update(
      JSON.stringify({
        image: request.image,
        command: request.command,
        status,
        exitCode,
        stdout: safeStdout,
        stderr: safeStderr,
        durationMs,
      }),
    )
    .digest("hex");

  return {
    status,
    exitCode,
    stdout: safeStdout,
    stderr: safeStderr,
    durationMs,
    evidenceSha256,
  };
}

export const verifierAvailable = true as const;
export const verifierLimits = Object.freeze({
  maxTimeoutMs: MAX_TIMEOUT_MS,
  maxOutputBytes: MAX_OUTPUT_BYTES,
  maxArtifactBytes: MAX_ARTIFACT_BYTES,
  network: "disabled",
  workspace: "read-only",
});
