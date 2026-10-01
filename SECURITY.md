# Security Policy

I maintain DAM, which manages Docker Compose applications and invokes Docker commands with the permissions of the user running it. Please report suspected vulnerabilities to me privately and allow time for investigation and a fix before public disclosure.

## Supported Versions

Security fixes are currently provided for the latest version on the repository's default branch. Older versions are not actively supported; update to the latest version before reporting an issue when it is safe to do so.

| Version | Supported |
| :------ | :-------- |
| Latest on the default branch | Yes |
| Older versions | No |

## Reporting a Vulnerability

**Do not report vulnerabilities in a public issue, pull request, discussion, or other public channel.**

Email me at [connect@upputuri.in](mailto:connect@upputuri.in) to report a vulnerability privately. You may also use the repository host's private vulnerability reporting feature (on GitHub, choose **Security → Report a vulnerability**) if it is enabled. Do not post sensitive details publicly.

Please include, as applicable:

- A concise description of the suspected vulnerability and its potential impact.
- Affected DAM version or commit and the relevant command/configuration.
- Required permissions, environment, and prerequisites.
- Reproduction steps or a minimal proof of concept that does not access systems or data you do not own or have permission to test.
- Expected behavior and actual behavior.
- Relevant sanitized logs and environment details, such as operating system, Bash version, Docker version, and Compose version.
- Any known workaround or mitigation.

Do not include passwords, access tokens, private keys, private registry credentials, personal data, or unredacted configuration. Do not run tests against other people's Docker hosts, services, or data.

## What to Report

Examples of security-relevant behavior include:

- Shell injection, unsafe argument handling, or unintended command execution.
- Unexpected privilege escalation or unsafe use of `sudo`.
- Destructive actions escaping the selected Compose project or configured cleanup scope.
- Unsafe handling of sourced configuration, app paths, or custom update scripts.
- Self-update integrity or transport failures that allow an attacker to replace the installed script.
- Sensitive information being exposed in output or logs.

The following are generally not vulnerabilities by themselves:

- A feature behaving as documented, including commands that intentionally remove resources after the documented confirmation or `-y` option.
- Issues requiring write access to trusted app directories or the root-owned system configuration, unless they demonstrate an additional security boundary failure.
- Vulnerabilities in Docker Engine, Docker Compose, the operating system, or third-party images; report those to their respective maintainers. DAM-specific impact or unsafe interaction should still be reported here.

If uncertain whether an issue is security-sensitive, report it privately.

## Response and Coordinated Disclosure

I aim to acknowledge reports within 48 hours. I will work with the reporter to validate the impact, determine affected versions, and agree on a remediation and disclosure timeline. Acknowledgement is not a guarantee that a fix or release will be available within a specific timeframe.

Please keep the report and reproduction details private while I investigate. Coordinate any public disclosure with me so users have a reasonable opportunity to update or apply a mitigation. I will credit reporters in an advisory or release note when they request credit and it is safe to do so.

## Security Notes for Users

- Run DAM as an unprivileged user for ordinary app operations where possible. Membership in the Docker group generally grants root-equivalent control over the host.
- Only manage app directories and Compose files you trust. Compose projects can request powerful host access, and DAM does not sandbox Compose.
- Custom `update*.sh` scripts execute with the invoking user's permissions when allowed. Review them before enabling or approving execution; do not run DAM with elevated privileges when unnecessary.
- The installed configuration is sourced as Bash. Protect it from modification by untrusted users.
- `cleanup` is host-wide, not limited to DAM-discovered apps. Review its documented scope and confirmations before use; `-y` bypasses prompts.
- Self-update replaces the installed script. Use the documented HTTPS source and, in environments requiring stronger integrity assurance, configure and verify the SHA-256 value.
- With a Docker context or `DOCKER_HOST`, Docker commands target the selected daemon, but DAM still reads app files on the machine where DAM runs. Verify the selected context before destructive operations.

See [docs/safety.md](docs/safety.md) for detailed command safety behavior.
