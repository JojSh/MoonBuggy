FROM ubuntu:22.04

# Install dependencies for Godot headless
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libgl1 \
    libglu1-mesa \
    libxcursor1 \
    libxi6 \
    libxinerama1 \
    libxrandr2 \
    libxrender1 \
    libasound2 \
    libpulse0 \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy the exported Godot server binary
COPY relay-build/moonbuggy-relay.x86_64 /app/moonbuggy-relay

# Make it executable
RUN chmod +x /app/moonbuggy-relay

# Expose the WebSocket port
EXPOSE 9080

# Run the relay server - directly load the relay scene, bypassing main_world
CMD ["/app/moonbuggy-relay", "--headless", "res://scenes/relay_server.tscn"]
