# Gastown Sandbox Container
CONTAINER_NAME := gastown-sandbox
IMAGE_NAME := gastown-sandbox
DASHBOARD_PORT := 3000

.PHONY: build start stop restart attach bash gt mayor clean logs

# Build the Docker image
build:
	docker build -t $(IMAGE_NAME) .

# Start the container (detached, with volume mount and port forward)
start: build
	@if docker ps -a --format '{{.Names}}' | grep -q "^$(CONTAINER_NAME)$$"; then \
		echo "Container exists, starting..."; \
		docker start $(CONTAINER_NAME); \
	else \
		echo "Creating and starting container..."; \
		docker run -d \
			--name $(CONTAINER_NAME) \
			-v "$(PWD):/workspace" \
			-p $(DASHBOARD_PORT):$(DASHBOARD_PORT) \
			-e ANTHROPIC_API_KEY \
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
