# Credentials adapter
Owns session and Commander request token files on the shared runtime volume.
Public API: `FileStore#write(name:, token:)`, `#read(name:)`, `#delete(name:)`, `#path(name:)`.
