# Gastown Sandbox Container
CONTAINER_NAME := gastown-sandbox
IMAGE_NAME := gastown-sandbox
DASHBOARD_PORT := 3000

# Network isolation configuration (can be overridden from command line)
# SANDBOX_MODE: strict (whitelist only), permissive (block dangerous ports), disabled
SANDBOX_MODE ?= strict
# ALLOWED_HOSTS: comma-separated list of allowed hosts/IPs (used in strict mode)
# Leave empty to use Dockerfile defaults
ALLOWED_HOSTS ?=
# ALLOW_DNS: true/false - allow DNS lookups
ALLOW_DNS ?= true
# ALLOW_LOCALHOST: true/false - allow localhost traffic
ALLOW_LOCALHOST ?= true

.PHONY: build start stop restart attach bash gt mayor clean logs

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Start the container (detached, with volume mount, port forward, and network isolation)
start: build
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Container exists, starting..."; \
		docker start $(CONTAINER_NAME); \
	else \
		echo "Creating and starting container..."; \
		docker run -d \
			--name $(CONTAINER_NAME) \
			--cap-add=NET_ADMIN \
			-v "$(PWD):/workspace" \
			-p $(DASHBOARD_PORT):$(DASHBOARD_PORT) \
			-e ANTHROPIC_API_KEY \
			-e SANDBOX_MODE=$(SANDBOX_MODE) \
			-e ALLOW_DNS=$(ALLOW_DNS) \
			-e ALLOW_LOCALHOST=$(ALLOW_LOCALHOST) \
			-e DASHBOARD_PORT=$(DASHBOARD_PORT) \
			$(if $(ALLOWED_HOSTS),-e ALLOWED_HOSTS="$(ALLOWED_HOSTS)",) \
			$(IMAGE_NAME) \
			tail -f /dev/null; \
	fi
	@echo "Container running. Dashboard available at http://localhost:$(DASHBOARD_PORT)"

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
# Usage: make gt CMD="status" or make gt CMD="agent list"
gt:
	docker exec -it $(CONTAINER_NAME) gt $(CMD)

# Run mayor command (gastown mayor)
# Usage: make mayor CMD="status" or just make mayor
mayor:
	docker exec -it $(CONTAINER_NAME) gt mayor $(CMD)

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
