# Digitaltwin Phase 0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine containerisierte, selbst gehostete Agent-Flotte liefert über Campfire revisionstreu freigegebene Code- und Rechercheergebnisse.

**Architecture:** Kirei bildet einen modularen Ruby-Monolithen mit getrennten Web- und Worker-Prozessen. PostgreSQL hält Workflowzustand und Jobs; Herdr steuert vier CLIs in einem gemeinsamen Non-root-Runtime-Container. Campfire und Git sind die einzigen Schnittstellen zu unabhängigen Deployments.

**Tech Stack:** Ruby, Kirei, Sorbet, Rack/Puma, Sequel, PostgreSQL, Docker Compose, Herdr, Wagglebot, Codex CLI, Claude Code, OpenCode, Gemini CLI.

**Spec:** [`../../agent-fleet-architecture-and-review.md`](../../agent-fleet-architecture-and-review.md), Arbeitsbaumrevision vom 2026-10-01, Commit ausstehend, Status `Draft for owner review`.

**Spec SHA-256:** `1f8d3c609cc9d35c721195fa81fba9ea0adecf006725807f1c6067e17ab717f8`.

**Planstatus:** Reviewbarer Entwurf, kein Implementierungsauftrag. Der Plan wurde zunächst auf `main` erstellt. Der Owner hat anschließend Branch, Commit, Push und Draft-PR für diese Planungsänderungen ausdrücklich beauftragt. Implementation und Deployment bleiben außerhalb des Auftrags. Vor Umsetzung benötigen Spec und Plan die Freigabe ihrer exakten Commits; Draftstatus ist keine Freigabe.

## Global Constraints

Die folgenden Werte und Grenzen stammen aus der Spec; alle Tasks müssen sie einhalten.

- Ziel: `Ubuntu 24.04 LTS on AMD64`; kein vorgeschriebener Mindestspeicher oder Flotten-Concurrency-Limit.
- Zwei Anwendungsimages: Kirei und Runtime. Produktion wählt OCI-Digests; Repository liefert nur Entwicklungs-/Integrations-Compose.
- Exakte Werkzeug- und Paketversionen in Manifesten; Wagglebot: `Node.js 22.20 or later, npm, and Git`.
- Runtime: `No Docker socket`, `No privileged mode`, `No host root mount`, Non-root, erforderliche Volumes und Netzwerke.
- Default-Workspace: `/workspace/repos`; Slug `owner/repository`; ein Workflow pro verifiziertem Campfire-Thread. Mehrere Threads eines Rooms können gleichzeitig arbeiten.
- Bots: `@agent` und `@worker`, konfigurierbar. Writer und Reviewer teilen die Worker-Botidentität.
- Writer/Reviewer benötigen unterschiedliche zugrunde liegende Provider **und** Basismodellfamilien; Default Codex/Claude Code.
- Jeder Projektworkflow benötigt Spec, Plan, Reviews und menschliche Freigaben der exakten Revisionen.
- Drei erfolglose Reviewrunden pro Gate blockieren; Reviewer ändert nur die gemeinsame Review-Markdown-Datei.
- Ein Workflowbranch, eine finale PR; kein automatischer Merge und keine automatische Post-merge-Synchronisierung.
- Raum-Mitglieder dürfen gewöhnliche Arbeit anfordern; konfigurierte lokale/Peer-Bots dürfen niemals menschlich freigeben oder bestätigen.
- Master: Gemini CLI über Herdr und lokale MCP-Bridge; kein direkter Gemini-API-Aufruf, kein Providerlogin über Campfire.
- Memory nur manuell über `@agent`/Basisanweisungen; kein Cron, keine verpflichtende Pflege nach jeder Session.
- GitHub bleibt gewählter Git-Host. Headscale/Tailscale bleiben gewählte private Zugriffsbasis.
- Ein gemeinsamer Runtime-Vertrauensbereich; keine behauptete Prozess- oder Projektisolierung gegen bösartige Agenten.
- Infrastruktur verantwortet öffentliche Route/TLS, Produktionsorchestrierung, tägliche verschlüsselte S3-Backups und 30-Tage-Bucket-Lifecycle.
- Backupalarm nach zwei aufeinanderfolgenden Fehlern; Loginzustand, Repositories und unpushed Arbeit sind ausgeschlossen.

## Review Focus

1. Doppelte oder verspätete Zustellungen dürfen keinen zweiten Start, keine zweite Freigabe und keine zweite Antwort erzeugen (Tasks 3, 4, 7).
2. Room-Rename, Slug-Traversal und Symlink-Escape dürfen keine fremden Workspaces erreichen (Task 5).
3. Revisionwechsel, konkurrierende Approvals und Bot-Sender dürfen keine veraltete Freigabe wiederverwenden (Tasks 7, 8).
4. Workercrash zwischen externem Effekt und DB-Abschluss sowie Herdr `unknown` dürfen keine Fertigmeldung vortäuschen (Tasks 3, 6, 11).
5. Writeränderungen während Review und manipulierte Callbacks dürfen den Review-Snapshot nicht verschieben (Task 8).

## Verifizierte Ausgangslage und lokale Anweisungen

