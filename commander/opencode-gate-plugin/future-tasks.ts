import { createHmac, randomUUID } from "node:crypto"
import { readFile } from "node:fs/promises"
import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const optionName = "digitaltwinFutureTasksEndpoint"
const secretFileOptionName = "digitaltwinFutureTasksCapabilitySecretFile"
const actorOptionName = "digitaltwinFutureTasksActor"
const endpointEnvironment = "DIGITALTWIN_FUTURE_TASKS_ENDPOINT"
const secretFileEnvironment = "DIGITALTWIN_FUTURE_TASKS_CAPABILITY_SECRET_FILE"
const actorEnvironment = "DIGITALTWIN_FUTURE_TASKS_ACTOR"
const capabilityLifetimeSeconds = 60

type Settings = Readonly<{
  endpoint: string
  secretFile: string
  actor: string
}>

function configured(options: Readonly<Record<string, unknown>>): Settings {
  const raw = options[optionName] ?? process.env[endpointEnvironment]
  if (typeof raw !== "string") throw new Error(`${optionName} must be configured by the operator`)
  const endpoint = new URL(raw)
  if (endpoint.pathname !== "/v1/future-tasks" || endpoint.search || endpoint.hash || (endpoint.protocol !== "https:" && endpoint.hostname !== "127.0.0.1" && endpoint.hostname !== "localhost")) {
    throw new Error(`${optionName} must be an HTTPS or loopback /v1/future-tasks origin`)
  }
  const secretFile = options[secretFileOptionName] ?? process.env[secretFileEnvironment]
  if (typeof secretFile !== "string" || !secretFile.startsWith("/"))
    throw new Error(`${secretFileOptionName} must be an absolute operator-owned file path`)
  const actor = options[actorOptionName] ?? process.env[actorEnvironment]
  if (typeof actor !== "string" || !actor.trim()) throw new Error(`${actorOptionName} must be configured by the operator`)
  return { endpoint: endpoint.toString().replace(/\/$/, ""), secretFile, actor }
}

async function issueCapability(settings: Settings, sessionID: string): Promise<string> {
  const secret = (await readFile(settings.secretFile, "utf8")).trim()
  if (!secret) throw new Error("Future-task capability secret file is empty")
  const issuedAt = Math.floor(Date.now() / 1000)
  const encoded = Buffer.from(JSON.stringify({
    aud: "future_tasks",
    actor: settings.actor,
    conversation: `opencode:${sessionID}`,
    owner: false,
    iat: issuedAt,
    exp: issuedAt + capabilityLifetimeSeconds,
    jti: randomUUID(),
  }), "utf8").toString("hex")
  return `${encoded}.${createHmac("sha256", secret).update(encoded, "utf8").digest("hex")}`
}

/** Native OpenCode v2.0.27 global custom-tool registration. */
export default Plugin.define({
  id: "digitaltwin-future-tasks",
  async setup(context) {
    const settings = configured(context.options)
    await context.tool.transform((editor) => editor.add({
      name: "future_tasks",
      description: "Create, list, read, update, or cancel a one-time Commander check-in.",
      input: Schema.Struct({
        operation: Schema.Literal("create", "list", "read", "update", "cancel", "disposition", "resolve_uncertain"),
        idempotency_key: Schema.optional(Schema.String), id: Schema.optional(Schema.String), expected_version: Schema.optional(Schema.Number),
        text: Schema.optional(Schema.String), due_at: Schema.optional(Schema.String), timezone: Schema.optional(Schema.String), local_time: Schema.optional(Schema.String),
        references: Schema.optional(Schema.Array(Schema.String)), cursor: Schema.optional(Schema.String), limit: Schema.optional(Schema.Number),
        disposition_key: Schema.optional(Schema.String), resolution_key: Schema.optional(Schema.String), outcome: Schema.optional(Schema.String), reason: Schema.optional(Schema.String),
      }),
      options: { codemode: false },
      async execute(input, tool) {
        const task = `${settings.endpoint}/${encodeURIComponent(input.id ?? "")}`
        const target = input.operation === "create" || input.operation === "list"
          ? settings.endpoint
          : input.operation === "disposition"
            ? `${task}/dispositions`
            : input.operation === "resolve_uncertain"
              ? `${task}/resolution`
              : task
        const method = input.operation === "create" || input.operation === "disposition" || input.operation === "resolve_uncertain" ? "POST" : input.operation === "list" || input.operation === "read" ? "GET" : input.operation === "cancel" ? "DELETE" : "PATCH"
        const query = new URLSearchParams()
        if (input.operation === "list" && input.cursor) query.set("cursor", input.cursor)
        if (input.operation === "list" && input.limit !== undefined) query.set("limit", String(input.limit))
        const url = query.size === 0 ? target : `${target}?${query}`
        const body = method === "GET" ? undefined : JSON.stringify(input)
        const capability = await issueCapability(settings, tool.sessionID)
        const response = await fetch(url, { method, headers: { authorization: `Bearer ${capability}`, ...(body === undefined ? {} : { "content-type": "application/json" }) }, body })
        return { content: JSON.stringify(await response.json()) }
      },
    }))
  },
})
