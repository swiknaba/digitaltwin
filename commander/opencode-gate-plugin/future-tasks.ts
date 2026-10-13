import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const optionName = "digitaltwinFutureTasksEndpoint"

function configuredEndpoint(options: Readonly<Record<string, unknown>>): string {
  const raw = options[optionName]
  if (typeof raw !== "string") throw new Error(`${optionName} must be configured by the operator`)
  const endpoint = new URL(raw)
  if (endpoint.pathname !== "/v1/future-tasks" || endpoint.search || endpoint.hash || (endpoint.protocol !== "https:" && endpoint.hostname !== "127.0.0.1" && endpoint.hostname !== "localhost")) {
    throw new Error(`${optionName} must be an HTTPS or loopback /v1/future-tasks origin`)
  }
  return endpoint.toString().replace(/\/$/, "")
}

/** Native OpenCode v2.0.27 global custom-tool registration. */
export default Plugin.define({
  id: "digitaltwin-future-tasks",
  async setup(context) {
    const endpoint = configuredEndpoint(context.options)
    await context.tool.transform((editor) => editor.add({
      name: "future_tasks",
      description: "Create, list, read, update, or cancel a one-time Commander check-in.",
      input: Schema.Struct({
        operation: Schema.Literal("create", "list", "read", "update", "cancel"), capability: Schema.String,
        idempotency_key: Schema.optional(Schema.String), id: Schema.optional(Schema.String), expected_version: Schema.optional(Schema.Number),
        text: Schema.optional(Schema.String), due_at: Schema.optional(Schema.String), timezone: Schema.optional(Schema.String), local_time: Schema.optional(Schema.String),
        references: Schema.optional(Schema.Array(Schema.String)), cursor: Schema.optional(Schema.String), limit: Schema.optional(Schema.Number),
      }),
      options: { codemode: false },
      async execute(input) {
        const target = input.operation === "create" || input.operation === "list" ? endpoint : `${endpoint}/${encodeURIComponent(input.id ?? "")}`
        const method = input.operation === "create" ? "POST" : input.operation === "list" || input.operation === "read" ? "GET" : input.operation === "cancel" ? "DELETE" : "PATCH"
        const query = new URLSearchParams()
        if (input.operation === "list" && input.cursor) query.set("cursor", input.cursor)
        if (input.operation === "list" && input.limit !== undefined) query.set("limit", String(input.limit))
        const url = query.size === 0 ? target : `${target}?${query}`
        const body = method === "GET" ? undefined : JSON.stringify(input)
        const response = await fetch(url, { method, headers: { authorization: `Bearer ${input.capability}`, ...(body === undefined ? {} : { "content-type": "application/json" }) }, body })
        return { content: JSON.stringify(await response.json()) }
      },
    }))
  },
})
