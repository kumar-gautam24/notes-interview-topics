# Backend Development with Go — Complete Guide
### From Mobile Dev Mindset to Building Production APIs

---

## 1. What is Backend? (Mental Model for Flutter Devs)

In Flutter, you consume APIs. Now you'll **build** them.

```
Flutter App                          Backend (Go)
┌──────────────┐                    ┌──────────────────────┐
│ UI Layer     │                    │ Handler/Controller   │
│ (Widgets)    │──HTTP Request──►   │ (Receives request)   │
│              │                    │         │            │
│ Repository   │                    │ Service Layer        │
│ (API calls)  │◄──JSON Response──  │ (Business logic)     │
│              │                    │         │            │
│ Models       │                    │ Repository Layer     │
│ (fromJson)   │                    │ (Database queries)   │
└──────────────┘                    │         │            │
                                    │ Database             │
                                    │ (PostgreSQL/MongoDB) │
                                    └──────────────────────┘
```

Your Flutter app's `http.get('api/users')` hits a **handler** on the backend. That handler calls a **service** (business logic), which calls a **repository** (database), and returns JSON.

---

## 2. HTTP Fundamentals

### What Happens When Your Flutter App Calls an API?

```
1. Flutter: http.get('https://api.example.com/users/1')

2. DNS resolves api.example.com → 52.23.145.2

3. TCP connection established (3-way handshake)

4. HTTP Request sent:
   GET /users/1 HTTP/1.1
   Host: api.example.com
   Authorization: Bearer eyJhbGciOi...
   Content-Type: application/json

5. Server receives, processes, responds:
   HTTP/1.1 200 OK
   Content-Type: application/json
   {"id": 1, "name": "Gautam", "email": "g@e.com"}

6. Flutter parses JSON → User.fromJson(data)
```

### HTTP Methods

```
GET     → Read data           (fetch user, list items)
POST    → Create data         (register user, create post)
PUT     → Replace entirely    (update full profile)
PATCH   → Partial update      (change just email)
DELETE  → Remove data         (delete account)
```

### Status Codes (What Your Backend Will Return)

```
2xx Success:
  200 OK              → Successful GET, PUT, PATCH
  201 Created         → Successful POST (resource created)
  204 No Content      → Successful DELETE

4xx Client Error (caller's fault):
  400 Bad Request     → Invalid JSON, missing fields
  401 Unauthorized    → No token / invalid token
  403 Forbidden       → Valid token but no permission
  404 Not Found       → Resource doesn't exist
  409 Conflict        → Duplicate entry
  422 Unprocessable   → Valid JSON but failed validation
  429 Too Many Requests → Rate limited

5xx Server Error (your backend's fault):
  500 Internal Server Error → Your code crashed
  502 Bad Gateway           → Upstream service down
  503 Service Unavailable   → Server overloaded
```

---

## 3. Your First HTTP Server in Go

### Using Standard Library (net/http)

```go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
)

type Response struct {
    Message string `json:"message"`
    Status  int    `json:"status"`
}

func helloHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    resp := Response{Message: "Hello from Go backend!", Status: 200}
    json.NewEncoder(w).Encode(resp)
}

func main() {
    http.HandleFunc("/hello", helloHandler)
    fmt.Println("Server starting on :8080")
    log.Fatal(http.ListenAndServe(":8080", nil))
}
```

```bash
go run main.go
curl http://localhost:8080/hello
# {"message":"Hello from Go backend!","status":200}
```

### Handling Methods & JSON Body

```go
type User struct {
    ID    int    `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}

var users = []User{}
var nextID = 1

func usersHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")

    switch r.Method {
    case http.MethodGet:
        json.NewEncoder(w).Encode(users)

    case http.MethodPost:
        var newUser User
        err := json.NewDecoder(r.Body).Decode(&newUser)
        if err != nil {
            w.WriteHeader(http.StatusBadRequest)
            json.NewEncoder(w).Encode(map[string]string{"error": "Invalid JSON"})
            return
        }
        newUser.ID = nextID
        nextID++
        users = append(users, newUser)
        w.WriteHeader(http.StatusCreated)
        json.NewEncoder(w).Encode(newUser)

    default:
        w.WriteHeader(http.StatusMethodNotAllowed)
    }
}
```

---

## 4. Gin Framework (Industry Standard)

Standard library works but **Gin** is what production Go APIs use.

```bash
go get github.com/gin-gonic/gin
```

### Full CRUD with Gin

```go
package main

