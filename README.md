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

## Getting the Claude OAuth Token

The container requires `CLAUDE_CODE_OAUTH_TOKEN` to authenticate with Claude. The Makefile reads this automatically from the macOS keychain entry `claude-code-oauth-token`.

To set up authentication, run:

```bash
claude setup-token
```

This command will output your OAuth token. Store it in the keychain entry that the Makefile expects:

```bash
security add-generic-password -a $USER -s "claude-code-oauth-token" -w "<your-oauth-token>"
```

The Makefile will automatically:
1. Read the token from the keychain
2. Pass it to the container as `CLAUDE_CODE_OAUTH_TOKEN`
3. The entrypoint creates `~/.claude.json` with `hasCompletedOnboarding: true` to skip interactive setup

This enables fully automated, reproducible Claude Code authentication in CI/CD environments.

## Getting the GitHub Token

The container requires a GitHub Personal Access Token to authenticate git operations (push, pull, clone). The Makefile reads this automatically from the macOS keychain entry `gastown-github-token`.

To create a GitHub token:

1. Go to GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a descriptive name (e.g., "Gastown Docker Sandbox")
4. Select scopes: `repo` (full control of private repositories)
5. Generate and copy the token

Store it in the keychain entry that the Makefile expects:

```bash
security add-generic-password -a $USER -s "gastown-github-token" -w "<your-github-token>"
```

The Makefile will automatically:
1. Read the token from the keychain
2. Pass it to the container as `GITHUB_TOKEN`
3. The git credential helper uses this token to authenticate all git operations

Without this token, git push/pull operations will fail with authentication errors.

## Git Configuration

The Docker image automatically copies your local git identity (name and email) from your host machine into the container. This happens at **build time**.

The Makefile reads from your local git config:
```bash
git config --get user.name
git config --get user.email
```

These values are baked into the Docker image via build args, so all commits made inside the container will be attributed to you. If you change your local git config, you'll need to rebuild the image:

```bash
make clean
make build
```

If git identity is not configured locally, you'll see a warning during build, but the image will still build successfully.

## Requirements

- Docker with `--cap-add=NET_ADMIN` support
- `CLAUDE_CODE_OAUTH_TOKEN` environment variable (for Claude Code / Gastown)
