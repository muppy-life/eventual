#!/bin/bash

CONTAINER_NAME="eventual_postgres"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "Stopping PostgreSQL container ${CONTAINER_NAME}..."
    docker stop ${CONTAINER_NAME}
    echo "Container stopped."
else
    echo "Container ${CONTAINER_NAME} is not running."
fi
