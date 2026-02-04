# =============================================================================
# Stage 1: Builder - Install all build tools and compile dependencies
# =============================================================================
FROM node:22-trixie-slim AS builder

# Build arguments
ARG TARGETARCH
ARG GO_VERSION=1.25.6
ARG GASTOWN_VERSION=v0.5.0
ARG UV_VERSION=0.5.20

# Install build dependencies (these won't be in final image)
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  pkg-config \
  libssl-dev \
  curl \
  ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Go
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${TARGETARCH}.tar.gz" | tar -C /usr/local -xzf -

ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/root/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Install Rust
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

# Install uv (installer puts binaries in ~/.local/bin, move to /usr/local/bin)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && mv /root/.local/bin/uv /usr/local/bin/uv \
  && mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install Python via uv
RUN /usr/local/bin/uv python install

# Install Node.js global packages
RUN npm install -g @anthropic-ai/claude-code @beads/bd

# Install gastown (gt)
RUN go install github.com/steveyegge/gastown/cmd/gt@${GASTOWN_VERSION}

# =============================================================================
# Stage 2: Runtime - Minimal image with only necessary tools
# =============================================================================
FROM node:22-trixie-slim

# Install only runtime dependencies (no build tools, no wget/vim/nano/gh)
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  curl \
  procps \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  ca-certificates \
  sudo \
  tmux \
  sqlite3 \
  libssl3 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy Go from builder
COPY --from=builder /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Copy Rust from builder (with correct permissions)
COPY --from=builder /usr/local/rustup /usr/local/rustup
COPY --from=builder /usr/local/cargo /usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"

# Copy uv from builder
COPY --from=builder /usr/local/bin/uv /usr/local/bin/uv
COPY --from=builder /usr/local/bin/uvx /usr/local/bin/uvx
COPY --from=builder /root/.local/share/uv /usr/local/share/uv
ENV UV_PYTHON_INSTALL_DIR=/usr/local/share/uv/python

# Copy Node.js global packages from builder
COPY --from=builder /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=builder /usr/local/bin/claude /usr/local/bin/claude
COPY --from=builder /usr/local/bin/bd /usr/local/bin/bd

# Copy gastown (gt) from builder
COPY --from=builder /root/go/bin/gt /usr/local/bin/gt

# Create workspace, go, and claude config directories
RUN mkdir -p /home/node/go /home/node/.claude && chown -R node:node /home/node/go /home/node/.claude

# Configure sudo access for node user (passwordless for network sandbox script only)
# Input validation is done in the script itself
RUN echo "node ALL=(ALL) NOPASSWD: /usr/local/bin/network-sandbox.sh" > /etc/sudoers.d/node \
  && chmod 0440 /etc/sudoers.d/node

# Copy network isolation scripts
COPY scripts/network-sandbox.sh /usr/local/bin/network-sandbox.sh
RUN chmod +x /usr/local/bin/network-sandbox.sh

# Copy git credential helper
COPY scripts/git-credential-github-token /usr/local/bin/git-credential-github-token
RUN chmod +x /usr/local/bin/git-credential-github-token

WORKDIR /workspace

# Expose gastown dashboard port
EXPOSE 8080

# Network isolation environment variables
# SANDBOX_MODE: strict (whitelist only), permissive (block dangerous ports), disabled
# ALLOWED_HOSTS: comma-separated list of allowed hosts/IPs (for strict mode)
# ALLOW_DNS: true/false - allow DNS lookups
# ALLOW_LOCALHOST: true/false - allow localhost traffic
ENV SANDBOX_MODE=strict
ENV ALLOWED_HOSTS="\
github.com,\
api.github.com,\
raw.githubusercontent.com,\
objects.githubusercontent.com,\
codeload.github.com,\
gitlab.com,\
bitbucket.org,\
registry.npmjs.org,\
npmjs.com,\
yarnpkg.com,\
registry.yarnpkg.com,\
crates.io,\
static.crates.io,\
index.crates.io,\
pypi.org,\
files.pythonhosted.org,\
proxy.golang.org,\
sum.golang.org,\
storage.googleapis.com,\
api.anthropic.com,\
anthropic.com,\
claude.ai,\
api.claude.ai,\
statsig.anthropic.com,\
sentry.io,\
o19835.ingest.sentry.io,\
dl.google.com,\
packages.microsoft.com,\
deb.nodesource.com,\
download.docker.com,\
astral.sh,\
sh.rustup.rs,\
static.rust-lang.org\
"
ENV ALLOW_DNS=true
ENV ALLOW_LOCALHOST=true
ENV DASHBOARD_PORT=8080

# Note: Container must be run with --cap-add=NET_ADMIN for iptables to work
# Example: docker run --cap-add=NET_ADMIN -e SANDBOX_MODE=strict ...

# Set shell to bash for better compatibility
SHELL ["/bin/bash", "-c"]

# Run as node user
USER node

# Use network sandbox as entrypoint (runs with sudo for iptables access)
ENTRYPOINT ["sudo", "/usr/local/bin/network-sandbox.sh"]

CMD ["bash"]
