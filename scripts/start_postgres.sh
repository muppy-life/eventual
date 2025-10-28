#!/bin/bash

# Configuration
CONTAINER_NAME="eventual_postgres"
POSTGRES_USER="postgres"
POSTGRES_PASSWORD="postgres"
POSTGRES_DB="eventual_test"
POSTGRES_PORT="5442"

# Check if container already exists
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "Container ${CONTAINER_NAME} exists."

    # Check if it's running
    if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
        echo "Container ${CONTAINER_NAME} is already running."
        exit 0
    else
        echo "Starting existing container ${CONTAINER_NAME}..."
        docker start ${CONTAINER_NAME}
        exit 0
    fi
fi

# Create and start new container
echo "Creating and starting new PostgreSQL container ${CONTAINER_NAME}..."
docker run -d \
  --name ${CONTAINER_NAME} \
  -e POSTGRES_USER=${POSTGRES_USER} \
  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
  -e POSTGRES_DB=${POSTGRES_DB} \
  -p ${POSTGRES_PORT}:5432 \
  postgres:16-alpine

echo "Waiting for PostgreSQL to be ready..."
sleep 3

echo "PostgreSQL is running on localhost:${POSTGRES_PORT}"
echo "Database: ${POSTGRES_DB}"
echo "User: ${POSTGRES_USER}"
echo "Password: ${POSTGRES_PASSWORD}"