- Checkout `/Users/lr/Sites/swiknaba/digitaltwin`, Remote `https://github.com/swiknaba/digitaltwin.git`, Branch `main`.
- Ausgangscheckout war sauber auf `e6fd46c`; lesendes Remote-Checking fand die neuere Spec. Fast-forward auf `6129059` erfolgte ohne Konflikte.
- Repository enthält bisher README und zwei Architekturtexte; keine Anwendung, Tests, Dockerfiles oder bestehende Taskqueue.
- Keine `AGENTS.md` in Repo oder den geprüften Eltern `/`, `/Users`, `/Users/lr`, `/Users/lr/Sites`, `/Users/lr/Sites/swiknaba`.
- Kein `.agents/skills` und keine `.agents/memory.md` im Digitaltwin-Checkout.
- Persönliche Regeln: `/Users/lr/.codex/AGENTS.md` und identische `/Users/lr/.agents/AGENTS.md` gelesen. Relevant: Delegation für Exploration, Quellenprüfung, knappe technische Prosa und `.agents/changelog.md` nach dauerhaften Änderungen.
- Persönliche Skills unter `/Users/lr/.agents/skills`: brainstorming, dispatching-parallel-agents, executing-plans, finishing-a-development-branch, i-have-adhd, receiving-code-review, requesting-code-review, subagent-driven-development, systematic-debugging, test-driven-development, using-git-worktrees, using-superpowers, verification-before-completion, writing-plans, writing-skills.
- Verwendet: `writing-plans` für Struktur, Interfaces, Tests und Selbstprüfung; `verification-before-completion` für Auslieferungsevidenz. `using-superpowers` und dessen Codex-Referenz sowie `dispatching-parallel-agents` wurden gelesen. Eine unabhängige Baseline-Untersuchung wurde gemäß persönlichen Delegationsregeln delegiert; Architektur und Plan bleiben hier.
- Keine neue Brainstorming-Runde: aktuelle Spec ist die angeforderte Grundlage. Keine Worktree-/Implementierungs-Skills ausgeführt: Plan auf `main`, Umsetzung außerhalb des Auftrags.
- Katalog-Skills sowie persönliche `.codex/skills/.system` vorhanden: imagegen, openai-docs, skill-creator, skill-installer; zusätzlich review-agent lokal gefunden. Diese lösen die Planungsaufgabe nicht und wurden nicht angewendet.
- `CODEX_HOME` war in der Shell nicht gesetzt. `~/.codex` wurde lokal bestätigt. Nur `memories/memory_summary.md` gelesen; keine Digitaltwin-Projektsektion vorhanden. Keine Memory-Datei geändert.
- Kirei-Referenz: `/Users/lr/Sites/swiknaba/kirei` bei `0f0a3e21a0e9c337f4c94499ddc0972c08dbe18c`; dessen `AGENTS.md` gelesen. Ruby/Sorbet/Rack/Sequel, Referenz `spec/test_app`, Ruby-Pin `4.0.2`.
- Wagglebot-Referenz: `/Users/lr/Sites/swiknaba/wagglebot` bei `d11c200202121563e34b92e28be92de1ed497ce0`, CLI-Paket `0.3.0`, Node `>=22.20.0`, `.nvmrc` v24.
- Aktuelle Shell: Node 22.16.0/Ruby 2.6.10; geeignete Node-24- und Ruby-4.0.2-Installationen existieren. Herdr ist im geprüften PATH nicht verfügbar. Es wurden keine App- oder Runtime-Tests ausgeführt.

## Planentscheidungen und früh zu schließende Voraussetzungen

Diese Entscheidungen ergänzen die Spec und benötigen Planreview; sie sind keine neuen Spec-Fakten.

- Domains liegen unter `app/domains/`, nach Kireis aktueller Test-App. Kein blindes Scaffold im bestehenden Checkout: der Generator schreibt ins Arbeitsverzeichnis und erzeugt keine vollständige Gemfile-/Testbasis.
- Ein Ruby-Codebestand erzeugt Web, Worker, `bin/digitaltwin`-Callback und stdio-MCP-Bridge. Die Runtime enthält das für die beiden kleinen Clients notwendige Paket.
- PostgreSQL-Sequel-Transaktionen koordinieren Gates, Sessiongenerationen, Jobs, Inbox und Outbox. Netzaufrufe laufen außerhalb kurzer DB-Locks.
- Reviews liegen in `docs/superpowers/reviews/<workflow-uuid>.md`; UUID bleibt intern, normale Chatnachrichten verwenden Projekt/Phase und Links.
- Neue Workflowbranches heißen `digitaltwin/<workflow-uuid>`; die manuelle Planerstellung auf main ist eine ausdrücklich angeforderte Ausnahme.
- Approval bindet den exakten bereitgemeldeten Artefaktcommit plus Blob-ID. Reviewcommits erhalten einen eigenen Ref und ersetzen den Targetcommit nicht. Jede neue Artefaktbereitmeldung benötigt erneute Review-/Humanfreigabe; Blobprüfungen erkennen stille Änderungen.
- Nachrichten während Review werden gespeichert, aber nicht an den Writer gesendet. Nach Review werden sie nach Revisions-/Phasenprüfung zugestellt.
- Start-Ersetzungsbestätigung und irreversible Masteroperationen verwenden einmalige, zeitlich begrenzte Bestätigungen, gebunden an Sender, Raum, Aktion und Parameterhash.
- Jobstandard: 30-Sekunden-Lease, Heartbeat alle 10 Sekunden, höchstens fünf Versuche, Backoff 1/5/15/60 Sekunden. Task 3 prüft die Folgen bei langsamen Aufrufen.
- Stale-Status nach 60 Sekunden ohne erfolgreiche Herdr-Abfrage; unsichere Zustände bleiben ausdrücklich unsicher.
- Externe Calls ohne Idempotenznachweis werden nach unbekanntem Ergebnis nicht blind wiederholt. Reconciliation oder menschliche Entscheidung schließen den Zustand.
- Versionen von Kirei, Herdr, CLIs, Campfire und PostgreSQL werden in Task 1 genau ausgewählt und eingetragen. Keine erfundenen Releases oder ungeprüften Socketmethoden.

