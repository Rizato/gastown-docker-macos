# =============================================================================
# Stage 1: Builder - Install all build tools and compile dependencies
# =============================================================================
FROM node:22-trixie-slim AS builder

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
ARG TARGETARCH
ARG GO_VERSION=1.25.6
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
ARG UV_VERSION=0.5.20
RUN curl -LsSf https://astral.sh/uv/install.sh | sh \
  && mv /root/.local/bin/uv /usr/local/bin/uv \
  && mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install Python via uv
RUN /usr/local/bin/uv python install


# =============================================================================
# Stage 2: Runtime - Minimal image with only necessary tools
# =============================================================================
FROM node:22-trixie-slim


# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  procps \
  gnupg2 \
  jq \
  ca-certificates \
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

# Install Claude Code (native)
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install beads via npm
RUN npm install -g @beads/bd

# Install gastown (gt)
ARG GASTOWN_VERSION=v0.5.0
RUN go install github.com/steveyegge/gastown/cmd/gt@${GASTOWN_VERSION}

# Create workspace, go, and claude config directories
RUN mkdir -p /home/node/go /home/node/.claude && chown -R node:node /home/node/go /home/node/.claude

# Copy claude config
COPY .claude.json /home/node/.claude.json
RUN chown node:node /home/node/.claude.json

# Copy git credential helper
COPY scripts/git-credential-github-token /usr/local/bin/git-credential-github-token
RUN chmod +x /usr/local/bin/git-credential-github-token

WORKDIR /workspace

# Expose gastown dashboard port
EXPOSE 8080

ENV DASHBOARD_PORT=8080

# Set shell to bash for better compatibility
SHELL ["/bin/bash", "-c"]

# Run as node user
USER node

# Setup git config
ARG GIT_USERNAME
ARG GIT_EMAIL
RUN git config --global credential.helper /usr/local/bin/git-credential-github-token
RUN git config --global user.name "${GIT_USERNAME}"
RUN git config --global user.email "${GIT_EMAIL}"

CMD ["bash"]
