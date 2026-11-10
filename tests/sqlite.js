import { DurableObject } from "cloudflare:workers";

export class Counter extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    ctx.storage.sql.exec(
      "CREATE TABLE IF NOT EXISTS counts (id INTEGER PRIMARY KEY, value INTEGER)"
    );
  }

  async fetch(req) {
    this.ctx.storage.sql.exec(
      "INSERT INTO counts (id, value) VALUES (1, 1) ON CONFLICT(id) DO UPDATE SET value = value + 1"
    );
    const cursor = this.ctx.storage.sql.exec("SELECT value FROM counts WHERE id = 1");
    const count = cursor.one().value;
    return new Response(JSON.stringify({ count }), {
      headers: { "content-type": "application/json" }
    });
  }
}

export default {
  async fetch(req, env) {
    const id = env.COUNTER.idFromName("global");
    const stub = env.COUNTER.get(id);
    return stub.fetch(req);
  }
};