## Dateikarte und gemeinsame Verträge

Alle folgenden Anwendungspfade sind **neu geplant**, sofern nicht als bestehend bezeichnet.

| Pfad | Verantwortung |
| --- | --- |
| `Gemfile`, `Gemfile.lock`, `.ruby-version`, `app.rb`, `config.ru`, `Rakefile`, `sorbet/` | Kirei-Bootstrap und reproduzierbare Ruby-Prüfungen |
| `config/runtime-tools.lock.yml`, `config/deployment.example.yml` | Exakte Pins, nicht geheime Konfiguration, Bot-/Modellidentitäten |
| `db/migrate/001_control_plane.rb` | Projekte, Workflows, Approvals, Reviews, Sessions, Jobs, Inbox, Outbox, Audit, Confirmations |
| `app/domains/{jobs,campfire,projects,workflows,reviews,runtime,forge,controller}/` | Pro Domain typisierte Entities, Services, dünne Controller und Adapter |
| `bin/{web,worker,digitaltwin,mcp}` | Prozess-Einstiege und kontrollierte Bedienung |
| `docker/{app,runtime}.Dockerfile`, `compose.yml`, `.dockerignore`, `.env.example` | Zwei OCI-Images und lokale Integration |
| `spec/{domains,integration,contracts}/`, `spec/fixtures/` | Unit-, PostgreSQL-, Adapter- und End-to-end-Evidenz |
| `docs/{interfaces,operations,acceptance}/` | Verträge, Bedienung, Validierungsergebnisse, Infra-Handoff |
| `AGENTS.md`, `.agents/changelog.md`, `CHANGELOG.md` | Workflowregeln und Zusammenfassungen, keine zweite Taskqueue |
| `README.md` (bestehend) | Entwicklungsbefehle und Links |

Gemeinsame Typen in `app/domains/workflows/entities.rb`:

- `Actor(user_id: String, room_id: String, member: Boolean, bot: Boolean)`; aus verifiziertem Campfire-Kontext, niemals frei vom Modell gesetzt.
- `RoleConfig(cli: String, provider: String, model: String, family: String)`; Writer/Reviewer-Paar prüft beide Unterschiede.
- `ArtifactRef(kind: spec|plan|implementation|review, commit: String, path: String, blob: String)`.
- `SessionRef(workflow_id: String, generation: Integer, role: writer|reviewer|controller, pane_id: String, alias: String)`.
- `Outcome(status: accepted|blocked|rejected|confirmation_required, reason: String, links: Array[String])`.
- Workflowzustände: `spec_writing → spec_review → spec_human_approval → plan_writing → plan_review → plan_human_approval → implementation → implementation_review → pr_ready → done → closed`; zusätzlich `blocked`, `paused`, `cancelled` mit gespeichertem vorherigem Zustand.
- `done` bedeutet verifizierte Lieferung einer offenen PR/Recherche, keinen Merge. `closed` folgt nur auf das explizite thread-spezifische `@worker finish` und archiviert die Herdr-Sessionmetadaten. Revisionen und Genehmigungen bleiben im Audit nachvollziehbar.

## Task 1: Interfacevalidierung und Versionsmanifest

**Files:** Create `config/runtime-tools.lock.yml`, `docs/interfaces/{herdr,campfire,cli-startup}.md`, `spec/contracts/{herdr,campfire}_spec.rb`, `spec/fixtures/contracts/`.

**Interfaces:** Produces dokumentierte, releasegebundene Herdr-Operationen für Start, Prompt, Status, Stop/Archive sowie Campfire-Authentisierung, Mitgliedschaft, Webhook-ID, Post-ID und Thread- oder Root-Post-ID.

- [ ] Prüfe die ausgewählten Releases anhand offizieller Dokumentation und installierter Artefakte. Trage exakte Versionen, Herkunft und Digests/Checksums ein.
- [ ] Schreibe Contracttests `starts_four_clis`, `writer_settles_after_ready`, `unknown_is_not_idle`, `gemini_calls_local_mcp`, `campfire_verifies_delivery_and_sender`.
- [ ] Starte alle vier CLIs mit Testzugängen über Herdr. Erfasse ready→idle/done, Crash, Timeout und Gemini-Screen-State, ohne echte Projektänderungen.
- [ ] Prüfe Gemini-MCP-Roundtrip mit `list_projects` und Source-Room-Kontext. Prüfe Rehydration in einer frischen Gemini-Session.
- [ ] Speichere bereinigte Request-/Response-Fixtures und reproduzierbare Befehle. Erwarte pro CLI Start-, Prompt-, Status- und Stopnachweis.
- [ ] Führe nach Task 2 `bundle exec rspec spec/contracts` aus; erwarte PASS gegen die validierten Fixtures. Task 1 liefert vorher protokollierte Livechecks.
- [ ] Blockiere Tasks 6–10, falls API, Idle-Handschlag, Webhookauthentisierung, verifizierte Threadidentität oder Gemini-MCP fehlen. Dokumentiere eine konkrete Alternative zur Freigabe statt Socketmethoden zu erfinden.
- [ ] Nach Review committen: `docs: validate pinned runtime and chat contracts`.

## Task 2: Kirei-Grundlage und lokale Images

