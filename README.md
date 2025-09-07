# distributed_applications_labs

## Task Service

* **Core responsibility:** Assign daily tasks at the start of the day based on each player’s role and career. Track completion of those tasks, reward in-game currency, and optionally generate rumors that influence the game narrative.

### Tech stack

* **Framework/language:** Java + Spring Boot (strong ecosystem, great support for REST APIs, built-in validation/security features).  
* **Database:** PostgreSQL (transactional safety for task assignment and reward crediting).  
* **Other:** Spring Data JPA (ORM), Spring Security (for authentication/authorization), Jackson (JSON serialization).  
* **Communication pattern:** REST API (JSON over HTTP) between services. Optionally event publishing (e.g., `rumor.created`) to a message broker in future extensions.

### Service Diagram

```mermaid
flowchart TD
  subgraph Client
    P[Players]
  end

  subgraph Game
    G[Game Service]
  end

  subgraph Task
    T[Task Service <br/> Java + Spring Boot]
  end

  subgraph User
    U[User Management Service]
  end

  P -->|View tasks / submit completion| T
  G -->|Day start signal| T
  T -->|Reward currency| U
```
### Schema
```java
enum TaskStatus {
    ASSIGNED,
    COMPLETED,
    FAILED
}

class TaskDefinition {
    UUID id;
    String role;            // role/career that receives this task
    String description;     
    String requirementType; // e.g., VISIT, USE_ITEM, INTERACT
}

class DailyTaskAssignment {
    UUID id;
    UUID userId;
    UUID taskDefinitionId;
    TaskStatus status;
    LocalDateTime createdAt;
    LocalDateTime completedAt;
}

class TaskEvent {
    UUID id;
    UUID assignmentId;
    String eventType;   // e.g., COMPLETION, FAILURE, RUMOR
    LocalDateTime createdAt;
}
```

### Endpoints
`POST v1/tasks/day/start` – Assign tasks for all players
Body:
```json
{ "day": 12 }
```
Response:
```json
{ "day": 12, "assignedTasks": 120 }
```

`GET v1/tasks/{userId}` – Retrieve tasks for a player
Path Params:
userId: string
Response:
```json
[
  { "id": "uuid", "description": "Visit hospital", "status": "ASSIGNED" }
]
```
`POST v1/tasks/{assignmentId}/complete` – Mark task as complete
Path Params:
`assignmentId: string`
Response:
```json
{ "status": "COMPLETED", "reward": 50 }
```

### Dependencies
- Game Service: sends the /day/start signal to begin daily tasks.
- User Management Service: credits currency to the player after task completion.
- Optional Shop/Roleplay Services: used to validate item/location/role requirements.
