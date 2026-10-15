import Fastify from "fastify";
export function buildApp() {
  const app = Fastify({ logger: false });
  app.get("/health", async () => ({
    status: "ok",
    service: "certifiks-api",
    productReady: false,
    note: "HTTP transport is running; bounty APIs are not implemented",
  }));
  return app;
}
