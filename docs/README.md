# DAM Documentation

**Docker App Manager** - Complete documentation for version 1.1.0.

---

## Quick Navigation

| Document | Description |
| :------- | :---------- |
| [Getting Started](getting-started.md) | Installation, prerequisites, first run, and configuration |
| [Command Reference](commands.md) | Index of all commands with exact underlying Docker commands |
| [Application Discovery](application-discovery.md) | How DAM finds and resolves apps |
| [Architecture & Concepts](architecture.md) | Internal design and conceptual model |
| [Troubleshooting](troubleshooting.md) | Error messages, common issues, and diagnostics |
| [Limitations](limitations.md) | Known limitations, edge cases, and architectural constraints |
| [DAM vs Docker/Compose](docker-vs-dam.md) | Side-by-side comparison with native Docker commands |
| [Safety & Security](safety.md) | Destructive operations, confirmations and security review |

---

## By Use Case

### I'm new to DAM
1. Read [Getting Started](getting-started.md) to install, set up, and configure.
2. Read [Architecture & Concepts](architecture.md) to understand how DAM maps to Docker.
3. Read [Application Discovery](application-discovery.md) to understand how apps are found.
4. Read the [Command Reference](commands.md) for basic usage.

### I want to understand what DAM actually runs
1. Read [Command Reference](commands.md) - every command lists exact Docker commands
2. Read [DAM vs Docker/Compose](docker-vs-dam.md) for side-by-side comparison

### I'm scripting with DAM
1. Read the "Non-Interactive" section in [Getting Started](getting-started.md)
2. Use the [`get` command](get.md) for extracting data
3. Always pass `-y` for automation

### I'm worried about data loss
1. Read [Safety & Security](safety.md)
2. Pay special attention to the `cleanup` command documentation
3. Read the cleanup section in [Limitations](limitations.md)

### I want to contribute
1. Read [Architecture & Concepts](architecture.md) to understand the codebase
2. Read [Limitations](limitations.md) for areas that could be improved
3. See [CONTRIBUTING.md](../CONTRIBUTING.md) for contribution guidelines

---

## External References

- [DAM Repository](https://gh.upputuri.in/dam)
- [Docker Compose CLI Reference](https://docs.docker.com/reference/cli/docker/compose/)
- [Docker CLI Reference](https://docs.docker.com/reference/cli/docker/)
