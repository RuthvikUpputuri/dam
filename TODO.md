# DAM Planning

DAM should make common operations on application stacks easier, not become a second Docker CLI. Keep DAM's interface focused and familiar; use native Docker commands for global maintenance and specialized Docker features.

## Active TODO

- [x] **Compose project identity support**
  *Added: 2026-10-01*
  Make app discovery and app-scoped commands resolve the effective Compose project name, including the Compose `name:` field and `COMPOSE_PROJECT_NAME`, rather than assuming it always matches the app directory. Do not add arbitrary app aliases as part of this work.

- [ ] **Application diagnostics**
  *Added: 2026-10-01*
  Replace the `debug` placeholder with a read-only, app-scoped report covering Compose configuration validation, container state and health, recent logs, and actionable failure hints. Keep it focused; do not make it a general report of every Docker resource.

## Deferred Ideas

These are not commitments or active work. Revisit them when there is a demonstrated user need.

- **Dependency Graph / Shared Resources:** During bulk operations (like `recreate all`), sequentially tearing down a stack might fail or disrupt other apps if it shares networks or volumes without `external: true` set. Consider implementing execution order dependencies (e.g., via a `.dam-dependencies` file) to ensure database stacks start before web stacks, mitigating resource conflicts.

- **Compose profiles:** Consider support for profiles in app operations. Prefer forwarding familiar Compose options where practical over inventing a DAM-specific command model.
- **Health-aware update verification:** After an update, optionally wait for services with declared health checks and fail with a clear report if they become unhealthy. Define which services are checked and a strict timeout; do not automatically roll back.
- **Structured output:** If users need to script DAM, consider stable JSON for `list`, `status`, and diagnostics. `get` already provides scriptable output. A `--no-color` option is a smaller usability improvement.
- **Remote Docker hosts:** Document that Docker contexts and `DOCKER_HOST` are honored by the Docker CLI, and that app files must exist on the machine running DAM. No separate remote-management layer is needed.
- **Update hooks:** Consider pre/post-update hooks for backups or migrations only if this need is demonstrated. If added, define ordering, fail-fast behavior, confirmation, and the permissions under which scripts run.
- **Docker Swarm:** Keep `docker stack` support as a possible long-term direction only; its lifecycle model differs substantially from Compose.

- **Doctor preflight:** Consider a read-only check for DAM configuration and app discovery, plus Docker Compose and daemon availability. It must be able to report those failures rather than being blocked by the normal Docker readiness check.
- **Dry-run / execution plan:** Consider previewing resolved apps and Compose commands for app-scoped operations such as update, recreate, and delete. Do not build a preview for global cleanup.

## Out of Scope

Use Docker's own CLI for global or specialized Docker operations. DAM should not grow wrappers for advanced cleanup/prune flags, global network or volume management, registry login/push, standalone image builds, or advanced Buildx options. Keep Kubernetes support out of scope unless DAM's purpose changes.
