import assert from "node:assert/strict"
import { mkdtemp, readFile, rm } from "node:fs/promises"
import { tmpdir } from "node:os"
import { join } from "node:path"
import test from "node:test"
import { commanderConversationId, emptyConversation } from "./contract.ts"
import { FileConversationStore } from "./file-store.ts"

test("durably restores records without persisting a capability presentation", async () => {
  const directory = await mkdtemp(join(tmpdir(), "digitaltwin-commander-bridge-"))
  const path = join(directory, "conversation.json")
  const conversation = commanderConversationId("commander:global")

  try {
    const writer = new FileConversationStore(path)
    const first = await writer.save({ conversation: emptyConversation(conversation) })
    assert.equal(first.ok, true)

    const restarted = new FileConversationStore(path)
    assert.equal((await restarted.load(conversation))?.id, conversation)
    const serialized = await readFile(path, "utf8")
    assert.equal(serialized.includes("token"), false)
    assert.equal(serialized.includes("nonce"), false)
  } finally {
    await rm(directory, { recursive: true, force: true })
  }
})
