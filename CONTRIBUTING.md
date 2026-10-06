# Contributing to DAM

Thank you for considering a contribution to Docker App Manager (DAM). I maintain DAM as a Bash utility for managing Docker Compose application stacks by app name and across multiple directories. Contributions should improve that focused workflow without turning DAM into a second Docker CLI.

## Ways to Contribute

- Report reproducible bugs or documentation errors.
- Suggest a focused improvement that addresses a real app-lifecycle need.
- Submit code, tests, or documentation changes.
- Review proposed changes and help clarify edge cases.

I review contributions and decide what fits the project's scope and direction. For security vulnerabilities, do not open a public issue; follow [SECURITY.md](SECURITY.md) instead.

## Before Starting

1. Check existing issues and pull requests for related work.
2. For substantial behavior changes, open an issue or discussion first so I can discuss the use case and scope before implementation.
3. Keep changes focused on DAM's Compose app-management purpose. Prefer using or passing through native Compose behavior over inventing a parallel interface.
4. Avoid adding wrappers for global or specialized Docker operations unless the project explicitly adopts that scope.

## Reporting a Bug

Open an issue in the project repository and include:

- What you expected and what happened.
- Exact commands and relevant, sanitized output.
- DAM version or commit, operating system, Bash version, Docker version, and Compose version.
- A minimal, reproducible example where practical.
- Whether the issue occurs with a local daemon, Docker context, or `DOCKER_HOST`.

Remove credentials, tokens, private registry names, hostnames, IP addresses, personal paths, and application data before posting. Never include secrets or report a vulnerability publicly.

## Proposing a Feature

Describe the user problem before proposing an implementation. Explain:

- Which app-management workflow is affected and who benefits.
- Why existing DAM or native Docker/Compose behavior is insufficient.
- The smallest useful behavior and any compatibility or safety implications.
- How users will discover and use it, including documentation changes.

Features should keep commands predictable and app-scoped where possible. Features that expand DAM into global Docker resource management or a different orchestrator need explicit discussion before implementation.

## Development Setup

DAM is a self-contained Bash script. Clone the repository and work from the project directory:

```bash
git clone https://gh.upputuri.in/dam.git
cd dam
```

The script requires Bash 4.4 or later for normal operation. Docker and Docker Compose are needed for end-to-end checks against real stacks. Static syntax validation does not require a running daemon.

Create a focused branch from the repository's current default branch. Keep commits and pull requests limited to one coherent change.

## Implementation Guidelines

- Follow the existing Bash structure, naming, output style, and command behavior.
- Quote expansions, use arrays for command arguments, and avoid `eval` or constructing executable shell strings.
- Preserve meaningful exit statuses and report errors instead of silently treating failures as success.
- Be especially careful with destructive operations and global-vs-project scope. Do not broaden cleanup side effects unintentionally.
- Do not run normal lifecycle commands as root unless required; DAM commands that modify system installation/configuration are a separate privileged workflow.
- Treat Compose files, sourced configuration, and optional `update*.sh` scripts as executable or trusted input. Do not weaken the existing safeguards around them.
- Avoid unrelated formatting or refactoring in the same change.
- Keep comments focused on non-obvious behavior.

## Validation

There is no automated test suite currently maintained in this repository. Do not claim a test suite passed unless one has actually been added and run.

For changes to `dam.sh`, run the available checks:

```bash
bash -n dam.sh
shellcheck dam.sh
```

ShellCheck is an optional external tool; if it is unavailable, report that rather than implying it ran. For behavior changes, also exercise the affected command using a disposable Compose project and a non-production Docker environment when available. Verify both success and failure paths, including confirmation behavior for destructive operations. Never test cleanup, deletion, or self-update against valuable data or a production host.

For documentation-only changes, check links, command examples, filenames, and statements against the current implementation. If a check cannot be run, state that clearly in the pull request.

## Documentation

Update documentation whenever user-visible behavior, options, safety properties, installation, configuration, or limitations change:

- Use [README.md](README.md) for the project overview and common workflows.
- Use the relevant page under [docs/](docs/) for detailed command behavior.
- Keep [TODO.md](TODO.md) and [SECURITY.md](SECURITY.md) consistent when planning scope or security reporting changes.
- Do not describe planned or deferred behavior as implemented.

## Code Review Standards

All changes (including those from the core maintainer) must be reviewed before merging into the default branch. The code review process evaluates the following criteria:

1. **Security & Safety:** Does the change introduce injection vulnerabilities, unsafe shell operations (`eval`), or unintended destructive side effects?
2. **Scope:** Does the change fit within DAM's goal as a focused Docker Compose lifecycle manager?
3. **Validation:** Does the code pass `bash -n` and `shellcheck` without warnings? Have manual tests been performed for destructive operations?
4. **Documentation:** Are user-facing changes documented in `README.md` and the `docs/` folder?

To be accepted, a pull request must pass all CI checks (Shellcheck), address any requested review feedback, and maintain the existing coding style.

## Pull Requests

Before submitting:

1. Confirm the change addresses the agreed scope and contains no unrelated edits.
2. Run the applicable validation above and list the exact checks and results.
3. Update relevant documentation and include examples for user-visible changes.
4. Review the diff for accidental secrets, generated files, temporary files, and unsafe shell changes.
5. Open a pull request against the current default branch with a descriptive title.

Include in the pull request description:

- The problem and the change made.
- Important behavior or compatibility changes.
- Tests/checks run and their results.
- Any checks not run and why.
- Known limitations or follow-up work.

Please keep issues, reviews, and discussions respectful and constructive. I may ask for changes, defer a proposal, or close it if it does not fit the project's scope.
