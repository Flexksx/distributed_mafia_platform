# Mafia Platform - Microservices Architecture

## Project Overview
The Mafia Platform is a distributed application that enables users to play a specialized version of the Mafia game with unique rules. The platform is built using a microservices architecture to ensure scalability, maintainability, and clear separation of concerns.

## Architecture Overview
The system is designed using microservices architecture where each service is responsible for a specific domain of the application. This approach allows for independent development, deployment, and scaling of services. The services communicate via APIs, enabling loose coupling between components.

## Service Boundaries

### Core Services
3. **Shop Service** - Manages in-game economy, items, and purchases
4. **Roleplay Service** - Controls role-specific actions and game events

## Microservices

### Shop Service
**Responsibility**: Manages the in-game economy and item system

**Functionality**:
- Inventory management for in-game items
- Purchase processing using in-game currency
- Dynamic item availability (daily quantity balancing algorithm)
- Item effects management (e.g., protection attributes)
- Transaction history tracking
- Currency management

**Service Boundaries**:
- Owns all item-related data and operations
- Manages economic transactions
- Controls item availability algorithms

**APIs Exposed**:
- GET /items - List available items
- GET /items/{id} - Get item details
- POST /purchases - Process a purchase
- GET /inventory/{userId} - View user's inventory
- GET /balance/{userId} - Check user's currency balance
- PUT /balance/{userId} - Update user's balance

### Roleplay Service
**Responsibility**: Controls game mechanics related to player roles and actions

**Functionality**:
- Role assignment and management
- Processing role-specific actions (e.g., Mafia kills, Sheriff investigations)
- Checking item effectiveness during actions
- Recording all action attempts for audit purposes
- Creating filtered announcements for the Game Service to broadcast
- Enforcing role-specific rules and constraints

**Service Boundaries**:
- Owns all role-related logic and actions
- Controls the outcome of night/day activities
- Manages immunity and protection mechanisms
- Does NOT handle direct user communication

**APIs Exposed**:
- POST /actions - Perform a role-specific action
- GET /roles - Get available roles information
- GET /roles/{userId} - Get a user's role
- POST /announcements - Create filtered game announcements
- GET /actions/history - Get action history (admin only)
- GET /actions/results - Get results of actions for the current phase

## Service Communication

### Inter-Service Dependencies
- **Shop Service** → **User Service**: To validate user identity and update currency
- **Shop Service** → **Game Service**: To sync with game state and phases
- **Roleplay Service** → **Shop Service**: To check for items that affect actions
- **Roleplay Service** → **Game Service**: To provide announcements and game state updates
- **Game Service** → **Roleplay Service**: To trigger role-based actions at appropriate phases

### Communication Patterns
- RESTful APIs for synchronous requests
- Message queues for asynchronous events
- Event-driven architecture for real-time updates

## Architecture Diagram

![alt text](assets/architectural_shop_and_roleplay_service.png)

In this diagram:
- The User Service and Game Service form the core of the platform
- My assigned Shop Service and Roleplay Service handle specialized functionality
- Bidirectional arrows indicate the communication between services
- Each service has its own dedicated database for storage
- The Game Service coordinates between the Roleplay Service and other components
- The Shop Service interacts with both the User Service (for authentication and balance) and the Roleplay Service (for item effects)

## Implementation Considerations

### Shop Service Implementation Notes
- Implement daily item stock refresh algorithm
- Track purchase history for audit purposes
- Provide item effectiveness metadata for Roleplay Service
- Implement transaction locking to prevent race conditions

### Roleplay Service Implementation Notes
- Design role-based permission system
- Create secure action recording mechanism
- Implement filtering algorithm for public announcements
- Build immunity and protection validation logic
- Ensure fairness in randomized outcomes
- Implement transaction locking to prevent race conditions
