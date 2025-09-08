# distributed_applications_labs

## Service Boundaries Overview

### Town Service & Character Service Communication Architecture

```mermaid
graph TB
    subgraph "Client Layer"
        Client[Game Client]
    end
    
    subgraph "Mafia Platform Services"
        subgraph "Core Game Services"
            Game[Game Service<br/>Java + Spring Boot]
            Task[Task Service<br/>Java + Spring Boot]
        end
        
        subgraph "Domain Services - Our Implementation"
            Town[Town Service<br/>Java + Spring Boot<br/>Location Management]
            Character[Character Service<br/>Java + Spring Boot<br/>Character & Inventory]
        end
        
        subgraph "Supporting Services"
            Shop[Shop Service<br/>Python + FastAPI]
            User[User Management<br/>Node.js + Express]
        end
    end
    
    subgraph "Data Layer"
        DB_Town[(Town Database<br/>PostgreSQL)]
        DB_Character[(Character Database<br/>PostgreSQL + Redis)]
    end

    %% Client connections
    Client --> Game
    Client --> Town
    Client --> Character
    
    %% Inter-service communication
    Town --> Task
    Town --> Character
    Character --> Shop
    Character --> User
    Task --> Character
    Game --> Town
    Game --> Character
    
    %% Database connections
    Town --> DB_Town
    Character --> DB_Character
    
    %% Styling
    classDef ourServices fill:#ff9999,stroke:#333,stroke-width:3px
    classDef otherServices fill:#cccccc,stroke:#333,stroke-width:1px
    classDef dbBox fill:#99ccff,stroke:#333,stroke-width:2px
    classDef clientBox fill:#99ff99,stroke:#333,stroke-width:2px
    
    class Town,Character ourServices
    class Game,Task,Shop,User otherServices
    class DB_Town,DB_Character dbBox
    class Client clientBox
```

### Focused Communication: Town ↔ Character Services

```mermaid
graph LR
    subgraph "Town Service Domain"
        TownAPI[Town Service API]
        LocationDB[(Location DB)]
    end
    
    subgraph "Character Service Domain"
        CharAPI[Character Service API]
        CharDB[(Character DB)]
    end
    
    subgraph "Communication Patterns"
        REST[REST API Calls]
        Events[Async Events]
    end
    
    TownAPI -->|Location Access Validation| CharAPI
    CharAPI -->|Item-based Access Check| TownAPI
    TownAPI -->|Movement Events| Events
    Events -->|Inventory Updates| CharAPI
    
    TownAPI --> LocationDB
    CharAPI --> CharDB
    
    style TownAPI fill:#ff9999
    style CharAPI fill:#ff9999
```

---

## Technologies and Communication Patterns

### Team Language Distribution
Our team implements services using **3 different programming languages** to leverage the strengths of each technology stack:

- **Java + Spring Boot**: Town Service, Character Service (our implementation)
- **Python + FastAPI**: Shop Service (team member implementation)
- **Node.js + Express**: User Management Service (team member implementation)

### Service Technologies

#### Town Service
- **Language**: Java 17
- **Framework**: Spring Boot 3.2 with Spring WebFlux
- **Database**: PostgreSQL 15 with spatial extensions
- **Caching**: Redis for location state caching
- **Additional Libraries**: 
  - Spring Data JPA for database operations
  - Spring WebSocket for real-time movement tracking
  - Jackson for JSON serialization
  - Micrometer for metrics

**Technology Justification for Mafia Platform Business Case**:
- **Concurrency Excellence**: Java's virtual threads (Project Loom) and Spring WebFlux enable handling thousands of simultaneous player movements without performance degradation - critical for a multiplayer mafia game where real-time location tracking is essential
- **Enterprise Reliability**: Spring Boot's production-ready features (health checks, metrics, security) ensure the Town Service can handle the high-stakes nature of mafia gameplay where system downtime could disrupt active games
- **Spatial Data Processing**: PostgreSQL's PostGIS extension combined with Java's robust geospatial libraries enable complex location-based queries needed for territory control and proximity-based game mechanics
- **Transaction Safety**: Java's strong typing and Spring's transaction management ensure movement logs are never corrupted, maintaining game integrity for investigations and alibis
- **Ecosystem Maturity**: Extensive security libraries available for implementing the secretive, authenticated nature of mafia platform communications

#### Character Service  
- **Language**: Java 17
- **Framework**: Spring Boot 3.2 with Spring MVC
- **Database**: PostgreSQL 15 for structured data, Redis for character state caching
- **Additional Libraries**:
  - Spring Data JPA with JSON support
  - Spring Cache abstraction
  - Bean Validation for data integrity
  - MapStruct for DTO mapping

