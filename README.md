# distributed_applications_labs


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

Comprehensive REST API for user management, currency transactions, device tracking, and access event monitoring.

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

### Device Endpoints

### `GET /v1/devices/{id}` – Get device by ID

**Responses:** 200 (OK) | 404 (Device not found)

### `GET /v1/devices` – List devices

**Query Params:**

* `userId` - string, filter by user ID
* `fingerprint` - string, filter by device fingerprint
* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/devices` – Create device

**Request Body:**

```json
{
    "userId": "user-uuid",
    "device": {
        "fingerprint": "sha256:abcd...",
        "platform": "WEB"
    }
}
```

**Responses:** 201 (Created) | 400 (Missing required fields)

### `DELETE /v1/devices/{id}` – Delete device

**Responses:** 200 (OK) | 404 (Device not found)

### User Device Endpoints

### `GET /v1/users/{id}/devices` – List devices for a user

**Query Params:**

* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/users/{id}/devices` – Create device for a user

**Request Body:**

```json
{
    "device": {
        "fingerprint": "sha256:abcd...", 
        "platform": "WEB"
    }
}
```

### `GET /v1/users/{id}/devices/latest` – Get latest device for user

Returns the most recently seen device based on access events.

**Responses:** 200 (OK) | 404 (No device found for user)

### Transaction Endpoints

### `GET /v1/transactions/{id}` – Get transaction by ID

**Responses:** 200 (OK) | 404 (Transaction not found)

### `GET /v1/transactions` – List transactions

**Query Params:**

* `userId` - string, filter by user ID
* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/transactions` – Create transaction

**Request Body:**

```json
{
    "userId": "user-uuid",
    "amount": 500,
    "type": "ADD",
    "reason": "REWARD"
}
```

**Responses:** 201 (Created) | 400 (Missing required fields)

### `PUT /v1/transactions/{id}` – Update transaction

**Request Body:**

```json
{
    "amount": 750,
    "type": "SUBTRACT", 
    "reason": "PURCHASE"
}
```

**Responses:** 200 (OK) | 400 (Validation error) | 404 (Transaction not found)

### `DELETE /v1/transactions/{id}` – Delete transaction

**Responses:** 200 (OK) | 404 (Transaction not found)

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

### Access Event Endpoints

### `GET /v1/access-events/{id}` – Get access event by ID

**Responses:** 200 (OK) | 404 (Access event not found)

### `GET /v1/access-events` – List access events

**Query Params:**

* `userId` - string, filter by user ID
* `deviceId` - string, filter by device ID
* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/access-events` – Create access event

**Request Body:**

```json
{
    "userId": "user-uuid",
    "deviceId": "device-uuid",
    "ip": "192.168.1.1",
    "country": "US"
}
```

Only `userId` is required.

**Responses:** 201 (Created) | 400 (Missing required fields)

### `PUT /v1/access-events/{id}` – Update access event

**Request Body:**

```json
{
    "deviceId": "device-uuid",
    "ip": "192.168.1.1", 
    "country": "US"
}
```

**Responses:** 200 (OK) | 400 (Validation error) | 404 (Access event not found)

### `DELETE /v1/access-events/{id}` – Delete access event

**Responses:** 200 (OK) | 404 (Access event not found)

### User Access Event Endpoints

### `GET /v1/users/{id}/access-events` – List access events for a user

**Query Params:**

* `limit` - number, pagination limit
* `offset` - number, pagination offset

### `POST /v1/users/{id}/access-events` – Create access event for a user

**Request Body:**

```json
{
    "deviceId": "device-uuid",
    "ip": "192.168.1.1",
    "country": "US"
}
```

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

### Endpoints

#### `POST v1/lobbies` – Create new lobby

Request body

```json
{ "name": "Lobby 1" }
```

#### `POST v1/lobbies/{id}/join` – Add player to lobby

Body:

```json
{ "userId": "uuid-of-user", "role": "VILLAGER", "career": "MERCHANT" }
```

Response: Player object.
Errors: 409 (lobby full or already joined).

#### `GET v1/lobbies/{id}` – Retrieve lobby state

### Dependencies

* PostgreSQL DB container

* Express.js + TypeScript runtime

* (Optional later) Message broker for real-time announcements (e.g. Kafka, RabbitMQ, or WebSocket layer)

## Shop Service

**Core responsibility:** Enables players to prepare for day/night cycles by purchasing protective items and task-assistance objects using in-game currency.

**Functionality**:
- Item catalog management for protective and task-assistance items
- Daily quantity balancing algorithm to ensure game economy stability
- Purchase processing (coordinating with User Management Service for currency)
- Inventory management for purchased items
- Item effects management for protection against specific roles/actions

