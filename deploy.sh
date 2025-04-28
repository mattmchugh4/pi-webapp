#!/bin/bash

# deploy.sh - Docker Swarm deployment script
# Usage: ./deploy.sh [OPTIONS]
#
# Options:
#   --pull         Pull latest images before deploying
#   --update-reddit Update and rebuild the reddit-summarizer image
#   --force        Force redeployment of services
#   --prune        Prune unused images after deployment
#   --help         Display this help message

set -e

# Default values
STACK_NAME="webstack"
COMPOSE_FILE="./swarm/docker-compose.yml"
PULL=false
UPDATE_REDDIT=false
FORCE=false
PRUNE=false

# Function to display help
show_help() {
  grep "^#" "$0" | grep -v "^#!/bin/bash" | sed 's/^# //' | sed 's/^#//'
}
# Process command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
  --pull)
    PULL=true
    ;;
  --update-reddit)
    UPDATE_REDDIT=true
    ;;
  --force)
    FORCE=true
    ;;
  --prune)
    PRUNE=true
    ;;
  --help)
    show_help
    exit 0
    ;;
  *)
    echo "Unknown option: $1"
    show_help
    exit 1
    ;;
  esac
  shift
done

echo "Starting deployment process..."

# Check if we're in a Docker Swarm
if ! docker info | grep -q "Swarm: active"; then
  echo "ERROR: Docker Swarm is not active. Initialize with 'docker swarm init'"
  exit 1
fi

# Pull the latest code
echo "Pulling latest code changes..."
git pull

# Single prompt to handle both pulling images and updating services
if [ "$PULL" = false ] && [ "$UPDATE_REDDIT" = false ]; then
  read -p "Update before deploying? This will rebuild the Reddit Summarizer and pull latest images (y/N): " response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    PULL=true
    UPDATE_REDDIT=true
  fi
fi

# Update and rebuild the reddit-summarizer if requested
if [ "$UPDATE_REDDIT" = true ]; then
  echo "Updating Reddit Summarizer service..."
  ./scripts/update_reddit_summarizer_flask.sh
fi

# Pull latest images if requested
if [ "$PULL" = true ]; then
  echo "Pulling latest Docker images..."
  docker compose -f "$COMPOSE_FILE" pull
fi

# Deploy the stack
echo "Deploying stack: $STACK_NAME with compose file: $COMPOSE_FILE"
if [ "$FORCE" = true ]; then
  echo "NOTICE: Forcing redeployment of all services..."
  docker stack deploy --compose-file $COMPOSE_FILE --prune --with-registry-auth --resolve-image always $STACK_NAME
else
  docker stack deploy --compose-file $COMPOSE_FILE --with-registry-auth $STACK_NAME
fi

# Wait a bit for deployment to start
sleep 3

# Check stack status
echo "Checking deployment status..."
docker stack services $STACK_NAME

# Prune unused images if requested
if [ "$PRUNE" = true ]; then
  echo "Pruning unused Docker images..."
  docker image prune -f
fi

echo "Deployment completed successfully."