**Files:** Create Bootstrap-Dateien der Dateikarte, `docker/app.Dockerfile`, `compose.yml`, `.env.example`, `.gitignore`, `spec/integration/boot_spec.rb`.

**Interfaces:** Produces `GET /livez`, `GET /readyz`, `bin/web`, `bin/worker`, `bundle exec rake db:migrate`; Readiness erfordert migrierte PostgreSQL-Verbindung.

- [ ] Schreibe `boot_spec`: `/livez` antwortet 200; `/readyz` antwortet 503 ohne DB und 200 nach Migration.
- [ ] Führe `bundle exec rspec spec/integration/boot_spec.rb` aus; erwarte zunächst fehlende Boot-/Health-Implementierung.
- [ ] Erstelle Ruby-4.0.2-Bootstrap nach Kirei-Test-App und releasegebundenem Gemfile/Lockfile. Pinne Basisimage und Bundler, setze Sorbet auf.
- [ ] Definiere Compose-Services `web`, `worker`, `postgres`, später `runtime`; kein Produktionsrouting und keine echten Secrets.
- [ ] Prüfe `docker compose config --quiet`, `docker compose build web worker`, den Boot-Test sowie `bundle exec spoom srb tc`.
- [ ] Nach Review committen: `build: bootstrap Kirei control plane and local compose`.

## Task 3: Dauerhafte Jobs, Inbox und Outbox

**Files:** Create Migration, `app/domains/jobs/{entities,worker,store}.rb`, `app/domains/campfire/outbox.rb`, `spec/domains/jobs_spec.rb`.

**Interfaces:** `Jobs.enqueue(kind: String, payload: Hash, key: String) -> String`; `Jobs.claim(worker_id: String, now: Time) -> Job?`; `complete(id:, lease_token:)`; `retry(id:, lease_token:, error:)`. `Outbox.enqueue(room_id:, body:, key:) -> String`.

- [ ] Schreibe PostgreSQL-Tests: zwei Worker claimen nie denselben Job; Unique-Key liefert einen Job; abgelaufene Lease ist wiederholbar; alter Lease-Token darf nicht abschließen.
- [ ] Ergänze `effect_succeeded_before_crash` und `unknown_post_result`: kein doppeltes Side Effect bei Recovery, unbekannte Antwort bleibt zur Reconciliation offen.
- [ ] Führe `bundle exec rspec spec/domains/jobs_spec.rb` aus; erwarte fehlendes Schema/Store.
- [ ] Implementiere kurze `FOR UPDATE SKIP LOCKED`-Claims, Lease/Heartbeat, gebundene Retrywerte und atomare Zustandsänderung plus Outbox. Lange Agentarbeit bleibt außerhalb DB-Transaktionen.
- [ ] Prüfe echte PostgreSQL-Konkurrenz, Retrybudget und tote Worker. Erwartung: fünf Fehlversuche führen zu sichtbarem Blocker, nicht Endlosschleife.
- [ ] Nach Review committen: `feat: add durable leased jobs and delivery outbox`.

## Task 4: Campfire-Routing und verifizierte Sender

**Files:** Create `app/domains/campfire/{controller,client,router,actor_resolver}.rb`, `spec/domains/campfire_spec.rb`.

**Interfaces:** `Router.ingest(delivery: VerifiedDelivery) -> Outcome`; `ActorResolver.resolve(room_id:, user_id:) -> Actor`; `VerifiedDelivery` enthält die verifizierte Room-, Post- und Thread- oder Root-Post-Identität. Clientmethoden richten sich exakt nach Task 1.

- [ ] Schreibe Tests für ungültige Webhooks, eigene Bots, Peer-Bots, Room-Mitgliedschaft, Replay und Mehrfachzustellung.
- [ ] Prüfe `agent_any_room_preserves_source`, `worker_unactivated_thread_does_not_start`, `worker_thread_routes_without_repeat_mention` und `worker_thread_cannot_route_to_another_workflow`; normale Nachrichten zeigen keine internen Workflow-IDs.
- [ ] Führe `bundle exec rspec spec/domains/campfire_spec.rb` aus; erwarte fehlenden Router.
- [ ] Implementiere `@agent` zum Master und thread-spezifisches `@worker start`/`approve`/`finish`/`cancel`/gewöhnliche Nachricht zur aktiven Projektphase. Aktiviere nur die Thread-Wurzel mit `@worker start`; route spätere menschliche Threadnachrichten ohne Wiederholungsmention. Speichere Inbox vor Dispatch.
- [ ] Prüfe, dass Sender-/Botklassifikation aus Campfire kommt; gefälschte JSON-/Modellfelder können keine menschliche Autorität verleihen.
- [ ] Nach Review committen: `feat: route authenticated Campfire mentions`.

## Task 5: Enrollment und Git-Workspace

**Files:** Create `app/domains/projects/{enroll,repository_identity,workspace}.rb`, `app/domains/forge/client.rb`, `spec/domains/projects_spec.rb`, `bin/digitaltwin`-Enrollment.

**Interfaces:** `Projects.enroll(actor: Actor, room_id: String, slug: String, choice: clone|create_private|stop) -> Outcome`; `Workspace.resolve(slug: String) -> String`; `Forge.clone(slug:, destination:)`, `create_private(slug:)`, `read_revision(repo:, commit:)`.

