# Future work

Use the FutureTasks capability only for a durable check-in that should appear in
Commander later. Keep ordinary project work in OpenCode.

- State the intended check-in, relevant repository references, local date/time, and
  IANA timezone.
- Include an explicit UTC offset in the local timestamp, especially around a DST
  fold. Do not schedule a nonexistent local time.
- Wait for the returned task ID before saying the commitment is scheduled.
- Use that task ID and its current version to update or cancel an unstarted task.
- A due task only asks Commander what to do; it does not start code, merge, or deploy
  work. Record a visible disposition or reschedule it on the same task ID.

The capability is unavailable when Kirei or the operator-issued capability exchange
is unavailable. Do not create a local fallback scheduler.