**Technology Justification for Mafia Platform Business Case**:
- **Data Consistency**: Java's strong typing system and Spring's transaction management ensure inventory operations are atomic - when a character purchases disguise items, the transaction either completes entirely or fails entirely, preventing inventory corruption that could compromise gameplay
- **Complex Object Modeling**: Java's OOP capabilities excel at modeling the intricate character customization system where items have effects, restrictions, and relationships - essential for a mafia game where appearance and equipment directly impact gameplay mechanics
- **Secure State Management**: Spring Security integration enables role-based character access (family boss vs. street thug) with different customization privileges and inventory restrictions
- **Performance Optimization**: Redis integration provides sub-millisecond character state retrieval, crucial when multiple services need to validate character abilities during fast-paced mafia operations
- **JSON Flexibility**: PostgreSQL's JSON support combined with Jackson allows storing flexible character appearance data while maintaining query performance for complex inventory searches

### Communication Patterns

#### Synchronous Communication
- **REST APIs**: Primary communication method between all services
  - **Protocol**: HTTP/HTTPS with JSON payloads
  - **Authentication**: JWT tokens for secure inter-service communication
  - **Rate Limiting**: Implemented to prevent service abuse during high-intensity mafia operations
  - **Circuit Breaker**: Hystrix pattern to handle service failures gracefully

**Business Case Alignment**: REST ensures immediate response for critical operations like location access validation and inventory verification during time-sensitive mafia activities.

#### Asynchronous Communication
- **Event-Driven Architecture**: 
  - **Technology**: Apache Kafka for event streaming
  - **Pattern**: Publish-Subscribe for movement events and inventory changes
  - **Event Store**: Persistent event log for game activity auditing
- **Message Queuing**: 
  - **Technology**: RabbitMQ for reliable message delivery
  - **Use Cases**: Delayed notifications, batch inventory processing, activity reporting to Task Service

**Business Case Alignment**: Async patterns enable the platform to handle the secretive nature of mafia operations - events can be processed without blocking other operations, and the event store provides an immutable audit trail for investigations.

#### Real-Time Communication
- **WebSockets**: 
  - **Implementation**: Spring WebSocket with STOMP protocol
  - **Use Cases**: Live location updates, real-time character appearance changes during meetings
  - **Fallback**: Server-Sent Events (SSE) for browsers with limited WebSocket support

**Business Case Alignment**: Real-time updates are crucial for mafia gameplay where knowing who's where and what they're wearing can be life-or-death information.

### Trade-offs Analysis

#### Performance vs Complexity
- **Decision**: Multi-pattern communication (REST + Events + WebSockets)
- **Trade-off**: Increased system complexity for superior user experience
- **Business Impact**: Enhanced gameplay immersion justifies the architectural overhead - mafia games require seamless real-time interactions

#### Consistency vs Availability  
- **Decision**: Strong consistency for inventory, eventual consistency for location tracking
- **Trade-off**: Some location updates may have slight delays vs guaranteed inventory accuracy
- **Business Impact**: Financial transactions (shop purchases) require absolute accuracy, while location tracking can tolerate minor delays

#### Java Ecosystem vs Polyglot Architecture
- **Decision**: Java for both our services despite having Python/Node.js options
- **Trade-off**: Miss some language-specific benefits vs consistent development experience
- **Business Impact**: Faster development and easier maintenance outweigh potential performance gains from language optimization

#### Horizontal Scaling Considerations
- **Stateless Design**: Both services designed to be horizontally scalable
- **Database Partitioning**: Character data partitioned by game instance, location data by geographical regions
- **Cache Distribution**: Redis cluster setup for handling high-concurrency character state access
- **Load Balancing**: Spring Cloud Gateway for intelligent request routing based on user location and character activity patterns

### Security Architecture
Given the "high-risk, high-reward" nature of the Mafia Platform:

- **End-to-End Encryption**: All inter-service communication encrypted with TLS 1.3
- **Zero-Trust Model**: Every service call authenticated and authorized
- **Audit Logging**: Complete activity trails for forensic analysis
- **Data Anonymization**: Personal data encrypted at rest with rotating keys
- **Rate Limiting**: Aggressive throttling to prevent reconnaissance attacks on the platform

This technology stack provides the reliability, security, and performance needed for a clandestine gaming platform where system failures or data breaches could have serious consequences for the fictional "organization" and its members.

---

## Town Service
* **Core responsibility:** Manages all game world locations and tracks player movement patterns within the town.

**Functionality**:
- Location registry management (Shop, Informator Bureau, safe houses, etc.)
- Real-time player movement tracking between locations
- Location access control and restrictions enforcement
- Activity reporting to Task Service for task validation
- Location-based event triggers and interactions
- Movement history and analytics