- [ ] Schreibe `valid_slug_maps_path`, `rejects_traversal_and_symlink_escape`, `remote_mismatch_blocks`, `rename_keeps_room_mapping`.
- [ ] Ergänze fehlendes Repo mit genau clone/create-private/stop; private Erstellung nur nach gewählter Aktion, nie implizit.
- [ ] Führe `bundle exec rspec spec/domains/projects_spec.rb` aus; erwarte fehlende Enrollment-Services.
- [ ] Implementiere validierte `owner/repository`-Segmente, realpath-basierte Containmentprüfung und Remoteidentität für HTTPS/SSH. Nutze argv statt zusammengesetzter Shellstrings.
- [ ] Verbinde Chat, MCP und Shell mit demselben Service. Initialisiere Wagglebot nach Task 6, bevor ein Projektworkflow startet.
- [ ] Prüfe mit Bare-Git-Fixtures, deren HEAD explizit auf main zeigt; Tests erstellen keine GitHub-Ressourcen.
- [ ] Nach Review committen: `feat: enroll rooms into verified Git workspaces`.

## Task 6: Non-root-Runtime, Herdr und Wagglebot

**Files:** Create `docker/runtime.Dockerfile`, `config/runtime-entrypoint.sh`, `app/domains/runtime/{herdr_client,sessions,reconcile}.rb`, `spec/{domains/runtime_spec.rb,integration/runtime_spec.rb}`.

**Interfaces:** `Sessions.start(workflow_id:, generation:, role:, config: RoleConfig, repo:) -> SessionRef`; `send_prompt(session:, text:, dispatch_key:)`; `state(session:) -> idle|done|working|unknown|missing`; `stop(session:)`.

- [ ] Schreibe Runtimeprüfungen: UID ≠ 0, alle vier CLIs vorhanden, keine verbotenen Mounts/Capabilities, Socket nur auf geteiltem Worker-Volume.
- [ ] Schreibe `unknown_never_completes`, `old_generation_cannot_receive_prompt`, `restart_reconciles_panes` anhand Task-1-Fixtures.
- [ ] Führe `bundle exec rspec spec/domains/runtime_spec.rb` aus; erwarte fehlende Sessionschnittstelle.
- [ ] Implementiere Adapter ausschließlich gegen Task-1-Vertrag. Persistiere Role→Pane/Alias, Sessiongeneration und getrennte Credentialbereiche im gemeinsamen Runtimehome.
- [ ] Baue Image mit den gepinnten Tools, OpenSSH und Wagglebot. Setup: `connect <company-git-url>`, `update --wagglebot`, pro Repo `init` und `update`.
- [ ] Stelle Upgrades nur über expliziten Operatorbefehl bereit. Dokumentiere interaktives Providerlogin; teste Persistenz nach Containerneustart.
- [ ] Prüfe `docker compose build runtime` und `docker compose run --rm runtime bin/runtime-smoke`; dieser neue Befehl prüft Versionen/UID und Herdr-CLI-Start. Authentifizierte Anbieterchecks bleiben gesonderte Operatorchecks.
- [ ] Nach Review committen: `feat: add persistent Herdr runtime and provisioning`.

## Task 7: Deterministische Workflows und Approvals

**Files:** Create `app/domains/workflows/{entities,machine,approvals,start}.rb`, `spec/domains/workflows_spec.rb`, `AGENTS.md`.

**Interfaces:** `Workflows.start(actor:, project_id:, thread_id:, writer: RoleConfig, reviewer: RoleConfig, confirmation_id: String?) -> Outcome`; `finish(actor:, workflow_id:, expected_version:)`; `transition(workflow_id:, event:, expected_version:)`; `Approvals.approve(actor:, workflow_id:, kind:, target_commit:) -> Outcome`.

- [ ] Schreibe tabellengesteuerte Tests aller erlaubten/verbotenen Zustandsübergänge, Spec-/Planfreigaben und Reviewer-Voraussetzung.
- [ ] Ergänze `same_family_across_cli_rejected`, `same_provider_rejected`, `bot_approval_rejected`, `artifact_change_invalidates`, `concurrent_approval_advances_once`, `finish_only_delivered`, `unknown_blocks_finish` und `cancel_reconciles_before_archive`.
- [ ] Führe `bundle exec rspec spec/domains/workflows_spec.rb` aus; erwarte fehlende Zustandsmaschine.
- [ ] Implementiere Zustandsänderungen mit Workflowlock/Version und Audit. Kontextuelles approve bindet beim Eingang die präsentierte Revision, nicht später einen bewegten HEAD.
- [ ] Ein thread-spezifischer start erzeugt frische Writer-/Reviewersessions auf einem Branch. Ein zweiter Start im aktiven Thread wird abgewiesen; ein anderer Thread kann einen unabhängigen Workflow erzeugen.
- [ ] Halte pause/resume/cancel/finish orthogonal zu Freigaben. `finish` schließt nur einen gelieferten Workflow nach explizitem Befehl und stoppt/archiviert seine Sessions. Resume darf keine Gates überspringen; Idlechat beendet oder startet nichts automatisch.
- [ ] Verankere verpflichtende Spec-/Planregeln im AGENTS.md; technische Enforcement bleibt in Kirei.
- [ ] Nach Review committen: `feat: enforce revision-bound workflow gates`.

## Task 8: Artifact-ready und gegenseitig ausgeschlossene Reviews

**Files:** Create `app/domains/reviews/{coordinator,callback,verdict}.rb`, `bin/digitaltwin`-Callback, `spec/domains/reviews_spec.rb`.

**Interfaces:** `Reviews.ready(session: SessionRef, artifact: ArtifactRef) -> Outcome`; `begin(workflow_id:, target:)`; `finish(session:, review_commit:, verdict: approve|changes_requested) -> Outcome`. CLI: `digitaltwin artifact-ready --kind <kind> --commit <sha>` und `review-ready --commit <sha> --verdict <verdict>`.

