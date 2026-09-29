# Phase 1: Voice Conversation with the Controller

Voice is another interface to the **same controller service and tools**, so a spoken answer uses the same status registry, permissions, and task references as `#master`.

For a real inbound or outbound telephone call, use a voice-capable Twilio number and Programmable Voice. Twilio Conversation Relay can transcribe caller speech, send text to the controller over a WebSocket, and speak its text responses. Support “call the controller” and a user-requested “call me with an update.” The voice gateway owns call setup, interruption, timeouts, and authentication; Gemini handles the question and calls the same typed status tools. Expose only the authenticated voice ingress publicly; keep Herdr and project routers private. Verify the call integration and caller identity (for example, an allowlisted number plus a PIN for sensitive details). Do not treat caller ID alone as authorization for project actions. [Outbound calls](https://www.twilio.com/docs/voice/tutorials/how-to-make-outbound-phone-calls) · [Conversation Relay](https://www.twilio.com/docs/voice/twiml/connect/conversationrelay)

A browser/app call using WebRTC could avoid a telephone number but requires a voice UI and signaling path. Telegram's Bot API supports voice messages, useful for asynchronous spoken updates; its documented bot interface does not provide the live bot phone call required here. Keep voice transport behind an adapter so that PSTN, an app call, or voice messages can reuse the controller. [Telegram Bot API](https://core.telegram.org/bots/api)

### Phase 1 acceptance test

From an authorized phone, ask “What's blocked, and what changed since yesterday?” The controller gives a concise spoken answer with project and task names, distinguishes stale data, supports a follow-up question and interruption, and sends the referenced task links to `#master` after the call. A user-requested outbound call provides the same behavior. A caller who fails authentication receives no project details.
