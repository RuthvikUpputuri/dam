You are documenting an existing project. Your job is to produce a **professional, highly accurate, source-code-driven README and full documentation for the repository you are currently working in**.

The most important rule is:

> **DO NOT ASSUME ANYTHING. DO NOT INVENT ANYTHING. DO NOT HARD-CODE INFORMATION FROM THIS PROMPT.**

The repository itself is the source of truth.

You must first thoroughly inspect and understand the entire project, especially the main script and every supporting file, and only then write the documentation.

NEVER use em-dashes in the documentation. Always try to use natural language instead of em-dashes if possible and if not, use regular dashes.

---

# 1. FIRST: FULLY AUDIT THE REPOSITORY

Before writing any documentation, inspect the repository comprehensively.

Do not only read the README, description, comments, or obvious entrypoint.

Inspect:

* all source files
* shell scripts
* configuration files
* environment/configuration examples
* installation/setup scripts
* helper scripts
* Docker/Compose-related files
* package/build metadata
* CI/CD workflows
* tests
* examples
* templates
* license
* gitignore
* version information
* command/help output
* any generated or vendored files that affect behavior
* documentation that already exists
* git history when useful for understanding behavior or intended design

Determine:

1. What the project actually does.
2. What problem it solves.
3. What its architecture is.
4. How the main executable works internally.
5. How command-line arguments are parsed.
6. How application/project discovery works.
7. How directories are searched.
8. How Compose files are detected.
9. How a discovered application is mapped to its Compose project.
10. What happens when multiple matches exist.
11. What happens when nothing is found.
12. How errors are handled.
13. What environment variables/configuration options exist.
14. What defaults exist.
15. What safety checks exist.
16. What confirmations exist.
17. What destructive operations exist.
18. What external programs are required.
19. What Docker/Docker Compose versions or features are implicitly required.
20. What edge cases and limitations exist.

Trace the actual execution flow through functions. Do not document a command merely because a function name suggests it does something. Follow the implementation.

If behavior differs depending on arguments, state, configuration, whether the app is running, whether files exist, etc., document each relevant branch.

---

# 2. DO A COMMAND-BY-COMMAND REVERSE ENGINEERING

Create a complete internal inventory of every user-facing command, subcommand, alias, option, flag, special keyword, and shortcut exposed by the project.

For EACH user-facing command, determine all of the following from the source code:

* command syntax
* required arguments
* optional arguments
* accepted keywords
* aliases
* default behavior
* application-selection behavior
* directory discovery behavior
* exact internal functions called
* exact underlying system commands executed
* exact Docker commands executed
* exact Docker Compose commands executed
* exact flags passed
* command execution order
* working directory at execution time
* environment/configuration that affects execution
* pre-checks
* post-checks
* status checks
* confirmation prompts
* cleanup behavior
* error handling
* behavior when the target app is missing
* behavior when multiple apps are selected
* behavior for special selectors such as all/exclusions, if implemented
* whether the operation affects one container, one Compose service, one Compose project, multiple Compose projects, images, volumes, networks, builds, etc.

Do not simplify this into vague statements such as:

> "This command restarts the app."

Instead explain what the implementation actually does.

For example, if a command internally resolves an application directory and then executes a particular Compose command with particular flags, document that exact sequence.

Where a command invokes another helper script or custom update script, document that behavior and the decision logic for when it is used.

---

# 3. EXPLICITLY DOCUMENT THE EXACT COMMANDS EXECUTED BEHIND DAM COMMANDS

This is one of the most important parts of the documentation.

Create a command execution reference that shows, for every custom DAM command:

DAM command
→ application/project resolution
→ directory selection
→ prerequisite checks
→ exact underlying command(s)
→ flags/options
→ post-processing

Do not merely state "uses Docker Compose."

Show the actual command semantics.

For example, the documentation should be able to answer questions like:

* Does this command execute `docker compose start`, `docker compose up`, or something else?
* Does it use `--force-recreate`?
* Does it use `--remove-orphans`?
* Does it pull images first?
* Does it build images?
* Does it preserve the previous running/stopped state?
* Does it run multiple Docker commands?
* Does it run non-Docker shell commands before/after them?
* Does behavior change for `all` versus a named application?
* Does behavior differ when the application is already running?
* Does it invoke an application-specific script?
* Does it operate on the Compose project or individual containers?

If the implementation uses shell commands such as `find`, `pushd`, `popd`, `awk`, `sed`, `grep`, `xargs`, `git`, `docker`, `docker compose`, etc., identify their purpose where relevant.

Do not invent commands that are not actually present in the source.

---

# 4. COMPARE DAM AGAINST ACTUAL DOCKER / DOCKER COMPOSE BEHAVIOR

