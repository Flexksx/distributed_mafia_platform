# distributed_applications_labs

The Mafia Game Platform now runs as a service-discovered mesh behind a slim API Gateway and a Message Broker. The gateway only handles user authentication and edge caching; all service-to-service calls (commands, events, fan-out) now flow through the Message Broker, which owns load balancing, circuit breaking, durable queues, DLQ, and gRPC delivery. Each service is containerized, owns its database, and registers with Service Discovery so both the gateway and the broker can route requests to healthy instances. Redis backs the gateway cache; each service has its own Postgres instance (or Mongo for document-first services).

Active services in the 2025 compose stack:

* **API Gateway** – Entry point for clients; enforces auth and caches responses in Redis. No business routes exposed for internal-only traffic.
* **Message Broker** – HTTP ingress + gRPC delivery for service-to-service commands and events. Owns LB, circuit breaking, DLQ, and 2PC.
* **Service Discovery** – Tracks service heartbeats, load, and health, and returns routable instances to the gateway.
* **User Management Service** – Single source of truth for player identity and in‑game currency.
* **Game Service** – Orchestrates lobbies, player state, and day/night cycles.
* **Shop Service** – Item catalog, purchases, inventory, and protection effects.
* **Roleplay Service** – Role definitions, assignments, actions, and announcements.
* **Task Service** – Role-based tasks and rewards.
* **Voting Service** – Evening exile votes with idempotency and tie-breaking logic.
* **Character Service** – Avatars and cosmetics.
* **Town Service** – Tracks player movement across locations.
* **Monitoring Stack** – Prometheus + Grafana shipped alongside the compose file.
* **Message Broker** – Redis-backed broker for pub/sub and request-reply (see `message_broker/`).

Together, these services compose a cohesive ecosystem where independent scaling, fault isolation, and clear domain boundaries make the platform robust, extensible, and ready for experimentation with service discovery, event-driven flows, and eventual consistency.

## Platform Architecture (May 2025)

```mermaid
flowchart LR
    Clients -->|REST/JSON| Gateway
    Gateway -->|auth + cache| RedisCache
    Gateway -->|commands/events| MessageBroker
    MessageBroker -->|gRPC| UserService
    MessageBroker -->|gRPC| GameService
    MessageBroker -->|gRPC| TaskService
    MessageBroker -->|gRPC| VotingService
    MessageBroker -->|gRPC| ShopService
    MessageBroker -->|gRPC| RoleplayService
    MessageBroker -->|gRPC| CharacterService
    MessageBroker -->|gRPC| TownService
    MessageBroker -->|topics| TopicQueues
    Gateway -->|instance lookup| ServiceDiscovery
    MessageBroker -->|instance lookup| ServiceDiscovery
    ServiceDiscovery --> UserService
    ServiceDiscovery --> GameService
    ServiceDiscovery --> TaskService
    ServiceDiscovery --> VotingService
    ServiceDiscovery --> ShopService
    ServiceDiscovery --> RoleplayService
    ServiceDiscovery --> CharacterService
    ServiceDiscovery --> TownService

    subgraph Observability
        Prometheus --> Grafana
    end

    subgraph Storage["Per-service storage"]
        PG1[(Postgres: user)]
        PG2[(Postgres: game)]
        PG3[(Postgres: tasks)]
        PG4[(Postgres: voting)]
        PG5[(Postgres: shop)]
        PG6[(Postgres: roleplay)]
        PG7[(Postgres: character)]
        PG8[(Postgres: town)]
    end

    UserService --> PG1
    GameService --> PG2
    TaskService --> PG3
    VotingService --> PG4
    ShopService --> PG5
    RoleplayService --> PG6
    CharacterService --> PG7
    TownService --> PG8
```

### Service inventory (from `docker-compose.yml`)

| Service | Port (env-driven) | Data store | Notes |
| --- | --- | --- | --- |
| API Gateway | `${GATEWAY_PORT}` | Redis edge cache `gateway-cache` | Auth + caching only; all S2S flows use Message Broker |
| Message Broker | `3005/8002 (HTTP)` `50051 (gRPC)` | Redis + SQLite | LB, circuit breaker, DLQ, 2PC, topic + per-subscriber queues |
| Service Discovery | `${SERVICE_DISCOVERY_PORT}` | In-memory registry | Health checks + load reporting |
| User Management | `${USER_SERVICE_PORT}` | Postgres `user-management-db` | Identity + currency |
| Game Service | `${GAME_SERVICE_PORT}` | Postgres `game-service-db` | Lobbies + cycles |
| Task Service | `${TASK_SERVICE_PORT}` | Postgres `task-service-db` | Tasks + rewards |
| Voting Service | `${VOTING_SERVICE_PORT}` | Postgres `voting-service-db` | Votes + tie-breakers |
| Shop Service | `${SHOP_SERVICE_PORT}` | Postgres `shop-service-db` | Catalog + purchases + inventory |
| Roleplay Service | `${ROLEPLAY_SERVICE_PORT}` | Postgres `roleplay-service-db` | Roles, actions, announcements |
| Character Service | `${CHARACTER_SERVICE_PORT}` | Postgres `character-service-db` | Avatars/cosmetics |
| Town Service | `${TOWN_SERVICE_PORT}` | Postgres `town-service-db` | Player locations |
| Monitoring | `${PROMETHEUS_PORT}`, `${GRAFANA_PORT}` | Prometheus TSDB | Pre-provisioned dashboards |

## Message Broker endpoints (HTTP ingress → gRPC delivery)

All services register with Service Discovery and include their subscribed topics during registration. Gateway-to-service requests and service-to-service events now use these broker endpoints:

**Command (Gateway/Service → Broker → gRPC target)**
- `POST /broker/command/execute`
  ```json
  {
    "destinationService": "shop-service",
    "method": "GET",
    "path": "/api/v1/items",
    "payload": { "page": 0, "size": 10 },
    "timeout_seconds": 30
  }
  ```
  Response:
  ```json
  { "status_code": 200, "body": { "message": "{...service response...}", "success": true } }
  ```

**Event publish (Service → Broker → Topic queues)**
- `POST /broker/event/publish`
  ```json
  {
    "topic": "GAME_STARTED",
    "payload": { "game_id": "123", "player_count": 8 },
    "priority": "high"
  }
  ```
  Response includes per-subscriber delivery results.

**Poll events (Service pulls topic messages)**
- `POST /broker/events/poll`
  ```json
  { "serviceName": "roleplay-service", "topics": ["GAME_STARTED"], "maxEvents": 10 }
  ```

**DLQ inspection**
- `GET /broker/dlq?queue=queue:shop-service&limit=10`

**Topics catalogue**
- `GET /topics` → lists topics and subscribers registered in Service Discovery.

**2PC (distributed transaction coordination)**
- `POST /api/v1/2pc/transaction/start`
  ```json
  {
    "transaction_id": "txn-uuid-12345",
    "participants": ["order-service", "payment-service"],
    "operation": "create_order",
    "payload": { "orderId": "12345", "total": 130.00 }
  }
  ```
- `GET /api/v1/2pc/transaction/{transaction_id}/status`

**gRPC delivery contract (services implement)**
```protobuf
service ServiceHandler {
  rpc DeliverMessage(MessageRequest) returns (MessageResponse);
}
```

## New endpoints & DTOs (latest microservice updates)

**Shop Service (`shop-service`, Spring Boot)**
- `GET /api/v1/items/allAvailable` – list in-stock items.
- `GET /api/v1/items/{itemId}` – item detail.
- `POST /api/v1/items` – create item. DTO:
  ```json
  {
    "name": "Vampire Ward",
    "description": "Protects the user from vampire attacks for one night",
    "price": 150.0,
    "category": "PROTECTION",
    "availableQuantity": 10,
    "maxDailyQuantity": 3,
    "replenishRate": 1,
    "imageUrl": "https://example.com/vampire-ward.png",
    "usageInstructions": "Use before nightfall. Effect lasts for one night cycle."
  }
  ```
- `PUT /api/v1/items/{itemId}` – update item (same DTO as create).
- `DELETE /api/v1/items/{itemId}` – remove item.
- `POST /api/v1/purchases` – purchase items. DTO:
  ```json
  {
    "userId": "user1",
    "gameId": "game123",
    "gameDay": 1,
    "items": [{ "itemId": "5319e0d8-a51a-4da4-ae79-56a58ee4460d", "quantity": 1 }]
  }
  ```
- `GET /api/v1/inventory/{userId}?gameId={gameId}` – view inventory for a game context.
- `POST /api/v1/inventory/{userId}/use` – consume an item. DTO:
  ```json
  {
    "gameId": "game123",
    "gameDay": 1,
    "gameCycle": "NIGHT",
    "inventoryItemId": "b43b461f-5023-4972-babb-b28f7b813118",
    "targetUserId": "string"
  }
  ```

**Roleplay Service (`roleplay-service`, Spring Boot)**
- `GET /api/v1/roles` – list available roles.
- `POST /api/v1/roles` – create role. DTO:
  ```json
  { "name": "Mafia", "description": "Eliminate town", "alignment": "TOWN" }
  ```
- `GET /api/v1/player-roles/user/{userId}/game/{gameId}` – fetch user role in a game.
- `POST /api/v1/player-roles` – assign role to player. DTO:
  ```json
  {
    "userId": "player123533",
    "gameId": "game456",
    "roleId": "role-id",
    "roleName": "Doctor",
    "alignment": "TOWN",
    "alive": true
  }
  ```
- `POST /api/v1/actions` – submit role action. DTO:
  ```json
  {
    "gameId": "game456",
    "userId": "player1233",
    "roleName": "Doctor",
    "actionType": "HEAL",
    "targets": ["targetPlayer789"],
    "gamePhase": "NIGHT"
  }
  ```
- `GET /api/v1/actions/history?gameId={gameId}` – action history for game.
- `GET /api/v1/actions/results?gameId={gameId}&userId={userId}&phase={DAY|NIGHT}` – resolved outcomes for a player/phase.
- `POST /api/v1/announcements` – broadcast message for a game. DTO:
  ```json
  {
    "gameId": "game456",
    "message": "A player has been eliminated!",
    "visibleTo": ["ALL"],
    "phase": "NIGHT"
  }
  ```

## User Management Service

**Dockerhub link** <https://hub.docker.com/repository/docker/flexksx/mafia_user_management_service/general>

* **Core responsibility:** Single user profile (email, username, hashed password) + in‑game currency balance.
* Track simple profiling info: device fingerprints and last known IP/location to discourage duplicate accounts.
* Keep it minimal; no government/passport style identification.

### Tech stack

* **Framework/language:** Express.js + TypeScript (fast iteration, typing)
* **Database:** PostgreSQL (transactions for currency updates). Prisma ORM is used for easy data manipulation.
* **Communication pattern:** For external communication it exposes a REST API, for internal communication it uses a persisted db connection exposed by the Prisma APIs.

### Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph subGraph0["Mafia Application"]
        B("User Management Service <br> Express.js + TypeScript")
        A["Client / Other Services"]
  end
 subgraph subGraph2["Data Persistence"]
        D[("PostgreSQL Database")]
  end
    A -- HTTP/REST API Call --> B
    B -- JSON Response --> A
    B -- Reads/Writes user data (name, email, password) --> D
    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
```

### Schema

Entities exposed by the rest API

```typescript
interface User {
    id: string;
    email: string;        // unique
    username: string;     // unique
    passwordHash: string; // not exposed
    transactions: CurrencyTransaction[];
    devices: Device[];
    accessEvents: UserAccessEvent[];
    updatedAt: string;
    createdAt: string;
}

enum DevicePlatform {
    WEB,
    ANDROID,
    IOS,
    DESKTOP
}

interface Device {
    id: string;
    userId: string;
    fingerprint: string;  // stable hash
    platform: DevicePlatform;
    lastSeenAt: string;
}

enum TransactionType {
    ADD,
    SUBTRACT
}

interface CurrencyTransaction {
    id: string;
    userId: string;
    transactionType: TransactionType; 
    amount: number;
    reason?: string;
    createdAt: string;
}

interface UserAccessEvent { 
    id: string;
    seenAt: Date;
    userId: string;
    deviceId?: string;
    ip?: string;
    country?: string;
}
```

### Endpoints

User-centric REST API for user management, currency transactions, device tracking, and access event monitoring. All endpoints are organized around users as the primary resource.

### User Endpoints

### `GET /v1/users/{id}` – Retrieve user by ID

Returns a user DAO

```typescript
interface UserDao {
    id: string;
    email: string;
    username: string;
    updatedAt: string;
    createdAt: string;
}
```

### `GET /v1/users` - List users with optional filters

**Query Params:**

* `email` - string, query by email
* `emails` - array of strings, query by multiple emails
* `limit` - number, pagination limit
* `offset` - number, pagination offset

Returns an array of `UserDao`.

### `POST /v1/users` – Create user

**Request Body:**

```json
{
    "email": "user@example.com",
    "username": "playerOne",
    "password": "plaintext_password"
}
```

**Responses:** 201 (Created) | 400 (Missing required fields)

### `PUT /v1/users/{id}` – Update user

**Request Body:**

```json
{
    "email": "newemail@example.com",
    "username": "newUsername", 
    "password": "newPassword"
}
```

At least one field must be provided.

**Responses:** 200 (OK) | 400 (Validation error) | 404 (User not found)

### `DELETE /v1/users/{id}` – Delete user

**Responses:** 200 (OK) | 404 (User not found)

### `GET /v1/users/{id}/balance` – Get user's currency balance

Returns detailed balance information:

```typescript
interface UserBalance {
    userId: string;
    balance: number;
    totalTransactions: number;
    totalAdd: number;
    totalSubtract: number;
}
```

### User Device Endpoints

### `GET /v1/users/{id}/devices` – List devices for a user

**Query Params:**

* `limit` - number, pagination limit
* `offset` - number, pagination offset

### User Transaction Endpoints

### `GET /v1/users/{id}/transactions` – List transactions for a user

**Query Params:**

* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/users/{id}/transactions` – Create transaction for a user

**Request Body:**

```json
{
    "amount": 500,
    "type": "ADD",
    "reason": "REWARD"
}
```

**Responses:** 201 (Created) | 400 (Missing required fields: amount and type) | 404 (User not found)

### User Access Event Endpoints

### `GET /v1/users/{id}/access-events` – List access events for a user

**Query Params:**

* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/users/{id}/access-events` – Create access event for a user

**Request Body:**

```json
{
    "ipAddress": "192.168.1.1",
    "country": "US",
    "platform": "WEB",
    "fingerprint": "optional-device-fingerprint"
}
```

Required fields: `ipAddress`, `country`, `platform`
Optional fields: `fingerprint`

**Responses:** 201 (Created) | 400 (Missing required fields: ipAddress, country, and platform) | 404 (User not found)

### API Documentation

Interactive API documentation is available at `/docs` when the service is running. The OpenAPI specification can be accessed at `/docs.json`.

### Dependencies

* PostgreSQL DB Container
* Password hashing lib (argon2/bcrypt)
* (Optional later) Message broker for events


## Game service

* **Core responsibility:** Main gameplay logic. Should handle lobbies of up to 30 players, track player state (alive/dead, role, career) and orchestrate the Day/Night cycle.
Should send notifications about events/announcements (kill, heal, rumor, visit, exile).
Initiates and manages the voting process before announcing exiles.

### Tech stack

* **Framework/language:** Express.js + TypeScript (consistent with other services and fast prototyping)
* **Databse:** PostgreSQL (data persistence, versatile DB)
* **Other:** Event/Notification mechanism via REST and WebSockets (consider upgrade to message brokers).
* **Communication pattern:** Internal REST API

### Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph subGraph0["Mafia Application"]
        B("Game Service <br> Express.js + TypeScript")
        A["Client / Other Services (e.g. Town Service, User Service)"]
  end
 subgraph subGraph2["Data Persistence"]
        D[("PostgreSQL Database")]
  end
    A -- HTTP/REST API Calls --> B
    B -- JSON Responses / Notifications --> A
    B -- Reads/Writes game/lobby data --> D
    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
```

### Schema

describe participating models and their schemas e.g.

```typescript
interface Lobby {
    id: string;
    name: string;
    players: Player[];
    dayNightCycle: CycleState;
    createdAt: string;
    updatedAt: string;
}

interface Player {
    id: string;
    userId: string;    // link to User Service
    lobbyId: string;
    role: Role;
    career: Career;
    isAlive: boolean;
    joinedAt: string;
}

enum Role {
    MAFIA,
    DOCTOR,
    DETECTIVE,
    VILLAGER
    // extendable
}

enum Career {
    LAWYER,
    JOURNALIST,
    MERCHANT,
    SOLDIER
    // flavor / abilities in future
}

enum CycleState {
    DAY,
    NIGHT
}

interface GameEvent {
    id: string;
    lobbyId: string;
    type: EventType;
    description: string;
    createdAt: string;
}

enum EventType {
    KILL,
    HEAL,
    RUMOR,
    VISIT,
    EXILE,
    ANNOUNCEMENT
}

interface Vote {
    id: string;
    lobbyId: string;
    voterPlayerId: string;
    targetPlayerId?: string; // optional (abstain)
    createdAt: string;
}
```

### REST API Endpoints

All endpoints are prefixed with `/v1/lobby`

#### Lobby Management

##### `GET /v1/lobby` – List lobbies

Query parameters:

