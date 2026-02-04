# Gastown Docker Sandbox

A Docker-based sandbox environment for running [Gastown](https://github.com/steveyegge/gastown) with network isolation. Provides a secure, reproducible environment with pre-installed development tools.

## Usage Model

**Clone this repository fresh for each Gastown project.** This repo contains the Gastown installation baked into the Docker image, providing complete isolation between projects. The `gt/` directory serves as the workspace volume and is gitignored.

```bash
git clone <this-repo> my-project-sandbox
cd my-project-sandbox
make start
make attach
```

## Security Posture

### Network Isolation

The sandbox implements network isolation using iptables with three modes:

| Mode | Description |
|------|-------------|
| `strict` (default) | Whitelist-only. All outbound traffic blocked except explicitly allowed hosts. |
| `permissive` | Blocks dangerous ports (SMTP, SSH, databases) but allows most traffic. |
| `disabled` | No network restrictions. |

**Strict mode allowed hosts include:**
- Package registries: npm, PyPI, crates.io, Go proxy
- Code hosting: GitHub, GitLab, Bitbucket
- Anthropic APIs: api.anthropic.com, claude.ai
- Language tooling: rustup, uv/astral

### Container Security

- **Non-root execution**: Runs as the `node` user, not root
- **Minimal sudo**: Passwordless sudo granted only for `/usr/local/bin/network-sandbox.sh`
- **Capability-limited**: Requires only `NET_ADMIN` capability (for iptables)

### What's Blocked (Strict Mode)

All outbound traffic except:
- DNS (port 53) when `ALLOW_DNS=true`
- Localhost when `ALLOW_LOCALHOST=true`
- Explicitly whitelisted hosts

### What's Blocked (Permissive Mode)

- SMTP (ports 25, 465, 587) - prevents spam
- SSH outbound (port 22) - prevents lateral movement
- Database ports (MySQL, PostgreSQL, MongoDB, Redis)

## Quick Reference

```bash
# Container management
make build       # Build the Docker image
make start       # Start container (builds if needed)
make stop        # Stop container
make attach      # Get a shell in the container
make bash        # Alias for attach
make logs        # View container logs
make clean       # Remove container and image
make status      # Show container status

# Gastown setup
make install                        # gt install --git (initialize workspace)
make rig add <name> <repo>          # Add a git repo to gastown
make rig list                       # List all projects
make crew add <name> --rig <rig>    # Create human worktree in a project

# Gastown operations
make gt agents                      # List active agents
make gt convoy list                 # View all convoys
make gt convoy create "<name>"      # Create work bundle
make gt sling <bead-id> <rig>       # Assign work to an agent
make mayor attach                   # Start Mayor coordinator session

# Dashboard
make dashboard          # Start gt dashboard in background tmux session
make dashboard-attach   # Attach to dashboard tmux session
make dashboard-stop     # Stop the dashboard session

# Run Claude Code directly
make claude
```

## Configuration

Override at runtime via environment variables or make arguments:

```bash
# Use permissive mode
make start SANDBOX_MODE=permissive

# Add custom allowed hosts
make start ALLOWED_HOSTS="api.example.com,cdn.example.com"

# Disable DNS
make start ALLOW_DNS=false

# Custom volume directory
make start VOLUME_DIR=/path/to/workspace
```

## Included Tools

- **Languages**: Node.js, Go 1.24, Rust, Python (via uv)
- **AI Tools**: Claude Code, Gastown (gt), beads (bd)

## Requirements

- Docker with `--cap-add=NET_ADMIN` support
- `CLAUDE_CODE_OAUTH_TOKEN` environment variable (for Claude Code / Gastown)
