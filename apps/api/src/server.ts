import { buildApp } from "./app.js";

const app = buildApp();
const port = Number(process.env.PORT || "3001");
if (!Number.isSafeInteger(port) || port < 1 || port > 65535)
  throw new Error("Invalid PORT");
try {
  await app.listen({ host: "127.0.0.1", port });
} catch (error) {
  app.log.error(error);
  process.exitCode = 1;
}