* `status` (optional): Filter by lobby status (`OPEN`, `IN_GAME`, `CLOSED`)
* `maxPlayers` (optional): Filter by maximum player count
* `limit` (optional): Number of results to return
* `offset` (optional): Number of results to skip

Response: Array of lobby objects

##### `GET /v1/lobby/:lobbyId` – Get lobby details

Response: Lobby object with current status and player information

##### `POST /v1/lobby` – Create new lobby

Request body:

```json
{
  "name": "Shadow Manor",
  "maxPlayers": 10
}
```

Response: Created lobby object (201)

##### `DELETE /v1/lobby/:lobbyId` – Delete lobby

Response: Success confirmation

#### Game State Management

##### `POST /v1/lobby/:lobbyId/start` – Start game

Starts the game if lobby has minimum required players (3+)
Response: Updated lobby object with game started

##### `POST /v1/lobby/:lobbyId/end` – End game

Ends the current active game
Response: Updated lobby object with game ended

##### `POST /v1/lobby/:lobbyId/cycle` – Switch time cycle

Request body:

```json
{
  "cycle": "DAY"
}
```

Valid cycles: `DAY`, `NIGHT`
Response: Updated lobby object with new cycle

#### Player Management

##### `GET /v1/lobby/:lobbyId/players` – List lobby players

Response: Array of active players in the lobby

##### `POST /v1/lobby/:lobbyId/players` – Join lobby

Request body:

```json
{
  "userId": "user-123",
  "role": "CIVILIAN",
  "career": "Detective"
}
```

Valid roles: `CIVILIAN`, `MAFIA`, `SHERIFF`, `DOCTOR`
Response: Created player object (201)

##### `DELETE /v1/lobby/:lobbyId/players/:userId` – Leave lobby

Response: Success confirmation

#### Player Game Actions

##### `POST /v1/lobby/:lobbyId/players/:userId/kill` – Kill player

Marks player as dead during active game
Response: Updated player object

##### `POST /v1/lobby/:lobbyId/players/:userId/heal` – Heal player

Heals a killed player (doctor action)
Response: Updated player object

##### `POST /v1/lobby/:lobbyId/players/:userId/imprison` – Imprison player

Temporarily imprisons player (sheriff action)
Response: Success confirmation

##### `POST /v1/lobby/:lobbyId/players/:userId/kick` – Kick player

Removes player from lobby (moderator action)
Response: Updated player object

##### `POST /v1/lobby/:lobbyId/players/:userId/ban` – Ban player

Permanently bans player from lobby
Response: Updated player object

#### Voting System

##### `POST /v1/lobby/:lobbyId/vote` – Cast or update vote

Request body:

```json
{
  "voterId": "user-123",
  "targetId": "user-456"
}
```

Response: Vote details with success message

* Creates new vote if player hasn't voted in current cycle
* Updates existing vote if player changes their vote
* Validates that both voter and target are active players
* Ensures game is in active state

#### Response Formats

**Lobby Object:**

```json
{
  "id": "clx1234567890",
  "name": "Shadow Manor",
  "status": "IN_GAME",
  "currentTimeCycle": "DAY",
  "cycleNumber": 3,
  "maxPlayers": 10,
  "gameStartTime": "2025-09-22T10:00:00Z",
  "gameEndTime": null,
  "createdAt": "2025-09-22T09:00:00Z",
  "updatedAt": "2025-09-22T10:30:00Z"
}
```

**Player Object:**

```json
{
  "id": "clx0987654321",
  "userId": "user-123",
  "lobbyId": "clx1234567890",
  "role": "CIVILIAN",
  "career": "Detective",
  "isAlive": true,
  "isActive": true,
  "joinedAt": "2025-09-22T09:15:00Z"
}
```

**Vote Response:**

```json
{
  "vote": {
    "id": "clx5678901234",
    "voterId": "user-123",
    "targetId": "user-456",
    "lobbyId": "clx1234567890",
    "lobbyTimeCycleId": "clx3456789012",
    "createdAt": "2025-09-22T10:45:00Z"
  },
  "isNewVote": true,
  "message": "Vote cast successfully"
}
```

#### Error Responses

All endpoints return appropriate HTTP status codes:

* `400 Bad Request`: Invalid input or game state
* `404 Not Found`: Resource not found
* `500 Internal Server Error`: Server error

Error response format:

```json
{
  "message": "Error description"
}
```

### Dependencies

* PostgreSQL DB container

* Express.js + TypeScript runtime

* (Optional later) Message broker for real-time announcements (e.g. Kafka, RabbitMQ, or WebSocket layer)

# Shop Service

**Core responsibility:** Enables players to prepare for day/night cycles by purchasing protective items and task-assistance objects using in-game currency.

## Docker Hub Images

The service is available as Docker images on Docker Hub:
- Service Image: `cebanvasile1/shop-service:1.0.0`
- Database Image: `cebanvasile1/shop-service-db:1.0.0`

## Quick Start

### Prerequisites

- Java 17 or higher
- Maven 3.6+ (or use the provided Maven wrapper)
- Docker & Docker Compose
- Git

### Quickest Start (Using Pre-built Images)

1. **Requirements:**
    - Docker installed (version 20.10.0 or higher)
    - 2GB RAM minimum
    - 1GB free disk space
    - Ports 8081 and 5432 available

2. **Run with a single command:**
   ```bash
   docker run -d --name shop-db --network shop_network -p 5432:5432 cebanvasile1/shop-service-db:1.0.0 && \
   docker run -d --name shop-service --network shop_network -p 8081:8081 -e SPRING_DATASOURCE_URL=jdbc:postgresql://shop-db:5432/shop_service_db -e SPRING_DATASOURCE_USERNAME=shop_user -e SPRING_DATASOURCE_PASSWORD=shop_password cebanvasile1/shop-service:1.0.0
   ```

   Or create a `docker-compose.yml`:
   ```yaml
   services:
     postgres:
       image: cebanvasile1/shop-service-db:1.0.0
       ports:
         - "5432:5432"
       volumes:
         - postgres_data:/var/lib/postgresql/data
       networks:
         - shop_network
       healthcheck:
         test: ["CMD-SHELL", "pg_isready -U shop_user -d shop_service_db"]
         interval: 10s
         timeout: 5s
         retries: 5

     shop-service:
       image: cebanvasile1/shop-service:1.0.0
       environment:
         SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/shop_service_db
         SPRING_DATASOURCE_USERNAME: shop_user
         SPRING_DATASOURCE_PASSWORD: shop_password
       ports:
         - "8081:8081"
       networks:
         - shop_network
       depends_on:
         postgres:
           condition: service_healthy

   networks:
     shop_network:
       driver: bridge

   volumes:
     postgres_data:
   ```

   Then run:
   ```bash
   docker-compose up -d
   ```

### Environment Setup (For Local Development)

1. **Clone the repository:**
   ```bash
   git clone https://github.com/ceban-vasile/Shop-Service.git
   cd Shop-Service
   ```

2. **Create environment file:**
   ```bash
   cp .env.example .env
   ```

3. **Configure your environment:**
   Edit the `.env` file and set your secure values for:
   ```properties
   # Database configuration
   POSTGRES_DB=shop_service_db
   POSTGRES_USER=your_db_user
   POSTGRES_PASSWORD=your_secure_password

   # PgAdmin configuration
   PGADMIN_DEFAULT_EMAIL=your_email@example.com
   PGADMIN_DEFAULT_PASSWORD=your_secure_password

   # Application configuration
   SPRING_DATASOURCE_URL=jdbc:postgresql://postgres:5432/shop_service_db
   SPRING_DATASOURCE_USERNAME=your_db_user
   SPRING_DATASOURCE_PASSWORD=your_secure_password

   # External Service URLs
   USER_SERVICE_URL=http://localhost:3000
   ROLEPLAY_SERVICE_URL=http://localhost:8082
   TASK_SERVICE_URL=http://localhost:3001
   GAME_SERVICE_URL=http://localhost:3000

   # Docker configuration
   DOCKER_USERNAME=your_docker_username
   DOCKER_IMAGE=shop-service
   DOCKER_TAG=1.0.0
   ```

### Running the Service

#### Using Docker Compose (Recommended)

1. **Start the services:**
   ```bash
   docker-compose up -d
   ```
   This will start:
    - PostgreSQL database with persistent volume
    - PgAdmin for database management
    - Shop Service application

2. **Check the services:**
   ```bash
   docker-compose ps
   ```

3. **View logs:**
   ```bash
   docker-compose logs -f shop-service
   ```

4. **Access the services:**
    - Shop Service API: http://localhost:8081
    - API Documentation: http://localhost:8081/swagger-ui.html
    - PgAdmin: http://localhost:5050
    - PostgreSQL: localhost:5432 (from other services)

5. **Stop the services:**
   ```bash
   docker-compose down
   ```
   > Note: Your data will persist in Docker volumes between restarts.

6. **To completely clean up:**
   ```bash
   docker-compose down -v
   ```
   > ⚠️ Warning: This will delete all data volumes!

#### Using Run Scripts (Alternative)

1. **Make the script executable (Linux/Mac):**
   ```bash
   chmod +x run.sh
   ```

2. **Run the service:**
    - On Windows:
      ```bash
      ./run.bat
      ```
    - On Linux/Mac:
      ```bash
      ./run.sh
      ```

The script will:
- Check if Docker is running
- Build the project with Maven
- Start PostgreSQL database
- Wait for the database to be ready
- Start the Spring Boot application

---

## Functionality

- Item catalog management for protective and task-assistance items
- Daily quantity balancing algorithm to ensure game economy stability
- Purchase processing (coordinating with User Management Service for currency)
- Inventory management for purchased items
- Item effects management for protection against specific roles/actions
- Integration with Character Service for asset purchases
- Integration with Roleplay Service for item effect validation
- Integration with Task Service for task-related item verification

---

## Tech Stack

* **Framework/language:** Java + Spring Boot (strong typing, enterprise-grade reliability)
* **Database:** PostgreSQL (ACID transactions for critical purchase operations)
* **Other:** Daily balancing algorithm, item effects engine
* **Communication pattern:** Internal REST API for service-to-service communication

---

## Service Diagram

```mermaid
flowchart LR
    subgraph MafiaApplication["Mafia Application"]
        SS[("Shop Service
        Java + Spring Boot")]
        UMS[("User Management Service")]
        TS[("Task Service")]
        RS[("Roleplay Service")]
        CS[("Character Service")]
        GS[("Game Service")]
    end

    subgraph DataPersistence["Data Persistence"]
        DB[(PostgreSQL Database)]
    end

    Client["Client / Other Services"]

    Client -- "HTTP/REST API Call" --> SS
    SS -- "JSON Response" --> Client
    SS -- "Reads/Writes item, inventory, transaction data" --> DB
    SS -- "POST /v1/users/{id}/transactions (SUBTRACT)" --> UMS
    UMS -- "GET /v1/users/{id}/balance" --> SS
    SS -- "POST /api/v1/actions/verify-item" --> RS
    RS -- "Item effectiveness response" --> SS
    SS -- "GET /v1/tasks/verify-item" --> TS
    TS -- "Task requirement validation" --> SS
    SS -- "POST /v1/users/{userId}/inventory (asset purchases)" --> CS
    CS -- "Asset added confirmation" --> SS
    GS -- "GET /api/v1/items/stock-status (game state)" --> SS
    SS -- "Active protection effects" --> GS
```

---

## Domain Models and Interfaces

### Item
```typescript
interface Item {
  id: string;
  name: string;
  description: string;
  price: number;
  category: ItemCategory;
  effects: ItemEffect[];
  availableQuantity: number; // Managed by daily balancing algorithm
  maxDailyQuantity: number;  // Used for balancing
  replenishRate: number;     // Daily restocking rate
  imageUrl: string;
  usageInstructions?: string;
  createdAt: Date;
  updatedAt: Date;
}

enum ItemCategory {
  PROTECTION,        // Items that protect against attacks
  TASK_ASSISTANCE,   // Items that help with daily tasks
  UTILITY,           // General purpose items
  SPECIAL,           // Limited edition or event items
  COSMETIC           // Character customization assets
}

interface ItemEffect {
  type: EffectType;
  value: number;      // Effect strength/duration
  duration: number;   // How many game cycles it lasts
  targetRole?: string; // Role-specific protections (aligns with Roleplay Service roles)
}

enum EffectType {
  WARD_VAMPIRE,       // e.g., garlic
  DOUSE_ARSONIST,     // e.g., water
  CONCEAL_IDENTITY,   // e.g., mask
  REVEAL_ROLE,        // e.g., magnifying glass
  BOOST_TASK,         // e.g., tools (integrates with Task Service)
  TRACKING,           // e.g., footprint detector
  BLOCK_ACTION        // e.g., handcuffs
}
```

### Inventory
```typescript
interface InventoryItem {
  id: string;
  userId: string;
  gameId: string;      // References Game Service lobby
  itemId: string;
  name: string;
  quantity: number;
  used: boolean;
  acquiredAt: Date;
  expiresAt?: Date;
  effects: ActiveItemEffect[];
}

interface ActiveItemEffect {
  type: EffectType;
  value: number;
  duration: number;
  active: boolean;
  appliedAt: Date;
}
```

### Transaction
```typescript
interface Transaction {
  transactionId: string;
  userId: string;
  gameId: string;
  items: PurchasedItem[];
  totalCost: number;
  timestamp: Date;
  status: 'COMPLETED' | 'FAILED' | 'PENDING';
  currencyTransactionId?: string; // Reference to User Service transaction
}

interface PurchasedItem {
  itemId: string;
  name: string;
  quantity: number;
  unitPrice: number;
  totalPrice: number;
}
```

---

## APIs Exposed

### Endpoint Summary

All endpoints are fully implemented with service integrations. The Shop Service provides **15 public endpoints** organized into 4 categories:

#### Items Management (6 endpoints)
1. `GET /api/v1/items/allAvailable` - Get available items with pagination
2. `GET /api/v1/items/{id}` - Get item details
3. `GET /api/v1/items/stock-status` - Get daily stock status
4. `GET /api/v1/items/recommendations` - Get personalized item recommendations (🔗 Task Service)
5. `GET /api/v1/items/{itemId}/effectiveness` - Get item effectiveness against roles
6. `POST /api/v1/items` - Create new item (Admin)

#### Inventory Management (7 endpoints)
7. `GET /api/v1/inventory/{userId}` - View user inventory
8. `POST /api/v1/inventory/{userId}/use` - Use item (🔗 Roleplay Service)
9. `GET /api/v1/inventory/{userId}/active-effects` - Get active protection effects
10. `POST /api/v1/inventory/transfer` - Transfer item to another player
11. `DELETE /api/v1/inventory/{userId}/effects/{effectId}` - Cancel active effect
12. `GET /api/v1/inventory/{userId}/unused` - Get unused items
13. `PUT /api/v1/inventory/{id}` - Update inventory item

#### Purchase Operations (3 endpoints)
14. `POST /api/v1/purchases` - Process purchase (🔗 Character Service for cosmetics)
15. `POST /api/v1/purchases/validate` - Validate purchase
16. `GET /api/v1/purchases/history` - Get purchase history

#### Game Events (1 endpoint)
17. `POST /api/v1/events/game-cycle` - Receive game cycle events (webhook)

🔗 = **Service Integration Active** - Endpoint communicates with external microservices

---

### 1. Get Available Items

**Endpoint:** `GET /api/v1/items/allAvailable`

**Description:** Retrieves all available items for purchase in the shop with dynamic quantity adjustment based on game context and daily balancing algorithm.

**Query Parameters:**
- `category` (optional): Filter by ItemCategory (PROTECTION, TASK_ASSISTANCE, COSMETIC, etc.)
- `page` (optional): Page number for pagination (default: 0)
- `size` (optional): Number of items per page (default: 10)
- `gameId` (optional): The game context (lobby ID from Game Service)
- `gameDay` (optional): The current game day for proper inventory balancing

**Response Format:**
```json
{
  "items": [
    {
      "id": "string",
      "name": "string",
      "description": "string",
      "price": 0,
      "category": "PROTECTION",
      "effects": [
        {
          "type": "WARD_VAMPIRE",
          "value": 100,
          "duration": 1,
          "targetRole": "MAFIA"
        }
      ],
      "availableQuantity": 5,
      "imageUrl": "string"
    }
  ],
  "totalItems": 0,
  "totalPages": 0,
  "currentPage": 0
}
```

**Status Codes:**
- 200: Success
- 400: Invalid parameters (missing gameId or gameDay)
- 500: Server error

---

### 2. Get Item Details

**Endpoint:** `GET /api/v1/items/{id}`

**Description:** Retrieves detailed information about a specific item including effects, pricing, and availability.

**Path Parameters:**
- `id`: Unique identifier of the item

**Query Parameters:**
- `gameId` (optional): Game context for dynamic pricing

**Response Format:**
```json
{
  "id": "string",
  "name": "Garlic Necklace",
  "description": "Wards off vampires for one night",
  "price": 50,
  "category": "PROTECTION",
  "effects": [
    {
      "type": "WARD_VAMPIRE",
      "value": 100,
      "duration": 1,
      "targetRole": "MAFIA"
    }
  ],
  "availableQuantity": 5,
  "imageUrl": "string",
  "usageInstructions": "Wear during the night phase for protection",
  "createdAt": "2025-10-08T12:00:00Z",
  "updatedAt": "2025-10-08T12:00:00Z"
}
```

