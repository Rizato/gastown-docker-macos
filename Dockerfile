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

# Copy claude config
COPY .claude.json /home/node/.claude.json
RUN chown node:node /home/node/.claude.json

# Copy entrypoint and git credential helper
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scripts/git-credential-github-token /usr/local/bin/git-credential-github-token
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/git-credential-github-token

WORKDIR /workspace

# Expose gastown dashboard port
EXPOSE 8080

ENV DASHBOARD_PORT=8080

# Set shell to bash for better compatibility
SHELL ["/bin/bash", "-c"]

# Run as node user
USER node

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bash"]
