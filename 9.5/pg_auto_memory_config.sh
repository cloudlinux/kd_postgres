#!/bin/bash

DATA_DIR="$1"
CONFIG_FILE="$DATA_DIR/postgresql.conf"
MEMORY_CONFIG_FILE=auto_memory_config.conf
MEM_STAT_FILE=/sys/fs/cgroup/memory/memory.stat

TOTAL_MEMORY=$(grep hierarchical_memory_limit $MEM_STAT_FILE|cut -d ' ' -f 2)

# Always clean old memory config file, because the amount of memory may change
# between container starts. Old config will be preserved in case of data
# directory is mounted as some kind of persistent volume.
echo '' > "$DATA_DIR/$MEMORY_CONFIG_FILE"

if ! [[ "$TOTAL_MEMORY" =~ ^[0-9]+$ ]] ; then
    echo "Failed to detect available memory size."
    exit 1
fi


# In case when there is no limit set in the container, TOTAL_MEMORY will
# contain very large value (9223372036854771712 or something like)
total_host_memory=$(free -b | awk 'NR==2{print$2}')
if (( $total_host_memory < $TOTAL_MEMORY )); then
    echo "No memory limit set in the container. Skip auto configuration."
    exit 0
fi

MEMORY_LIMIT_256M=$((256 * 1024 * 1024))
MEMORY_LIMIT_512M=$((512 * 1024 * 1024))
MEMORY_LIMIT_1G=$((1024 * 1024 * 1024))
MEMORY_LIMIT_2G=$((2 * 1024 * 1024 * 1024))

if (($TOTAL_MEMORY < $MEMORY_LIMIT_256M)); then
    max_connections=20
elif (($TOTAL_MEMORY < $MEMORY_LIMIT_512M)); then
    max_connections=40
elif (($TOTAL_MEMORY < $MEMORY_LIMIT_1G)); then
    max_connections=60
elif (($TOTAL_MEMORY < $MEMORY_LIMIT_2G)); then
    max_connections=150
else
    max_connections=300
fi

shared_buffers=$(($TOTAL_MEMORY / 4))

# Assume available memory for caching (OS + database). It is recommended to set
# it from 1/2 to 3/4 of available memory.
effective_cache_size=$(($TOTAL_MEMORY * 3 / 4))

shared_buffers=$(($shared_buffers / (1024 * 1024)))MB
effective_cache_size=$(($effective_cache_size / (1024 * 1024)))MB


cat > "$DATA_DIR/$MEMORY_CONFIG_FILE" << EOF
# Auto memory configuration.
# TOTAL_MEMORY: $TOTAL_MEMORY
max_connections = $max_connections
shared_buffers = $shared_buffers
effective_cache_size = $effective_cache_size
EOF

grep -Fq "$MEMORY_CONFIG_FILE" "$CONFIG_FILE" || echo "include = '$MEMORY_CONFIG_FILE'" >> "$CONFIG_FILE"