- [ ] Schreibe `callback_wrong_session_rejected`, `dirty_writer_blocks`, `writer_working_or_unknown_blocks`, `queued_writer_prompt_not_dispatched`.
- [ ] Ergänze exakten Zielcommit, Reviewer-Diff nur Reviewdatei, append-only Abschnitte, echte Reviewidentitäten, dritter Fehlschlag blockiert.
- [ ] Führe `bundle exec rspec spec/domains/reviews_spec.rb` aus; erwarte fehlenden Koordinator.
- [ ] Stoppe neue Writerdispatches, sende Transitionprompt, verifiziere Callback/Artefakt/Commit/Cleanliness und settled Herdrstate. Persistiere Reviewlock vor Reviewerstart.
- [ ] Binde Callback an kurzlebiges Sessioncredential und Generation; kein Vertrauen in Modelltext oder reine Herdr-Lifecycle-Events.
- [ ] Vergleiche Reviewercommit mit eingefrorenem HEAD; andere Dateidiffs blockieren die Runde. Ein Abschnitt enthält Provider/Modell/Familie, Target, Findings, Verdict und Timestamp.
- [ ] Übergib verifizierten Reviewpfad/-commit an Writer; entsperre erst für Korrekturphase. Revalidiere pending Nachrichten und Gate-Revision.
- [ ] Prüfe, dass alle drei Gates dieselben Regeln verwenden und Bot-/Promptanweisungen den Lock nicht umgehen.
- [ ] Nach Review committen: `feat: coordinate immutable artifact review rounds`.

## Task 9: Master und lokale MCP-Bridge

**Files:** Create `app/domains/controller/{tools,confirmations,master}.rb`, `bin/mcp`, `spec/domains/controller_spec.rb`.

**Interfaces:** MCP-Tools `list_projects`, `list_workflows`, `get_workflow`, `enroll_project`, `start_workflow`, `send_prompt`, `pause_workflow`, `resume_workflow`, `finish_workflow`, `cancel_workflow`, `git_action`, `deployment_action`, `delete_resource`, `change_credentials`. Alle erhalten einen serverseitigen Actor-/Room-/Thread-Kontext.

- [ ] Schreibe `master_uses_gemini_cli`, `room_context_survives_tool_call`, `restart_creates_fresh_session`, `secret_values_never_returned`.
- [ ] Ergänze `bot_cannot_confirm`, `confirmation_replay_rejected`, `changed_parameters_require_confirmation`, `unconfigured_deployment_tool_rejected`.
- [ ] Führe `bundle exec rspec spec/domains/controller_spec.rb` aus; erwarte fehlenden Master/MCP-Server.
- [ ] Implementiere stdio-MCP-Bridge gegen dieselben Anwendungsservices, ohne rohe Shell- oder Credential-Read-Tools.
- [ ] Serialize Requests an eine logische Mastersession; übergib verifizierten Kontext per requestgebundener Capability, nicht über frei wählbare Modellparameter.
- [ ] Fordere zweite menschliche Bestätigung vor destruktiven/irreversiblen Operationen. Bestätigungsfenster beträgt zehn Minuten; Audit enthält Parameterhash, niemals Secretwerte.
- [ ] Prüfe echten Gemini-MCP-Roundtrip aus Task 1. Nach Neustart ist PostgreSQL-/Toolstatus Grundlage, nicht die alte Unterhaltung.
- [ ] Nach Review committen: `feat: add authorized Gemini master operations`.

## Task 10: Verifizierte Lieferung, Recherche, Memory und Peerhandoffs

**Files:** Create `app/domains/forge/{delivery,memory}.rb`, `app/domains/campfire/peer_handoff.rb`, `docs/operations/project-runbook.md`, `spec/domains/delivery_spec.rb`.

**Interfaces:** `Delivery.finalize(workflow_id:, commit:, evidence:) -> Outcome`; `Memory.change(actor:, slug:, path:, mode: additive|reorganization) -> Outcome`; `PeerHandoff.receive(actor:, recipient:, slug:, revision:, action:) -> Outcome`.

- [ ] Schreibe `one_branch_one_pr`, `research_requires_sources_and_uncertainty`, `no_automatic_merge_or_pull`, `failed_push_not_delivered`.
- [ ] Ergänze konfigurierbare Memoryslug, additive Defaultbranchänderung, Reorganisation nur Branch/PR; ohne Memorybedarf darf Workflow abschließen.
- [ ] Prüfe Peer mit eigener Gitidentität: verifiziert Remote/Revision, erreicht keine privaten Pfade/API und erzeugt keine Selbstbot-Schleife.
- [ ] Führe `bundle exec rspec spec/domains/delivery_spec.rb` aus; erwarte fehlende Lieferlogik.
- [ ] Implementiere finale PR erst nach Implementationreview. Liefere Commit, Prüfungsevidenz, Blocker und Links; eine offene PR gilt als Lieferergebnis.
- [ ] Dokumentiere Researchpfade `docs/research/<topic>.md` sowie Quellen, Zugriffstag und Unsicherheit; Spec-/Plangates bleiben auch für Research verbindlich.
- [ ] Definiere `CHANGELOG.md` als menschliche Resultatzusammenfassung und `.agents/changelog.md` als Agentänderungsprotokoll. Beide enthalten keine Schedulerzustände.
- [ ] Prüfe mit simuliertem Campfirepeer und lokalen Gitremotes; keine zweite Serverflotte nötig. Reale Push-/PR-/Memoryprüfungen nur nach separater Autorisierung.
- [ ] Nach Review committen: `feat: deliver reviewed artifacts and scoped peer handoffs`.

