import { serve } from "@std/http/server";

const handler = (req: Request): Response => {
  const url = new URL(req.url);

  if (url.pathname === "/") {
    return new Response("Hello from Deno! 🦕", {
      headers: { "content-type": "text/plain" },
    });
  }

  if (url.pathname === "/api/status") {
    return new Response(JSON.stringify({
      status: "ok",
      runtime: "Deno",
      version: Deno.version.deno
    }), {
      headers: { "content-type": "application/json" },
    });
  }

  return new Response("Not Found", { status: 404 });
};

console.log("HTTP server running on http://localhost:8000/");
await serve(handler, { port: 8000 });
