# ---------------------------------------------------------------------------
# Self-contained build: you only need Docker, not Java or Maven.
#   docker build -t fuel-tracker:1.1.0 .
#   docker run -d -p 8080:8080 --name fuel-tracker fuel-tracker:1.1.0
# (Jenkins uses Dockerfile.ci instead, which packages the WAR it already tested.)
# ---------------------------------------------------------------------------

# ---- stage 1: build ----------------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /src
# dependencies first so they're cached between code changes
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
RUN mvn -B -q -DskipTests -DskipITs package

# ---- stage 2: runtime --------------------------------------------------------
FROM eclipse-temurin:17-jre-jammy

LABEL org.opencontainers.image.title="Vehicle Fuel Expense Tracker" \
      org.opencontainers.image.source="https://github.com/<your-user>/vehicle-fuel-expense-tracker"

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app && useradd --system --uid 10001 --gid app --home /app app \
    && mkdir -p /app/data && chown -R app:app /app

WORKDIR /app
COPY --from=build --chown=app:app /src/target/fuel-tracker.war /app/app.war

USER app
ENV APP_ENV=docker \
    DB_URL=jdbc:h2:file:/app/data/fueltracker \
    JAVA_OPTS="-Xms128m -Xmx384m"
EXPOSE 8080
VOLUME /app/data

HEALTHCHECK --interval=15s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -fs http://localhost:8080/actuator/health | grep -q '"status":"UP"' || exit 1

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.war"]