## Task 11: Recovery und Betriebsstatus

**Files:** Create `app/domains/runtime/recovery.rb`, `app/domains/controller/status.rb`, `spec/integration/recovery_spec.rb`.

**Interfaces:** `Recovery.run(now: Time) -> RecoveryReport`; `Status.snapshot(project_id:, now:) -> StatusSnapshot` mit Phase, Revision, Sessionstate, Aktivität, PR, Blocker, Evidence und Staleness.

- [ ] Schreibe Crashmatrix: vor/nach Sessionstart, Callback, Reviewlock, Approval, Gitpush und Campfirepost. Replays erhalten dieselbe fachliche Wirkung.
- [ ] Ergänze missing pane, unbekannter Providerstate, alter Alias und DB-Recovery mit fehlendem Workspace; niemals automatisch als done markieren.
- [ ] Führe `bundle exec rspec spec/integration/recovery_spec.rb` aus; erwarte fehlende Reconciliation.
- [ ] Implementiere Startreconciliation von DB, Git und Herdr; erzeuge frischen Master. Rekonstruiere Arbeit aus committed Artefakten und vorhandenem ignored Superpowers-Ledger.
- [ ] Kennzeichne Status ab 60 Sekunden ohne verifizierte Runtimeabfrage als stale. Surface blockierte Jobs und Phasen über deduplizierte Outbox.
- [ ] Prüfe Containerrestart mit benannten Volumes; zwei Threads eines Rooms und zwei unabhängige Räume arbeiten gleichzeitig. Beende nur einen gelieferten Thread mit explizitem `finish` und prüfe, dass seine Herdr-Sessions archiviert werden.
- [ ] Nach Review committen: `feat: reconcile runtime state after interruption`.

## Task 12: Portable Betriebsverträge und Infrastruktur-Handoff

**Files:** Create `docs/operations/{containers,private-access,backup-restore,secrets}.md`, `spec/integration/image_contract_spec.rb`; Modify `README.md`, `compose.yml`.

**Interfaces:** Vertragsdokumente listen pro Image ENV, Secretfile, UID/GID, Volumes, Ports, Healthcheck und Startkommando. Worker/Runtime benötigen dieselbe Host-/Task-Socketvolume.

- [ ] Schreibe `image_contract_spec`: Non-root, Healthcheck, persistente Pfade, keine Docker-/Rootmounts und öffentlich publizierte Runtime-SSH-Ports.
- [ ] Führe `bundle exec rspec spec/integration/image_contract_spec.rb` aus; erwarte fehlende vollständige Imageverträge.
- [ ] Dokumentiere PostgreSQL und vorhandenes/official Campfire als externe Dienste; local Compose kann Testabhängigkeiten starten. Keine Produktions-Compose im Apprepo.
- [ ] Beschreibe private Tailscale/OpenSSH-Anbindung, Headscale DNS-only über Traefik mit vertrauenswürdigem TLS; weder Cloudflare Proxy noch Tunnel für Headscale.
- [ ] Dokumentiere ignorierte `.env`, optionale `op://`-Referenzen und root/0600-Produktionsdateien im Infrarepo. Keine Secretwerte oder Loginzustände in Images/Git.
- [ ] Erstelle Backup-/Restorematrix: DB, Campfire/Anhänge, Herdr, Konfiguration/Audit und Headscale eingeschlossen; Repos/unpushed Arbeit/CLI-Logins ausgeschlossen.
- [ ] Übergib tägliche S3-Clientverschlüsselung, externen Schlüssel, 30-Tage-Lifecycle und zweiten Fehleralarm an Infra. Wiederanmeldung nach Restore ausdrücklich dokumentieren.
- [ ] Dokumentiere Image-by-Digest-Beispiel für Production-Compose und Hosted-Task inkl. gemeinsamem Socket. Portabilität nicht als getestetes ECS-Deployment ausgeben.
- [ ] Nach Review committen: `docs: define production image and recovery contracts`.

## Task 13: End-to-end-Abnahme und Releaseevidenz

**Files:** Create `spec/integration/phase0_spec.rb`, `bin/acceptance`, `docs/acceptance/phase0.md`; Modify `README.md`, `CHANGELOG.md`, `.agents/changelog.md`.

**Interfaces:** `bin/acceptance local` prüft lokale Flows mit simulierten Providern/Peer; `bin/acceptance operator` erzeugt eine manuell zu vervollständigende Live-Checkliste, startet kein Deployment.

- [ ] Schreibe lokalen Gesamtflow: zwei Räume, mobile Interviewantwort, Specreview/Freigabe, Planreview/Freigabe, Implementationreview und eine PRlieferung.
- [ ] Ergänze Researchflow, optionale gepushte Memoryänderung, Peerhandoff und Neustart zwischen Gates. Verbotene Approvals/Transitions müssen fehlschlagen.
- [ ] Führe `docker compose run --rm web bundle exec rspec spec/integration/phase0_spec.rb` aus; erwarte fehlende Gesamtintegration vor Implementierung.
- [ ] Vervollständige Gesamtintegration und führe `bundle exec rspec`, `bundle exec spoom srb tc`, `bundle exec rubocop`, `docker compose config --quiet` und Imagebuilds aus.
- [ ] Erfasse Output, Commit, Image-Digests und Testumgebung. Livechecks und simulierte Checks getrennt ausweisen.
- [ ] Nach separater Deploymentfreigabe prüft der Operator echte CLIs, Campfiremobilzugriff, Tailnetattachment, extern geschlossenen SSH-Port, alle Servicehealthchecks und verschlüsselten Restore.
- [ ] Prüfe jede untenstehende Abnahmezeile; fehlende Liveevidenz bleibt offen und darf keine Phase-0-Abnahme vortäuschen.
- [ ] Nach Review committen: `test: document Phase 0 acceptance evidence`.