Perform a factual comparison against the current official Docker and Docker Compose documentation.

Use official Docker documentation as the primary source whenever possible.

Do not rely on memory for Docker behavior when it matters.

Research the actual current behavior of relevant Docker/Docker Compose commands and concepts.

For every DAM command that overlaps with Docker or Docker Compose, explain:

1. What the native Docker/Docker Compose command does.
2. What DAM does.
3. Whether they are actually equivalent.
4. If not equivalent, exactly how they differ.
5. The scope difference:

   * container
   * service
   * Compose project
   * multiple Compose projects
   * host-wide Docker resources
6. Whether DAM primarily adds:

   * application discovery
   * directory resolution
   * multi-project selection
   * batching
   * safety checks
   * orchestration
   * custom update behavior
   * different flags
   * different lifecycle semantics
7. Whether the native Docker command requires a container name, service name, Compose project directory, or Compose file.
8. Whether DAM removes the need for the user to know those implementation details.

Pay particular attention to cases where commands have similar names but different semantics.

Do NOT make the common mistake of treating:

`docker <command>`

and

`docker compose <command>`

as interchangeable.

Also do NOT assume that a container name is the same thing as a Compose application name.

Explain the distinction clearly wherever relevant.

---

# 5. BUILD A DETAILED COMPARISON TABLE

Create a table covering the entire user-facing command set.

Suggested columns:

| DAM Command | Native Docker Equivalent | Native Compose Equivalent | Actually Equivalent? | What DAM Adds | Scope | Exact Backend Operation |

Populate the table entirely from the source and verified Docker documentation.

Do not force an equivalent if none exists.

Use "None" / "No direct equivalent" where appropriate.

If two commands appear similar but have different behavior, explicitly explain the difference.

---

# 6. DOCUMENT THE CORE CONCEPTUAL MODEL

Explain the mental model users should have.

The documentation should clearly distinguish concepts such as:

* Docker daemon
* Docker container
* Docker image
* Docker volume
* Docker network
* Docker Compose service
* Docker Compose project/application
* Compose file
* application directory
* DAM application discovery
* container name vs service name vs project name
* host filesystem path vs Docker-managed resource

Explain how DAM maps a human-facing application name to the actual Compose project.

Make this understandable to a beginner without sacrificing technical accuracy.

---

# 7. DOCUMENT APPLICATION DISCOVERY IN DETAIL

Reverse-engineer exactly how DAM finds applications.

Document:

* search roots
* default search locations
* configuration methods
* supported Compose filenames
* recursive/non-recursive behavior
* directory naming assumptions
* duplicate names
* collision behavior
* ignored directories
* failure behavior
* special cases
* precedence rules
* how the final Compose project is selected

Do not hard-code the explanation from this prompt.

Derive every detail from the implementation.

If the implementation has limitations, document them honestly.

---

# 8. DOCUMENT CONFIGURATION

Create a complete configuration reference.

For every configurable variable, option, path, setting, or environment variable found in the repository, document:

* name
* purpose
* default
* accepted values
* format
* where it is configured
* precedence
* whether it can be overridden
* examples using values discovered from the repository
* behavior when invalid or missing

Do not invent variables.

Only document things that actually exist.

---

# 9. INSTALLATION AND SETUP

Write clear installation instructions based on the repository's actual installation mechanism.

Determine whether the project supports things such as:

* direct script installation
* cloning
* copying the script
* symlinking
* PATH installation
* package managers
* shell profile configuration
* dependencies
* Docker installation assumptions

Document the actual supported process.

Do not invent an installation workflow just because it would be conventional.

Also document how to verify installation.

---

# 10. USAGE GUIDE

Create a beginner-friendly usage section that explains:

* first run
* discovering applications
* inspecting available applications
* operating on a single application
* operating on multiple applications
* operating on all applications
* excluding applications, if supported
* update workflows
* recreate workflows
* destructive operations
* cleanup operations
* status/reporting commands

All examples must come from the actual supported syntax.

Do not invent commands.

---

# 11. USE REAL EXAMPLES FROM THE REPOSITORY

Where examples are useful, derive names, paths, options, and syntax from the actual repository.

Do NOT invent application names, directory names, flags, environment variables, or output.

If no safe concrete example exists in the source, use clearly marked generic placeholders such as:

`<app-name>`

rather than pretending an example is real.

---

# 12. DOCUMENT DESTRUCTIVE COMMANDS AND SAFETY

Identify every command that can:

* stop workloads
* remove containers
* remove images
* remove volumes
* remove networks
* delete files
* alter application state
* rebuild/recreate containers
* cause downtime
* prune Docker resources

