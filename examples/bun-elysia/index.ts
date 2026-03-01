import { Elysia } from "elysia";

const app = new Elysia()
  .get("/", () => "Hello from Bun! 🥟")
  .get("/api/status", () => ({
    status: "ok",
    runtime: "Bun",
    version: Bun.version
  }))
  .post("/api/echo", ({ body }) => body)
  .listen(3000);

console.log(
  `🦊 Elysia is running at ${app.server?.hostname}:${app.server?.port}`
);