## Abnahmematrix zur Spec §25

| Nr. | Zuständigkeit | Verlangte Evidenz |
| --- | --- | --- |
| 1 | 12/13 + Infra | veröffentlichte OCI-Digests starten in bestehender Infrastruktur; separate Freigabe |
| 2 | 2/13 | lokale Compose-Integration mit Exit 0 |
| 3 | 12 | gleiche ENV/Volume/Healthverträge, Compose- und Hosted-Task-Definition |
| 4 | 6/12/13 + Infra | Health von Campfire, DB, Web, Worker, Runtime, Headscale, Tailscale |
| 5–6 | 6/12 | Contracttest und inspizierter Container-UID-/Mount-/Capabilityzustand |
| 7 | 6/11 | Hostrestart, persistente Repos/Herdr/Wagglebot/Loginzustände |
| 8 | 1/6 | vier echte CLI-Starts durch gepinntes Herdr |
| 9–10 | 12/13 + Infra | Tailnetattachment erfolgreich; externer SSH-Verbindungstest abgelehnt |
| 11 | 4/9 | Masterrequest aus zwei Rooms trägt korrekten Source-Room |
| 12–13 | 6/7 | frische Role-Sessions; aktive Ersetzung benötigt Bestätigung |
| 14–16 | 5 | Pfad-/Remoteprüfungen, drei Setupaktionen, ein gemeinsamer Service |
| 17–19 | 7 | Revisions-/Bot-/Race-Negativtests |
| 20–24 | 8 | immutable Reviewziel, Handshake, Writerlock, Reviewübergabe, dritte Niederlage |
| 25–26 | 10 | ein Branch/PR, kein automatischer Merge |
| 27 | 9/11 | frische Gemini-Session mit dauerhaft rekonstruiertem Status |
| 28 | 10/13 | simulierter Peer und getrennte Gitidentität, ausschließlich Chat/Git |
| 29 | 12/13 + Infra | verschlüsselter Restore aller enthaltenen Dienste; Logins nicht wiederhergestellt |
| 30 | 13 + Operator | Interview von mobilem Campfireclient beendet |
| 31 | 10/13 | committed Research-Markdown mit Quellen und Unsicherheit |
| 32 | 10/13 + Operator | Memory-Commit und Push an konfigurierte Repoidentität verifiziert |

## Offene Entscheidungen und Freigabegates

1. **Ownerreview:** Spec ist weiter Draft. Exakte Spec- und spätere Plancommits müssen vor Umsetzung geprüft und freigegeben werden. Dieser Auftrag erlaubt Planung und deren Veröffentlichung als Draft-PR, keine Umsetzung.
2. **Herdrfähigkeit:** Task 1 entscheidet anhand Liveevidenz, ob vier CLIs und der Idle-Handschlag ausreichend zuverlässig sind. Ohne Nachweis keine Runtime-/Reviewimplementierung gegen Annahmen.
3. **Pins und Zugangsdaten:** Operator liefert Companyconfig-, Memoryslug-, Modellkonfiguration und Testzugänge. Geheimnisse bleiben außerhalb des Plans. Releasepins werden geprüft ausgewählt, nicht aus diesem Entwurf als bereits bewiesen übernommen.
4. **Campfirevertrag:** Webhookauthentisierung, Mitgliedschaftslookup und Post-Reconciliation müssen am eingesetzten Release bestätigt werden. Fehlende sichere Senderprüfung blockiert Humanapproval.
5. **Infrastruktur:** Produktion, Imagepublication, Headscale, Backupbucket und Restoretest sind eigene autorisierte Arbeit im Infrastrukturkontext. Hier werden nur Verträge geliefert.
6. **Reviewexklusion:** Kirei verhindert Promptdispatch, prüft Git und beobachtet Herdr. Der akzeptierte gemeinsame Runtimebereich schützt nicht vor absichtlichen direkten Terminal-/Filesystemeingriffen. Ein solcher Eingriff blockiert/invalidiert Review statt als genehmigte Arbeit zu gelten.

## Selbstprüfung dieses Plans

- Spec §§1–27 gegen Tasks und Abnahmematrix geprüft. Voice ist ausdrücklich Phase 1 und bleibt außerhalb.
- Frühere periodische Memory-/Mehrtask-/Auto-merge-Entscheidungen wurden nicht übernommen.
- Neue Datei- und Typnamen sowie Interfacebezüge konsistent geprüft; Herdrmethoden bleiben releasegebunden statt erfunden.
- Alle fünf Review-Focus-Klassen besitzen benannte Negativ-/Recoverytests.
- Jede Task besitzt eine überprüfbare Lieferung; Task 1 ist ein Evidenzgate, kein versteckter Implementierungsauftrag.
- Testbefehle beziehen sich auf **zukünftig zu erstellende** Dateien/Binaries. Sie wurden im Planungsauftrag nicht ausgeführt.
- Planerstellung ändert nur Plan, README-Link und Agentchangelog; vorhandene Spec und Implementierungsdateien bleiben erhalten.
