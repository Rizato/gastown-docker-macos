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
RUN npm install -g @gastown/gt

# Create workspace, go, and claude config directories
RUN mkdir -p /home/node/go /home/node/.claude && chown -R node:node /home/node/go /home/node/.claude

WORKDIR /workspace

# Expose dashboard port
EXPOSE 3000

USER node

# Set shell to bash for better compatibility
SHELL ["/bin/bash", "-c"]

CMD ["bash"]
