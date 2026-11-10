export default {
  async fetch(request, env, ctx) {
    return new Response(JSON.stringify({
      status: "ok",
      runtime: "workerd-android-bionic",
      timestamp: Date.now()
    }), {
      headers: { "content-type": "application/json" }
    });
  }
};
