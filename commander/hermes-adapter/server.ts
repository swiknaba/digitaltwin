import { mkdir, rename } from "node:fs/promises"
import { dirname } from "node:path"
import { CommanderHarness } from "./harness"
import { HermesGatewayClient } from "./client"
import type { CommanderHarnessState, CommanderHarnessStore } from "./contract"

class JsonStore implements CommanderHarnessStore {
  constructor(private readonly path: string) {}

  async read(): Promise<CommanderHarnessState> {
    const file = Bun.file(this.path)
    if (!(await file.exists())) return { revision: 0 }
    const value: unknown = await file.json()
    if (!value || typeof value !== "object" || typeof (value as Record<string, unknown>).revision !== "number") throw new Error("Commander Hermes state is invalid.")
    return value as CommanderHarnessState
  }

  async write(state: CommanderHarnessState) {
    await mkdir(dirname(this.path), { recursive: true })
    const temporary = `${this.path}.${process.pid}.next`
    await Bun.write(temporary, JSON.stringify(state))
    await rename(temporary, this.path)
  }
}

const port = numeric("DIGITALTWIN_HERMES_ADAPTER_PORT", 3087)
const endpoint = process.env.DIGITALTWIN_HERMES_API_URL
const token = process.env.DIGITALTWIN_HERMES_API_TOKEN
const statePath = required("DIGITALTWIN_HERMES_STATE_FILE")
const harness = endpoint && token ? new CommanderHarness(new HermesGatewayClient(new URL(endpoint), token), new JsonStore(statePath)) : undefined

Bun.serve({
  port,
  hostname: "127.0.0.1",
  async fetch(request) {
    const url = new URL(request.url)
    try {
      if (url.pathname === "/health") return Response.json({ ok: true, hermes: !!harness })
      if (!harness) return Response.json({ error: "Hermes adapter is not configured. Set project-local DIGITALTWIN_HERMES_API_URL and DIGITALTWIN_HERMES_API_TOKEN." }, { status: 503 })
      if (request.method === "GET" && url.pathname === "/state") return Response.json(await harness.state())
      if (request.method === "GET" && url.pathname === "/capabilities") return Response.json(await harness.capabilities())
      if (request.method === "GET" && url.pathname === "/models") return Response.json(await harness.models())
      if (request.method === "POST" && url.pathname === "/model") {
        const body = await json(request)
        if (typeof body.provider !== "string" || typeof body.model !== "string") return Response.json({ error: "provider and model are required." }, { status: 400 })
        return Response.json(await harness.selectModel({ provider: body.provider, model: body.model }))
      }
      if (request.method === "POST" && url.pathname === "/runs") {
        const body = await json(request)
        if (typeof body.text !== "string") return Response.json({ error: "text is required." }, { status: 400 })
        return Response.json(await harness.start(body.text, typeof body.request_id === "string" ? body.request_id : undefined))
      }
      const match = /^\/runs\/([^/]+)(?:\/(events|steer|stop))?$/.exec(url.pathname)
      if (!match) return new Response("Not found", { status: 404 })
      const runID = decodeURIComponent(match[1])
      if (request.method === "GET" && !match[2]) return Response.json(await harness.status(runID))
      if (request.method === "POST" && match[2] === "steer") {
        const body = await json(request)
        if (typeof body.text !== "string") return Response.json({ error: "text is required." }, { status: 400 })
        await harness.steer(runID, body.text)
        return new Response(null, { status: 204 })
      }
      if (request.method === "POST" && match[2] === "stop") {
        await harness.stop(runID)
        return new Response(null, { status: 204 })
      }
      if (request.method === "GET" && match[2] === "events") {
        const after = url.searchParams.get("after")
        const stream = new ReadableStream({
          async start(controller) {
            for await (const event of harness.events(runID, after === null ? undefined : Number(after))) controller.enqueue(`data: ${JSON.stringify(event)}\n\n`)
            controller.close()
          },
        })
        return new Response(stream, { headers: { "Content-Type": "text/event-stream", "Cache-Control": "no-cache" } })
      }
      return new Response("Method not allowed", { status: 405 })
    } catch (error) {
      return Response.json({ error: error instanceof Error ? error.message : "Commander Hermes adapter failed." }, { status: 502 })
    }
  },
})

function required(name: string) {
  const value = process.env[name]
  if (!value) throw new Error(`${name} is required.`)
  return value
}

function numeric(name: string, fallback: number) {
  const value = process.env[name]
  if (!value) return fallback
  if (!/^\d+$/.test(value)) throw new Error(`${name} must be numeric.`)
  return Number(value)
}

async function json(request: Request): Promise<Record<string, unknown>> {
  const value: unknown = await request.json()
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("JSON object required.")
  return value as Record<string, unknown>
}
