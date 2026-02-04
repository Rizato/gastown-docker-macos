FROM node:trixie-slim

# Install basic development tools, build essentials, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential \
  cmake \
  pkg-config \
  libssl-dev \
  less \
  git \
  curl \
  wget \
  procps \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  ca-certificates \
  sudo \
  tmux \
  sqlite3 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Go
ENV GO_VERSION=1.24.12
RUN curl -fsSL https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/node/go"
ENV PATH="${GOPATH}/bin:${PATH}"

# Install Rust (as node user later, but prepare rustup)
ENV RUSTUP_HOME=/usr/local/rustup
ENV CARGO_HOME=/usr/local/cargo
ENV PATH="/usr/local/cargo/bin:${PATH}"
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path \
  && chmod -R a+rwx ${RUSTUP_HOME} ${CARGO_HOME}

# Install uv and Python (uv manages Python directly)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && mv /root/.local/bin/uv /usr/local/bin/uv \
  && mv /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true
RUN uv python install

# Install Node.js global packages
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g @beads/bd

# Install gastown (gt)
ARG GASTOWN_VERSION=v0.5.0
RUN go install github.com/steveyegge/gastown/cmd/gt@${GASTOWN_VERSION}

# Create workspace, go, and claude config directories
RUN mkdir -p /home/node/go /home/node/.claude && chown -R node:node /home/node/go /home/node/.claude

# Configure sudo access for node user (passwordless for network sandbox script only)
RUN echo "node ALL=(ALL) NOPASSWD: /usr/local/bin/network-sandbox.sh" > /etc/sudoers.d/node \
  && chmod 0440 /etc/sudoers.d/node

# Copy network isolation scripts
COPY scripts/network-sandbox.sh /usr/local/bin/network-sandbox.sh
RUN chmod +x /usr/local/bin/network-sandbox.sh

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
