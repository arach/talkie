# Security Model

This document describes Talkie's security architecture, threat model, and design decisions for the workflow execution system.

## Threat Model

### Environment Assumptions

1. **Trusted Users**: Talkie operates in a controlled environment where users are trusted. The application is not designed for public multi-tenant deployment.

2. **Untrusted Content**: While users are trusted, the *content* flowing through workflows is not:
   - Voice transcriptions come from Apple's Speech framework
   - LLM outputs may contain adversarial content (prompt injection attempts)
   - External webhook responses are untrusted

3. **Powerful Integrations**: Users expect full access to their configured tools:
   - Claude CLI with MCP servers
   - GitHub CLI with authentication
   - Custom scripts and automation

### Primary Threats

| Threat | Description | Mitigation |
|--------|-------------|------------|
| **Prompt Injection** | LLM outputs malicious commands that get executed by shell steps | Content sanitization, injection detection, audit logging |
| **Command Injection** | Transcript content contains shell metacharacters | No shell expansion, direct Process() execution, argument isolation |
| **Privilege Escalation** | Workflow attempts to run sudo/su | Executable blocklist |
| **Data Exfiltration** | Malicious workflow sends data to external servers | Allowlist model for executables |
| **Denial of Service** | Infinite loops, resource exhaustion | Timeout enforcement, content length limits |

## Security Architecture

### Shell Step Execution

The workflow system includes a "Run Shell Command" step type. Security is implemented in layers:

#### Layer 1: Executable Allowlist

Only pre-approved executables can run. The allowlist includes:

```
Text Processing:     /bin/echo, /bin/cat, /usr/bin/grep, etc.
JSON Processing:     /opt/homebrew/bin/jq
HTTP Clients:        /usr/bin/curl
Developer CLIs:      /opt/homebrew/bin/gh, /usr/local/bin/claude
Scripting:           /usr/bin/python3, /opt/homebrew/bin/node
macOS Automation:    /usr/bin/osascript, /usr/bin/open
```

Users can extend this list via Settings for their specific tools.

#### Layer 2: Executable Blocklist

Certain executables are explicitly blocked regardless of allowlist:

```
Destructive:         /bin/rm, /bin/rmdir, /bin/mv
Privilege:           /usr/bin/sudo, /usr/bin/su
Raw Shells:          /bin/sh, /bin/bash, /bin/zsh
Network Exfil:       /usr/bin/ssh, /usr/bin/nc
Disk Operations:     /usr/sbin/diskutil
```

#### Layer 3: No Shell Expansion

Commands are executed via `Process()` directly, NOT through `/bin/sh -c`. This means:
- No command substitution (`$(...)`, backticks)
- No pipes (`|`)
- No redirections (`>`, `<`)
- No command chaining (`&&`, `||`, `;`)

Arguments are passed as an array directly to the executable.

#### Layer 4: Content Sanitization

Dynamic content (from templates like `{{TRANSCRIPT}}`, `{{OUTPUT}}`) is sanitized:
- Null bytes removed (can break C-based tools)
- Length limited to 500KB (prevents DoS)

#### Layer 5: Injection Detection (Audit)

Content is scanned for suspicious patterns. These generate warnings in logs but don't block execution (to avoid false positives on legitimate content):

```
Command substitution:  $(, `
Shell operators:       &&, ||, ;, |, >, <
Script injection:      #!/, import os, subprocess, eval(, exec(
```

Warnings are logged for security audit and debugging.

#### Layer 6: Execution Controls

- **Timeout**: 1-300 seconds (default 30)
- **Working Directory**: Controlled, not user-influenced
- **Environment**: Dangerous variables removed (`LD_PRELOAD`, `DYLD_INSERT_LIBRARIES`)

### Data Flow Security

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Apple     │────▶│   Talkie    │────▶│    LLM      │
│   Speech    │     │  Workflow   │     │   Step      │
└─────────────┘     └─────────────┘     └─────────────┘
                           │                    │
                           │                    ▼
                           │            ┌─────────────┐
                           │            │  Sanitize   │
                           │            │  + Detect   │
                           │            └─────────────┘
                           │                    │
                           ▼                    ▼
                    ┌─────────────┐     ┌─────────────┐
                    │   Shell     │◀────│  Template   │
                    │   Step      │     │  Resolution │
                    └─────────────┘     └─────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │  Process()  │
                    │  (no shell) │
                    └─────────────┘
```

## Design Decisions

### Why Not Full Sandboxing?

We considered using macOS App Sandbox or stricter process isolation but chose not to because:

1. **User Experience**: Users expect `claude` to access their MCP servers, `gh` to use their GitHub auth, etc.
2. **Trusted Environment**: The threat isn't malicious users but malicious content
3. **Complexity**: Full sandboxing would require extensive entitlement configuration per-tool

### Why Allowlist Instead of Blocklist-Only?

A pure blocklist approach is fragile:
- New dangerous tools get added to systems
- Tool names can be aliased
- Difficult to enumerate all dangerous commands

The allowlist ensures only explicitly approved tools can run.

### Why Log Injection Attempts Instead of Blocking?

False positives are a concern:
- A legitimate transcript might mention "import os" in a programming discussion
- LLM output explaining code might contain `eval(`
- Technical discussions reference shell syntax

Blocking would create user frustration. Logging allows security review while maintaining usability.

## Recommendations for Deployment

### For Development/Personal Use

The default configuration is appropriate. Add tools to the allowlist as needed via Settings.

### For Team/Organization Deployment

1. **Review the Allowlist**: Remove tools your workflows don't need
2. **Enable Audit Logging**: Monitor injection warnings
3. **Limit Workflow Creation**: Consider restricting who can create shell steps
4. **Review LLM Prompts**: Ensure system prompts instruct the LLM to output structured data, not commands

### Security Checklist

- [ ] Review allowed executables for your use case
- [ ] Test workflows with adversarial inputs before production use
- [ ] Monitor logs for injection warnings
- [ ] Keep tools (claude, gh, etc.) updated
- [ ] Use specific tool paths (not relying on PATH)

## Reporting Security Issues

If you discover a security vulnerability, please report it by:
1. Opening a private issue (if repository supports it)
2. Emailing the maintainers directly

Do not disclose security issues publicly until they have been addressed.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2024-11-26 | Initial security model for shell step execution |
