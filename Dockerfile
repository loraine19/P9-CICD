# syntax=docker/dockerfile:1
#
# MicroCRM — multi-stage build
#
# Available targets:
#   --target front   Caddy image serving the static Angular bundle
#   --target back    JRE image running the Spring Boot JAR
#
# Applied principles (see documentation §3.1):
#   - official, minimal (alpine) and versioned base images (never `latest`)
#   - build / runtime separation: no JDK or node_modules in the final image
#   - one single process per container, orchestration is delegated to docker compose
#   - runs as a non-privileged user

# =============================================================================
# Step 1 — Build the Angular front-end
# =============================================================================
FROM node:22-alpine AS front-build

WORKDIR /src

# Copy only the manifests first: as long as they don't change,
# the `npm ci` layer is reused from cache.
COPY front/package.json front/package-lock.json ./
RUN npm ci

COPY front/ ./
RUN npm run build -- --configuration production

# =============================================================================
# Step 2 — Build the Spring Boot back-end
# =============================================================================
FROM eclipse-temurin:17-jdk-alpine AS back-build

WORKDIR /src

# The Gradle wrapper guarantees the same Gradle version (8.7) as locally.
COPY back/gradlew ./gradlew
COPY back/gradle ./gradle
COPY back/build.gradle back/settings.gradle ./
RUN chmod +x gradlew

COPY back/src ./src

# `--no-daemon`: no need to keep a Gradle daemon alive in a disposable container.
# Tests run in CI, not here (building the image is packaging only).
RUN ./gradlew --no-daemon clean bootJar

# =============================================================================
# Step 3 — Front-end runtime image
# =============================================================================
FROM caddy:2-alpine AS front

COPY --from=front-build /src/dist/microcrm/browser /srv
COPY misc/docker/Caddyfile /etc/caddy/Caddyfile

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost/ > /dev/null || exit 1

# The start command is inherited from the official Caddy image.

# =============================================================================
# Step 4 — Back-end runtime image
# =============================================================================
FROM eclipse-temurin:17-jre-alpine AS back

# Non-privileged user: limits the impact of a container compromise.
RUN addgroup -S spring && adduser -S spring -G spring

WORKDIR /app

COPY --from=back-build --chown=spring:spring /src/build/libs/*.jar /app/microcrm.jar

USER spring

# Spring Boot listens on 8080 .
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=5 \
    CMD wget -qO- http://localhost:8080/persons > /dev/null || exit 1

ENTRYPOINT ["java", "-jar", "/app/microcrm.jar"]