For each one, explain exactly what it does and what it does NOT delete.

Pay particular attention to commands involving:

* `down`
* `rm`
* `prune`
* volumes
* images
* networks
* build cache
* application-specific delete behavior

Document confirmation prompts and safeguards exactly as implemented.

Do not exaggerate safety guarantees.

---

# 13. DOCUMENT UPDATE / UPGRADE SEMANTICS IN DETAIL

If the project has an update command, reverse-engineer it carefully.

Document:

* whether images are pulled
* whether builds occur
* whether builds force fresh base images
* whether containers are recreated
* whether stopped applications remain stopped
* whether running applications remain running
* whether custom update scripts are supported
* when custom update scripts are selected
* what happens if a custom update script fails
* what happens if pull/build/up fails
* whether orphan containers are removed
* status output after update

This section must reflect the actual implementation rather than a generic Docker update workflow.

---

# 14. DOCUMENT ERROR HANDLING AND EDGE CASES

Include a dedicated troubleshooting/behavior section covering things such as:

* Docker unavailable
* Docker Compose unavailable
* application not found
* multiple matching directories
* invalid application name
* invalid command
* missing Compose file
* malformed Compose configuration
* permission issues
* unavailable image
* failed build
* failed container startup
* missing helper script
* partial failure during multi-app operation
* interrupted command
* empty application set

Only document cases that are supported by the implementation or are clearly relevant to observed dependencies.

Distinguish between:

* behavior explicitly handled by DAM
* behavior inherited from Docker/Compose
* behavior that is not handled specially

---

# 15. DOCUMENT ARCHITECTURE / INTERNAL DESIGN

Include a technical architecture section describing:

* entrypoint
* command parser
* application discovery
* application resolution
* command dispatch
* execution helpers
* Docker/Compose abstraction layer
* update logic
* cleanup logic
* output/reporting
* error propagation
* configuration handling

Where helpful, include an ASCII flow diagram.

Example style:

user input
↓
argument parsing
↓
command dispatch
↓
application resolution
↓
Compose project discovery
↓
command execution
↓
result/status handling

But only include components actually present in the implementation.

---

# 16. DOCUMENT WHAT DAM IS NOT

Explain clearly what DAM does NOT attempt to replace.

For example, determine whether users should continue using native Docker commands for operations such as:

* container logs
* exec
* inspect
* image management
* low-level networking
* low-level volume operations
* daemon configuration
* advanced Docker features

Do not decide this philosophically. Base the explanation on the project's actual scope and implementation.

---

# 17. DOCUMENT LIMITATIONS HONESTLY

Create a "Limitations" section.

Look for architectural limitations such as:

* dependence on directory structure
* Compose filename assumptions
* naming collisions
* inability to distinguish certain projects
* shell compatibility
* operating system assumptions
* Docker/Compose version assumptions
* lack of remote Docker support
* lack of Kubernetes support
* security assumptions
* parsing limitations
* special-case project layouts
* multi-file Compose limitations
* behavior with profiles
* behavior with overrides
* behavior with environment files

Only document limitations that are actually supported by the implementation or verified behavior.

Do not manufacture limitations.

---

# 18. SECURITY REVIEW

Include a practical security section.

Inspect the code for:

* shell command construction
* quoting
* argument handling
* command injection risk
* use of `eval`
* handling of arbitrary paths
* privileges
* destructive commands
* use of `sudo`
* environment variables
* execution of application-provided scripts
* trust assumptions about directories

Do not claim the code is secure merely because it looks reasonable.

Report the actual implementation and identify any security considerations.

---

# 19. OFFICIAL SOURCE CITATIONS

When documenting Docker/Docker Compose behavior, cite official Docker documentation where the documentation format supports links/references.

Prefer:

* Docker official CLI documentation
* Docker Compose official documentation
* official Docker reference pages

For DAM-specific behavior, cite the relevant repository file/section where practical.

Do not cite third-party explanations when an official source is available.

---

# 20. README SHOULD BE A GOOD PROJECT LANDING PAGE

Do NOT dump the entire technical manual into README.md.

Generate a polished README that contains the information a new user needs quickly.

The README should normally include sections such as:

1. Project title
2. One-line description
3. What problem it solves
4. Why it exists
5. Key capabilities
6. Installation
7. Quick start
8. Basic usage
9. Example workflows
10. What makes DAM different from native Docker commands
11. Supported commands overview
12. Configuration overview
13. Safety notes
14. Link to full documentation
15. Requirements
16. Limitations
17. Contributing
18. License

The exact structure may be changed if the project suggests a better organization.

Make the README concise enough to be useful, but detailed enough that a new user understands why DAM exists.

