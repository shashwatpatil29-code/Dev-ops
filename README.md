# FuelLog — Vehicle Fuel Expense Tracker

Small fleets (a few delivery vans, a pickup, a car or two) usually track fuel in a WhatsApp group
and a notebook. Nobody notices that one vehicle's mileage has quietly dropped 30 %, that a driver
"filled" 71 litres into a 60-litre tank, or that a receipt has a lower odometer than last week's.

FuelLog is a small web app that records every fill, works out spend and mileage per vehicle,
and **flags the fills that don't add up**. Around it is a full DevOps pipeline: Git branching,
Jenkins CI with a Selenium gate, Docker images in a registry, automatic deploys, and an Ansible
playbook that builds a server from scratch and rolls back a bad release on its own.

![Dashboard](docs/images/dashboard.png)

---

## Run it (pick one)

**1 · Docker only (nothing else to install)**
```bash
docker compose up -d --build
# → http://localhost:8080
```

**2 · Java 17+**
```bash
./mvnw spring-boot:run            # Windows: mvnw.cmd spring-boot:run
# or build the WAR and run it
./mvnw clean package && java -jar target/fuel-tracker.war
```

**3 · External Tomcat 10.1** – copy `target/fuel-tracker.war` into `webapps/` → `http://localhost:8080/fuel-tracker`

The app starts with a demo fleet of five Mumbai vehicles and ~110 fills (with a few planted
problems so the alert view isn't empty). Set `SEED_DEMO_DATA=false` to start empty.

**Tests**
```bash
./mvnw test       # 18 unit / API tests
./mvnw verify     # + 5 Selenium user journeys (HtmlUnit, no browser needed)
./mvnw verify -Dbrowser=chrome   # same journeys in headless Chrome
```

---

## What it does

| | |
|---|---|
| **Log a fill** | date, odometer, litres, ₹/L, station, full-tank flag → total is calculated; impossible values are rejected with a message next to the field |
| **Searchable dashboard** | free-text (reg. no., vehicle, station, notes) + vehicle + date range. The indicator tiles recompute for whatever is filtered |
| **Summary indicators** | total spend, this month, average km/L (full-tank to full-tank), fuel cost per km, open/critical alerts |
| **Status drill-down** | each vehicle gets OK / Warning / Critical / No data; its page shows *why*, a spend chart, and the full history with per-fill km/L |
| **Alert / exception view** | 5 rules – odometer rollback, tank overfill (critical); price spike, mileage drop, long gap between fills (warning) |
| **REST API** | everything above as JSON under `/api`, plus `/actuator/health` |

![Vehicle drill-down](docs/images/vehicle-detail.png)

---

## DevOps pipeline at a glance

```
 git push ─▶ Jenkins (poll SCM)
              ├─ checkout, read version from pom
              ├─ ./mvnw package ............. compile + 18 unit/API tests
              ├─ Selenium (5 journeys) ...... any failure stops here – nothing gets deployed
              ├─ archive fuel-tracker.war
              ├─ docker build  → localhost:5000/fuel-tracker:1.1.0-<build>
              ├─ docker push   → private registry (or Docker Hub)
              ├─ deploy container fuel-tracker-<env>   (APP_ENV = dev | qa | prod)
              ├─ smoke test /actuator/health  → auto-restore previous image if unhealthy
              └─ Selenium again, against the deployed container

 Ansible ─▶ clean Ubuntu node: packages, user, folders, config, Docker, Nginx, firewall
            deploy release N → health check → (fail?) → restore release N-1
            re-run → changed=0 (idempotent)
```

Bring up the whole CI/CD lab (Jenkins + registry + Tomcat) with one command:

```bash
cd infra/jenkins && docker compose up -d --build
# Jenkins → http://localhost:8088  (admin / admin), jobs are pre-created
```

---

## Repository map → assignment tasks

| # | Task | Where |
|---|---|---|
| 1 | Problem definition & scope | [docs/01-problem-definition.md](docs/01-problem-definition.md) |
| 2 | Agile plan, backlog, DoD, DevOps lifecycle | [docs/02-agile-plan.md](docs/02-agile-plan.md) |
| 3 | SRS, use cases, architecture, data model, API | [docs/03-srs-architecture.md](docs/03-srs-architecture.md) |
| 4 | Git / GitHub repo, templates, branch policy | [docs/04-git-repository.md](docs/04-git-repository.md), [CONTRIBUTING.md](CONTRIBUTING.md), [.github/](.github) |
| 5 | Feature branch → PR → merge | [docs/05-feature-branch-pr.md](docs/05-feature-branch-pr.md) |
| 6 | MVP, merge conflict, tag | [docs/06-mvp-conflict-tag.md](docs/06-mvp-conflict-tag.md) |
| 7 | Jenkins CI job | [docs/07-jenkins-ci-job.md](docs/07-jenkins-ci-job.md), [infra/jenkins/](infra/jenkins) |
| 8 | Jenkinsfile + Tomcat/Docker deploy | [Jenkinsfile](Jenkinsfile), [docs/08-pipeline-deploy.md](docs/08-pipeline-deploy.md) |
| 9 | Selenium tests | [src/test/java/com/fueltracker/ui](src/test/java/com/fueltracker/ui), [docs/09-selenium-test-plan.md](docs/09-selenium-test-plan.md) |
| 10 | Continuous testing, defect fix | [docs/10-continuous-testing.md](docs/10-continuous-testing.md) |
| 11 | Dockerfile & container lifecycle | [Dockerfile](Dockerfile), [docs/11-docker.md](docs/11-docker.md) |
| 12 | Jenkins → Docker continuous deployment | [docs/12-jenkins-docker-cd.md](docs/12-jenkins-docker-cd.md) |
| 13 | Ansible configuration management | [infra/ansible/](infra/ansible), [docs/13-configuration-management.md](docs/13-configuration-management.md) |
| 14 | Provisioning, idempotency, rollback | [docs/14-provisioning-reliability.md](docs/14-provisioning-reliability.md) |

Raw logs from real runs (build, Docker lifecycle, Jenkins console, Ansible) are in [evidence/](evidence).

## Tech

Java 17 · Spring Boot 3.5 (MVC, Thymeleaf, Data JPA, Validation, Actuator) · H2 (file) ·
Maven (wrapper included) · JUnit 5 · Selenium 4 · Jenkins · Docker · Nginx · Tomcat 10.1 · Ansible

## Configuration

| Env var | Default | |
|---|---|---|
| `APP_ENV` | `dev` | shown in the footer and `/api/info`; Jenkins passes dev/qa/prod |
| `PORT` | `8080` | |
| `DB_URL` | `jdbc:h2:file:./data/fueltracker` | any JDBC URL |
| `MAX_PRICE_PER_LITRE` | `115` | price-spike alert threshold (₹) |
| `SEED_DEMO_DATA` | `true` | load the demo fleet on an empty DB |
