## Service name

* **Core responsibility:** describe the core responsibility of the service

### Tech stack

* **Framework/language:** which framework and why
* **Databse:** which db and why
* **Other:** other technologies used
* **Communication pattern:** describe the communication protocols used

### Schema

describe participating models and their schemas e.g.

```typescript
enum UserRole{
    ADMIN
    STUDENT
    FAF_NGO
}

class User{
    userId: string
    firstName: string
    lastName: string
    role: UserRole
}
```

### Endpoints

some boilerplate endpoint description

#### `GET v1/users/{id}` - Retrieve user by Id

**Path Params:**

1. `id: string` - id of the user to be retrieved

**Query Params:**

#### `GET v1/users` - Retrieve all users

**Path Params:**

**Query Params:**

1. `roles: string[]` - list of roles to filter users for

### Dependencies

Describe on which services does this service depend on.