If the project already has a README.md, update it following the guidelines above. and make sure to include professional HTML type headers where critical info is shown, various badges are displayed, and other important information is displayed in a beautiful and professional manner. Don't remove the existing content unless it's not relevant to the project. If it is relevant to the project, keep it and place it in the appropriate section. For badges, use the badges that are available in the GitHub README or generate new ones based on the project's features.

---

# 21. FULL DOCUMENTATION SHOULD BE SEPARATE

Create a proper documentation structure rather than putting everything into one giant README.

Use a logical structure based on the project's complexity.

For example, documentation may include:

docs/
getting-started.md
commands.md
architecture.md
configuration.md
docker-vs-dam.md
application-discovery.md
updates.md
safety.md
troubleshooting.md
limitations.md

Only create files that are actually useful.

A smaller number of well-organized documents is preferable to artificial fragmentation.

---

# 22. COMMAND REFERENCE MUST BE EXHAUSTIVE

Create a reference that covers EVERY supported user-facing command.

For each command, use a consistent format:

## `<actual-command>`

### Purpose

What it does.

### Syntax

Actual supported syntax.

### Arguments

Exact arguments and selectors.

### Behavior

Detailed execution behavior.

### Underlying commands

Exact Docker/Compose/shell commands executed.

### Scope

Container/service/project/multi-project/host.

### State changes

What it starts/stops/removes/updates.

### Failure behavior

Important failure cases.

### Examples

Only valid examples derived from the source.

### Related commands

Only when relevant.

Do not omit obscure or rarely used commands just because they are not common.

---

# 23. DO NOT HIDE IMPLEMENTATION DETAILS

This documentation is intended to be both user-facing documentation and a reliable technical reference.

Therefore, explicitly expose important implementation details where they affect behavior.

Examples:

* exact flags
* working directory behavior
* command ordering
* whether `docker compose up` is used instead of `docker compose start`
* whether `down` is used before recreation
* whether orphan removal is enabled
* whether builds happen during updates
* whether the application is expected to remain stopped
* whether the script invokes custom update hooks

The reader should be able to understand the actual behavior without reading the source code.

---

# 24. VERIFY EVERYTHING BEFORE WRITING

Before finalizing documentation:

1. Re-read the main script.
2. Trace every command implementation again.
3. Compare documented behavior against the source.
4. Verify Docker semantics against official Docker documentation.
5. Search for undocumented commands/options in the source.
6. Search for undocumented configuration.
7. Search for hard-coded assumptions.
8. Check that every example actually works according to the parser.
9. Check that command names and flags are spelled exactly as implemented.
10. Remove every unsupported claim.
11. Remove every invented example.
12. Remove every statement that cannot be backed by either source code or authoritative external documentation.

The goal is **accuracy over marketing**.

---

# 25. IMPORTANT: DO NOT MODIFY THE SOFTWARE

Your task is documentation.

Do not change the project's functional code unless explicitly required to make the documentation build correctly.

Do not refactor the script.

Do not rename commands.

Do not "fix" behavior because it seems unconventional.

Document the current implementation accurately.

If you discover a bug or inconsistency, document it in a dedicated "Known Issues" section rather than silently changing behavior.

---

# 26. DELIVERABLES

Produce:

### A. A polished `README.md`

This should be the project's main landing page.

### B. A complete `docs/` documentation set

Choose the structure based on what the repository actually contains.

### C. A Docker-vs-DAM comparison

This must be detailed and technically accurate.

### D. An exhaustive command execution reference

For every DAM command, show exactly what happens internally and which underlying commands are executed.

### E. A list of discovered limitations / edge cases

Clearly distinguish implementation limitations from Docker limitations.

### F. Any documentation index/navigation needed

Make the documentation easy to navigate.

---

# 27. FINAL QUALITY CHECK

Before considering the task complete, ask yourself:

* Did I actually inspect every relevant source file?
* Did I trace the implementation instead of guessing?
* Did I document every public command?
* Did I document exact underlying Docker/Compose commands?
* Did I distinguish Docker CLI from Docker Compose CLI?
* Did I explain container vs service vs project semantics?
* Did I explain how application discovery works?
* Did I verify Docker claims using official documentation?
* Did I avoid invented values and examples?
* Did I document destructive behavior?
* Did I document edge cases?
* Did I document configuration?
* Did I document limitations?
* Does README.md accurately represent the actual software?
* Could a beginner install and use the project from the documentation?
* Could an experienced Docker user understand exactly why DAM exists and how it differs from native Docker tooling?

If any answer is "no", continue investigating the repository before finalizing.

The final documentation should be **source-code-accurate, technically rigorous, beginner-readable, and honest about what DAM does and does not provide.**
