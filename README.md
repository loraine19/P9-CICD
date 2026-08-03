<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM — Chaîne CI/CD (Option B)

[![CI](https://github.com/loraine19/p9-cicd/actions/workflows/ci.yml/badge.svg)](https://github.com/loraine19/p9-cicd/actions/workflows/ci.yml)
[![Nightly](https://github.com/loraine19/p9-cicd/actions/workflows/nightly.yml/badge.svg)](https://github.com/loraine19/p9-cicd/actions/workflows/nightly.yml)

Industrialisation de la chaîne d'intégration et de déploiement continus de
**MicroCRM**, l'application interne d'Orion : un CRM simplifié bâti sur
**Spring Boot 3** (API) et **Angular 17** (client).

Ce dépôt contient les workflows GitHub Actions, les Dockerfiles, l'orchestration
Docker Compose et la configuration d'analyse SonarQube Cloud. La documentation
technique détaillée se trouve dans [`OPCR/documentation.md`](./OPCR/documentation.md).

---

## Sommaire

- [Architecture du dépôt](#architecture-du-dépôt)
- [Démarrage rapide](#démarrage-rapide)
- [Développement local](#développement-local)
- [Tests](#tests)
- [La chaîne CI/CD](#la-chaîne-cicd)
- [Conteneurisation](#conteneurisation)
- [Publier une version](#publier-une-version)
- [Configuration requise du dépôt](#configuration-requise-du-dépôt)
- [Choix techniques](#choix-techniques)

---

## Architecture du dépôt

```
.
├── .github/
│   ├── workflows/
│   │   ├── ci.yml          Build, tests, Sonar, images, scan   (push / PR)
│   │   ├── release.yml     Publication images + release GitHub (tag vX.Y.Z)
│   │   └── nightly.yml     Non-régression + veille sécurité    (planifié)
│   └── dependabot.yml      Mises à jour automatisées des dépendances
├── back/                   API Spring Boot 3.2.5 — Java 17, Gradle 8.7
├── front/                  Client Angular 17 — npm, Karma/Jasmine
├── misc/docker/            Configuration Caddy du conteneur front
├── OPCR/                   Documentation technique et livrables
├── Dockerfile              Build multi-stage (cibles `front` et `back`)
├── docker-compose.yml      Orchestration locale
└── sonar-project.properties
```

> **Note** — le back-end est construit avec **Gradle** (et non Maven) : le dépôt
> fourni embarque un wrapper Gradle 8.7. La chaîne CI/CD a été alignée sur cet
> outillage existant plutôt que de migrer le projet.

---

## Démarrage rapide

Prérequis : **Docker** et **Docker Compose v2**.

```bash
docker compose up --build
```

| Service   | URL                   |
| --------- | --------------------- |
| Front-end | http://localhost:4200 |
| API       | http://localhost:8080 |

Le front n'est démarré qu'une fois l'API déclarée saine (`healthcheck`).
Pour arrêter : `docker compose down`.

### Utiliser les images publiées

```bash
TAG=v1.0.0 REGISTRY=ghcr.io/loraine19 docker compose up
```

---

## Développement local

Prérequis : **JDK 17** (voir avertissement ci-dessous), **Node.js 22**, **npm ≥ 10**.

> ⚠️ **Le JDK doit être en version 17 ou 21, pas au-delà.** Le projet utilise le
> wrapper Gradle 8.7, qui ne supporte pas Java 22+. Avec un JDK plus récent
> (Java 25 par ex.), le build échoue avec `Unsupported class file major version`.
> Si `java -version` affiche autre chose que 17/21, installez et ciblez un JDK 17 :
>
> ```bash
> # Debian / Ubuntu / ChromeOS (Crostini)
> sudo apt update && sudo apt install -y openjdk-17-jdk
> export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64   # adaptez via `ls /usr/lib/jvm/`
> ```

<details>
<summary><strong>Back-end</strong></summary>

```bash
cd back
chmod +x gradlew           # une seule fois : le wrapper doit être exécutable
./gradlew bootRun          # démarre l'API sur http://localhost:8080
./gradlew bootJar          # produit build/libs/microcrm-0.0.1-SNAPSHOT.jar
```

</details>

<details>
<summary><strong>Front-end</strong></summary>

```bash
cd front
npm ci                     # installation déterministe depuis le lockfile
npm start                  # serveur de développement sur http://localhost:4200
npm run build              # bundle de production dans dist/microcrm/browser
```

</details>

---

## Tests

| Commande                     | Où elle est définie               | Ce qu'elle fait                         | Quand elle s'exécute           |
| ---------------------------- | --------------------------------- | --------------------------------------- | ------------------------------ |
| `./gradlew build`            | `back/build.gradle`               | Compile et lance les tests JUnit 5      | CI (push/PR), nightly, release |
| `./gradlew jacocoTestReport` | `back/build.gradle`               | Produit le XML de couverture pour Sonar | CI, nightly                    |
| `npm test`                   | `front/package.json` → `ng test`  | Lance les specs Jasmine dans Karma      | CI (push/PR), nightly, release |
| `npm run build`              | `front/package.json` → `ng build` | Bundle de production                    | CI, release                    |

En local :

```bash
# Back-end (JDK 17 requis, cf. section précédente)
cd back && ./gradlew test
```

```bash
# Front-end — un navigateur Chrome/Chromium doit être installé.
# `ng test` seul tente de lancer Chrome en fenêtré et échoue en headless :
# utilisez toujours le launcher ChromeHeadlessNoSandbox.
sudo apt install -y chromium            # si aucun Chrome n'est installé
export CHROME_BIN=$(which chromium)
cd front && npm test -- --watch=false --browsers=ChromeHeadlessNoSandbox
```

> Erreur `No binary for Chrome browser on your platform` → la variable
> `CHROME_BIN` n'est pas définie ou aucun navigateur n'est installé.

En CI, ces prérequis sont déjà satisfaits : le runner `ubuntu-latest` embarque
Chromium et le JDK est fixé à 17. Le launcher `ChromeHeadlessNoSandbox` est
défini dans `karma.conf.js`.

```bash
npm test -- --watch=false --browsers=ChromeHeadlessNoSandbox --code-coverage
```

### Vulnérabilités npm

`npm ci` signale ~85 vulnérabilités : **~77 sont dans l'outillage de build**
(webpack, karma…) qui **n'est jamais déployé**. Seules **8** concernent le code
livré (production), toutes dans Angular 17 lui-même.

- **Ne pas exécuter `npm audit fix --force`** : cela casse Angular.
- Vérifier ce qui touche réellement la production : `npm audit --omit=dev`.
- La correction de fond (montée d'Angular) est hors périmètre de la mission et
  suivie par Dependabot + SonarCloud (cf. plan de sécurité, documentation §5).

---

## La chaîne CI/CD

### `ci.yml` — intégration continue

Déclenché sur `push` (`main`, `develop`), sur `pull_request` et manuellement.

```
        ┌──────────┐   ┌──────────┐
        │   back   │   │  front   │      builds + tests en parallèle
        └────┬─────┘   └────┬─────┘
             └───────┬──────┘
              ┌──────┴───────┐
        ┌─────┴─────┐  ┌─────┴──────┐
        │   sonar   │  │   docker   │   analyse qualité / build + smoke test
        └───────────┘  └─────┬──────┘
                             │
                       ┌─────┴─────┐
                       │   scan    │   vulnérabilités des images (Trivy)
                       └───────────┘
```

Les jobs `back` et `front` sont indépendants : ils s'exécutent en parallèle pour
réduire le temps de retour au développeur. `sonar` et `docker` attendent leurs
artefacts.

Le job `docker` ne se contente pas de construire les images : il les **démarre**
et vérifie que l'API répond sur `/persons` et que le front sert bien l'application.

### `nightly.yml` — testing périodique

Planifié du lundi au vendredi à 03h00 UTC. Rejoue l'intégralité des tests,
démarre la stack complète via `docker compose` et scanne les dépendances.
Objectif : détecter les régressions liées à l'environnement (nouvelles CVE,
dérive des images de base) et non au code.

### `release.yml` — déploiement continu

Déclenché par un tag SemVer. Rejoue les tests, publie les images sur GHCR et
crée la release GitHub avec les artefacts.

---

## Conteneurisation

`Dockerfile` est un build multi-stage à deux cibles :

| Cible   | Image de base                   | Contenu                        | Port |
| ------- | ------------------------------- | ------------------------------ | ---- |
| `front` | `caddy:2-alpine`                | Bundle Angular servi par Caddy | 80   |
| `back`  | `eclipse-temurin:17-jre-alpine` | JAR Spring Boot                | 8080 |

```bash
docker build --target back  -t microcrm-back:local  .
docker build --target front -t microcrm-front:local .
```

Principes appliqués :

- **images officielles, minimales et versionnées** — jamais de tag `latest` ;
- **séparation build / runtime** — ni JDK ni `node_modules` dans l'image finale ;
- **utilisateur non privilégié** pour le back-end ;
- **un processus par conteneur** — l'orchestration est le rôle de Compose ;
- **healthchecks** exploités par `depends_on: condition: service_healthy`.

---

## Publier une version

Le versionnement suit **SemVer** (`MAJOR.MINOR.PATCH`). La mise en production
est une décision humaine explicite : elle est déclenchée par la pose d'un tag.

```bash
git tag -a v1.0.0 -m "Première version stable"
git push origin v1.0.0
```

Le workflow produit alors :

- les images `ghcr.io/loraine19/p9-cicd-back` et `-front`, taguées `1.0.0`, `1.0` et `latest` ;
- une release GitHub contenant le JAR, le bundle Angular zippé et les sommes SHA-256 ;
- un changelog généré à partir des pull requests fusionnées.

Une pré-version (`v1.0.0-rc.1`) est automatiquement marquée _pre-release_ et ne
reçoit pas le tag `latest`.

---

## Configuration requise du dépôt

Avant la première exécution complète de la CI :

1. **SonarQube Cloud** — créer le projet sur [sonarcloud.io](https://sonarcloud.io),
   puis reporter `sonar.projectKey` et `sonar.organization` dans
   `sonar-project.properties`.
2. **Secret `SONAR_TOKEN`** — _Settings → Secrets and variables → Actions →
   New repository secret_. Aucun secret n'est stocké dans le dépôt : les
   workflows les lisent exclusivement via `${{ secrets.* }}`.
3. **GHCR** — aucune configuration : les workflows s'authentifient avec le
   `GITHUB_TOKEN` éphémère du job.
4. **Permissions** — _Settings → Actions → General_ : autoriser la lecture et
   l'écriture pour le workflow de release.

---

## Choix techniques

| Décision                       | Justification                                                                                       |
| ------------------------------ | --------------------------------------------------------------------------------------------------- |
| **GitHub Actions**             | Natif au dépôt, aucun serveur à maintenir, secrets et registre intégrés.                            |
| **Gradle conservé**            | Le projet embarque un wrapper Gradle 8.7 ; migrer vers Maven aurait ajouté un risque sans bénéfice. |
| **Jobs parallèles**            | Le retour d'erreur au développeur est donné par le composant le plus rapide.                        |
| **`npm ci` / wrapper Gradle**  | Builds reproductibles : versions figées par le lockfile et le wrapper.                              |
| **GHCR plutôt que Docker Hub** | Authentification par `GITHUB_TOKEN`, pas de compte ni de secret externe à gérer.                    |
| **Release sur tag**            | Sépare l'intégration continue (automatique) de la livraison (décision humaine tracée).              |
| **Trivy**                      | Équivalent libre et maintenu de Twistlock, s'intègre nativement à GitHub Security.                  |
| **Dependabot**                 | Les montées de version arrivent en PR et sont validées par la CI avant fusion.                      |

---

## Captures d'écran

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)