### Service Diagram

```mermaid
flowchart LR
    subgraph MafiaApplication["Mafia Application"]
        SS[("Shop Service
        Java + Spring Boot")]
        UMS[("User Management Service")]
        TS[("Task Service")]
        RS[("Roleplay Service")]
    end

    subgraph DataPersistence["Data Persistence"]
        DB[(PostgreSQL Database)]
    end

    Client["Client / Other Services"]

    Client -- "HTTP/REST API Call" --> SS
    SS -- "JSON Response" --> Client
    SS -- "Reads/Writes item, inventory, transaction data" --> DB
    SS -- "Verify/Deduct currency" --> UMS
    UMS -- "Currency balance/update response" --> SS
    SS -- "Validate item effects" --> RS
    SS -- "Check task requirements" --> TS
```

### Domain Models and Interfaces

#### Item
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
}

enum ItemCategory {
  PROTECTION,        // Items that protect against attacks
  TASK_ASSISTANCE,   // Items that help with daily tasks
  UTILITY,           // General purpose items
  SPECIAL            // Limited edition or event items
}

interface ItemEffect {
  type: EffectType;
  value: number;      // Effect strength/duration
  duration: number;   // How many game cycles it lasts
  targetRole?: string; // Role-specific protections
}

enum EffectType {
  WARD_VAMPIRE,       // e.g., garlic
  DOUSE_ARSONIST,     // e.g., water
  CONCEAL_IDENTITY,   // e.g., mask
  REVEAL_ROLE,        // e.g., magnifying glass
  BOOST_TASK,         // e.g., tools
  TRACKING,           // e.g., footprint detector
  BLOCK_ACTION        // e.g., handcuffs
}
```

#### Inventory
```typescript
interface InventoryItem {
  id: string;
  userId: string;
  gameId: string;
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

#### Transaction
```typescript
interface Transaction {
  transactionId: string;
  userId: string;
  gameId: string;
  items: PurchasedItem[];
  totalCost: number;
  timestamp: Date;
  status: 'COMPLETED' | 'FAILED' | 'PENDING';
}

interface PurchasedItem {
  itemId: string;
  name: string;
  quantity: number;
  unitPrice: number;
  totalPrice: number;
}
```

### APIs Exposed

#### 1. Get Available Items

**Endpoint:** `GET /api/v1/items`

**Description:** Retrieves all available items for purchase in the shop, with quantities determined by the daily balancing algorithm.

**Query Parameters:**
- `category` (optional): Filter by ItemCategory (PROTECTION, TASK_ASSISTANCE, etc.)
- `page` (optional): Page number for pagination
- `size` (optional): Number of items per page
- `gameDay` (required): The current game day for proper inventory balancing

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
          "duration": 1
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
- 400: Invalid parameters
- 500: Server error

#### 2. Get Item Details

**Endpoint:** `GET /api/v1/items/{id}`

**Description:** Retrieves detailed information about a specific item.

**Path Parameters:**
- `id`: Unique identifier of the item

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
      "targetRole": "VAMPIRE"
    }
  ],
  "availableQuantity": 5,
  "imageUrl": "string",
  "usageInstructions": "Wear during the night phase for protection",
  "createdAt": "string (ISO-8601 format)"
}
```

**Status Codes:**
- 200: Success
- 404: Item not found
- 500: Server error

#### 3. Process Purchase

**Endpoint:** `POST /api/v1/purchases`

**Description:** Processes a purchase transaction for one or more items. Coordinates with User Management Service to verify and deduct currency.

**Request Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "gameDay": 3,
  "items": [
    {
      "itemId": "string",
      "quantity": 0
    }
  ]
}
```

