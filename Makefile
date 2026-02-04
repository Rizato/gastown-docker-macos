# Gastown Docker macOS Container
CONTAINER_NAME := gastown-docker-macos
IMAGE_NAME := gastown
DASHBOARD_PORT := 8080

# Volume directory to mount into /workspace (can be overridden via environment)
VOLUME_DIR ?= $(PWD)/gt

# Secrets from macOS Keychain (keychain item names)
CLAUDE_CODE_OAUTH_TOKEN := $(shell security find-generic-password -s "claude-code-oauth-token" -w 2>/dev/null)
GITHUB_TOKEN := $(shell security find-generic-password -s "gastown-github-token" -w 2>/dev/null)

# Git identity from local git config (baked into image at build time)
GIT_USERNAME := $(shell git config --get user.name 2>/dev/null)
GIT_EMAIL := $(shell git config --get user.email 2>/dev/null)

.PHONY: build start stop restart attach bash gt mayor clean logs status claude install rig crew dashboard dashboard-attach dashboard-stop

# Argument capture for passthrough commands (allows: make gt status, make rig add foo, etc.)
PASSTHROUGH_TARGETS := gt mayor rig crew
ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(PASSTHROUGH_TARGETS)),)
  ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  $(eval $(ARGS):;@:)
endif

# Build the Docker image
build:
	@if [ -z "$(GIT_USERNAME)" ]; then \
		echo "WARNING: git user.name not configured locally. Image will be built without git identity."; \
	fi
	@if [ -z "$(GIT_EMAIL)" ]; then \
		echo "WARNING: git user.email not configured locally. Image will be built without git identity."; \
	fi
	docker build \
		--build-arg GIT_USERNAME="$(GIT_USERNAME)" \
		--build-arg GIT_EMAIL="$(GIT_EMAIL)" \
		-t $(IMAGE_NAME) .

# Start the container (detached, with volume mount and port forward)
start: build
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Container exists, starting..."; \
		docker start $(CONTAINER_NAME); \
	else \
		echo "Creating and starting container..."; \
		if [ -z "$(CLAUDE_CODE_OAUTH_TOKEN)" ]; then echo "ERROR: claude-code-oauth-token not found in keychain. Run: security add-generic-password -a \$$USER -s claude-code-oauth-token -w"; exit 1; fi; \
		if [ -z "$(GITHUB_TOKEN)" ]; then echo "WARNING: gastown-github-token not found in keychain. Git push/pull will not work."; fi; \
		docker run -d \
			--name $(CONTAINER_NAME) \
			-v "$(VOLUME_DIR):/workspace" \
			-p $(DASHBOARD_PORT):$(DASHBOARD_PORT) \
			-e CLAUDE_CODE_OAUTH_TOKEN=$(CLAUDE_CODE_OAUTH_TOKEN) \
			-e GITHUB_TOKEN=$(GITHUB_TOKEN) \
			-e DASHBOARD_PORT=$(DASHBOARD_PORT) \
			$(IMAGE_NAME) \
			tail -f /dev/null; \
	fi

# Stop the container
stop:
	@docker stop $(CONTAINER_NAME) 2>/dev/null || echo "Container not running"

# Restart the container
restart: stop start

# Attach to the container (for interactive session with job control)
attach:
	docker exec -it $(CONTAINER_NAME) bash

# Open a bash shell in the container
bash:
	docker exec -it $(CONTAINER_NAME) bash

# Execute gastown (gt) commands directly
# Usage: make gt status, make gt agent list
gt:
	docker exec -it $(CONTAINER_NAME) gt $(ARGS)

# Run mayor command (gastown mayor)
# Usage: make mayor status, make mayor
mayor:
	docker exec -it $(CONTAINER_NAME) gt mayor $(ARGS)

# View container logs
logs:
	docker logs -f $(CONTAINER_NAME)

# Clean up - remove container and image
clean:
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm $(CONTAINER_NAME) 2>/dev/null || true
	@docker rmi $(IMAGE_NAME) 2>/dev/null || true
	@echo "Cleaned up container and image"

# Show container status
status:
	@docker ps -a --filter "name=$(CONTAINER_NAME)" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Run claude-code in the container
claude:
	docker exec -it $(CONTAINER_NAME) claude

# Start the dashboard in a detached tmux session
dashboard:
	@docker exec $(CONTAINER_NAME) tmux has-session -t dashboard 2>/dev/null && \
		echo "Dashboard session already running. Use 'make dashboard-attach' to view." || \
		(docker exec -d $(CONTAINER_NAME) tmux new-session -d -s dashboard 'gt dashboard' && \
		echo "Dashboard started in tmux session. Available at http://localhost:$(DASHBOARD_PORT)")

# Attach to the dashboard tmux session
dashboard-attach:
	docker exec -it $(CONTAINER_NAME) tmux attach-session -t dashboard

# Stop the dashboard tmux session
dashboard-stop:
	@docker exec $(CONTAINER_NAME) tmux kill-session -t dashboard 2>/dev/null && \
		echo "Dashboard session stopped" || echo "No dashboard session running"

# Initialize gastown with git integration
install:
	docker exec -it $(CONTAINER_NAME) gt install --git

# Add git repos to gastown
# Usage: make rig add myrepo, make rig list
rig:
	docker exec -it $(CONTAINER_NAME) gt rig $(ARGS)

# Add human worktrees to gastown
# Usage: make crew add human1, make crew list
crew:
	docker exec -it $(CONTAINER_NAME) gt crew $(ARGS)
