import { Plugin } from "@opencode/plugin"
import { Schema } from "effect"

const endpoint = "http://127.0.0.1:3000/v1/future-tasks"

/** Native OpenCode v2.0.27 global custom-tool registration. */
export default Plugin.define({
  id: "digitaltwin-future-tasks",
  async setup(context) {
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
        const url = method === "GET" && input.operation === "list" && input.cursor ? `${target}?cursor=${encodeURIComponent(input.cursor)}${input.limit === undefined ? "" : `&limit=${input.limit}`}` : target
        const body = method === "GET" ? undefined : JSON.stringify(input)
        const response = await fetch(url, { method, headers: { authorization: `Bearer ${input.capability}`, ...(body === undefined ? {} : { "content-type": "application/json" }) }, body })
        return { content: JSON.stringify(await response.json()) }
      },
    }))
  },
})