**Response Format:**
```json
{
  "transactionId": "string",
  "status": "string",
  "timestamp": "string (ISO-8601 format)",
  "totalCost": 0,
  "remainingBalance": 0,
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
- 400: Insufficient funds or quantity not available
- 404: Item not found
- 500: Server error

#### 4. View User Inventory

**Endpoint:** `GET /api/v1/inventory/{userId}`

**Description:** Retrieves the inventory of items owned by a user.

**Path Parameters:**
- `userId`: Unique identifier of the user

**Query Parameters:**
- `gameId` (required): The game context for the inventory

**Response Format:**
```json
{
  "userId": "string",
  "gameId": "string",
  "items": [
    {
      "id": "string",
      "itemId": "string",
      "name": "Garlic Necklace",
      "quantity": 1,
      "used": false,
      "acquiredAt": "string (ISO-8601 format)",
      "expiresAt": "string (ISO-8601 format)",
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
- 404: User not found or no inventory
- 500: Server error

#### 5. Use Item

**Endpoint:** `POST /api/v1/inventory/{userId}/use`

**Description:** Uses an item from the user's inventory and applies its protective or task-assistance effects.

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
  "remainingQuantity": 0
}
```

**Status Codes:**
- 200: Success
- 404: Item not found in inventory
- 400: Invalid use conditions
- 500: Server error

#### 6. Get Daily Stock Status

**Endpoint:** `GET /api/v1/items/stock-status`

**Description:** Provides information about the current stock levels and next restock time.

**Query Parameters:**
- `gameId` (required): The game context
- `gameDay` (required): The current game day

**Response Format:**
```json
{
  "gameDay": 3,
  "nextRestockTime": "string (ISO-8601 format)",
  "rareItemsAvailable": true,
  "categories": [
    {
      "name": "PROTECTION",
      "itemsAvailable": 4,
      "totalItems": 6
    },
    {
      "name": "TASK_ASSISTANCE",
      "itemsAvailable": 8,
      "totalItems": 10
    }
  ]
}
```

**Status Codes:**
- 200: Success
- 400: Invalid parameters
- 500: Server error

### Inter-Service Communication

#### Outgoing Requests:

1. **To User Management Service**
   - Check user currency balance before purchase
   - Deduct currency after successful purchase
   - API: `POST v1/users/{id}/currency` with transaction type "SUBTRACT"

2. **To Roleplay Service**
   - Verify item effect compatibility with user's role
   - Register active protection effects when items are used
   - API: `POST /api/v1/actions/verify-item`

3. **To Task Service**
   - Check if an item satisfies a task requirement
   - API: `GET /v1/tasks/verify-item`

#### Incoming Requests:

1. **From Game Service**
   - Request for active protection effects during night phase
   - Request for inventory information during day phase

2. **From Roleplay Service**
   - Check active protections when processing role actions

### Implementation Considerations

- **Daily Item Balancing Algorithm**: Implements a dynamic balancing system that:
  - Adjusts available quantities based on player counts and game day
  - Creates artificial scarcity for powerful items
  - Ensures all player roles have access to appropriate protective items
  - Randomizes some stock quantities to prevent predictable patterns

- **Protection Effectiveness System**: 
  - Different protection items have varying effectiveness against specific roles
  - Some items provide partial protection (percentage-based)
  - Stacking rules prevent overpowered combinations

- **Transaction Safety**:
  - Implement optimistic locking for inventory operations
  - Ensure atomic transactions when purchasing limited items
  - Add idempotency keys for purchase operations

- **Performance Optimization**:
  - Cache frequently accessed catalog items
  - Batch update inventory records
  - Use read replicas for inventory queries during high-traffic periods

## Roleplay Service

**Core responsibility:** Controls role-specific game mechanics and handles player role-based actions.

**Functionality**:
- Role ability execution (e.g., Mafia kills, Sheriff investigations)
- Role-based action validation and processing
- Action outcome determination based on roles and item protections
- Recording action attempts for game integrity
- Creating filtered announcements for consumption by Game Service
- Managing role-specific rules, constraints, and interactions

### Tech stack

* **Framework/language:** Java + Spring Boot (strong typing for role action logic)
* **Database:** PostgreSQL (ACID transactions for critical role actions)
* **Other:** Role action evaluation engine, protection status checker
* **Communication pattern:** Internal REST API, event notifications to Game Service

### Service Diagram

```mermaid
flowchart LR
    subgraph MafiaApplication["Mafia Application"]
        RS[("Roleplay Service
        Java + Spring Boot")]
        GS[("Game Service")]
        SS[("Shop Service")]
    end

    subgraph DataPersistence["Data Persistence"]
        DB[(PostgreSQL Database)]
    end

    Client["Client"]
    
    Client -- "Action Requests" --> RS
    RS -- "Action Results" --> Client
    RS -- "Role Actions Data" --> DB
    GS -- "Game State" --> RS
    RS -- "Action Outcomes" --> GS
    SS -- "Item Effects" --> RS
    RS -- "Protection Status" --> SS
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

#### 2. Get Available Role Actions

**Endpoint:** `GET /api/v1/actions/available`

**Description:** Retrieves available actions for a user's role in the current game phase.

**Query Parameters:**
- `gameId` (required): The game context
- `userId` (required): The user requesting available actions
- `phase` (required): Game phase (DAY, NIGHT)

**Response Format:**
```json
{
  "actions": [
    {
      "actionType": "string",
      "description": "string",
      "targets": 0,
      "cooldown": 0,
      "remainingCooldown": 0
    }
  ],
  "currentPhase": "DAY|NIGHT"
}
```

**Status Codes:**
- 200: Success
- 404: User or game not found
- 500: Server error

#### 3. Verify Item Effects Against Role

**Endpoint:** `POST /api/v1/actions/verify-item`

**Description:** Verifies if an item effect is applicable against a specific role.

**Request Format:**
```json
{
  "itemId": "string",
  "effectType": "string",
  "targetRoleId": "string",
  "gamePhase": "DAY|NIGHT"
}
```

**Response Format:**
```json
{
  "effective": true,
  "effectMultiplier": 1.0,
  "message": "Item is effective against this role"
}
```

**Status Codes:**
- 200: Success
- 404: Item or role not found
- 500: Server error

#### 4. Get Action Results

**Endpoint:** `GET /api/v1/actions/results`

**Description:** Retrieves the results of actions for the current phase visible to the requesting user.

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
      "outcome": "string",
      "message": "string",
      "timestamp": "string (ISO-8601 format)"
    }
  ],
  "roleSpecificResults": [
    {
      "actionType": "string",
      "targets": ["string"],
      "outcome": "string",
      "message": "string",
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

### Dependencies

* Game Service: provides game state, player roles, and cycles
* Shop Service: item effects verification and protection status
* User Management Service: user authentication and role validation

### Inter-Service Communication

#### Receives from Game Service:
- Game state updates (day/night cycle)
- Player role assignments
- Player alive/dead status

#### Sends to Game Service:
- Action outcomes for announcements
- Role-based event notifications
- Player status change requests (e.g., death from Mafia kill)

#### Receives from Shop Service:
- Item protection status for target players
- Item effect details for action resolution

#### Sends to Shop Service:
- Item effectiveness verification requests
- Item usage outcome notifications

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


# Voting Service

* **Core responsibility:** Manage the evening vote. Open voting sessions, collect one vote per eligible player, tally results, resolve ties, and return the exiled player to the Game Service.

### Tech stack

* **Framework/language:** Java + Spring Boot (strong concurrency support, production-grade for voting logic).  
* **Database:** PostgreSQL (ensures durability of votes, supports tally queries).  
* **Other:** Spring Data JPA (ORM), Jackson (JSON), Spring Security (for role-based access).  
* **Communication pattern:** REST API (JSON over HTTP) for synchronous operations. Future extension: publish `player.exiled` events via a broker.

### Service Diagram

```mermaid
flowchart TD
  subgraph Client
    P[Players]
  end

  subgraph Game
    G[Game Service]
  end

  subgraph Voting
    V[Voting Service <br/> Java + Spring Boot]
  end

  P -->|Cast vote| V
  G -->|Evening start + eligible list| V
  V -->|Exiled result| G
```

## Schema
```java
class VoteWindow {
    UUID id;
    int day;
    boolean open;
    LocalDateTime openedAt;
    LocalDateTime closedAt;
}

class Vote {
    UUID id;
    UUID voterId;
    UUID targetUserId;
    int day;
    LocalDateTime createdAt;
}

class VoteResult {
    UUID id;
    int day;
    UUID exiledUserId;
    String tieBreakMethod;  // e.g., NONE, RANDOM
    LocalDateTime createdAt;
}
```
## Endpoints
`POST v1/votes/open` – Start a new voting session
Request
```json
{ "day": 12, "eligiblePlayers": ["uuid1", "uuid2"], "eligibleTargets": ["uuid3","uuid4"] }
```
Response 200
```json
{ "day": 12, "status": "OPEN", "closesAt": "2025-09-07T20:00:00Z" }
```
Errors
```json
{ "error": { "code": "VOTE_ALREADY_OPEN", "message": "A vote is already active" } }
```
`POST v1/votes` – Cast a vote
Headers: `Idempotency-Key: string`
Request
```json
{ "day": 12, "voterId": "uuid1", "targetUserId": "uuid2" }
```
Response 200
```json
{ "accepted": true, "voteId": "uuid" }
```
Errors
```json
{ "error": { "code": "ALREADY_VOTED", "message": "Voter already cast a vote" } }
```
`POST v1/votes/close` – Close voting and compute result
Request
```json
{ "day": 12 }
```
Response 200
```json
{
  "day": 12,
  "exiledUserId": "uuid2",
  "counts": [
    { "userId": "uuid2", "votes": 5 },
    { "userId": "uuid3", "votes": 3 }
  ],
  "tieBreakMethod": "RANDOM"
}
```
Errors
```json
{ "error": { "code": "NOT_OPEN", "message": "No vote is currently active" } }
```

## Dependencies
- Game Service: opens/closes vote windows, receives exile result.
- Clients (Players): cast votes via this service.

## Data ownership:
This service exclusively manages `vote_windows`, `votes`, and `vote_results`. No other service writes to this DB.


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