### Tech stack
* **Framework/language:** Java + Spring Boot (robust concurrency for real-time tracking, excellent ecosystem)
* **Database:** PostgreSQL (spatial data support for locations, transaction safety for movement logs)
* **Other:** WebSocket support via Spring WebSocket, Spring Data JPA, Jackson for JSON
* **Communication pattern:** REST API + WebSocket for real-time updates + Event publishing

### Service Diagram
```mermaid
---
config:
  layout: dagre
---
flowchart TD
 subgraph subGraph0["Mafia Application"]
        B("Town Service <br> Java + Spring Boot")
        A["Client / Game Service / Task Service"]
  end
 subgraph subGraph2["Data Persistence"]
        D[("PostgreSQL Database")]
  end
    A -- HTTP/REST API Calls + WebSocket --> B
    B -- JSON Responses / Movement Events --> A
    B -- Reads/Writes location/movement data --> D
    style B fill:#f9f,stroke:#333,stroke-width:2px
    style D fill:#bbf,stroke:#333,stroke-width:2px
```

### Schema
```typescript
interface Location {
    id: string;
    name: string;
    type: LocationType;
    description: string;
    accessRules: AccessRule[];
    capacity?: number;
    coordinates: { x: number, y: number };
    isActive: boolean;
    createdAt: string;
}

enum LocationType {
    SHOP,
    INFORMATOR_BUREAU,
    SAFE_HOUSE,
    PUBLIC_AREA,
    RESTRICTED_ZONE
}

interface AccessRule {
    requirement: string;  // ROLE, ITEM, TIME_WINDOW
    value: string;
    allowed: boolean;
}

interface PlayerMovement {
    id: string;
    userId: string;
    gameId: string;
    fromLocationId?: string;
    toLocationId: string;
    timestamp: string;
    duration?: number;  // time spent at location
    purpose?: string;   // TASK, SHOPPING, INVESTIGATION
}

interface LocationActivity {
    id: string;
    locationId: string;
    userId: string;
    activityType: ActivityType;
    metadata: Record<string, any>;
    reportedToTaskService: boolean;
    timestamp: string;
}

enum ActivityType {
    VISIT,
    PURCHASE,
    INVESTIGATION,
    MEETING,
    TASK_COMPLETION
}
```

### Endpoints

#### `GET v1/locations` – Get all available locations
Response 200:
```json
{
  "locations": [
    {
      "id": "uuid",
      "name": "Central Shop",
      "type": "SHOP",
      "description": "Main shopping area",
      "accessRules": [],
      "capacity": 50,
      "coordinates": { "x": 10, "y": 20 },
      "isActive": true
    }
  ]
}
```

#### `POST v1/movements` – Record player movement
Request:
```json
{
  "userId": "uuid",
  "gameId": "uuid", 
  "toLocationId": "uuid",
  "purpose": "TASK"
}
```

Response 201:
```json
{
  "movementId": "uuid",
  "fromLocation": "Previous Location",
  "toLocation": "New Location", 
  "timestamp": "2025-09-08T10:00:00Z",
  "accessGranted": true
}
```

#### `GET v1/movements/{userId}/history` – Get movement history
Query params: `gameId`, `limit`, `offset`

Response 200:
```json
{
  "movements": [
    {
      "locationName": "Central Shop",
      "timestamp": "2025-09-08T10:00:00Z",
      "duration": 300,
      "purpose": "SHOPPING"
    }
  ]
}
```

### Dependencies
* Task Service: reports activities for task validation
* Game Service: receives location-based events
* Character Service: validates location access based on inventory

---

## Character Service
* **Core responsibility:** Manages player character customization and inventory system.

**Functionality**:
- Character appearance customization system
- Inventory management for purchased and earned items
- Asset catalog management (clothing, accessories, tools)
- Slot-based customization system (hair, coat, accessories)
- Character state persistence and synchronization
- Item effect tracking for gameplay mechanics

### Tech stack
* **Framework/language:** Java + Spring Boot (consistent enterprise-grade architecture, excellent ORM support)
* **Database:** PostgreSQL (JSON support for flexible customization data, ACID properties for inventory consistency)
* **Other:** Redis for caching character states, Jackson for JSON processing, Spring Data JPA
* **Communication pattern:** REST API + Event publishing for inventory changes

### Service Diagram
```mermaid
flowchart TD
    subgraph MafiaApp["Mafia Application"]
        CharService["Character Service<br/>Java + Spring Boot"]
        Clients["Client / Shop Service / Game Service"]
    end
    subgraph DataLayer["Data Persistence"]
        PostgresDB[("PostgreSQL Database")]
        RedisCache[("Redis Cache")]
    end
    
    Clients -->|HTTP/REST API Calls| CharService
    CharService -->|JSON Responses| Clients
    CharService -->|Reads/Writes character data| PostgresDB
    CharService -->|Caches character states| RedisCache
    
    style CharService fill:#f9f,stroke:#333,stroke-width:2px
    style PostgresDB fill:#bbf,stroke:#333,stroke-width:2px
    style RedisCache fill:#ffd,stroke:#333,stroke-width:2px
```

