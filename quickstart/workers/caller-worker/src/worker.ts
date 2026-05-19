import { Worker, Trigger } from "iii-sdk";

const worker = new Worker({
  engineUrl: process.env.III_ENGINE_URL ?? "ws://localhost:49134",
});

// RPC bridge: called by other workers or direct function triggers
worker.registerFunction("inference::get_response", async (payload: any) => {
  const result = await worker.trigger({
    function_id: "inference::run_inference",
    payload,
  });
  return result;
});

// HTTP handler: receives POST /v1/chat/completions from the internet
worker.registerFunction("http::run_inference_over_http", async (payload: any) => {
  const body =
    typeof payload.body === "string" ? JSON.parse(payload.body) : payload.body;

  const result = await worker.trigger({
    function_id: "inference::run_inference",
    payload: { messages: body.messages },
  });

  return {
    status: 200,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
    body: JSON.stringify({
      id: `chatcmpl-${Date.now()}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model: "gemma-3-270m",
      choices: [
        {
          index: 0,
          message: {
            role: "assistant",
            content: typeof result === "string" ? result : result?.output ?? JSON.stringify(result),
          },
          finish_reason: "stop",
        },
      ],
    }),
  };
});

// Health check endpoint
worker.registerFunction("http::healthz", async () => ({
  status: 200,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ status: "ok", model: "gemma-3-270m" }),
}));

// Wire HTTP triggers
worker.registerTrigger(
  Trigger.http({
    method: "POST",
    path: "/v1/chat/completions",
    function_id: "http::run_inference_over_http",
  })
);

worker.registerTrigger(
  Trigger.http({
    method: "GET",
    path: "/healthz",
    function_id: "http::healthz",
  })
);

worker.start();