**Status Codes:**
- 200: Success
- 404: Item not found
- 500: Server error

---

### 3. Process Purchase

**Endpoint:** `POST /api/v1/purchases`

**Description:** Processes a purchase transaction for one or more items. Verifies user balance, deducts currency, and adds items to inventory.

**Request Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "gameDay": 3,
  "items": [
    {
      "itemId": "string",
      "quantity": 1
    }
  ]
}
```

**Response Format:**
```json
{
  "transactionId": "string",
  "status": "COMPLETED",
  "timestamp": "2025-10-08T12:00:00Z",
  "totalCost": 50,
  "remainingBalance": 450,
  "currencyTransactionId": "string",
  "items": [
    {
      "itemId": "string",
      "name": "Garlic Necklace",
      "quantity": 1,
      "unitPrice": 50,
      "totalPrice": 50
    }
  ],
  "message": "Purchase successful"
}
```

**Status Codes:**
- 201: Purchase successful
- 400: Insufficient funds, quantity not available, or invalid request
- 404: Item not found or user not found
- 500: Server error

**Business Logic:**
1. Verify user exists via User Management Service
2. Check user balance via `GET /v1/users/{userId}/balance`
3. Validate item availability and quantities
4. For cosmetic items, verify compatibility with Character Service
5. Create transaction record with status PENDING
6. Deduct currency via `POST /v1/users/{userId}/transactions` (type: SUBTRACT)
7. Update item quantities
8. Add items to user inventory
9. For cosmetic items, notify Character Service via `POST /v1/users/{userId}/inventory`
10. Update transaction status to COMPLETED
11. Return response with remaining balance

---

### 4. View User Inventory

**Endpoint:** `GET /api/v1/inventory/{userId}`

**Description:** Retrieves the inventory of items owned by a user for a specific game, including active effects and usage status.

**Path Parameters:**
- `userId`: Unique identifier of the user

**Query Parameters:**
- `gameId` (optional): The game context for the inventory
- `includeUsed` (optional): Include used items (default: false)
- `category` (optional): Filter by item category

**Response Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "totalItems": 5,
  "items": [
    {
      "id": "string",
      "itemId": "string",
      "name": "Garlic Necklace",
      "category": "PROTECTION",
      "quantity": 1,
      "used": false,
      "acquiredAt": "2025-10-08T12:00:00Z",
      "expiresAt": "2025-10-09T12:00:00Z",
      "effects": [
        {
          "type": "WARD_VAMPIRE",
          "value": 100,
          "duration": 1,
          "active": false
        }
      ]
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 404: User not found or no inventory for game
- 500: Server error

---

### 5. Use Item

**Endpoint:** `POST /api/v1/inventory/{userId}/use`

**Description:** Uses an item from the user's inventory and applies its protective or task-assistance effects. Notifies Roleplay Service for protection effects.

**Path Parameters:**
- `userId`: Unique identifier of the user

**Request Format:**
```json
{
  "gameId": "string",
  "gameDay": 3,
  "gameCycle": "NIGHT",
  "inventoryItemId": "string",
  "targetUserId": "string"
}
```

**Response Format:**
```json
{
  "success": true,
  "message": "Garlic Necklace activated for night protection",
  "appliedEffects": [
    {
      "type": "WARD_VAMPIRE",
      "value": 100,
      "duration": 1
    }
  ],
  "remainingQuantity": 0,
  "expiresAt": "2025-10-09T12:00:00Z"
}
```

**Status Codes:**
- 200: Success
- 404: Item not found in inventory
- 400: Invalid use conditions (wrong cycle, already used, etc.)
- 500: Server error

**Business Logic:**
1. Verify item exists in user's inventory
2. Validate game cycle matches item usage requirements
3. Check if item is already used or expired
4. For PROTECTION items, register effects with Roleplay Service via `POST /api/v1/actions/verify-item`
5. For TASK_ASSISTANCE items, notify Task Service
6. Mark item as used and activate effects
7. Decrease quantity or mark as consumed
8. Return success response with applied effects

---

### 6. Get Daily Stock Status

**Endpoint:** `GET /api/v1/items/stock-status`

**Description:** Provides information about the current stock levels and next restock time for a specific game.

**Query Parameters:**
- `gameId` (required): The game context
- `gameDay` (required): The current game day

**Response Format:**
```json
{
  "gameId": "string",
  "gameDay": 3,
  "nextRestockTime": "2025-10-09T00:00:00Z",
  "rareItemsAvailable": true,
  "categories": [
    {
      "name": "PROTECTION",
      "itemsAvailable": 4,
      "totalItems": 6,
      "restockPercentage": 66.7
    },
    {
      "name": "TASK_ASSISTANCE",
      "itemsAvailable": 8,
      "totalItems": 10,
      "restockPercentage": 80.0
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 400: Invalid parameters
- 404: Game not found
- 500: Server error

---

### 7. Get Active Protection Effects (Internal API)

**Endpoint:** `GET /api/v1/inventory/{userId}/active-effects`

**Description:** Returns currently active protection effects for a user. Called by Game Service and Roleplay Service during night phase.

**Path Parameters:**
- `userId`: Unique identifier of the user

**Query Parameters:**
- `gameId` (required): The game context
- `currentCycle` (required): Current game cycle (DAY/NIGHT)

**Response Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "activeEffects": [
    {
      "effectType": "WARD_VAMPIRE",
      "value": 100,
      "duration": 1,
      "appliedAt": "2025-10-08T20:00:00Z",
      "expiresAt": "2025-10-09T08:00:00Z",
      "itemName": "Garlic Necklace"
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 404: User not found
- 500: Server error

---

### 8. Game Cycle Event (Webhook)

**Endpoint:** `POST /api/v1/events/game-cycle`

**Description:** Receives game cycle change notifications from Game Service. Updates shop availability and triggers daily stock refresh.

**Request Format:**
```json
{
  "gameId": "string",
  "gameDay": 3,
  "cycle": "NIGHT",
  "timestamp": "2025-10-08T20:00:00Z",
  "eventType": "CYCLE_CHANGE"
}
```

**Response Format:**
```json
{
  "success": true,
  "message": "Game cycle updated to NIGHT for day 3",
  "stockRefreshed": true,
  "affectedItems": 15
}
```

**Status Codes:**
- 200: Success
- 400: Invalid cycle data
- 500: Server error

**Business Logic:**
1. Update current game cycle state
2. If new day detected, trigger daily stock refresh
3. Apply balancing algorithm to adjust quantities
4. Expire old active effects
5. Notify clients via WebSocket (future enhancement)

---

### 9. Validate Purchase

**Endpoint:** `POST /api/v1/purchases/validate`

**Description:** Validates a purchase without committing the transaction. Checks user balance, item availability, and calculates total cost.

**Request Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "items": [
    {
      "itemId": "string",
      "quantity": 2
    }
  ]
}
```

**Response Format:**
```json
{
  "valid": true,
  "totalCost": 300,
  "userBalance": 500,
  "remainingBalance": 200,
  "itemsAvailable": true,
  "warnings": [],
  "errors": []
}
```

**Status Codes:**
- 200: Validation complete (check `valid` field for result)
- 400: Invalid request format
- 500: Server error

---

### 10. Get Item Recommendations

**Endpoint:** `GET /api/v1/items/recommendations`

**Description:** Suggests items based on user's role, current threats in game, and budget.

**Query Parameters:**
- `userId` (required): User requesting recommendations
- `gameId` (required): Current game context
- `maxPrice` (optional): Budget limit

**Response Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "recommendations": [
    {
      "itemId": "string",
      "name": "Garlic Necklace",
      "price": 150,
      "reason": "Protection against vampire attacks detected in game",
      "priority": "HIGH",
      "category": "PROTECTION"
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 404: User or game not found
- 500: Server error

---

### 11. Get Item Effectiveness

**Endpoint:** `GET /api/v1/items/{itemId}/effectiveness`

**Description:** Shows how effective an item is against specific roles or threats.

**Path Parameters:**
- `itemId`: Item to check

**Query Parameters:**
- `targetRole` (optional): Specific role to check against
- `gameId` (optional): Game context for dynamic effectiveness

**Response Format:**
```json
{
  "itemId": "string",
  "name": "Garlic Necklace",
  "effectiveness": [
    {
      "againstRole": "VAMPIRE",
      "protectionLevel": 100,
      "description": "Complete protection against vampire attacks"
    },
    {
      "againstRole": "MAFIA",
      "protectionLevel": 0,
      "description": "No protection against mafia attacks"
    }
  ],
  "usageInstructions": "Use during day phase to activate protection for the upcoming night"
}
```

**Status Codes:**
- 200: Success
- 404: Item not found
- 500: Server error

---

### 12. Transfer Item

**Endpoint:** `POST /api/v1/inventory/transfer`

**Description:** Transfer items between players in the same game (gifting/trading).

**Request Format:**
```json
{
  "fromUserId": "string",
  "toUserId": "string",
  "gameId": "string",
  "inventoryItemId": "string",
  "quantity": 1,
  "message": "Here's some protection for tonight!"
}
```

**Response Format:**
```json
{
  "success": true,
  "transactionId": "string",
  "message": "Item transferred successfully",
  "senderNewQuantity": 0,
  "recipientNewQuantity": 1
}
```

**Status Codes:**
- 200: Success
- 400: Invalid transfer (insufficient quantity, same user, etc.)
- 404: User or item not found
- 500: Server error

---

### 13. Get Purchase History

**Endpoint:** `GET /api/v1/purchases/history`

**Description:** Retrieves purchase history for a user in a specific game or across all games.

**Query Parameters:**
- `userId` (required): User to get history for
- `gameId` (optional): Filter by specific game
- `startDate` (optional): Filter from date
- `endDate` (optional): Filter to date
- `page` (optional): Page number (default: 0)
- `size` (optional): Page size (default: 20)

**Response Format:**
```json
{
  "userId": "string",
  "totalPurchases": 15,
  "totalSpent": 2250,
  "purchases": [
    {
      "transactionId": "string",
      "gameId": "string",
      "purchaseDate": "2025-10-08T12:00:00Z",
      "items": [
        {
          "itemId": "string",
          "name": "Garlic Necklace",
          "quantity": 1,
          "pricePerUnit": 150,
          "totalPrice": 150
        }
      ],
      "totalCost": 150
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 404: User not found
- 500: Server error

---

### 14. Cancel Active Effect

**Endpoint:** `DELETE /api/v1/inventory/{userId}/effects/{effectId}`

**Description:** Cancels an active item effect (useful if activated by mistake).

**Path Parameters:**
- `userId`: User who owns the effect
- `effectId`: Active effect to cancel

**Query Parameters:**
- `gameId` (required): Game context

**Response Format:**
```json
{
  "success": true,
  "message": "Effect cancelled successfully",
  "refundIssued": false,
  "effectType": "WARD_VAMPIRE"
}
```

**Status Codes:**
- 200: Success
- 404: Effect not found or already expired
- 400: Effect cannot be cancelled (already applied)
- 500: Server error

---

## Inter-Service Communication

### Outgoing Requests (Shop Service → Other Services)

#### 1. To User Management Service

**Purpose:** Currency validation and deduction

**Endpoints Used:**
- `GET /v1/users/{id}/balance` - Check user's current balance before purchase
- `POST /v1/users/{id}/transactions` - Deduct currency after successful purchase

**Request Example:**
```json
POST /v1/users/{userId}/transactions
{
  "amount": 150,
  "type": "SUBTRACT",
  "reason": "Shop purchase - transaction ID: txn_123"
}
```

**Error Handling:**
- If balance insufficient: Return 400 to client
- If user not found: Return 404 to client
- Transaction failures: Rollback shop transaction

---

#### 2. To Roleplay Service

**Purpose:** Verify item effect compatibility and register active protections

**Endpoints Used:**
- `POST /api/v1/actions/verify-item` - Verify item effectiveness against roles

**Request Example:**
```json
POST /api/v1/actions/verify-item
{
  "itemId": "item_garlic_001",
  "effectType": "WARD_VAMPIRE",
  "targetRoleId": "role_mafia_001",
  "gamePhase": "NIGHT"
}
```

**Response Example:**
```json
{
  "effective": true,
  "effectMultiplier": 1.0,
  "message": "Item is effective against this role"
}
```

**When to Call:**
- During item usage (`POST /api/v1/inventory/{userId}/use`)
- When Game Service queries active protections

---

#### 3. To Task Service

**Purpose:** Validate if items satisfy task requirements

**Endpoints Used:**
- `GET /v1/tasks/verify-item` - Check if item helps complete a task

**Request Example:**
```json
GET /v1/tasks/verify-item?userId=user123&itemId=item_tools_001&gameId=game_001
```

**Response Example:**
```json
{
  "applicable": true,
  "taskId": "task_456",
  "taskName": "Repair the fence",
  "bonusReward": 50
}
```

**When to Call:**
- During purchase to show task-related recommendations
- During item usage to notify task completion

---

#### 4. To Character Service

**Purpose:** Sync cosmetic asset purchases

**Endpoints Used:**
- `POST /v1/users/{userId}/inventory` - Add cosmetic asset to character inventory

**Request Example:**
```json
POST /v1/users/{userId}/inventory
{
  "assetId": "asset_red_coat_001",
  "source": "SHOP_PURCHASE"
}
```

**When to Call:**
- Only for items with category `COSMETIC`
- After successful purchase transaction

---

### Implemented Service Integrations

The Shop Service now includes REST client implementations for seamless integration with other microservices:

#### 1. CharacterServiceClient

**Location:** `src/main/java/com/mafia/shop_service/client/CharacterServiceClient.java`

**Purpose:** Automatically syncs cosmetic item purchases to Character Service inventory

**Integration Point:**
- **Trigger:** Automatically called in `PurchaseServiceImpl.processPurchase()` when item category is `COSMETIC`
- **Endpoint Called:** `POST /v1/users/{userId}/inventory` on Character Service
- **Error Handling:** Graceful degradation - purchase succeeds even if Character Service is unavailable
- **Configuration:** `external.character-service.url` (default: http://localhost:8080)

**Example Flow:**
```java
// After successful cosmetic purchase
if (item.getCategory() == ItemCategory.COSMETIC) {
    characterServiceClient.addToInventory(
        userId, 
        item.getId(), 
        "SHOP_PURCHASE"
    );
}
```

---

#### 2. TaskServiceClient

**Location:** `src/main/java/com/mafia/shop_service/client/TaskServiceClient.java`

**Purpose:** Verifies if items help complete user tasks and provides personalized recommendations

**Integration Point:**
- **Trigger:** Called in `ItemService.getRecommendations()` for TASK_ASSISTANCE items
- **Endpoint Called:** `GET /v1/tasks/verify-item?userId={userId}&itemId={itemId}&gameId={gameId}` on Task Service
- **Benefits:** Shows task-specific benefits and bonus rewards in recommendations
- **Error Handling:** Returns default recommendations if Task Service is unavailable
- **Configuration:** `external.task-service.url` (default: http://localhost:3001)

**Example Response Enhancement:**
```json
{
  "itemId": "tool_hammer_001",
  "name": "Hammer",
  "price": 50,
  "reason": "Helps complete task: Repair the fence",
  "priority": "MEDIUM",
  "category": "TASK_ASSISTANCE"
}
```

---

#### 3. RoleplayServiceClient

**Location:** `src/main/java/com/mafia/shop_service/client/RoleplayServiceClient.java`

**Purpose:** Registers active protections and verifies item effectiveness against roles

**Integration Points:**

**A. Protection Registration**
- **Trigger:** Called in `InventoryService.useItem()` when player uses a protection item
- **Endpoint Called:** `POST /api/v1/protections` on Roleplay Service
- **Items Affected:** WARD_*, DOUSE_*, BLOCK_ACTION, CONCEAL_IDENTITY effects
- **Error Handling:** Item is still marked as used even if registration fails
- **Configuration:** `external.roleplay-service.url` (default: http://localhost:8082)

**B. Effectiveness Verification**
- **Trigger:** Can be called during item effectiveness checks
- **Endpoint Called:** `POST /api/v1/actions/verify-item` on Roleplay Service
- **Purpose:** Validates item effectiveness against specific roles

**Example Protection Registration:**
```java
// When player uses Garlic Necklace
roleplayServiceClient.registerProtection(
    userId, 
    gameId, 
    inventoryItemId, 
    "WARD_VAMPIRE"
);
```

---

#### Configuration Properties

All external service integrations are configured via `application.properties`:

```properties
# External Service URLs
external.user-service.url=${USER_SERVICE_URL:http://localhost:3000}
external.game-service.url=${GAME_SERVICE_URL:http://localhost:3000}
external.roleplay-service.url=${ROLEPLAY_SERVICE_URL:http://localhost:8082}
external.task-service.url=${TASK_SERVICE_URL:http://localhost:3001}
external.character-service.url=${CHARACTER_SERVICE_URL:http://localhost:8080}

# Resilience Configuration
resilience4j.circuitbreaker.enabled=true
resilience4j.retry.max-attempts=3
```

**Environment Variable Support:**
- Set `CHARACTER_SERVICE_URL`, `TASK_SERVICE_URL`, `ROLEPLAY_SERVICE_URL` etc. in your deployment environment
- Defaults to localhost URLs for local development
- Docker deployments should use service names (e.g., `http://character-service:8080`)

---

#### RestTemplate Configuration

**Location:** `src/main/java/com/mafia/shop_service/config/RestClientConfig.java`

**Features:**
- Connection timeout: 5 seconds
- Read timeout: 10 seconds
- Shared bean for all service clients
- Simple and reliable HTTP client factory

---

#### Integration Benefits

✅ **Automatic Cosmetic Sync:** Cosmetic purchases instantly appear in Character Service  
✅ **Smart Recommendations:** Item suggestions consider active tasks and potential bonuses  
✅ **Protection Coordination:** Protection effects are tracked across services  
✅ **Graceful Degradation:** Core shop functionality works even if optional services are down  
✅ **Configurable URLs:** Easy deployment across different environments  
✅ **Error Resilience:** Comprehensive error handling prevents cascading failures  

---

### Incoming Requests (Other Services → Shop Service)

#### 1. From Game Service

**Purpose:** Query active protections during game cycles

**Endpoints Called:**
- `GET /api/v1/inventory/{userId}/active-effects` - Get active item protections
- `GET /api/v1/items/stock-status` - Check shop availability for announcements

**Usage Scenarios:**
- Night phase begins: Check all players' active protections
- Day cycle: Display shop availability in game UI
- Game events: Verify if items blocked certain actions

---

#### 2. From Roleplay Service

**Purpose:** Check active protections when processing role actions

**Endpoints Called:**
- `GET /api/v1/inventory/{userId}/active-effects` - Verify protection status

**Usage Scenarios:**
- Mafia attempts kill: Check if target has protection items
- Detective investigates: Check if target has concealment items
- Doctor heals: Check if target already has protective items

---

#### 3. From Character Service

**Purpose:** Query cosmetic item catalog for character customization

**Endpoints Called:**
- `GET /api/v1/items?category=COSMETIC` - Get available cosmetic items

**Usage Scenarios:**
- Character creation/customization screen
- Preview available cosmetic purchases

---

## Implementation Considerations

### 1. Daily Item Balancing Algorithm

**Purpose:** Dynamic stock management based on game state

**Algorithm Logic:**
```typescript
interface BalancingFactors {
  gameDay: number;
  totalPlayers: number;
  activePlayers: number;
  playerDeaths: number;
  averagePlayerBalance: number;
}

function calculateAvailableQuantity(
  item: Item,
  factors: BalancingFactors
): number {
  let quantity = item.maxDailyQuantity;
  
  // Adjust for game progression
  if (factors.gameDay > 5) {
    quantity *= 0.8; // Reduce availability in late game
  }
  
  // Adjust for player count
  const playerRatio = factors.activePlayers / factors.totalPlayers;
  quantity *= playerRatio;
  
  // Adjust for rarity
  if (item.category === 'SPECIAL') {
    quantity = Math.max(1, Math.floor(quantity * 0.3));
  }
  
  // Ensure minimum availability
  return Math.max(1, Math.floor(quantity));
}
```

**Features:**
- Adjusts available quantities based on player counts and game day
- Creates artificial scarcity for powerful items
- Ensures all player roles have access to appropriate protective items
- Randomizes some stock quantities to prevent predictable patterns
- Daily restocking at midnight (game time)

---

### 2. Protection Effectiveness System

**Integration with Roleplay Service:**
- Different protection items have varying effectiveness against specific roles
- Some items provide partial protection (percentage-based)
- Stacking rules prevent overpowered combinations

**Example:**
```typescript
// Garlic Necklace: 100% protection against Mafia
// Silver Bullet: 100% protection against Werewolf
// Holy Water: 50% protection against any evil role
```

---

### 3. Transaction Safety

**ACID Compliance:**
- Implement optimistic locking for inventory operations
- Ensure atomic transactions when purchasing limited items
- Add idempotency keys for purchase operations
- Rollback mechanisms for failed currency deductions

**Transaction Flow:**
```
1. BEGIN TRANSACTION
2. Lock item stock record
3. Verify user balance (external call)
4. Create pending transaction record
5. Deduct currency (external call)
6. Update item quantities
7. Add to user inventory
8. Update transaction status to COMPLETED
9. COMMIT TRANSACTION
10. Send notifications (async)
```

**Rollback Scenarios:**
- Currency deduction fails → Rollback inventory changes
- Service timeout → Mark transaction as PENDING for manual review
- Concurrent purchase of last item → First transaction wins

---

### 4. Performance Optimization

**Caching Strategy:**
- Cache item catalog (TTL: 1 hour)
- Cache user inventory (TTL: 5 minutes, invalidate on purchase)
- Cache active effects (TTL: 30 seconds during night phase)

**Database Optimization:**
- Index on `userId` + `gameId` for inventory queries
- Index on `itemId` + `category` for catalog queries
- Batch update inventory records for multiple purchases
- Use read replicas for inventory queries during high-traffic periods

**Async Processing:**
- Purchase notifications to Character Service (async)
- Task completion notifications (async)
- Stock level logging and analytics (async)

---

## Data Ownership

This service owns:
- `items` - Item catalog and definitions
- `inventory_items` - User inventory per game
- `transactions` - Purchase transaction records
- `item_effects` - Item effect definitions
- `daily_stock_records` - Historical stock levels

---

## Testing

### API Testing with Postman

1. Import `shop-service.postman_collection.json`
2. Set environment variables:
    - `baseUrl`: `http://localhost:8081`
    - `userId`: Test user ID
    - `gameId`: Test game/lobby ID
3. Run workflows:
    - Complete purchase flow
    - Inventory management
    - Item usage scenarios

### Integration Testing

**Prerequisites:**
- User Management Service running (port 3000)
- Game Service running (port 3000)
- Roleplay Service running (port 8082)

**Test Scenarios:**
1. Purchase with sufficient balance
2. Purchase with insufficient balance
3. Purchase unavailable item
4. Use protection item during night phase
5. Use task assistance item
6. Query active effects during game

### Unit Testing

```bash
# Run all tests
mvn test

# Run with coverage
mvn test jacoco:report

# Integration tests only
mvn verify -P integration-tests
```

---

## Deployment

### Docker Deployment

```bash
# Pull from Docker Hub
docker pull cebanvasile1/shop-service:1.0.0

# Run with environment variables
docker run -d \
  --name shop-service \
  -p 8081:8081 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://db:5432/shop_db \
  -e USER_SERVICE_URL=http://user-service:3000 \
  -e ROLEPLAY_SERVICE_URL=http://roleplay-service:8082 \
  -e TASK_SERVICE_URL=http://task-service:3001 \
  cebanvasile1/shop-service:1.0.0
```

### Service Dependencies

**Required Services:**
- User Management Service (for currency operations)
- PostgreSQL Database

**Optional Services (graceful degradation):**
- Roleplay Service (item effectiveness validation)
- Task Service (task-related item bonuses)
- Character Service (cosmetic asset sync)
- Game Service (game state queries)

---

## Monitoring & Health Checks

**Health Endpoints:**
- `GET /actuator/health` - Service health
- `GET /actuator/health/db` - Database connectivity
- `GET /actuator/health/external` - External service connectivity

**Metrics:**
- Total purchases per day
- Average transaction value
- Most popular items
- Stock depletion rates
- Failed transaction reasons

---

## Error Handling

**Error Response Format:**
```json
{
  "timestamp": "2025-10-08T12:00:00Z",
  "status": 400,
  "error": "Bad Request",
  "message": "Insufficient funds",
  "path": "/api/v1/purchases",
  "details": {
    "required": 150,
    "available": 100,
    "userId": "user123"
  }
}
```

**Common Error Codes:**
- `INSUFFICIENT_FUNDS` - User doesn't have enough currency
- `ITEM_OUT_OF_STOCK` - Item quantity not available
- `ITEM_NOT_FOUND` - Invalid item ID
- `USER_NOT_FOUND` - Invalid user ID
- `GAME_NOT_ACTIVE` - Game is not in active state
- `INVALID_GAME_CYCLE` - Item cannot be used in current cycle
- `ALREADY_USED` - Item already consumed
- `EXTERNAL_SERVICE_ERROR` - Dependency service unavailable

---

## API Documentation

Interactive API documentation is available at `/swagger-ui.html` when the service is running. The OpenAPI specification can be accessed at `/v3/api-docs`.

---

## Security Considerations

- Validate all user inputs
- Sanitize item descriptions to prevent XSS
- Rate limit purchase endpoints (max 10 purchases per minute per user)
- Log all transactions for audit trail
- Encrypt sensitive transaction data
- Implement CSRF protection for state-changing operations

---

## Future Enhancements

1. **Auction System**: Players can bid on rare items
2. **Item Trading**: Player-to-player item exchange
3. **Crafting System**: Combine items to create new ones
4. **Seasonal Items**: Limited-time event items
5. **Bulk Purchase Discounts**: Volume-based pricing
6. **Wishlist Feature**: Notify users when items restock
7. **Gift System**: Send items to other players
8. **Item Rental**: Temporary item usage for lower cost
9. **Dynamic Pricing**: Adjust prices based on supply/demand
10. **Loyalty Rewards**: Discounts for frequent shoppers

---

## Configuration

### Application Properties

```properties
# Server Configuration
server.port=8081
server.servlet.context-path=/

# Database Configuration
spring.datasource.url=${SPRING_DATASOURCE_URL}
spring.datasource.username=${SPRING_DATASOURCE_USERNAME}
spring.datasource.password=${SPRING_DATASOURCE_PASSWORD}
spring.jpa.hibernate.ddl-auto=update
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.format_sql=true

# External Service URLs
services.user-management.url=${USER_SERVICE_URL:http://localhost:3000}
services.roleplay.url=${ROLEPLAY_SERVICE_URL:http://localhost:8082}
services.task.url=${TASK_SERVICE_URL:http://localhost:3001}
services.character.url=${CHARACTER_SERVICE_URL:http://localhost:8083}
services.game.url=${GAME_SERVICE_URL:http://localhost:3000}

# Shop Configuration
shop.daily-restock-time=00:00:00
shop.max-purchase-quantity=10
shop.transaction-timeout-seconds=30
shop.enable-dynamic-pricing=true
shop.cache-ttl-minutes=60

# Circuit Breaker Configuration (Resilience4j)
resilience4j.circuitbreaker.instances.user-service.failure-rate-threshold=50
resilience4j.circuitbreaker.instances.user-service.wait-duration-in-open-state=30s
resilience4j.circuitbreaker.instances.user-service.sliding-window-size=10

# Rate Limiting
spring.cloud.gateway.routes[0].filters[0]=RequestRateLimiter=10,1m

# Logging
logging.level.root=INFO
logging.level.com.mafia.shop=DEBUG
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} - %msg%n
```

---

## Service Communication Examples

### Example 1: Complete Purchase Flow

```mermaid
sequenceDiagram
    participant Client
    participant ShopService
    participant UserService
    participant CharacterService
    participant RoleplayService

    Client->>ShopService: POST /api/v1/purchases
    ShopService->>ShopService: Validate request
    ShopService->>UserService: GET /v1/users/{userId}/balance
    UserService-->>ShopService: Balance: 500
    ShopService->>ShopService: Check item availability
    ShopService->>ShopService: Calculate total cost: 150
    ShopService->>UserService: POST /v1/users/{userId}/transactions (SUBTRACT 150)
    UserService-->>ShopService: Transaction successful, new balance: 350
    ShopService->>ShopService: Update item quantities
    ShopService->>ShopService: Add items to inventory
    
    alt Item is COSMETIC
        ShopService->>CharacterService: POST /v1/users/{userId}/inventory
        CharacterService-->>ShopService: Asset added
    end
    
    ShopService->>ShopService: Mark transaction COMPLETED
    ShopService-->>Client: Purchase successful (201)
```

### Example 2: Using Protection Item During Night Phase

```mermaid
sequenceDiagram
    participant Client
    participant ShopService
    participant RoleplayService
    participant GameService

    Client->>ShopService: POST /api/v1/inventory/{userId}/use
    ShopService->>ShopService: Verify item in inventory
    ShopService->>ShopService: Check game cycle = NIGHT
    ShopService->>RoleplayService: POST /api/v1/actions/verify-item
    RoleplayService-->>ShopService: Item effective (100%)
    ShopService->>ShopService: Activate protection effects
    ShopService->>ShopService: Mark item as used
    ShopService-->>Client: Protection activated (200)
    
    Note over GameService: Later during night phase
    GameService->>ShopService: GET /api/v1/inventory/{userId}/active-effects
    ShopService-->>GameService: Active: WARD_VAMPIRE (expires in 1 cycle)
```

### Example 3: Daily Stock Restock

```mermaid
sequenceDiagram
    participant Scheduler
    participant ShopService
    participant GameService
    participant Database

    Scheduler->>ShopService: Trigger daily restock (00:00:00)
    ShopService->>GameService: GET /v1/lobby?status=IN_GAME
    GameService-->>ShopService: Active games list
    
    loop For each active game
        ShopService->>ShopService: Calculate balancing factors
        ShopService->>ShopService: Run balancing algorithm
        ShopService->>Database: Update item quantities
        ShopService->>Database: Log stock record
    end
    
    ShopService->>ShopService: Clear item catalog cache
    ShopService-->>Scheduler: Restock completed
```

---

## Troubleshooting

### Common Issues

#### 1. Purchase Fails with "Insufficient Funds"

**Symptoms:**
```json
{
  "status": 400,
  "error": "INSUFFICIENT_FUNDS",
  "message": "User has insufficient balance"
}
```

**Solutions:**
- Verify user balance: `GET /v1/users/{userId}/balance` on User Service
- Check if currency was recently spent in another transaction
- Ensure currency synchronization between services

---

#### 2. Items Not Restocking

**Symptoms:**
- All items show `availableQuantity: 0`
- Stock status doesn't update at midnight

**Solutions:**
- Check scheduler logs for restock job execution
- Verify game state is active: `GET /v1/lobby/{gameId}` on Game Service
- Check database for `daily_stock_records` table entries
- Manually trigger restock: `POST /api/v1/admin/restock` (admin endpoint)

---

#### 3. Item Usage Fails During Night Phase

**Symptoms:**
```json
{
  "status": 400,
  "error": "INVALID_GAME_CYCLE",
  "message": "Item cannot be used during current cycle"
}
```

**Solutions:**
- Verify current game cycle from Game Service
- Check item's `usablePhase` requirements
- Ensure game is in active state
- Check if item is already consumed

---

#### 4. External Service Timeouts

**Symptoms:**
- Purchases fail with timeout errors
- Circuit breaker opens frequently

**Solutions:**
- Check User Service health: `GET /health` on port 3000
- Verify network connectivity between services
- Increase timeout configuration in `application.properties`
- Check circuit breaker metrics in `/actuator/metrics`

---

#### 5. Inventory Synchronization Issues

**Symptoms:**
- Items purchased but not appearing in inventory
- Character Service doesn't receive cosmetic items

**Solutions:**
- Check transaction status in database: `SELECT * FROM transactions WHERE status = 'PENDING'`
- Verify Character Service connectivity
- Replay failed notifications: `POST /api/v1/admin/retry-notifications`
- Check async processing logs

---

## Database Schema

### Tables

```sql
-- Items catalog
CREATE TABLE items (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    price INTEGER NOT NULL,
    category VARCHAR(50) NOT NULL,
    available_quantity INTEGER NOT NULL DEFAULT 0,
    max_daily_quantity INTEGER NOT NULL,
    replenish_rate INTEGER NOT NULL DEFAULT 1,
    image_url VARCHAR(500),
    usage_instructions TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Item effects
CREATE TABLE item_effects (
    id VARCHAR(36) PRIMARY KEY,
    item_id VARCHAR(36) NOT NULL,
    effect_type VARCHAR(50) NOT NULL,
    value INTEGER NOT NULL,
    duration INTEGER NOT NULL,
    target_role VARCHAR(50),
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE
);

-- User inventory
CREATE TABLE inventory_items (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    game_id VARCHAR(36) NOT NULL,
    item_id VARCHAR(36) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    used BOOLEAN DEFAULT FALSE,
    acquired_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    INDEX idx_user_game (user_id, game_id),
    INDEX idx_item (item_id)
);

-- Active effects
CREATE TABLE active_effects (
    id VARCHAR(36) PRIMARY KEY,
    inventory_item_id VARCHAR(36) NOT NULL,
    effect_type VARCHAR(50) NOT NULL,
    value INTEGER NOT NULL,
    duration INTEGER NOT NULL,
    active BOOLEAN DEFAULT TRUE,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (inventory_item_id) REFERENCES inventory_items(id) ON DELETE CASCADE
);

-- Purchase transactions
CREATE TABLE transactions (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    game_id VARCHAR(36) NOT NULL,
    total_cost INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL,
    currency_transaction_id VARCHAR(36),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_game (user_id, game_id),
    INDEX idx_status (status)
);

-- Transaction items
CREATE TABLE transaction_items (
    id VARCHAR(36) PRIMARY KEY,
    transaction_id VARCHAR(36) NOT NULL,
    item_id VARCHAR(36) NOT NULL,
    quantity INTEGER NOT NULL,
    unit_price INTEGER NOT NULL,
    total_price INTEGER NOT NULL,
    FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE CASCADE,
    FOREIGN KEY (item_id) REFERENCES items(id)
);

-- Daily stock records
CREATE TABLE daily_stock_records (
    id VARCHAR(36) PRIMARY KEY,
    game_id VARCHAR(36) NOT NULL,
    game_day INTEGER NOT NULL,
    item_id VARCHAR(36) NOT NULL,
    available_quantity INTEGER NOT NULL,
    recorded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id),
    UNIQUE KEY unique_game_day_item (game_id, game_day, item_id)
);
```

### Seed Data

```sql
-- Protection items
INSERT INTO items (id, name, description, price, category, available_quantity, max_daily_quantity, replenish_rate, image_url) VALUES
('item_garlic_001', 'Garlic Necklace', 'Wards off vampires for one night', 50, 'PROTECTION', 10, 10, 5, '/images/garlic.png'),
('item_water_001', 'Holy Water', 'Provides 50% protection against evil roles', 75, 'PROTECTION', 8, 8, 4, '/images/holy-water.png'),
('item_mask_001', 'Identity Mask', 'Conceals your identity during investigations', 100, 'PROTECTION', 5, 5, 3, '/images/mask.png');

-- Task assistance items
INSERT INTO items (id, name, description, price, category, available_quantity, max_daily_quantity, replenish_rate, image_url) VALUES
('item_tools_001', 'Repair Tools', 'Helps complete repair tasks faster', 30, 'TASK_ASSISTANCE', 15, 15, 10, '/images/tools.png'),
('item_magnify_001', 'Magnifying Glass', 'Reveals clues for investigation tasks', 60, 'TASK_ASSISTANCE', 10, 10, 5, '/images/magnifying-glass.png');

-- Item effects
INSERT INTO item_effects (id, item_id, effect_type, value, duration, target_role) VALUES
('effect_garlic_001', 'item_garlic_001', 'WARD_VAMPIRE', 100, 1, 'MAFIA'),
('effect_water_001', 'item_water_001', 'BLOCK_ACTION', 50, 1, NULL),
('effect_mask_001', 'item_mask_001', 'CONCEAL_IDENTITY', 100, 2, 'DETECTIVE'),
('effect_tools_001', 'item_tools_001', 'BOOST_TASK', 30, 1, NULL),
('effect_magnify_001', 'item_magnify_001', 'REVEAL_ROLE', 50, 1, NULL);
```

---

## API Request/Response Examples

### Purchase Multiple Items

**Request:**
```bash
curl -X POST http://localhost:8081/api/v1/purchases \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {JWT_TOKEN}" \
  -d '{
    "userId": "user_123",
    "gameId": "game_abc_001",
    "gameDay": 3,
    "items": [
      {
        "itemId": "item_garlic_001",
        "quantity": 2
      },
      {
        "itemId": "item_tools_001",
        "quantity": 1
      }
    ]
  }'
```

**Response:**
```json
{
  "transactionId": "txn_789xyz",
  "status": "COMPLETED",
  "timestamp": "2025-10-08T14:30:00Z",
  "totalCost": 130,
  "remainingBalance": 370,
  "currencyTransactionId": "curr_txn_456",
  "items": [
    {
      "itemId": "item_garlic_001",
      "name": "Garlic Necklace",
      "quantity": 2,
      "unitPrice": 50,
      "totalPrice": 100
    },
    {
      "itemId": "item_tools_001",
      "name": "Repair Tools",
      "quantity": 1,
      "unitPrice": 30,
      "totalPrice": 30
    }
  ],
  "message": "Purchase successful. Items added to your inventory."
}
```

---

### Get Inventory with Filters

**Request:**
```bash
curl -X GET "http://localhost:8081/api/v1/inventory/user_123?gameId=game_abc_001&category=PROTECTION&includeUsed=false" \
  -H "Authorization: Bearer {JWT_TOKEN}"
```

**Response:**
```json
{
  "userId": "user_123",
  "gameId": "game_abc_001",
  "totalItems": 2,
  "items": [
    {
      "id": "inv_item_001",
      "itemId": "item_garlic_001",
      "name": "Garlic Necklace",
      "category": "PROTECTION",
      "quantity": 2,
      "used": false,
      "acquiredAt": "2025-10-08T14:30:00Z",
      "expiresAt": null,
      "effects": [
        {
          "type": "WARD_VAMPIRE",
          "value": 100,
          "duration": 1,
          "active": false,
          "targetRole": "MAFIA"
        }
      ]
    },
    {
      "id": "inv_item_002",
      "itemId": "item_mask_001",
      "name": "Identity Mask",
      "category": "PROTECTION",
      "quantity": 1,
      "used": false,
      "acquiredAt": "2025-10-07T10:15:00Z",
      "expiresAt": "2025-10-10T08:00:00Z",
      "effects": [
        {
          "type": "CONCEAL_IDENTITY",
          "value": 100,
          "duration": 2,
          "active": false,
          "targetRole": "DETECTIVE"
        }
      ]
    }
  ]
}
```

---

### Use Item with Target

**Request:**
```bash
curl -X POST http://localhost:8081/api/v1/inventory/user_123/use \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {JWT_TOKEN}" \
  -d '{
    "gameId": "game_abc_001",
    "gameDay": 3,
    "gameCycle": "NIGHT",
    "inventoryItemId": "inv_item_001",
    "targetUserId": "user_123"
  }'
```

**Response:**
```json
{
  "success": true,
  "message": "Garlic Necklace activated for night protection",
  "appliedEffects": [
    {
      "type": "WARD_VAMPIRE",
      "value": 100,
      "duration": 1,
      "targetRole": "MAFIA"
    }
  ],
  "remainingQuantity": 1,
  "expiresAt": "2025-10-09T08:00:00Z",
  "protectionDetails": {
    "effectiveAgainst": ["MAFIA"],
    "effectPercentage": 100,
    "activeDuringCycles": ["NIGHT"]
  }
}
```

---

## Admin Endpoints (Internal Use)

### Manually Trigger Restock

**Endpoint:** `POST /api/v1/admin/restock`

**Description:** Manually trigger the daily restocking algorithm for all active games.

**Request:**
```bash
curl -X POST http://localhost:8081/api/v1/admin/restock \
  -H "Authorization: Bearer {ADMIN_TOKEN}"
```

**Response:**
```json
{
  "message": "Restock completed successfully",
  "gamesProcessed": 5,
  "itemsRestocked": 45,
  "timestamp": "2025-10-08T15:00:00Z"
}
```

---

### View Transaction Logs

**Endpoint:** `GET /api/v1/admin/transactions`

**Description:** View all transactions with filtering options.

**Query Parameters:**
- `status` (optional): Filter by transaction status
- `userId` (optional): Filter by user
- `gameId` (optional): Filter by game
- `startDate` (optional): Start date range
- `endDate` (optional): End date range
- `page` (optional): Page number
- `size` (optional): Items per page

**Response:**
```json
{
  "transactions": [
    {
      "transactionId": "txn_789xyz",
      "userId": "user_123",
      "gameId": "game_abc_001",
      "totalCost": 130,
      "status": "COMPLETED",
      "itemCount": 3,
      "timestamp": "2025-10-08T14:30:00Z"
    }
  ],
  "totalTransactions": 150,
  "totalPages": 15,
  "currentPage": 0
}
```
---

# Roleplay-Service
The Mafia Platform is built using a microservices architecture, with each service encapsulating specific functionality to ensure modularity and independence. The platform enables users to play a game of Mafia with customized roles and rules.

**Responsibility**: Controls game mechanics related to player roles and actions

## Quick Start with Docker

The fastest way to get started is using Docker. All services are available on Docker Hub.

### Docker Hub Images
- **Application**: `cebanvasile1/roleplay-service:latest`
- **Database**: `cebanvasile1/roleplay-postgres:latest`

### Prerequisites
- Docker Engine 24.0.0 or later
- Docker Compose v2.20.0 or later
- At least 1GB of free RAM
- At least 1GB of free disk space

### Quick Start with Docker Compose
1. Create a `compose.yaml` file:
```yaml
services:
  postgres:
    image: cebanvasile1/roleplay-postgres:latest
    container_name: roleplay-postgres
    environment:
      POSTGRES_DB: mydatabase
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: secret
      LANG: en_US.utf8
    ports:
      - "5433:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U myuser -d mydatabase"]
      interval: 10s
      timeout: 5s
      retries: 5

  roleplay-service:
    image: cebanvasile1/roleplay-service:latest
    container_name: roleplay-service
    environment:
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_NAME=mydatabase
      - DB_USERNAME=myuser
      - DB_PASSWORD=secret
      - SERVER_PORT=8082
      - JPA_DDL_AUTO=update
      - JPA_SHOW_SQL=true
    ports:
      - "8082:8082"
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  postgres_data:
    name: roleplay-postgres-data
```

2. Run the services:
```bash
docker-compose up -d
```

The service will be available at `http://localhost:8082/api/v1/`

### Docker Images Details

#### 1. Roleplay Service (`cebanvasile1/roleplay-service`)
- Spring Boot application with game logic
- Built on OpenJDK 17
- Exposed port: 8082
- Health check endpoint: `/actuator/health`

#### 2. PostgreSQL Database (`cebanvasile1/roleplay-postgres`)
- Based on PostgreSQL 15
- Includes initialization scripts for:
  - Game roles (Town, Mafia, Neutral)
  - Role abilities
  - Game mechanics
- Exposed port: 5432
- Includes health check configuration

### Environment Variables

#### Roleplay Service Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `DB_HOST` | `postgres` | PostgreSQL host |
| `DB_PORT` | `5432` | PostgreSQL port |
| `DB_NAME` | `mydatabase` | Database name |
| `DB_USERNAME` | `myuser` | Database username |
| `DB_PASSWORD` | `secret` | Database password |
| `SERVER_PORT` | `8082` | Application port |
| `JPA_DDL_AUTO` | `update` | Hibernate DDL mode |
| `JPA_SHOW_SQL` | `true` | Show SQL queries |

#### PostgreSQL Variables
| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_DB` | `mydatabase` | Database name |
| `POSTGRES_USER` | `myuser` | Database username |
| `POSTGRES_PASSWORD` | `secret` | Database password |

### Data Persistence
The PostgreSQL database uses a named volume `postgres_data` to persist data across container restarts. The volume is automatically created when you start the services.

### Alternative Setup Methods

### Prerequisites
- Java 17 or higher
- Maven 3.6+ (or use the included Maven wrapper)
- PostgreSQL database (or use Docker Compose)

### Quick Start

#### Option 1: Using the provided scripts
For Windows:
```bash
run.bat
```

For Linux/Mac:
```bash
chmod +x run.sh
./run.sh
```

#### Option 2: Manual commands
Build and run the project manually:
```bash
# Build the project
./mvnw clean compile

# Run the application
./mvnw spring-boot:run
```

#### Option 3: Using Docker Compose
If you have Docker installed, you can use the provided Docker Compose configuration:
```bash
docker-compose up
```
**Functionality**:
- Role assignment and management
- Processing role-specific actions (e.g., Mafia kills, Sheriff investigations)
- Checking item effectiveness during actions
- Recording all action attempts for audit purposes
- Creating filtered announcements for the Game Service to broadcast
- Enforcing role-specific rules and constraints

### Service diagram

```mermaid
flowchart LR
    subgraph MafiaApplication["Mafia Application"]
        RS[("Roleplay Service
        Java + Spring Boot")]
    end

    subgraph DataPersistence["Data Persistence"]
        DB[(PostgreSQL Database)]
    end

    Client["Client / Other Services"]

    Client -- "HTTP/REST API Call" --> RS
    RS -- "JSON Response" --> Client
    RS -- "Reads/Writes roles, actions, announcements, player status" --> DB

```

### Domain Models and Interfaces

#### Role
```typescript
interface Role {
  id: string;
  name: string;
  alignment: 'TOWN' | 'MAFIA' | 'NEUTRAL';
  description: string;
  abilities: Ability[];
  winCondition: string;
}

interface Ability {
  name: string;
  description: string;
  usablePhase: 'DAY' | 'NIGHT' | 'BOTH';
  cooldown: number;
  targets: number;  // Number of players that can be targeted
}
```

#### PlayerRole
```typescript
interface PlayerRole {
  userId: string;
  gameId: string;
  roleId: string;
  roleName: string;
  alignment: 'TOWN' | 'MAFIA' | 'NEUTRAL';
  abilities: PlayerAbility[];
  alive: boolean;
  protectionStatus: Protection[];
}

interface PlayerAbility {
  name: string;
  description: string;
  usablePhase: 'DAY' | 'NIGHT' | 'BOTH';
  cooldown: number;
  remainingCooldown: number;
  used: boolean;
  targets: number;
}

interface Protection {
  type: string;
  source: string;
  expiresAt: Date;
}
```

#### Action
```typescript
interface Action {
  actionId: string;
  gameId: string;
  userId: string;
  roleName: string;
  actionType: string;
  targets: string[];
  usedItems?: string[];
  gamePhase: 'DAY' | 'NIGHT';
  status: 'PENDING' | 'SUCCESS' | 'FAILED' | 'BLOCKED';
  results: ActionResult[];
  timestamp: Date;
}

interface ActionResult {
  targetId: string;
  outcome: string;
  visible: boolean;
  message: string;
}
```

#### Announcement
```typescript
interface Announcement {
  announcementId: string;
  gameId: string;
  message: string;
  visibleTo: ('ALL' | 'MAFIA' | 'TOWN' | 'SPECIFIC_ROLE' | 'SPECIFIC_USER')[];
  targetUsers?: string[];
  phase: 'DAY' | 'NIGHT';
  timestamp: Date;
}
```

### APIs Exposed

#### 1. Perform Role Action

**Endpoint:** `POST /api/v1/actions`

**Description:** Executes a role-specific action in the game.

**Request Format:**
```json
{
  "gameId": "string",
  "userId": "string",
  "actionType": "string",
  "targets": ["string"],
  "usedItems": ["string"],
  "gamePhase": "DAY|NIGHT",
  "timestamp": "string (ISO-8601 format)"
}
```

**Response Format:**
```json
{
  "actionId": "string",
  "status": "PENDING|SUCCESS|FAILED|BLOCKED",
  "results": [
    {
      "targetId": "string",
      "outcome": "string",
      "visible": true,
      "message": "string"
    }
  ],
  "timestamp": "string (ISO-8601 format)",
  "message": "string"
}
```

**Status Codes:**
- 201: Action submitted
- 404: User, game, or target not found
- 500: Server error

#### 2. Get Available Roles

**Endpoint:** `GET /api/v1/roles`

**Description:** Retrieves information about all available roles in the game.

**Response Format:**
```json
{
  "roles": [
    {
      "id": "string",
      "name": "string",
      "alignment": "TOWN|MAFIA|NEUTRAL",
      "description": "string",
      "abilities": [
        {
          "name": "string",
          "description": "string",
          "usablePhase": "DAY|NIGHT|BOTH",
          "cooldown": 0,
          "targets": 0
        }
      ],
      "winCondition": "string"
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 500: Server error

#### 3. Get User Role

**Endpoint:** `GET /api/v1/roles/{userId}`

**Description:** Retrieves the role assigned to a specific user in a game.

**Path Parameters:**
- `userId`: Unique identifier of the user

**Query Parameters:**
- `gameId` (required): The game context for the role query

**Response Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "roleName": "string",
  "alignment": "TOWN|MAFIA|NEUTRAL",
  "abilities": [
    {
      "name": "string",
      "description": "string",
      "usablePhase": "DAY|NIGHT|BOTH",
      "cooldown": 0,
      "remainingCooldown": 0,
      "used": false,
      "targets": 0
    }
  ],
  "alive": true,
  "protectionStatus": [
    {
      "type": "string",
      "source": "string",
      "expiresAt": "string (ISO-8601 format)"
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 404: User or game not found
- 500: Server error

#### 4. Create Game Announcement

**Endpoint:** `POST /api/v1/announcements`

**Description:** Creates a filtered game announcement based on game events.

**Request Format:**
```json
{
  "gameId": "string",
  "eventType": "string",
  "rawData": {
    "key1": "value1",
    "key2": "value2"
  },
  "visibleTo": ["ALL|MAFIA|TOWN|SPECIFIC_ROLE|SPECIFIC_USER"],
  "targetUsers": ["string"],
  "phase": "DAY|NIGHT",
  "timestamp": "string (ISO-8601 format)"
}
```

**Response Format:**
```json
{
  "announcementId": "string",
  "gameId": "string",
  "message": "string",
  "visibleTo": ["ALL|MAFIA|TOWN|SPECIFIC_ROLE|SPECIFIC_USER"],
  "targetUsers": ["string"],
  "phase": "DAY|NIGHT",
  "timestamp": "string (ISO-8601 format)"
}
```

**Status Codes:**
- 201: Announcement created
- 404: Game not found
- 500: Server error

#### 5. Get Action History

**Endpoint:** `GET /api/v1/actions/history`

**Description:** Retrieves the history of actions in a game (admin only).

**Query Parameters:**
- `gameId` (required): The game context for the action history

**Response Format:**
```json
{
  "actions": [
    {
      "actionId": "string",
      "gameId": "string",
      "userId": "string",
      "roleName": "string",
      "actionType": "string",
      "targets": ["string"],
      "usedItems": ["string"],
      "gamePhase": "DAY|NIGHT",
      "status": "PENDING|SUCCESS|FAILED|BLOCKED",
      "results": [
        {
          "targetId": "string",
          "outcome": "string",
          "visible": true,
          "message": "string"
        }
      ],
      "timestamp": "string (ISO-8601 format)"
    }
  ],
  "totalActions": 0,
  "totalPages": 0,
  "currentPage": 0
}
```

**Status Codes:**
- 200: Success
- 403: Unauthorized access
- 404: Game not found
- 500: Server error

#### 6. Get Action Results

**Endpoint:** `GET /api/v1/actions/results`

**Description:** Retrieves the results of actions for the current phase.

**Query Parameters:**
- `gameId` (required): The game context for the action results
- `userId` (required): The user requesting the results
- `phase` (required): Game phase (DAY, NIGHT)

**Response Format:**
```json
{
  "gameId": "string",
  "phase": "DAY|NIGHT",
  "results": [
    {
      "actionType": "string",
      "actor": "string",
      "targets": ["string"],
      "outcome": "string",
      "message": "string",
      "timestamp": "string (ISO-8601 format)"
    }
  ],
  "roleSpecificResults": [
    {
      "actionType": "string",
      "actor": "string",
      "targets": ["string"],
      "outcome": "string",
      "message": "string",
      "visibleTo": ["string"],
      "timestamp": "string (ISO-8601 format)"
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 403: Unauthorized access
- 404: Game or user not found
- 500: Server error

#### 7. Register Protection (Shop Service Integration)

**Endpoint:** `POST /api/v1/protections`

**Description:** Registers a protection effect when a player uses a protective item from the Shop Service. This endpoint is called by the Shop Service when a player activates a protective item like Garlic Necklace, Holy Water, etc.

**Request Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "itemId": "string",
  "type": "WARD_VAMPIRE|DOUSE_ARSONIST|CONCEAL_IDENTITY|BLOCK_ACTION",
  "expiresAt": "string (ISO-8601 format)"
}
```

**Response Format:**
```json
{
  "success": true,
  "message": "Protection registered successfully",
  "protectionId": "string"
}
```

**Status Codes:**
- 201: Protection registered successfully
- 404: Player role not found
- 400: Invalid request data
- 500: Server error

**Business Logic:**
1. Validates that the player exists in the specified game
2. Creates a protection record linked to the player's role
3. Sets the protection source as "SHOP_ITEM:{itemId}"
4. Applies the protection until the specified expiration time
5. Returns success confirmation with protection ID

**Integration with Shop Service:**
- Called when player uses item via `POST /api/v1/inventory/{userId}/use`
- Protection is automatically checked during role actions
- Expired protections are cleaned up automatically

---

#### 8. Verify Item Effectiveness

**Endpoint:** `POST /api/v1/actions/verify-item`

**Description:** Verifies how effective a shop item will be against specific roles or during specific game phases. This helps the Shop Service provide accurate information to players about item effectiveness.

**Request Format:**
```json
{
  "itemId": "string",
  "effectType": "WARD_VAMPIRE|DOUSE_ARSONIST|CONCEAL_IDENTITY|BLOCK_ACTION|REVEAL_ROLE",
  "targetRoleId": "string (optional)",
  "gamePhase": "DAY|NIGHT"
}
```

**Response Format:**
```json
{
  "effective": true,
  "effectMultiplier": 1.0,
  "message": "Item is fully effective against this role"
}
```

**Effect Multiplier Values:**
- `1.0` - Fully effective (100% protection/success)
- `0.5-0.9` - Partially effective
- `0.0` - Not effective

**Effectiveness Matrix:**

| Protection Type | Effective Against | Multiplier |
|----------------|-------------------|------------|
| WARD_VAMPIRE | MAFIA, VAMPIRE | 1.0 |
| WARD_VAMPIRE | NEUTRAL, TOWN | 0.0 |
| DOUSE_ARSONIST | ARSONIST | 1.0 |
| DOUSE_ARSONIST | NEUTRAL | 0.3 |
| CONCEAL_IDENTITY | DETECTIVE, INVESTIGATOR | 1.0 |
| CONCEAL_IDENTITY | SHERIFF | 0.8 |
| CONCEAL_IDENTITY | TOWN | 0.5 |
| BLOCK_ACTION | MAFIA, NEUTRAL | 0.5 |
| BLOCK_ACTION | TOWN | 0.3 |
| REVEAL_ROLE | MAFIA | 0.8 |
| REVEAL_ROLE | NEUTRAL | 0.6 |

**Status Codes:**
- 200: Success
- 400: Invalid request data
- 500: Server error

**Usage Examples:**

1. **Check protection against specific role:**
```json
{
  "itemId": "item_garlic_001",
  "effectType": "WARD_VAMPIRE",
  "targetRoleId": "role_mafia_001",
  "gamePhase": "NIGHT"
}
```
Response:
```json
{
  "effective": true,
  "effectMultiplier": 1.0,
  "message": "Item is fully effective against this role"
}
```

2. **Check general effectiveness:**
```json
{
  "itemId": "item_mask_001",
  "effectType": "CONCEAL_IDENTITY",
  "gamePhase": "DAY"
}
```
Response:
```json
{
  "effective": true,
  "effectMultiplier": 0.5,
  "message": "Item is generally effective"
}
```

**Integration with Shop Service:**
- Called when displaying item details: `GET /api/v1/items/{itemId}/effectiveness`
- Used for item recommendations: `GET /api/v1/items/recommendations`
- Helps players make informed purchasing decisions

---

### Inter-Service Communication

#### Incoming Requests from Shop Service

The Roleplay Service now provides two integration endpoints for the Shop Service:

**1. Protection Registration**
- **Trigger:** When player uses protective item via Shop Service
- **Flow:** Shop Service → `POST /api/v1/protections` → Roleplay Service
- **Purpose:** Register active protection that will be checked during night actions
- **Example:** Player uses Garlic Necklace, protection registered, prevents Mafia kill

**2. Item Effectiveness Verification**
- **Trigger:** When displaying item details or recommendations in Shop Service
- **Flow:** Shop Service → `POST /api/v1/actions/verify-item` → Roleplay Service
- **Purpose:** Provide accurate effectiveness information to players
- **Example:** Player views Garlic Necklace, sees it's 100% effective against Mafia

#### Integration Sequence Diagram

```mermaid
sequenceDiagram
    participant Player
    participant ShopService
    participant RoleplayService
    participant Database

    Note over Player,Database: Item Purchase & Usage Flow
    
    Player->>ShopService: POST /api/v1/inventory/{userId}/use
    ShopService->>ShopService: Verify item in inventory
    ShopService->>RoleplayService: POST /api/v1/actions/verify-item
    RoleplayService-->>ShopService: Effectiveness: 100%, Effective: true
    ShopService->>RoleplayService: POST /api/v1/protections
    RoleplayService->>Database: Save protection record
    RoleplayService-->>ShopService: Protection registered (ID)
    ShopService->>ShopService: Mark item as used
    ShopService-->>Player: Protection activated

    Note over Player,Database: Later during Night Phase
    
    Player->>RoleplayService: POST /api/v1/actions (Mafia kill attempt)
    RoleplayService->>Database: Check target protections
    Database-->>RoleplayService: WARD_VAMPIRE active
    RoleplayService->>RoleplayService: Block action (protection active)
    RoleplayService-->>Player: Action blocked
```

---

## API Endpoint Summary

The Roleplay Service provides **8 public endpoints** organized into 4 categories:

### Role Management (3 endpoints)
1. `GET /api/v1/roles` - Get all available roles
2. `GET /api/v1/roles/{userId}` - Get user's role in a game
3. `POST /api/v1/player-roles` - Assign role to player (Admin)

### Action Processing (4 endpoints)
4. `POST /api/v1/actions` - Perform role-specific action
5. `GET /api/v1/actions/history` - Get action history (Admin)
6. `GET /api/v1/actions/results` - Get action results for current phase
7. `POST /api/v1/actions/verify-item` - Verify item effectiveness (🔗 Shop Service)

### Protection Management (1 endpoint)
8. `POST /api/v1/protections` - Register protection from Shop Service (🔗 Shop Service)

### Announcements (1 endpoint - Admin)
9. `POST /api/v1/announcements` - Create game announcement

🔗 = **Service Integration** - Endpoint used by external microservices

---

## Testing

### API Testing with cURL

#### 1. Test Item Effectiveness Verification

```bash
# Check if Garlic Necklace is effective against Mafia
curl -X POST http://localhost:8082/api/v1/actions/verify-item \
  -H "Content-Type: application/json" \
  -d '{
    "itemId": "item_garlic_001",
    "effectType": "WARD_VAMPIRE",
    "targetRoleId": "role_mafia_001",
    "gamePhase": "NIGHT"
  }'
```

Expected Response:
```json
{
  "effective": true,
  "effectMultiplier": 1.0,
  "message": "Item is fully effective against this role"
}
```

#### 2. Test Protection Registration

```bash
# Register protection when player uses protective item
curl -X POST http://localhost:8082/api/v1/protections \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_123",
    "gameId": "game_abc_001",
    "itemId": "item_garlic_001",
    "type": "WARD_VAMPIRE",
    "expiresAt": "2025-10-11T08:00:00Z"
  }'
```

Expected Response:
```json
{
  "success": true,
  "message": "Protection registered successfully",
  "protectionId": "protection_xyz_789"
}
```

#### 3. Test Role Action

```bash
# Perform a Mafia kill action
curl -X POST http://localhost:8082/api/v1/actions \
  -H "Content-Type: application/json" \
  -d '{
    "gameId": "game_abc_001",
    "userId": "user_456",
    "actionType": "KILL",
    "targets": ["user_123"],
    "gamePhase": "NIGHT",
    "timestamp": "2025-10-10T22:00:00Z"
  }'
```

Expected Response (if target has protection):
```json
{
  "actionId": "action_123",
  "status": "BLOCKED",
  "results": [
    {
      "targetId": "user_123",
      "outcome": "BLOCKED",
      "visible": false,
      "message": "Target was protected by WARD_VAMPIRE"
    }
  ],
  "timestamp": "2025-10-10T22:00:00Z",
  "message": "Action blocked by active protection"
}
```

#### 4. Get User Role

```bash
# Get player's role information
curl -X GET "http://localhost:8082/api/v1/roles/user_123?gameId=game_abc_001"
```

Expected Response:
```json
{
  "userId": "user_123",
  "gameId": "game_abc_001",
  "roleName": "Villager",
  "alignment": "TOWN",
  "abilities": [],
  "alive": true,
  "protectionStatus": [
    {
      "type": "WARD_VAMPIRE",
      "source": "SHOP_ITEM:item_garlic_001",
      "expiresAt": "2025-10-11T08:00:00Z"
    }
  ]
}
```

### Integration Testing with Shop Service

#### Complete Flow Test

1. **Setup prerequisite data:**
```bash
# Ensure player role exists
# Ensure game is active
# Ensure Shop Service is running on port 8081
```

2. **Purchase item from Shop:**
```bash
curl -X POST http://localhost:8081/api/v1/purchases \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user_123",
    "gameId": "game_abc_001",
    "gameDay": 3,
    "items": [{"itemId": "item_garlic_001", "quantity": 1}]
  }'
```

3. **Use item (triggers protection registration):**
```bash
curl -X POST http://localhost:8081/api/v1/inventory/user_123/use \
  -H "Content-Type: application/json" \
  -d '{
    "gameId": "game_abc_001",
    "gameDay": 3,
    "gameCycle": "NIGHT",
    "inventoryItemId": "inv_item_001",
    "targetUserId": "user_123"
  }'
```

4. **Verify protection was registered:**
```bash
curl -X GET "http://localhost:8082/api/v1/roles/user_123?gameId=game_abc_001"
# Check protectionStatus in response
```

5. **Test protection during action:**
```bash
# Attempt kill action against protected player
curl -X POST http://localhost:8082/api/v1/actions \
  -H "Content-Type: application/json" \
  -d '{
    "gameId": "game_abc_001",
    "userId": "mafia_user",
    "actionType": "KILL",
    "targets": ["user_123"],
    "gamePhase": "NIGHT"
  }'
# Should return BLOCKED status
```

### Unit Testing

```bash
# Run all tests
./mvnw test

# Run specific test class
./mvnw test -Dtest=ProtectionServiceTest

# Run with coverage
./mvnw test jacoco:report
# View coverage at target/site/jacoco/index.html
```

### Test Coverage

The service includes comprehensive tests for:
- ✅ Protection registration and validation
- ✅ Item effectiveness calculation
- ✅ Role action processing with protections
- ✅ Protection expiration cleanup
- ✅ Integration with Shop Service endpoints
- ✅ Error handling and edge cases

---

## Configuration

### Application Properties

```properties
# Server Configuration
server.port=${SERVER_PORT:8082}
spring.application.name=roleplay-service

# Database Configuration
spring.datasource.url=jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:mydatabase}
spring.datasource.username=${DB_USERNAME:myuser}
spring.datasource.password=${DB_PASSWORD:secret}
spring.jpa.hibernate.ddl-auto=${JPA_DDL_AUTO:update}
spring.jpa.show-sql=${JPA_SHOW_SQL:true}
spring.jpa.properties.hibernate.format_sql=true

# Connection Pool
spring.datasource.hikari.maximum-pool-size=10
spring.datasource.hikari.minimum-idle=5
spring.datasource.hikari.connection-timeout=30000

# Logging
logging.level.root=INFO
logging.level.com.mafia.roleplay_service=DEBUG
logging.pattern.console=%d{yyyy-MM-dd HH:mm:ss} - %msg%n

# CORS Configuration
cors.allowed-origins=*
cors.allowed-methods=GET,POST,PUT,DELETE,OPTIONS
cors.allowed-headers=*

# Protection Cleanup Schedule (runs daily at midnight)
protection.cleanup.cron=0 0 0 * * *
```

### Environment Variables

Create a `.env` file for local development:

```env
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=roleplay_db
DB_USERNAME=roleplay_user
DB_PASSWORD=your_secure_password

# Server Configuration
SERVER_PORT=8082

# JPA Configuration
JPA_DDL_AUTO=update
JPA_SHOW_SQL=true

# External Services (for future integration)
GAME_SERVICE_URL=http://localhost:3000
SHOP_SERVICE_URL=http://localhost:8081
```

---

## Database Schema

### Core Tables

```sql
-- Roles table (predefined game roles)
CREATE TABLE roles (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    alignment VARCHAR(20) NOT NULL,
    description TEXT,
    win_condition TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Abilities table (role abilities)
CREATE TABLE abilities (
    id VARCHAR(36) PRIMARY KEY,
    role_id VARCHAR(36) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    usable_phase VARCHAR(20) NOT NULL,
    cooldown INTEGER DEFAULT 0,
    targets INTEGER DEFAULT 1,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

-- Player roles (assigned to users in games)
CREATE TABLE player_roles (
    id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    game_id VARCHAR(36) NOT NULL,
    role_id VARCHAR(36) NOT NULL,
    alive BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id),
    UNIQUE KEY unique_user_game (user_id, game_id),
    INDEX idx_game (game_id),
    INDEX idx_user (user_id)
);

-- Player abilities (tracking cooldowns and usage)
CREATE TABLE player_abilities (
    id VARCHAR(36) PRIMARY KEY,
    player_role_id VARCHAR(36) NOT NULL,
    ability_id VARCHAR(36) NOT NULL,
    remaining_cooldown INTEGER DEFAULT 0,
    used BOOLEAN DEFAULT FALSE,
    FOREIGN KEY (player_role_id) REFERENCES player_roles(id) ON DELETE CASCADE,
    FOREIGN KEY (ability_id) REFERENCES abilities(id)
);

-- Protections (Shop Service integration)
CREATE TABLE protections (
    id VARCHAR(36) PRIMARY KEY,
    player_role_id VARCHAR(36) NOT NULL,
    type VARCHAR(50) NOT NULL,
    source VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (player_role_id) REFERENCES player_roles(id) ON DELETE CASCADE,
    INDEX idx_expiration (expires_at),
    INDEX idx_player (player_role_id)
);

-- Actions (game actions performed by players)
CREATE TABLE actions (
    id VARCHAR(36) PRIMARY KEY,
    game_id VARCHAR(36) NOT NULL,
    user_id VARCHAR(36) NOT NULL,
    action_type VARCHAR(50) NOT NULL,
    game_phase VARCHAR(20) NOT NULL,
    status VARCHAR(20) DEFAULT 'PENDING',
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_game_phase (game_id, game_phase),
    INDEX idx_user (user_id)
);

-- Action results
CREATE TABLE action_results (
    id VARCHAR(36) PRIMARY KEY,
    action_id VARCHAR(36) NOT NULL,
    target_id VARCHAR(36) NOT NULL,
    outcome VARCHAR(50) NOT NULL,
    visible BOOLEAN DEFAULT TRUE,
    message TEXT,
    FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE CASCADE
);

-- Announcements
CREATE TABLE announcements (
    id VARCHAR(36) PRIMARY KEY,
    game_id VARCHAR(36) NOT NULL,
    message TEXT NOT NULL,
    phase VARCHAR(20) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_game (game_id)
);
```

### Seed Data (Included in Docker Image)

The database initialization scripts include:

**Roles:**
- Town: Villager, Doctor, Detective, Sheriff
- Mafia: Godfather, Goon
- Neutral: Survivor, Jester

**Abilities:**
- Doctor: Heal (NIGHT, targets: 1)
- Detective: Investigate (NIGHT, targets: 1)
- Mafia: Kill (NIGHT, targets: 1)
- And more...

---

## Error Handling

### Error Response Format

All endpoints return standardized error responses:

```json
{
  "timestamp": "2025-10-10T12:00:00Z",
  "status": 404,
  "error": "Not Found",
  "message": "Player role not found for user user_123 in game game_abc_001",
  "path": "/api/v1/protections"
}
```

### Common Error Codes

| Status | Error | Description |
|--------|-------|-------------|
| 400 | Bad Request | Invalid request data or validation failure |
| 404 | Not Found | Resource not found (player, role, game) |
| 409 | Conflict | Duplicate resource or conflicting state |
| 500 | Internal Server Error | Unexpected server error |

### Shop Service Integration Errors

**Protection Registration Errors:**

1. **Player Not Found:**
```json
{
  "status": 404,
  "error": "ResourceNotFoundException",
  "message": "Player role not found for user user_123 in game game_abc_001"
}
```
**Solution:** Ensure player role is assigned before registering protection

2. **Invalid Protection Type:**
```json
{
  "status": 400,
  "error": "Bad Request",
  "message": "Protection type is required"
}
```
**Solution:** Verify protection type is one of: WARD_VAMPIRE, DOUSE_ARSONIST, CONCEAL_IDENTITY, BLOCK_ACTION

**Item Effectiveness Verification Errors:**

1. **Unknown Effect Type:**
```json
{
  "effective": false,
  "effectMultiplier": 0.0,
  "message": "Unknown protection type: INVALID_TYPE"
}
```
**Solution:** Use valid effect types defined in the effectiveness matrix

2. **Role Not Found:**
```json
{
  "effective": false,
  "effectMultiplier": 0.0,
  "message": "Target role not found"
}
```
**Solution:** Verify targetRoleId exists in the roles table

## Rumors Service

* **Core responsibility:** Currency-based information marketplace allowing players to purchase intelligence about other players based on their tasks and appearance data. Track information availability by role restrictions and generate rumors from Task Service and Character Service data.

### Tech stack

* **Framework/language:** Java + Spring Boot (enterprise-grade reliability for financial transactions, strong typing for currency operations, third language requirement)
* **Database:** MongoDB (flexible document storage for varied rumor data structures, easy schema evolution)
* **Other:** Redis for caching expensive rumor generation, JWT for authentication
* **Communication pattern:** REST API with other services, async processing for rumor generation

### Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph subGraph0["Mafia Application"]
        B("Rumors Service <br> Java + Spring Boot")
        A["Client / Other Services"]
  end
 subgraph subGraph2["Data Persistence"]
        D[("MongoDB Database")]
        E[("Redis Cache")]
  end
    A -- HTTP/REST API Call --> B
    B -- JSON Response --> A
    B -- Reads/Writes rumor data --> D
    B -- Caches rumor generation --> E
    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
    style E fill:#bbf,stroke:#333,stroke-width:2px
```

### Schema

```java
public class Rumor {
    private String id;
    private String buyerId;
    private String targetPlayerId;
    private String informationType; // "TASK", "APPEARANCE", "INVENTORY"
    private String content;
    private Double accuracy; // 0.0 to 1.0
    private Integer cost;
    private List<String> availableToRoles;
    private LocalDateTime purchasedAt;
}

public class RumorTemplate {
    private String id;
    private String template; // "Player {name} was seen {action}"
    private String sourceService;
    private List<String> roleRestrictions;
    private Integer baseCost;
}
```

### Endpoints

#### `POST v1/rumors/purchase` – Buy a rumor with currency

Body:
```json
{
    "targetPlayerId": "uuid-of-target",
    "informationType": "TASK"
}
```

#### `GET v1/rumors/available` – Get available rumors for user's role

Returns array of available rumor types for the current user's role.

#### `GET v1/rumors/pricing` – Get current rumor costs

Returns pricing information for different rumor types.

#### `GET v1/rumors/history/{userId}` – Get purchase history

Returns user's rumor purchase history.

### Dependencies

* MongoDB container
* Redis container  
* Java Spring Boot runtime
* Integration with User Management Service (currency deduction)
* Integration with Task Service (task data)
* Integration with Character Service (appearance data)

## Communication Service

* **Core responsibility:** Multi-channel chat system with game-state-aware messaging rules. Global chat during voting hours, private Mafia channels, location-based messaging.

### Tech stack

* **Framework/language:** Java + Spring Boot (consistent with Rumors Service, WebSocket support, enterprise reliability for real-time messaging)
* **Database:** PostgreSQL (ACID compliance for chat history, consistent with other services)
* **Other:** WebSocket for real-time messaging, Redis pub/sub for message broadcasting
* **Communication pattern:** REST + WebSocket APIs, event-driven messaging

### Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph subGraph0["Mafia Application"]
        B("Communication Service <br> Java + Spring Boot")
        A["Client / Other Services"]
  end
 subgraph subGraph2["Data Persistence"]
        D[("PostgreSQL Database")]
        E[("Redis Pub/Sub")]
  end
    A -- HTTP/REST + WebSocket --> B
    B -- Real-time Messages --> A
    B -- Reads/Writes chat data --> D
    B -- Message broadcasting --> E
    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
    style E fill:#bbf,stroke:#333,stroke-width:2px
```

### Schema

```java
public class ChatMessage {
    private String id;
    private String senderId;
    private String channelId;
    private String content;
    private String type; // "GLOBAL", "MAFIA", "LOCATION"
    private LocalDateTime timestamp;
}

public class ChatChannel {
    private String id;
    private String type;
    private String name;
    private String locationId; // optional for location-based chats
    private List<String> participants;
    private Boolean isActive;
}
```

### Endpoints

#### `POST v1/chat/global/messages` – Send global message (voting hours only)

Body:
```json
{
    "content": "I think player X is suspicious"
}
```

#### `GET v1/chat/global/messages` – Get global chat history

Returns array of global chat messages.

#### `POST v1/chat/mafia/messages` – Send Mafia private message

Body:
```json
{
    "content": "Let's target player Y tonight"
}
```

#### `GET v1/chat/channels/{channelId}/messages` – Get channel messages

Returns messages for specific channel.

#### `WS v1/chat/ws` – WebSocket connection for real-time messaging

WebSocket endpoint for real-time message delivery.

### Dependencies

* PostgreSQL DB container
* Redis container
* Java Spring Boot runtime
* WebSocket support
* Integration with Game Service (voting hours, game state)
* Integration with User Management Service (user roles, authentication)

# Task Service

**Core responsibility:** Assign daily tasks at the start of the day based on each player's role and career. Track completion of those tasks, reward in-game currency, and optionally generate rumors that influence the game narrative.

## Docker Hub Images

**Published on Docker Hub:**
- `rayderr/mafia_liviu_task_service:1.0.6` - Multi-platform support (Windows/Mac/Linux)
- `rayderr/mafia_liviu_task_service:latest` - Latest build

## Quick Start with Docker (Recommended)

### Prerequisites
- Docker & Docker Compose installed
- No Node.js or local setup needed!
- Works on Windows, macOS (Intel/M1/M2), and Linux

### Run from Docker Hub
```bash
# Start PostgreSQL database
docker run -d --name task-db \
  -e POSTGRES_USER=task_user \
  -e POSTGRES_PASSWORD=secure_password_123 \
  -e POSTGRES_DB=task_service_db \
  -p 5001:5432 \
  postgres:16-alpine

# Run Task Service from Docker Hub
docker run -d --name task-service \
  -p 3001:3001 \
  -e DATABASE_URL="postgresql://task_user:secure_password_123@task-db:5432/task_service_db" \
  --link task-db \
  rayderr/mafia_liviu_task_service:latest

# Verify it's working
curl http://localhost:3001/health
```

## Tech Stack

- **Framework/Language:** TypeScript + Express.js (lightweight, fast development, excellent ecosystem for REST APIs)
- **Database:** PostgreSQL (transactional safety for task assignment and reward crediting)
- **ORM:** Prisma (type-safe database access, automatic migrations, great TypeScript integration)
- **Validation:** Zod (runtime type validation for API requests)
- **Authentication:** JWT middleware for request authorization
- **Communication:** REST API (JSON over HTTP) between services

## Service Architecture

```mermaid
flowchart TD
  subgraph Client
    P[Players]
  end

  subgraph Game
    G[Game Service]
  end

  subgraph Task
    T[Task Service <br/> TypeScript + Express]
  end

  subgraph User
    U[User Management Service]
  end

  P -->|View tasks / submit completion| T
  G -->|Day start signal| T
  T -->|Reward currency| U
```

## API Endpoints

### Interactive Documentation
**Swagger UI:** http://localhost:3001/docs

### Main Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/tasks/day/start` | Start new day and assign tasks |
| GET | `/api/v1/tasks/user/{userId}` | Get user's tasks |
| POST | `/api/v1/tasks/{id}/start` | Start a task |
| POST | `/api/v1/tasks/{id}/complete` | Complete task |
| POST | `/api/v1/tasks/{id}/fail` | Fail a task |
| GET | `/api/v1/tasks/day/{day}/stats` | Day statistics |
| POST | `/api/v1/tasks/day/{day}/end` | End day and expire tasks |
| GET | `/api/v1/definitions` | List task definitions |
| POST | `/api/v1/definitions` | Create task definition |
| PATCH | `/api/v1/definitions/{id}` | Update task definition |
| DELETE | `/api/v1/definitions/{id}` | Delete task definition |
| GET | `/api/v1/rumors/day/{day}` | Get day rumors |
| GET | `/api/v1/rumors/user/{userId}` | Get user rumors |

### Example Requests

**Start Day 2 (Day 1 has seed data):**
```bash
curl -X POST http://localhost:3001/api/v1/tasks/day/start \
  -H "Content-Type: application/json" \
  -d '{
    "day": 2,
    "activeUsers": [
      {"userId": "user-1", "role": "doctor"},
      {"userId": "user-2", "role": "teacher"}
    ]
  }'
```

**Get User Tasks:**
```bash
curl "http://localhost:3001/api/v1/tasks/user/user-1?day=2"
```

## Database Schema

### Core Models (Prisma)

```prisma
model TaskDefinition {
  id              String   @id @default(uuid())
  role            String   // Target role (doctor, teacher, ANY)
  title           String
  description     String
  requirementType TaskRequirementType
  rewardAmount    Int
  difficulty      Int      // 1-5 scale
  isActive        Boolean
}

model DailyTaskAssignment {
  id               String     @id @default(uuid())
  userId           String
  taskDefinitionId String
  day              Int
  status           TaskStatus // ASSIGNED, IN_PROGRESS, COMPLETED, FAILED
  expiresAt        DateTime
  earnedReward     Int?
}

model Rumor {
  id           String   @id @default(uuid())
  day          Int
  sourceUserId String
  content      String
  visibility   String   // PUBLIC, PRIVATE, ROLE_SPECIFIC
}
```

## Testing

### 1. API Testing with Postman (Recommended)
1. Import `Task_Service_Complete.postman_collection.json` or `postman/task-service.postman_collection.json`
2. Set `baseUrl` to `http://localhost:3001`
3. Run the collection or individual requests
4. Use the "Workflows" folder for complete task flow testing

**Important:** The 400 errors like "DAY_ALREADY_STARTED" or "TASK_ALREADY_COMPLETED" are **correct behavior**, not bugs! They prevent duplicate operations.

### 2. Interactive Testing with Swagger UI
Open in browser: http://localhost:3001/docs
- Try out all endpoints directly in the browser
- See request/response examples
- Test with different parameters

### 3. Quick API Tests with cURL
```bash
# Health check
curl http://localhost:3001/health

# Start a new day
curl -X POST http://localhost:3001/api/v1/tasks/day/start \
  -H "Content-Type: application/json" \
  -d '{"day": 1, "activeUsers": [{"userId": "user1", "role": "doctor"}]}'

# Get user tasks
curl http://localhost:3001/api/v1/tasks/user/user1

# Get task definitions
curl http://localhost:3001/api/v1/definitions
```

### 4. Unit Testing
```bash
# Run all tests
npm test

# Run tests with coverage (91% statement coverage)
npm run test:coverage

# Run specific test suite
npm run test:unit
```

### 5. Test Scripts
```bash
# Quick test script - health checks and status
./quick-test.sh

# Comprehensive test script - full API testing
./test-service.sh
```

### 6. Docker Testing
```bash
# Ensure service is running
docker-compose up -d

# Check logs
docker-compose logs -f task-service

# Run tests in container
docker exec task-service npm test
```

### 7. Reset for Fresh Testing
```bash
# Reset database with seed data
docker exec task-service npm run db:reset

# Or start with different day numbers (Day 2, 3, etc.) instead of Day 1
```

## Data Ownership

This service owns:
- `task_definitions` - Task templates
- `daily_task_assignments` - User task assignments
- `task_events` - Task lifecycle events
- `rumors` - Generated rumors from task completions

## Deployment Instructions

### Cross-Platform Deployment (Windows/Mac/Linux)

**Option A: Using Docker Compose (Recommended)**
```bash
# Clone repository
git clone <repository>
cd task-service

# Start services
docker-compose up -d

# Verify it's working
curl http://localhost:3001/health
# Or open browser: http://localhost:3001/docs
```

**Option B: Using Published Docker Image**
```bash
# Pull latest image
docker pull rayderr/mafia_liviu_task_service:latest

# Run with docker-compose
docker-compose up -d
```

### Windows-Specific Instructions
```powershell
# Using PowerShell or Command Prompt
docker-compose up -d

# Check health (PowerShell)
Invoke-RestMethod http://localhost:3001/health
```

### macOS/Linux Instructions
```bash
# Standard Docker commands work
docker-compose up -d
curl http://localhost:3001/health
```

### Testing the Service
1. Open Swagger UI: http://localhost:3001/docs
2. Import Postman collection from `/postman` folder
3. Run test workflows to demonstrate functionality


# Voting Service - Mafia Game Platform

**Core responsibility:** Manage evening voting sessions. Open voting windows, collect one vote per eligible player, tally results, resolve ties, and return the exiled player information to the Game Service.

## Docker Hub Images

**Published on Docker Hub:**
- `rayderr/mafia_liviu_voting_service:1.0.6` - Multi-platform support (Windows/Mac/Linux)
- `rayderr/mafia_liviu_voting_service:latest` - Latest build

## Quick Start with Docker (Recommended)

### Prerequisites
- Docker & Docker Compose installed
- No Node.js or local setup needed!
- Works on Windows, macOS (Intel/M1/M2), and Linux

### Run from Docker Hub
```bash
# Start PostgreSQL database
docker run -d --name voting-db \
  -e POSTGRES_USER=voting_user \
  -e POSTGRES_PASSWORD=secure_password_123 \
  -e POSTGRES_DB=voting_service_db \
  -p 5002:5432 \
  postgres:16-alpine

# Run Voting Service from Docker Hub
docker run -d --name voting-service \
  -p 3002:3002 \
  -e DATABASE_URL="postgresql://voting_user:secure_password_123@voting-db:5432/voting_service_db" \
  --link voting-db \
  rayderr/mafia_liviu_voting_service:latest

# Verify it's working
curl http://localhost:3002/health
```

## Tech Stack

- **Framework/Language:** TypeScript + Express.js (excellent concurrency support, production-grade for voting logic)
- **Database:** PostgreSQL (ensures vote durability and supports complex tally queries)
- **ORM:** Prisma (type-safe database operations, transaction support)
- **Validation:** Zod (runtime validation for vote requests)
- **Real-time:** Socket.io (optional - for live vote count updates)
- **Authentication:** JWT middleware for request authorization
- **Communication:** REST API (JSON over HTTP) for synchronous operations
## Service Architecture

```mermaid
flowchart TD
  subgraph Client
    P[Players]
  end

  subgraph Game
    G[Game Service]
  end

  subgraph Voting
    V[Voting Service <br/> TypeScript + Express]
  end

  P -->|Cast votes| V
  G -->|Open voting + eligible players| V
  V -->|Return exile result| G

```

## API Endpoints

### Interactive Documentation
**Swagger UI:** http://localhost:3002/docs

### Main Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/v1/votes/open` | Open a voting window |
| POST | `/api/v1/votes` | Cast a vote |
| GET | `/api/v1/votes/status/{day}` | Get voting status |
| POST | `/api/v1/votes/close` | Close window and compute results |
| GET | `/api/v1/votes/history/{day}` | Get voting history for day |
| GET | `/api/v1/votes/active` | Get current active window |
| GET | `/api/v1/votes/user/{userId}` | Get user vote history |
| GET | `/api/v1/votes/results` | Get voting results |
| GET | `/api/v1/votes/statistics` | Get overall statistics |

### Example Requests

**Open Voting Window:**
```bash
curl -X POST http://localhost:3002/api/v1/votes/open \
  -H "Content-Type: application/json" \
  -d '{
    "day": 1,
    "eligibleVoters": ["player1", "player2", "player3"],
    "eligibleTargets": ["player1", "player2", "player3"]
  }'
```

**Cast Vote:**
```bash
curl -X POST http://localhost:3002/api/v1/votes \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: unique-key-123" \
  -d '{
    "day": 1,
    "voterId": "player1",
    "targetUserId": "player2"
  }'
```

## Features

### Core Voting Functionality
- **Voting Windows**: Time-boxed voting sessions per game day
- **Eligibility Management**: Define who can vote and who can be voted for
- **Vote Casting**: One vote per player per day with validation
- **Result Computation**: Automatic winner determination
- **Tie Breaking**: Configurable strategies (RANDOM, ELDEST, NO_EXILE)

### Advanced Features
- **Idempotency**: Prevent duplicate votes with idempotency keys
- **Real-time Status**: Track voting progress without revealing individual votes
- **Vote History**: Complete audit trail for all voting activities
- **Statistics**: Aggregate voting metrics and trends
- **Event Logging**: Comprehensive event tracking for debugging

## Architecture

```
voting-service/
├── src/
│   ├── domain/
│   │   └── voting/
│   │       └── service/
│   │           └── VotingService.ts    # Core business logic
│   └── server/
│       ├── index.ts                    # Express server setup
│       └── routes/
│           └── index.ts                 # API route handlers
├── prisma/
│   ├── schema.prisma                   # Database schema
│   └── seed.ts                         # Seed data script
├── tests/
│   ├── voting.test.ts                  # Integration tests
│   ├── service.test.ts                 # Unit tests
│   └── setup.ts                        # Test configuration
├── swagger.yaml                        # OpenAPI specification
├── Dockerfile                          # Multi-stage Docker build
├── docker-compose.yml                  # Container orchestration
└── package.json                        # Dependencies & scripts
```

## Database Schema

### Core Models (Prisma)

```prisma
model VoteWindow {
  id              String    @id @default(uuid())
  day             Int       @unique
  isOpen          Boolean   @default(true)
  eligibleVoters  String[]  // Array of user IDs who can vote
  eligibleTargets String[]  // Array of user IDs who can be voted for
  openedAt        DateTime  @default(now())
  closedAt        DateTime?

  votes           Vote[]
  result          VoteResult?
  
  @@map("vote_windows")
}

model Vote {
  id           String   @id @default(uuid())
  voterId      String
  targetUserId String
  day          Int
  createdAt    DateTime @default(now())

  voteWindow   VoteWindow @relation(fields: [day], references: [day])

  @@unique([voterId, day]) // One vote per voter per day
  @@map("votes")
}

model VoteResult {
  id             String   @id @default(uuid())
  day            Int      @unique
  exiledUserId   String?  // null if tie couldn't be resolved
  totalVotes     Int
  winningVotes   Int
  tieBreakMethod String?  // RANDOM, ELDEST, etc.
  voteCounts     Json     // Detailed vote breakdown
  createdAt      DateTime @default(now())
  voteWindow     VoteWindow @relation(fields: [day], references: [day])

  @@map("vote_results")
}

model VoteEvent {
  id          String   @id @default(uuid())
  day         Int
  eventType   String   // WINDOW_OPENED, VOTE_CAST, etc.
  metadata    Json
  createdAt   DateTime @default(now())

  @@map("vote_events")
}

model VotingConfiguration {
  id             String   @id @default(uuid())
  tieBreakMethod String   @default("RANDOM")
  voteDuration   Int      @default(120) // minutes
  updatedAt      DateTime @updatedAt

  @@map("voting_configuration")
}
```

## Testing

### 1. API Testing with Postman (Recommended)
1. Import `voting-service.postman_collection.json`
2. Set `baseUrl` to `http://localhost:3002`
3. Run the collection or individual requests
4. Use the "Workflows" folder for complete voting flow testing

**Important:** The 400 errors like "VOTE_ALREADY_OPEN" or "ALREADY_VOTED" are **correct behavior**, not bugs! They prevent duplicate operations.

### 2. Interactive Testing with Swagger UI
Open in browser: http://localhost:3002/docs
- Try out all endpoints directly in the browser
- See request/response examples
- Test with different parameters

### 3. Quick API Tests with cURL
```bash
# Health check
curl http://localhost:3002/health

# Open voting window
curl -X POST http://localhost:3002/api/v1/votes/open \
  -H "Content-Type: application/json" \
  -d '{"day": 1, "eligibleVoters": ["user1", "user2"], "eligibleTargets": ["user1", "user2"]}'

# Cast a vote
curl -X POST http://localhost:3002/api/v1/votes \
  -H "Content-Type: application/json" \
  -d '{"day": 1, "voterId": "user1", "targetUserId": "user2"}'

# Get voting status
curl http://localhost:3002/api/v1/votes/status/1
```

### 4. Unit Testing
```bash
# Run all tests
npm test

# Run tests with coverage (>80% statement coverage)
npm run test:coverage

# Run specific test suite
npm run test:unit

# Run in watch mode
npm run test:watch
```

### 5. Test Scripts
```bash
# Quick test script - health checks and status
./test.sh --quick

# Comprehensive test script - full API testing
./test.sh --full

# Unit tests only
./test.sh --unit

# Integration tests only
./test.sh --integration
```

### 6. Docker Testing
```bash
# Ensure service is running
docker-compose up -d

# Check logs
docker-compose logs -f voting-service

# Run tests in container
docker exec voting-service npm test
```

### 7. Reset for Fresh Testing
```bash
# Reset database with seed data
docker exec voting-service npm run db:seed

# Or start with different day numbers (Day 2, 3, etc.) instead of Day 1
```

## Data Ownership

This service owns:
- `vote_windows` - Voting session definitions
- `votes` - Individual player votes
- `vote_results` - Computed voting outcomes
- `vote_events` - Audit trail for all voting activities
- `voting_configuration` - System-wide voting parameters

## Voting Rules & Logic

### Tie Breaking
When multiple players receive the same highest vote count:
1. **RANDOM**: Randomly select one of the tied players
2. **ELDEST**: Exile the player who joined the game earliest
3. **NO_EXILE**: If configured, no one gets exiled on ties

### Vote Validation
- Each player can cast exactly one vote per day
- Players can only vote for eligible targets
- Votes cannot be changed once cast
- Voting window must be open

## Deployment Instructions

### Cross-Platform Deployment (Windows/Mac/Linux)

**Option A: Using Docker Compose (Recommended)**
```bash
# Clone repository
git clone <repository>
cd voting-service

# Start services
docker-compose up -d

# Verify it's working
curl http://localhost:3002/health
# Or open browser: http://localhost:3002/docs
```

**Option B: Using Published Docker Image**
```bash
# Pull latest image
docker pull rayderr/mafia_liviu_voting_service:latest

# Run with docker-compose
docker-compose up -d
```

### Windows-Specific Instructions
```powershell
# Using PowerShell or Command Prompt
docker-compose up -d

# Check health (PowerShell)
Invoke-RestMethod http://localhost:3002/health
```

### macOS/Linux Instructions
```bash
# Standard Docker commands work
docker-compose up -d
curl http://localhost:3002/health
```

### Testing the Service
1. Open Swagger UI: http://localhost:3002/docs
2. Import Postman collection from `/postman` folder or `VotingService.postman_collection.json`
3. Run test workflows to demonstrate functionality

## Testing Scripts

- `./test.sh` - Comprehensive test runner with options
- `./run.sh` - Service startup script with Docker support

## Production Deployment

### Requirements
- Docker and Docker Compose installed
- Environment configuration file (copy from `.env.example`)

### Deployment Steps

1. **Prepare environment file**
   - Copy `.env.example` to `.env`
   - Update passwords and secrets

2. **Start the service**
   ```bash
   docker pull rayderr/mafia_liviu_voting_service:1.0.6
   docker-compose up -d
   ```

3. **Verify deployment**
   ```bash
   curl http://localhost:3002/health
   ```

### Service Management

**View logs:**
```bash
docker-compose logs -f voting-service
```

**Restart service:**
```bash
docker-compose restart voting-service
```

**Stop service:**
```bash
docker-compose down
```

**Backup database:**
```bash
docker exec voting-service-db pg_dump -U voting_user voting_service_db > backup.sql
```

## Environment Setup

Create `.env` file:
```env
# Database
DATABASE_URL="postgresql://username:password@localhost:5432/voting_service_db"

# Server
PORT=3002
NODE_ENV=development

# JWT
JWT_SECRET=your-secret-key

# External Services
GAME_SERVICE_URL=http://localhost:3000
USER_SERVICE_URL=http://localhost:3003

# Voting Configuration
VOTE_DURATION_MINUTES=120
TIE_BREAK_METHOD=RANDOM
```

## Running the Service

```bash
# Install dependencies
npm install

# Generate Prisma client and run migrations
npm run db:setup

# Start development server
npm run dev

# Run tests
npm test

# Build for production
npm run build
npm start
```

## Dependencies

- **Game Service:** Opens/closes voting windows, receives exile results
- **User Management Service:** Validates eligible players
- **Client Applications:** Players cast votes through web/mobile interfaces

## Additional Development Information

### Available Scripts

```bash
# Development
npm run dev          # Start with hot reload
npm run build        # Build TypeScript
npm run lint         # Run ESLint
npm run format       # Format with Prettier

# Database
npm run prisma:generate  # Generate Prisma client
npm run prisma:migrate  # Run migrations
npm run prisma:studio    # Open Prisma Studio
npm run db:seed         # Seed database
npm run db:setup        # Generate + migrate + seed

# Testing
npm test                # Run tests
npm run test:watch      # Watch mode
npm run test:coverage   # Coverage report

# Production
npm start              # Start production server
npm run start:prod     # Start with PM2
```

### Monitoring

**Health Endpoints:**
- `/health` - Service status and uptime
- `/health/database` - Database connectivity

**Metrics Tracked:**
- Total voting sessions
- Votes cast per session
- Players exiled
- Average participation rates

### Security Features

- **Input Validation**: All inputs sanitized
- **SQL Injection Prevention**: Prisma parameterized queries
- **CORS Configuration**: Controlled cross-origin access
- **Rate Limiting Ready**: Infrastructure for rate limits
- **JWT Authentication Ready**: Token validation support
- **Idempotency**: Prevent duplicate operations

# Town Service

## Overview
The **Town Service** manages all available locations in the town (including the **Shop** and the **Information Bureau**).  
It tracks user movements across these locations and reports them to the **Task Service** for further processing.  

This service is minimal by design and does not handle authentication or sensitive data (delegated to the **User Management Service**).  

---

## Core Responsibilities
- Store and manage a catalog of **locations** in the town.
- Track **user movements** between locations.
- Provide an API to query current location, movement history, and available destinations.
- Notify the **Task Service** when relevant movements happen (e.g., entering Shop).

---

## Tech Stack
- **Language/Framework**: Java + Spring Boot  
- **Database**: PostgreSQL  
- **Communication**: Internal REST API for events  
- **Other**: JSON serialization, DB migrations  

---

## Data Schema

### Entities

```java
public class Location {
    private String id;
    private String name;        // unique name, e.g., "Shop", "TownSquare"
    private String description;
    private String createdAt;
    private String updatedAt;
}

public class UserLocation {
    private String id;
    private String userId;      // from User Service
    private String locationId;  // references Location
    private String enteredAt;
    private String exitedAt; 
}
```
## Endpoints

### **Locations**

* `GET v1/locations`
  Returns a list of all available locations.

  **Response:**

  ```json
  [
    { "id": "loc1", "name": "Shop", "description": "Main item shop" }
  ]
  ```

* `POST v1/locations`
  Create a new location.

  **Body:**

  ```json
  { "name": "Library", "description": "Silent reading area" }
  ```

  **Responses:** `201` | `409` (duplicate name)

---

### **Movements**

* `POST v1/movements`
  Record a user entering a new location.
  If the user already has an active location, that record will be closed with `exitedAt`.

  **Body:**

  ```json
  { "userId": "u123", "locationId": "loc1" }
  ```

  **Responses:** `201`

* `GET /v1/location?user_id={userId}`
  Get the user’s current location.

  **Response:**

  ```json
  + {
  +   "userId": "u123",
  +   "locationId": "loc1",
  +   "enteredAt": "2025-09-21T12:00:00Z"
  + }
  ```

* `GET /v1/movements?user_id={userId}`
  Get the user’s movement history.

  **Response:**

  ```json
  + [
  +   { "userId": "u123", "locationId": "loc1", "enteredAt": "...", "exitedAt": "..." },
  +   { "userId": "u123", "locationId": "loc2", "enteredAt": "...", "exitedAt": null }
  + ]

  ```

---

## Dependencies

* PostgreSQL DB Container
* Flyway (DB migrations)
* Jackson (JSON serialization)
* (Optional later) Kafka / RabbitMQ for reporting to Task Service

---

## Example Flow

1. User logs in via **User Management Service**.
2. Client calls `POST /movements` to move user into **TownSquare**.
3. Service stores the record and notifies **Task Service**.
4. Client calls `GET /users/{id}/location` to fetch the active location.

---

## Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
  subgraph subGraph0["Mafia Application"]
        A["Client / Other Services (e.g. User Service, Task Service)"]
        B("Town Service <br> Java + Spring Boot")
  end
  subgraph subGraph2["Data Persistence"]
        D[("PostgreSQL Database")]
  end

    A -- HTTP/REST API Calls --> B
    B -- JSON Responses / Notifications --> A
    B -- Reads/Writes locations & movements --> D

    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
```
---

# Character Service

## Overview

The **Character Service** manages player characters, their customization, and their in-game inventories.
It enables players to personalize their avatar by equipping items (assets) into specific **slots** (e.g., hair, coat, shoes), as well as manage purchased assets from the **Shop**.

This service is the core of user visual identity and customization. It stores character state and communicates with the **Town Service** and **Shop Service** when assets are acquired or updated.

---

## Core Responsibilities

* Create and manage **characters** associated with users.
* Store a list of available **assets** for customization.
* Provide **slots** for equipping items (e.g., `hair`, `eyes`, `coat`, `weapon`).
* Track the **inventory** of owned assets purchased via the **Shop**.
* Equip/unequip items from a user’s inventory to their character.
* Provide APIs to fetch a character’s current appearance and inventory.

---

## Tech Stack

* **Language/Framework**: Java + Spring Boot
* **Database**: PostgreSQL
* **Other**: JSON serialization, DB migrations (Flyway / Liquibase), optional caching (Redis)

---

## Data Schema

### Entities

```java
public class Character {
    private String id;
    private String userId;                   // references User Service
    private String name;                     // display name
    private List<EquippedAsset> equipped;    // equipped assets
    private Instant createdAt;
    private Instant updatedAt;

}

public class Asset {
    private String id;
    private String name;                     // e.g., "Red Coat", "Spiky Hair"
    private String description;
    private SlotType slot;                   // where it can be equipped
    private RarityType rarity;               // enum for consistency

    public enum RarityType {
        COMMON,
        RARE,
        EPIC
    }
}

public class InventoryItem {
    private String id;
    private String userId;
    private String assetId;                  // references Asset
    private Instant acquiredAt;
    private AcquisitionSource source;        // enum for acquisition source

    public enum AcquisitionSource {
        SHOP_PURCHASE,
        QUEST_REWARD
    }
}

public class EquippedAsset {
    private SlotType slot;
    private String assetId;
}

public enum SlotType {
    HAIR,
    FACE,
    COAT,
    ACCESSORY,
    SHOES,
    WEAPON
}
```

---

## Endpoints

### **Characters**

* `POST /v1/characters`
  Create a new character for a user.

  **Body:**

  ```json
  {
    "userId": "u123",
    "name": "Hero123"
  }
  ```

  **Responses:** `201` | `409` (character already exists for user)

* `GET /v1/characters/{id}`
  Retrieve character details, including equipped assets.

* `PATCH /v1/characters/{id}`
  Update character name or equipped assets.

---

### **Assets**

* `GET /v1/assets`
  Returns a list of all available customization assets.

* `POST /v1/assets`
  Add a new asset (admin only).

  **Body:**

  ```json
  { "name": "Blue Hat", "slot": "ACCESSORY", "rarity": "common" }
  ```

---

### **Inventory**

* `GET /v1/users/{userId}/inventory`
  Get a user’s owned assets.

* `POST /v1/users/{userId}/inventory`
  Add an asset to user’s inventory (e.g., after shop purchase).

  **Body:**

  ```json
  { "assetId": "a123", "source": "SHOP_PURCHASE" }
  ```

* `POST /v1/characters/{characterId}/equip`
  Equip an asset from inventory to character.

  **Body:**

  ```json
  { "assetId": "a123", "slot": "COAT" }
  ```

* `POST /v1/characters/{characterId}/unequip`
  Unequip an asset from a slot.

  **Body:**

  ```json
  { "slot": "COAT" }
  ```

---

## Dependencies

* PostgreSQL DB Container
* Flyway / Liquibase (DB migrations)
* Jackson (JSON serialization)
* Redis (optional, for caching character appearances)
* Integration with **User Management Service** (validate user exists)
* Integration with **Shop Service** (sync asset purchases)

---

## Example Flow

1. User buys a **Red Coat** in **Shop Service**.
2. Shop Service calls Character Service `POST /inventory` to add the asset.
3. User opens profile screen and equips the coat using `POST /characters/{id}/equip`.
4. Character Service stores the equipped state and makes it available via `GET /characters/{id}`.
5. Game client fetches updated appearance.

---

## Service Diagram

```mermaid
---
config:
  layout: dagre
---
flowchart TD
  subgraph subGraph0["Mafia Application"]
        A["Client / Game Client"]
        B("Character Service <br> Java + Spring Boot")
        C("User Management Service")
        D("Shop Service")
  end

  subgraph subGraph2["Data Persistence"]
        DB[("PostgreSQL Database")]
  end

    A -- REST API Calls --> B
    B -- Validates User --> C
    D -- Purchase Events --> B
    B -- Reads/Writes characters, inventory, assets --> DB
    B -- Returns Character State --> A

    style B fill:#f9f,stroke:#333,stroke-width:2px
    style DB fill:#bbf,stroke:#333,stroke-width:2px
```