### Schema
```typescript
interface Character {
    id: string;
    userId: string;
    gameId: string;
    appearance: CharacterAppearance;
    inventory: InventoryItem[];
    customizationSlots: CustomizationSlot[];
    lastUpdated: string;
    createdAt: string;
}

interface CharacterAppearance {
    skinTone: string;
    hairStyle: string;
    hairColor: string;
    eyeColor: string;
    clothing: ClothingSet;
    accessories: string[];
}

interface ClothingSet {
    hat?: string;
    shirt: string;
    pants: string;
    shoes: string;
    coat?: string;
}

interface InventoryItem {
    id: string;
    assetId: string;
    name: string;
    category: AssetCategory;
    quantity: number;
    acquiredFrom: 'SHOP' | 'REWARD' | 'TASK';
    effects: ItemEffect[];
    isEquipped: boolean;
    acquiredAt: string;
}

interface CustomizationSlot {
    slotType: SlotType;
    equippedAssetId?: string;
    restrictions: string[];  // role, level, or item requirements
}

enum SlotType {
    HAIR,
    HAT,
    SHIRT,
    PANTS, 
    SHOES,
    COAT,
    ACCESSORY_1,
    ACCESSORY_2,
    TOOL
}

enum AssetCategory {
    HAIR,
    CLOTHING,
    ACCESSORY,
    TOOL,
    CONSUMABLE
}

interface Asset {
    id: string;
    name: string;
    description: string;
    category: AssetCategory;
    imageUrl: string;
    rarity: 'COMMON' | 'RARE' | 'LEGENDARY';
    requirements: AssetRequirement[];
    effects: ItemEffect[];
}

interface AssetRequirement {
    type: 'ROLE' | 'LEVEL' | 'ITEM';
    value: string;
}

interface ItemEffect {
    type: 'STEALTH' | 'CHARISMA' | 'PROTECTION' | 'SPEED';
    value: number;
    duration?: number;
}
```

### Endpoints

#### `GET v1/characters/{userId}` – Get character data
Query params: `gameId`

Response 200:
```json
{
  "id": "uuid",
  "userId": "uuid", 
  "appearance": {
    "skinTone": "light",
    "hairStyle": "short",
    "hairColor": "brown",
    "clothing": {
      "shirt": "casual-blue",
      "pants": "jeans",
      "shoes": "sneakers"
    }
  },
  "inventory": [
    {
      "id": "uuid",
      "name": "Leather Coat",
      "category": "CLOTHING",
      "quantity": 1,
      "isEquipped": false,
      "effects": [
        {
          "type": "PROTECTION",
          "value": 10
        }
      ]
    }
  ]
}
```

#### `PUT v1/characters/{userId}/customize` – Update character appearance
Request:
```json
{
  "gameId": "uuid",
  "changes": {
    "hairStyle": "long",
    "equippedItems": {
      "COAT": "leather-coat-001"
    }
  }
}
```

Response 200:
```json
{
  "success": true,
  "character": {
    "appearance": { /* updated appearance */ },
    "activeEffects": [
      {
        "type": "PROTECTION",
        "value": 10,
        "source": "Leather Coat"
      }
    ]
  }
}
```

#### `GET v1/assets` – Get available customization assets
Query params: `category`, `rarity`, `availableOnly`

Response 200:
```json
{
  "assets": [
    {
      "id": "uuid",
      "name": "Fedora Hat",
      "category": "CLOTHING",
      "imageUrl": "https://assets.game/fedora.png",
      "rarity": "RARE",
      "requirements": [
        {
          "type": "ROLE",
          "value": "DETECTIVE"
        }
      ]
    }
  ]
}
```

#### `POST v1/characters/{userId}/inventory/add` – Add item to inventory
Request:
```json
{
  "gameId": "uuid",
  "assetId": "uuid",
  "quantity": 1,
  "source": "SHOP"
}
```

Response 201:
```json
{
  "inventoryItemId": "uuid",
  "message": "Item added to inventory"
}
```

### Dependencies
* Shop Service: receives purchased items
* Town Service: validates location-based item usage
* Game Service: applies character effects to gameplay
* User Management Service: validates user ownership

## Data ownership:
- Town Service exclusively manages `locations`, `player_movements`, and `location_activities`
- Character Service exclusively manages `characters`, `assets`, `inventory_items`, and `customization_slots`