import (
    "fmt"
    "net/http"
    "github.com/gin-gonic/gin"
)

type User struct {
    ID    int    `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}

var users = []User{
    {ID: 1, Name: "Gautam", Email: "gautam@example.com"},
    {ID: 2, Name: "Alice", Email: "alice@example.com"},
}

func main() {
    r := gin.Default() // Includes Logger + Recovery middleware

    // GET /users — list all
    r.GET("/users", func(c *gin.Context) {
        c.JSON(http.StatusOK, users)
    })

    // GET /users/:id — get one
    r.GET("/users/:id", func(c *gin.Context) {
        id := c.Param("id")
        for _, u := range users {
            if fmt.Sprintf("%d", u.ID) == id {
                c.JSON(http.StatusOK, u)
                return
            }
        }
        c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
    })

    // POST /users — create
    r.POST("/users", func(c *gin.Context) {
        var newUser User
        if err := c.ShouldBindJSON(&newUser); err != nil {
            c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
            return
        }
        newUser.ID = len(users) + 1
        users = append(users, newUser)
        c.JSON(http.StatusCreated, newUser)
    })

    // PUT /users/:id — update
    r.PUT("/users/:id", func(c *gin.Context) {
        id := c.Param("id")
        var updated User
        if err := c.ShouldBindJSON(&updated); err != nil {
            c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
            return
        }
        for i, u := range users {
            if fmt.Sprintf("%d", u.ID) == id {
                updated.ID = u.ID
                users[i] = updated
                c.JSON(http.StatusOK, updated)
                return
            }
        }
        c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
    })

    // DELETE /users/:id
    r.DELETE("/users/:id", func(c *gin.Context) {
        id := c.Param("id")
        for i, u := range users {
            if fmt.Sprintf("%d", u.ID) == id {
                users = append(users[:i], users[i+1:]...)
                c.JSON(http.StatusOK, gin.H{"message": "deleted"})
                return
            }
        }
        c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
    })

    r.Run(":8080")
}
```

### Query Params, Headers, Validation

```go
// Query params: GET /search?q=golang&page=2
r.GET("/search", func(c *gin.Context) {
    query := c.Query("q")
    page := c.DefaultQuery("page", "1")
    c.JSON(200, gin.H{"query": query, "page": page})
})

// Binding with validation tags
type CreateUserRequest struct {
    Name  string `json:"name" binding:"required,min=2,max=50"`
    Email string `json:"email" binding:"required,email"`
    Age   int    `json:"age" binding:"required,gte=18,lte=120"`
}

r.POST("/users", func(c *gin.Context) {
    var req CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }
    // req is validated — proceed safely
})
```

### Route Groups & Middleware

```go
func main() {
    r := gin.Default()

    // Public routes
    public := r.Group("/api")
    {
        public.POST("/login", loginHandler)
        public.POST("/register", registerHandler)
    }

    // Protected routes
    protected := r.Group("/api")
    protected.Use(AuthMiddleware())
    {
        protected.GET("/profile", getProfile)
        protected.GET("/users", listUsers)
    }

    r.Run(":8080")
}

func AuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        token := c.GetHeader("Authorization")
        if token == "" {
            c.AbortWithStatusJSON(401, gin.H{"error": "unauthorized"})
            return
        }
        // Validate token...
        userID, err := validateToken(token)
        if err != nil {
            c.AbortWithStatusJSON(401, gin.H{"error": "invalid token"})
            return
        }
        c.Set("userID", userID)
        c.Next()
    }
}
```

---

## 5. JSON Encoding & Decoding

### Marshal (Struct → JSON)

```go
import "encoding/json"

type User struct {
    ID       int    `json:"id"`
    Name     string `json:"name"`
    Email    string `json:"email,omitempty"` // Omit if empty
    Password string `json:"-"`              // Never in JSON
}

user := User{ID: 1, Name: "Gautam", Email: "g@e.com", Password: "secret"}

jsonBytes, err := json.Marshal(user)
// {"id":1,"name":"Gautam","email":"g@e.com"}
// Password excluded! Email would be excluded if empty.

// Pretty print
jsonPretty, _ := json.MarshalIndent(user, "", "  ")
```

### Unmarshal (JSON → Struct)

```go
jsonStr := `{"id":1,"name":"Gautam","email":"g@e.com"}`

var user User
err := json.Unmarshal([]byte(jsonStr), &user)
fmt.Println(user.Name) // "Gautam"

// Unknown/dynamic JSON — use map
var data map[string]interface{}
json.Unmarshal([]byte(jsonStr), &data)
```

> **Flutter comparison:** `json.Marshal` = `jsonEncode()`, `json.Unmarshal` = `jsonDecode()`. Struct tags = `@JsonKey` annotations.

---

## 6. Database — PostgreSQL

### Option A: Raw SQL (database/sql)

```bash
go get github.com/lib/pq
```

```go
package main

import (
    "database/sql"
    "fmt"
    "log"
    _ "github.com/lib/pq"
)

func main() {
    connStr := "host=localhost port=5432 user=postgres password=secret dbname=myapp sslmode=disable"
    db, err := sql.Open("postgres", connStr)
    if err != nil {
        log.Fatal(err)
    }
    defer db.Close()

    // Verify connection
    if err := db.Ping(); err != nil {
        log.Fatal("Cannot connect:", err)
    }

    // CREATE TABLE
    db.Exec(`
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    `)

    // INSERT (always use $1, $2 — NEVER string concat for SQL injection safety)
    var newID int
    db.QueryRow(
        "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id",
        "Gautam", "gautam@example.com",
    ).Scan(&newID)

    // SELECT one
    var name, email string
    err = db.QueryRow("SELECT name, email FROM users WHERE id = $1", newID).
        Scan(&name, &email)

    // SELECT multiple
    rows, _ := db.Query("SELECT id, name, email FROM users")
    defer rows.Close()
    for rows.Next() {
        var id int
        var n, e string
        rows.Scan(&id, &n, &e)
        fmt.Printf("User: %d %s %s\n", id, n, e)
    }

    // UPDATE
    db.Exec("UPDATE users SET name = $1 WHERE id = $2", "Gautam K", newID)

    // DELETE
    db.Exec("DELETE FROM users WHERE id = $1", newID)
}
```

### Option B: GORM (ORM — Recommended for Most Projects)

```bash
go get gorm.io/gorm
go get gorm.io/driver/postgres
```

```go
package main

import (
    "log"
    "time"
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
)

type User struct {
    ID        uint           `json:"id" gorm:"primaryKey"`
    Name      string         `json:"name" gorm:"not null"`
    Email     string         `json:"email" gorm:"uniqueIndex;not null"`
    Age       int            `json:"age"`
    CreatedAt time.Time      `json:"created_at"`
    UpdatedAt time.Time      `json:"updated_at"`
    DeletedAt gorm.DeletedAt `json:"-" gorm:"index"` // Soft delete
}

func main() {
    dsn := "host=localhost user=postgres password=secret dbname=myapp port=5432 sslmode=disable"
    db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{})
    if err != nil {
        log.Fatal(err)
    }

    // Auto-migrate (creates/updates table)
    db.AutoMigrate(&User{})

    // CREATE
    user := User{Name: "Gautam", Email: "g@e.com", Age: 25}
    db.Create(&user) // user.ID auto-populated

    // READ by ID
    var found User
    db.First(&found, user.ID)

    // READ by condition
    var users []User
    db.Where("age > ?", 20).Find(&users)

    // READ with pagination
    var page []User
    db.Offset(0).Limit(10).Order("created_at desc").Find(&page)

    // UPDATE
    db.Model(&found).Updates(User{Name: "Gautam Kumar", Age: 26})

    // DELETE (soft delete)
    db.Delete(&found)
}
```

---

## 7. Project Architecture (Clean Architecture)

```
my-api/
├── cmd/
│   └── server/
│       └── main.go              # Entry point
├── internal/
│   ├── models/                  # Structs & DTOs
│   │   ├── user.go
│   │   └── response.go
│   ├── handlers/                # HTTP handlers (like controllers)
│   │   └── user_handler.go
│   ├── services/                # Business logic
│   │   └── user_service.go
│   ├── repository/              # Database operations
│   │   └── user_repository.go
│   └── middleware/              # Auth, CORS, logging
│       ├── auth.go
│       └── cors.go
├── pkg/                         # Shared/public utilities
│   └── config/
│       └── config.go
├── migrations/                  # SQL migrations
├── go.mod
├── go.sum
├── .env
└── Dockerfile
```

### Models Layer

```go
// internal/models/user.go
package models

import "time"

type User struct {
    ID        uint      `json:"id" gorm:"primaryKey"`
    Name      string    `json:"name" gorm:"not null"`
    Email     string    `json:"email" gorm:"uniqueIndex"`
    Password  string    `json:"-" gorm:"not null"`
    CreatedAt time.Time `json:"created_at"`
    UpdatedAt time.Time `json:"updated_at"`
}

// Request DTOs
type CreateUserRequest struct {
    Name     string `json:"name" binding:"required,min=2"`
    Email    string `json:"email" binding:"required,email"`
    Password string `json:"password" binding:"required,min=8"`
}

type LoginRequest struct {
    Email    string `json:"email" binding:"required,email"`
    Password string `json:"password" binding:"required"`
}

// Response DTOs (never expose password)
type UserResponse struct {
    ID    uint   `json:"id"`
    Name  string `json:"name"`
    Email string `json:"email"`
}

type APIResponse struct {
    Success bool        `json:"success"`
    Message string      `json:"message,omitempty"`
    Data    interface{} `json:"data,omitempty"`
    Error   string      `json:"error,omitempty"`
}
```

### Repository Layer

```go
// internal/repository/user_repository.go
package repository

import (
    "github.com/gautam/my-api/internal/models"
    "gorm.io/gorm"
)

type UserRepository struct {
    db *gorm.DB
}

func NewUserRepository(db *gorm.DB) *UserRepository {
    return &UserRepository{db: db}
}

func (r *UserRepository) Create(user *models.User) error {
    return r.db.Create(user).Error
}

func (r *UserRepository) FindByID(id uint) (*models.User, error) {
    var user models.User
    err := r.db.First(&user, id).Error
    return &user, err
}

func (r *UserRepository) FindByEmail(email string) (*models.User, error) {
    var user models.User
    err := r.db.Where("email = ?", email).First(&user).Error
    return &user, err
}

func (r *UserRepository) FindAll(page, limit int) ([]models.User, int64, error) {
    var users []models.User
    var total int64
    r.db.Model(&models.User{}).Count(&total)
    offset := (page - 1) * limit
    err := r.db.Offset(offset).Limit(limit).Order("created_at desc").Find(&users).Error
    return users, total, err
}

func (r *UserRepository) Update(user *models.User) error {
    return r.db.Save(user).Error
}

func (r *UserRepository) Delete(id uint) error {
    return r.db.Delete(&models.User{}, id).Error
}
```

### Service Layer

```go
// internal/services/user_service.go
package services

import (
    "errors"
    "github.com/gautam/my-api/internal/models"
    "github.com/gautam/my-api/internal/repository"
    "golang.org/x/crypto/bcrypt"
)

type UserService struct {
    repo *repository.UserRepository
}

func NewUserService(repo *repository.UserRepository) *UserService {
    return &UserService{repo: repo}
}

func (s *UserService) Register(req *models.CreateUserRequest) (*models.UserResponse, error) {
    // Check duplicate email
    existing, _ := s.repo.FindByEmail(req.Email)
    if existing != nil {
        return nil, errors.New("email already registered")
    }

    // Hash password
    hashed, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
    if err != nil {
        return nil, err
    }

    user := &models.User{
        Name:     req.Name,
        Email:    req.Email,
        Password: string(hashed),
    }

    if err := s.repo.Create(user); err != nil {
        return nil, err
    }

    return &models.UserResponse{ID: user.ID, Name: user.Name, Email: user.Email}, nil
}

func (s *UserService) GetByID(id uint) (*models.UserResponse, error) {
    user, err := s.repo.FindByID(id)
    if err != nil {
        return nil, errors.New("user not found")
    }
    return &models.UserResponse{ID: user.ID, Name: user.Name, Email: user.Email}, nil
}
```

### Handler Layer

```go
// internal/handlers/user_handler.go
package handlers

import (
    "net/http"
    "strconv"
    "github.com/gautam/my-api/internal/models"
    "github.com/gautam/my-api/internal/services"
    "github.com/gin-gonic/gin"
)

type UserHandler struct {
    service *services.UserService
}

func NewUserHandler(service *services.UserService) *UserHandler {
    return &UserHandler{service: service}
}

func (h *UserHandler) Register(c *gin.Context) {
    var req models.CreateUserRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusBadRequest, models.APIResponse{Success: false, Error: err.Error()})
        return
    }

    user, err := h.service.Register(&req)
    if err != nil {
        c.JSON(http.StatusConflict, models.APIResponse{Success: false, Error: err.Error()})
        return
    }

    c.JSON(http.StatusCreated, models.APIResponse{
        Success: true, Message: "User registered", Data: user,
    })
}

func (h *UserHandler) GetUser(c *gin.Context) {
    id, err := strconv.ParseUint(c.Param("id"), 10, 32)
    if err != nil {
        c.JSON(http.StatusBadRequest, models.APIResponse{Success: false, Error: "invalid ID"})
        return
    }

    user, err := h.service.GetByID(uint(id))
    if err != nil {
        c.JSON(http.StatusNotFound, models.APIResponse{Success: false, Error: err.Error()})
        return
    }

    c.JSON(http.StatusOK, models.APIResponse{Success: true, Data: user})
}
```

### Wiring in main.go

```go
// cmd/server/main.go
package main

import (
    "log"
    "github.com/gautam/my-api/internal/handlers"
    "github.com/gautam/my-api/internal/middleware"
    "github.com/gautam/my-api/internal/models"
    "github.com/gautam/my-api/internal/repository"
    "github.com/gautam/my-api/internal/services"
    "github.com/gautam/my-api/pkg/config"
    "github.com/gin-gonic/gin"
    "gorm.io/driver/postgres"
    "gorm.io/gorm"
)

func main() {
    cfg := config.Load()

    // Database
    db, err := gorm.Open(postgres.Open(cfg.DatabaseURL), &gorm.Config{})
    if err != nil {
        log.Fatal("DB connection failed:", err)
    }
    db.AutoMigrate(&models.User{})

    // Dependency injection (manual — no GetIt needed in Go)
    userRepo := repository.NewUserRepository(db)
    userService := services.NewUserService(userRepo)
    userHandler := handlers.NewUserHandler(userService)

    // Router
    r := gin.Default()
    r.Use(middleware.CORS())

    api := r.Group("/api/v1")
    {
        api.POST("/register", userHandler.Register)
        api.POST("/login", userHandler.Login)

        protected := api.Group("/")
        protected.Use(middleware.AuthMiddleware())
        {
            protected.GET("/users", userHandler.ListUsers)
            protected.GET("/users/:id", userHandler.GetUser)
        }
    }

    log.Printf("Server starting on :%s", cfg.Port)
    r.Run(":" + cfg.Port)
}
```

---

## 8. Authentication — JWT

```bash
go get github.com/golang-jwt/jwt/v5
go get golang.org/x/crypto/bcrypt
```

### Token Generation & Validation

```go
package auth

import (
    "errors"
    "time"
    "github.com/golang-jwt/jwt/v5"
)

var jwtSecret = []byte("your-secret-key-change-in-production")

type Claims struct {
    UserID uint   `json:"user_id"`
    Email  string `json:"email"`
    jwt.RegisteredClaims
}

func GenerateToken(userID uint, email string) (string, error) {
    claims := Claims{
        UserID: userID,
        Email:  email,
        RegisteredClaims: jwt.RegisteredClaims{
            ExpiresAt: jwt.NewNumericDate(time.Now().Add(24 * time.Hour)),
            IssuedAt:  jwt.NewNumericDate(time.Now()),
        },
    }
    token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
    return token.SignedString(jwtSecret)
}

func ValidateToken(tokenString string) (*Claims, error) {
    token, err := jwt.ParseWithClaims(tokenString, &Claims{},
        func(token *jwt.Token) (interface{}, error) {
            return jwtSecret, nil
        },
    )
    if err != nil {
        return nil, err
    }
    claims, ok := token.Claims.(*Claims)
    if !ok || !token.Valid {
        return nil, errors.New("invalid token")
    }
    return claims, nil
}
```

### Auth Middleware

```go
package middleware

import (
    "net/http"
    "strings"
    "github.com/gautam/my-api/internal/auth"
    "github.com/gin-gonic/gin"
)

func AuthMiddleware() gin.HandlerFunc {
    return func(c *gin.Context) {
        authHeader := c.GetHeader("Authorization")
        if authHeader == "" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no token"})
            return
        }

        parts := strings.Split(authHeader, " ")
        if len(parts) != 2 || parts[0] != "Bearer" {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid format"})
            return
        }

        claims, err := auth.ValidateToken(parts[1])
        if err != nil {
            c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
            return
        }

        c.Set("userID", claims.UserID)
        c.Set("email", claims.Email)
        c.Next()
    }
}
```

### Login Handler

```go
func (h *UserHandler) Login(c *gin.Context) {
    var req models.LoginRequest
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(400, gin.H{"error": err.Error()})
        return
    }

    user, err := h.service.FindByEmail(req.Email)
    if err != nil {
        c.JSON(401, gin.H{"error": "invalid credentials"})
        return
    }

    // Compare hashed password
    err = bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(req.Password))
    if err != nil {
        c.JSON(401, gin.H{"error": "invalid credentials"})
        return
    }

    token, _ := auth.GenerateToken(user.ID, user.Email)
    c.JSON(200, gin.H{
        "token": token,
        "user":  models.UserResponse{ID: user.ID, Name: user.Name, Email: user.Email},
    })
}
```

---

## 9. Environment & Config

```bash
go get github.com/joho/godotenv
```

### .env

```env
PORT=8080
DB_HOST=localhost
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=secret
DB_NAME=myapp
JWT_SECRET=super-secret-change-this
GIN_MODE=debug
```

### Config Loader

```go
// pkg/config/config.go
package config

import (
    "fmt"
    "os"
    "github.com/joho/godotenv"
)

type Config struct {
    Port        string
    DatabaseURL string
    JWTSecret   string
}

func Load() *Config {
    godotenv.Load() // Loads .env (ignore error in prod)

    dbURL := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
        getEnv("DB_HOST", "localhost"),
        getEnv("DB_PORT", "5432"),
        getEnv("DB_USER", "postgres"),
        getEnv("DB_PASSWORD", ""),
        getEnv("DB_NAME", "myapp"),
    )

    return &Config{
        Port:        getEnv("PORT", "8080"),
        DatabaseURL: dbURL,
        JWTSecret:   getEnv("JWT_SECRET", "default-secret"),
    }
}

func getEnv(key, fallback string) string {
    if val := os.Getenv(key); val != "" {
        return val
    }
    return fallback
}
```

---

## 10. Essential Middleware

### CORS (Required for Flutter Web)

```go
func CORS() gin.HandlerFunc {
    return func(c *gin.Context) {
        c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
        c.Writer.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
        c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization")

        if c.Request.Method == "OPTIONS" {
            c.AbortWithStatus(204)
            return
        }
        c.Next()
    }
}
```

### Request Logger

```go
func Logger() gin.HandlerFunc {
    return func(c *gin.Context) {
        start := time.Now()
        c.Next()
        log.Printf("[%s] %s %s %d %v",
            c.Request.Method, c.Request.URL.Path,
            c.ClientIP(), c.Writer.Status(), time.Since(start))
    }
}
```

### Rate Limiter

```go
import "golang.org/x/time/rate"

func RateLimiter(rps int) gin.HandlerFunc {
    limiter := rate.NewLimiter(rate.Limit(rps), rps)
    return func(c *gin.Context) {
        if !limiter.Allow() {
            c.AbortWithStatusJSON(429, gin.H{"error": "too many requests"})
            return
        }
        c.Next()
    }
}
```

---

## 11. Context (Request Lifecycle)

```go
import "context"

// Every HTTP request has a context
// If client disconnects, context is cancelled → your DB query stops too

func (h *UserHandler) GetUser(c *gin.Context) {
    ctx := c.Request.Context()
    user, err := h.service.GetByID(ctx, id)
    // If client disconnects, ctx is cancelled automatically
}

// In repository — pass context to DB
func (r *UserRepository) FindByID(ctx context.Context, id uint) (*User, error) {
    var user User
    err := r.db.WithContext(ctx).First(&user, id).Error
    return &user, err
}

// Creating context with timeout
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel() // ALWAYS defer cancel

result, err := longOperation(ctx)
if err == context.DeadlineExceeded {
    fmt.Println("Timed out!")
}
```

---

## 12. Database Migrations (Production)

Don't use AutoMigrate in production. Use proper migration files.

```bash
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Create migration
migrate create -ext sql -dir migrations -seq create_users_table
```

```sql
-- migrations/000001_create_users_table.up.sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_users_email ON users(email);

-- migrations/000001_create_users_table.down.sql
DROP TABLE IF EXISTS users;
```

```bash
# Run migrations
migrate -path migrations -database "postgresql://postgres:secret@localhost:5432/myapp?sslmode=disable" up

# Rollback
migrate -path migrations -database "..." down 1
```

---

## 13. Dockerizing Your Go App

### Dockerfile

```dockerfile
# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /app/server ./cmd/server

# Runtime stage (tiny ~20MB image!)
FROM alpine:3.19
RUN apk --no-cache add ca-certificates tzdata
WORKDIR /app
COPY --from=builder /app/server .
COPY --from=builder /app/migrations ./migrations
EXPOSE 8080
CMD ["./server"]
```

### docker-compose.yml

```yaml
version: '3.8'
services:
  api:
    build: .
    ports:
      - "8080:8080"
    environment:
      - PORT=8080
      - DB_HOST=postgres
      - DB_PORT=5432
      - DB_USER=postgres
      - DB_PASSWORD=secret
      - DB_NAME=myapp
      - JWT_SECRET=change-this
      - GIN_MODE=release
    depends_on:
      - postgres

  postgres:
    image: postgres:16-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=secret
      - POSTGRES_DB=myapp
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

```bash
docker-compose up -d          # Start
docker-compose logs -f api    # Logs
docker-compose up --build     # Rebuild
```

> **Why Go rocks for Docker:** Your binary is ~15MB, final image ~20MB. Node.js images are 200-900MB. Huge win for deployment.

---

## 14. Deployment to Production

### Option 1: VPS (DigitalOcean/AWS EC2)

```bash
# Cross-compile for Linux from any OS
GOOS=linux GOARCH=amd64 go build -o server ./cmd/server

# Copy to server
scp server user@your-server:/app/

# Create systemd service
sudo nano /etc/systemd/system/myapi.service
```

```ini
[Unit]
Description=My Go API
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/app
ExecStart=/app/server
Restart=always
EnvironmentFile=/app/.env

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable myapi
sudo systemctl start myapi
```

### Option 2: Railway/Render (Easiest — Push to GitHub, Auto-deploy)

Both auto-detect Go and deploy. Zero config needed.

### Nginx Reverse Proxy + HTTPS

```nginx
server {
    listen 80;
    server_name api.yourdomain.com;

    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

```bash
sudo certbot --nginx -d api.yourdomain.com  # Free HTTPS
```

---

## 15. Testing

### Unit Test

```go
// user_service_test.go
func TestRegister_DuplicateEmail(t *testing.T) {
    // Setup mock repository...
    service := NewUserService(mockRepo)

    _, err := service.Register(&CreateUserRequest{
        Name:     "Test",
        Email:    "existing@email.com",
        Password: "password123",
    })

    if err == nil {
        t.Error("Expected error for duplicate email, got nil")
    }
}
```

### Table-Driven Tests (Go Idiom)

```go
func TestValidateEmail(t *testing.T) {
    tests := []struct {
        name    string
        email   string
        isValid bool
    }{
        {"valid email", "user@example.com", true},
        {"no @", "userexample.com", false},
        {"no domain", "user@", false},
        {"empty", "", false},
    }

    for _, tc := range tests {
        t.Run(tc.name, func(t *testing.T) {
            result := IsValidEmail(tc.email)
            if result != tc.isValid {
                t.Errorf("IsValidEmail(%q) = %v, want %v", tc.email, result, tc.isValid)
            }
        })
    }
}
```

### API Integration Test

```go
func TestCreateUser_API(t *testing.T) {
    router := setupTestRouter()

    body := `{"name":"Test","email":"test@e.com","password":"pass12345"}`
    req, _ := http.NewRequest("POST", "/api/v1/register", strings.NewReader(body))
    req.Header.Set("Content-Type", "application/json")

    w := httptest.NewRecorder()
    router.ServeHTTP(w, req)

    if w.Code != 201 {
        t.Errorf("Expected 201, got %d", w.Code)
    }
}
```

### Testing Commands

```bash
go test ./...           # Run all tests
go test -v ./...        # Verbose
go test -cover ./...    # Coverage
go test -race ./...     # Race condition detection
```

### Testing with curl

```bash
# Register
curl -X POST http://localhost:8080/api/v1/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Gautam","email":"g@e.com","password":"pass12345"}'

# Login (get token)
curl -X POST http://localhost:8080/api/v1/login \
  -H "Content-Type: application/json" \
  -d '{"email":"g@e.com","password":"pass12345"}'

# Protected route
curl http://localhost:8080/api/v1/users \
  -H "Authorization: Bearer <token-from-login>"
```

---

## 16. Debugging & Common Gotchas

### Top Mistakes from Dart/Flutter Background

```go
// 1. NEVER ignore errors
result, _ := riskyOperation()  // BAD — silent failures
result, err := riskyOperation()
if err != nil { /* handle it */ }

// 2. Nil pointer dereference (#1 runtime panic)
var user *User // nil
fmt.Println(user.Name) // PANIC!
// Fix: always check nil before accessing pointer fields

// 3. Forgetting to close response body
resp, err := http.Get("https://api.example.com")
if err != nil { log.Fatal(err) }
defer resp.Body.Close() // MUST close — or leak connections

// 4. Goroutine leaks
go func() {
    for { /* runs forever, leaking memory */ }
}()
// Fix: use context.WithCancel or context.WithTimeout

// 5. Unused variables = COMPILE ERROR (not just a warning)
x := 42 // error: x declared and not used

// 6. Slice gotcha — slices share underlying memory
a := []int{1, 2, 3, 4}
b := a[1:3] // b = [2, 3] but shares memory with a
b[0] = 99
fmt.Println(a) // [1, 99, 3, 4] — a changed too!
// Fix: use copy() for independent slices

// 7. Map iteration order is random
// Don't depend on map order — sort keys if needed
```

### Debug Tools

```bash
# Quick debug printing
fmt.Printf("DEBUG: %+v\n", user)   # %+v shows field names
fmt.Printf("TYPE: %T\n", value)    # %T shows type

# Delve debugger
go install github.com/go-delve/delve/cmd/dlv@latest
dlv debug ./cmd/server

# Race detector
go run -race main.go
go test -race ./...
```

---

## 17. Useful Go Packages Cheatsheet

| Purpose | Package | Install |
|---|---|---|
| HTTP framework | `gin-gonic/gin` | `go get github.com/gin-gonic/gin` |
| ORM | `gorm.io/gorm` | `go get gorm.io/gorm` |
| JWT auth | `golang-jwt/jwt` | `go get github.com/golang-jwt/jwt/v5` |
| Password hash | `bcrypt` | `go get golang.org/x/crypto/bcrypt` |
| Env files | `godotenv` | `go get github.com/joho/godotenv` |
| Validation | `validator` | `go get github.com/go-playground/validator/v10` |
| Logging | `zap` | `go get go.uber.org/zap` |
| UUID | `google/uuid` | `go get github.com/google/uuid` |
| WebSocket | `gorilla/websocket` | `go get github.com/gorilla/websocket` |
| Redis | `go-redis` | `go get github.com/redis/go-redis/v9` |
| Testing | `testify` | `go get github.com/stretchr/testify` |
| Rate limit | `x/time/rate` | `go get golang.org/x/time` |
| Migrations | `golang-migrate` | `go install github.com/golang-migrate/migrate/v4/cmd/migrate` |
| Swagger docs | `swaggo/swag` | `go install github.com/swaggo/swag/cmd/swag@latest` |
| HTTP client | `resty` | `go get github.com/go-resty/resty/v2` |

---

## 18. Learning Roadmap

```
Week 1-2: Go Language Basics
  ✦ Variables, types, control flow, functions
  ✦ Structs, interfaces, methods
  ✦ Error handling pattern (if err != nil)
  ✦ Build CLI tools to practice

Week 3-4: Go Intermediate
  ✦ Pointers and when to use them
  ✦ Goroutines, channels, sync.WaitGroup
  ✦ Packages, modules, project structure
  ✦ Testing (table-driven tests)

Week 5-6: HTTP & APIs
  ✦ net/http basics → Gin framework
  ✦ CRUD handlers, JSON encode/decode
  ✦ Middleware (auth, cors, logging)
  ✦ Build a simple REST API

Week 7-8: Database & Auth
  ✦ PostgreSQL setup & raw SQL
  ✦ GORM for ORM approach
  ✦ JWT authentication
  ✦ Password hashing with bcrypt
  ✦ Database migrations

Week 9-10: Production Skills
  ✦ Clean architecture (handler→service→repo)
  ✦ Environment config & secrets
  ✦ Docker & docker-compose
  ✦ Structured logging

Week 11-12: Deploy & Beyond
  ✦ Deploy to VPS or Railway
  ✦ Nginx reverse proxy + HTTPS
  ✦ CI/CD basics (GitHub Actions)
  ✦ Monitoring & error tracking
  ✦ WebSocket for real-time features

Ongoing: Build your manpower management system!
  Apply everything above to a real project.
```
