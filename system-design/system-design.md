# System Design — From First Principles

A complete reference for engineers who want to understand how large-scale systems are built, what trade-offs are made, and how to reason about them. Beginner to intermediate level. Use as a learning guide and keep as a reference.

---

## Table of Contents

1. [What Is System Design and Why It Matters](#1)
2. [The Framework — How to Approach Any Design Problem](#2)
3. [Scale Estimation — Back-of-the-Envelope Math](#3)
4. [Core Building Blocks](#4)
   - Load Balancer
   - CDN
   - Cache
   - Database
   - Message Queue
   - Object Storage
5. [SQL vs NoSQL — Choosing a Database](#5)
6. [Caching — Every Layer Explained](#6)
7. [Load Balancing — Algorithms and Patterns](#7)
8. [Consistent Hashing — Distributing Load Without Reshuffling](#8)
9. [Rate Limiting — Protecting Your System](#9)
10. [API Design — REST, gRPC, and WebSockets](#10)
11. [Microservices vs Monolith](#11)
12. [Message Queues and Event-Driven Architecture](#12)
13. [Distributed System Concepts](#13)
    - CAP Theorem
    - Consistency Models
    - Distributed Transactions
14. [Reliability Patterns](#14)
    - Circuit Breaker
    - Retry with Backoff
    - Bulkhead
    - Timeout
15. [Observability — Metrics, Logs, Traces](#15)
16. [Common System Design Examples](#16)
    - URL Shortener
    - Social Media Feed
    - Chat System
    - File Storage (like S3)
17. [The Decision Framework](#17)

---

## 1. What Is System Design and Why It Matters

System design is the process of defining the architecture, components, and data flow of a system to satisfy functional and non-functional requirements.

**Functional requirements:** what the system does.
```
"Users can post tweets. Users can follow other users. The feed shows posts from followed users."
```

**Non-functional requirements:** how well the system does it.
```
Availability:    99.99% uptime (≈52 minutes downtime per year)
Latency:         Feed loads in < 200 ms (p99)
Throughput:      Handle 100,000 requests per second
Durability:      No data loss
Consistency:     User always sees their own posts immediately
Scalability:     Must handle 10× traffic in 6 months
```

Understanding the difference between these two is the first step to making good design decisions.

---

## 2. The Framework — How to Approach Any Design Problem

When asked to design a system, follow this structure. Do not jump to solutions before understanding requirements.

### Step 1: Clarify Requirements (5 minutes)

Ask questions before drawing anything.

```
Functional:
  - What are the core features? What is out of scope?
  - Who are the users? (consumers, businesses, developers via API?)
  - What does "post a tweet" mean exactly? Text only? Images? Video?
  - Read-heavy or write-heavy?

Non-functional:
  - How many users? DAU? Concurrent users?
  - What latency is acceptable? Read vs write?
  - What consistency is required? Can users see slightly stale data?
  - What is the uptime requirement?
  - Data retention: how long do we store data?
```

### Step 2: Estimate Scale (5 minutes)

Back-of-envelope numbers to guide your design. See Section 3.

### Step 3: High-Level Design (10 minutes)

Draw the major components and how data flows between them.

```
Client → API Gateway → Service → Cache → Database
                     ↓
               Message Queue → Worker → Storage
```

Start with the simplest thing that could work. Add complexity only when the problem demands it.

### Step 4: Deep Dive — Components (15 minutes)

Pick the 2–3 most critical or challenging parts and go deep:
- Database schema
- API endpoints
- Caching strategy
- Sharding / partitioning strategy
- Replication and failover

### Step 5: Trade-offs and Bottlenecks (5 minutes)

What are the weaknesses of your design?
- Single points of failure
- Potential bottlenecks
- Scaling limits
- Consistency vs availability decisions
- What you would change with more time

---

## 3. Scale Estimation — Back-of-the-Envelope Math

Engineers who do this well are taken seriously. The numbers don't need to be precise — order of magnitude is enough.

### Memory and storage units

```
KB = 10^3 bytes   = 1,000 bytes
MB = 10^6 bytes   = 1,000,000 bytes
GB = 10^9 bytes   = 1,000,000,000 bytes
TB = 10^12 bytes
PB = 10^15 bytes

A tweet: ~200 bytes
A user profile: ~1 KB
A compressed photo: ~200 KB
A 1-minute video (compressed): ~6 MB
```

### Latency reference numbers (know these)

```
L1 cache read:          0.5 ns
L2 cache read:          7 ns
RAM read:               100 ns
SSD random read:        100 µs  (0.1 ms)
SSD sequential read:    1 µs per KB
Network same datacenter: 0.5 ms
Network cross-region:   30–100 ms
Disk spinning read:     10 ms
Packet round-trip CA→NL: 150 ms
```

Lesson: RAM is 1000× faster than SSD. SSD is 100× faster than spinning disk. Network in the same datacenter is fast; cross-region is not.

### Example: Designing Twitter

```
Assumptions:
  300 million monthly active users (MAU)
  50% use daily → 150 million DAU
  Each user reads their feed 5 times per day
  Each user posts 2 tweets per day

Read QPS:
  150M users × 5 reads / 86400 seconds ≈ 8,700 reads/second
  Peak (assume 3× average):              26,100 reads/second

Write QPS:
  150M users × 2 posts / 86400 seconds ≈ 3,500 writes/second
  Peak:                                   10,500 writes/second
  → Heavily read-biased (8:1 read-to-write ratio)

Storage:
  Tweets: 3,500 writes/second × 200 bytes × 86400 sec × 365 days
         ≈ 22 TB per year for tweet text alone
  Media:  If 10% of tweets have a photo (200 KB average):
          350 media writes/second × 200 KB × 86400 × 365
         ≈ 2.2 PB per year

Bandwidth:
  Read bandwidth: 26,100 reads/sec × 10 KB per feed response ≈ 250 MB/s outbound
```

These numbers tell you: you need aggressive caching, object storage for media, a CDN for delivery, and a read-optimized architecture.

---

## 4. Core Building Blocks

Every large system is assembled from a set of standard components. Know each one deeply.

### Load Balancer

Distributes incoming traffic across multiple servers.

```
           Clients
              │
         Load Balancer
        /      │      \
   Server 1  Server 2  Server 3
```

**Why:** A single server has finite CPU, RAM, and network capacity. As traffic grows, one server is not enough. A load balancer lets you add more servers and spread the load.

**What it does:**
- Health checks: removes unhealthy servers from the pool
- SSL termination: decrypts HTTPS once at the load balancer; servers communicate in HTTP internally
- Session affinity (sticky sessions): routes the same user to the same server (for stateful apps)

**Types:**
- Layer 4 (L4): routes based on IP + TCP port. Fast, no content inspection.
- Layer 7 (L7): routes based on HTTP headers, URL, cookies. Smarter routing (e.g., `/api/*` → API servers, `/static/*` → CDN).

Examples: AWS ALB (L7), AWS NLB (L4), Nginx, HAProxy.

---

### CDN — Content Delivery Network

A globally distributed set of servers that cache static content close to the user.

```
User in Mumbai → CDN edge node in Mumbai → serves cached content
                                         (instead of hitting origin server in US)
```

**Why:** Network latency depends on physical distance. Serving a 2 MB image from a server 1000 km away vs 20 km away: the closer one is 50× faster.

**What goes on a CDN:**
- Static files: JS, CSS, images, fonts, videos
- HTML pages (if cacheable)
- API responses (with cache headers)

**Cache-Control headers tell the CDN how long to cache:**

```http
Cache-Control: public, max-age=86400    # cache for 1 day
Cache-Control: private, no-store        # don't cache (user-specific data)
Cache-Control: public, s-maxage=3600    # CDN caches for 1 hour
```

**CDN invalidation:** when you deploy new code, old cached files are still served. Use content-based hashing in filenames: `app.a3f9b2.js` instead of `app.js`. When the content changes, the filename changes, and the new file is immediately fetched.

Examples: Cloudflare, AWS CloudFront, Fastly.

---

### Cache

A fast in-memory store that sits in front of slower data sources (database, API, disk).

```
Request → App → Cache (Redis) → if hit: return  → done
                              → if miss: query DB → store in cache → return
```

See Section 6 for complete caching strategies.

---

### Database

Persistent storage for structured data. The source of truth.

See Section 5 for SQL vs NoSQL decision-making.
See the DATABASE_AT_SCALE doc for deep Postgres internals.

---

### Message Queue

A buffer that decouples a producer (the system creating a task) from a consumer (the system executing it).

```
Producer (web server)  →  Queue (Kafka / SQS / RabbitMQ)  →  Consumer (worker)
"Send a welcome email"    [task stored here]                  "sends the email"
```

**Why:**
- The web server responds immediately ("email queued") without waiting for the email to send
- If the consumer crashes, the task stays in the queue and is retried
- Consumers can scale independently from producers
- Smooths out traffic spikes: 10,000 tasks arrive in 1 second, consumers process them over 10 seconds

See Section 12 for message queue patterns in depth.

---

### Object Storage

Stores large, unstructured binary objects: images, videos, backups, logs.

```
App  →  PUT /uploads/photo.jpg  →  Object Storage (S3)
User →  GET https://cdn.example.com/photo.jpg  →  CDN → S3
```

**Why not the database:** Storing a 5 MB image in Postgres is slow, bloats the database, and is expensive. Object storage is cheap, durable (3 copies across availability zones by default), and built for this.

**Pattern:**
1. Client requests a pre-signed upload URL from your API
2. Client uploads directly to S3 (not through your server)
3. S3 sends a webhook: "object uploaded"
4. Your server records the S3 URL in the database

Examples: AWS S3, Google Cloud Storage, Cloudflare R2.

---

## 5. SQL vs NoSQL — Choosing a Database

This is one of the most important and most confused decisions in system design.

### SQL (Relational)

```
Examples: PostgreSQL, MySQL, SQLite

Structure:
  Predefined schema (tables, columns, types)
  Rows and columns
  Foreign key relationships enforced
  ACID transactions

Best for:
  Structured data with clear relationships
  Complex queries (joins, aggregations, grouping)
  Transactional integrity required (payments, inventory, user accounts)
  When you need rich querying flexibility
  When correctness matters more than write throughput
```

### NoSQL — Document Store

```
Examples: MongoDB, CouchDB, Firestore

Structure:
  Schema-less JSON documents
  Nested data in one document
  No joins (embed related data)

Best for:
  Semi-structured or schema-flexible data
  Hierarchical/nested data (product catalog with varying attributes)
  Rapid iteration when schema evolves frequently
  Read-heavy workloads on a single document

Example: E-commerce product catalog — each product has different attributes
  { "id": 1, "type": "laptop", "cpu": "M3", "ram": "16GB" }
  { "id": 2, "type": "shoe",   "size": "42", "color": "black" }
  SQL needs nullable columns or EAV (ugly); MongoDB stores it naturally.
```

### NoSQL — Key-Value Store

```
Examples: Redis, DynamoDB (also supports key-value), Memcached

Structure:
  key → value (any type: string, list, hash, set, sorted set)
  No querying by value — only by key

Best for:
  Session storage
  Caching
  Leaderboards (sorted sets)
  Rate limiting counters
  Pub/sub messaging

Not good for:
  Complex queries
  Relationships
  Large datasets where you need to query by value
```

### NoSQL — Wide-Column Store

```
Examples: Apache Cassandra, HBase, Google Bigtable

Structure:
  Table with rows and columns, but columns can vary per row
  Rows are identified by a partition key
  Optimized for writes and range reads within a partition

Best for:
  Time-series data (sensor readings, events, logs)
  IoT data
  Write-heavy workloads at massive scale (millions of writes/second)
  Data that is always accessed by a known key

Not good for:
  Ad-hoc queries
  Joins
  Transactions across rows
```

### NoSQL — Search Engine

```
Examples: Elasticsearch, OpenSearch, Typesense, Meilisearch

Structure:
  Documents with full-text search
  Inverted index
  Near real-time search

Best for:
  Full-text search (user searches for "python tutorial")
  Log analytics (ELK stack)
  Autocomplete and fuzzy matching

Not the source of truth — sync data from your main DB into Elasticsearch.
```

### Decision cheat sheet

| Question | If yes, lean toward |
|----------|--------------------:|
| Need transactions (money, inventory)? | SQL |
| Need complex joins and aggregations? | SQL |
| Schema changes frequently? | Document DB |
| Write volume > 100k/second? | Cassandra / DynamoDB |
| Need full-text search? | Elasticsearch |
| Need fast key-value with sub-ms latency? | Redis |
| Storing files, images, videos? | Object storage (S3) |
| Building a graph of relationships? | Graph DB (Neo4j) |

**The most common mistake:** choosing NoSQL because it sounds modern. Start with Postgres. It handles more use cases than people think, is battle-tested, and is far easier to operate.

---

## 6. Caching — Every Layer Explained

Cache at every layer. The goal is to never recompute or re-fetch something you already have.

### The 5 layers of caching

```
Layer 1: Browser cache
  HTTP headers tell the browser to store static assets locally.
  User visits page, loads JS/CSS from disk instead of network.
  Cost: free. Zero server load.

Layer 2: CDN cache
  Static assets cached at CDN edge nodes globally.
  Image requested from CDN edge 10 km away instead of origin server 5,000 km away.
  Cost: cheap CDN bandwidth. Massive latency reduction.

Layer 3: Application cache (Redis)
  Database query result cached in Redis.
  "Get user profile" returns from Redis in <1 ms instead of DB in 10 ms.
  Cost: Redis servers. Requires invalidation logic.

Layer 4: Database query cache
  Postgres buffer pool: frequently-read pages stay in RAM.
  Postgres's own cache — not something you manage directly.

Layer 5: CPU cache
  OS and hardware cache disk blocks in RAM.
  Invisible to you. Handled by the OS page cache.
```

### Redis data structures and their use cases

Redis is not just a key-value store. Its data structures are powerful.

```
String:
  Simple values: user session, feature flag, counter
  SET user:123:session "abc..." EX 3600
  INCR page_views:homepage        # atomic counter

Hash:
  Object fields: user profile, product attributes
  HSET user:123 name "gautam" age "25" email "g@example.com"
  HGET user:123 name              # returns "gautam"
  HGETALL user:123               # returns all fields

List:
  Recent items, queues, activity feed
  LPUSH recent:posts post_id_new   # push to front
  LRANGE recent:posts 0 49         # get first 50

Set:
  Unique membership: followers, tags, online users
  SADD user:123:following user:456
  SISMEMBER user:123:following user:456   # check if following
  SMEMBERS user:123:following             # all followed users

Sorted Set:
  Leaderboards, priority queues, rate limiting
  ZADD leaderboard 9500 "gautam"    # score=9500, member="gautam"
  ZADD leaderboard 8200 "alice"
  ZREVRANGE leaderboard 0 9         # top 10 users
  ZRANK leaderboard "gautam"        # rank of gautam

Pub/Sub:
  Real-time notifications, chat
  PUBLISH channel:notifications "new message"
  SUBSCRIBE channel:notifications
```

### Cache invalidation strategies

```
TTL (Time-To-Live): simplest approach
  Set an expiry on every key. Key auto-deletes after N seconds.
  Risk: stale data for up to N seconds.
  Use for: data where slight staleness is acceptable (user profiles, feeds).

  redis.setex("user:123", 300, data)   # expires in 5 minutes

Write-through invalidation: delete on write
  When data changes in DB, delete the cache key immediately.
  Next read repopulates from DB.
  Use for: data where staleness is not acceptable.

  async def update_user(user_id, data):
      db.execute("UPDATE users SET ...")
      redis.delete(f"user:{user_id}")   # invalidate immediately

Event-based invalidation: publish change events
  When DB changes, publish an event. Cache listens and invalidates.
  More complex. Good for distributed systems with multiple caches.
```

---

## 7. Load Balancing — Algorithms and Patterns

### Algorithms

**Round Robin:** requests go to servers in order (1, 2, 3, 1, 2, 3...).
```
Good for: stateless servers with roughly equal workloads.
Bad for: sessions (user hits a different server each time).
```

**Weighted Round Robin:** servers get different proportions based on capacity.
```
Server A (8 CPU cores) → 80% of traffic
Server B (2 CPU cores) → 20% of traffic
Good for: heterogeneous servers.
```

**Least Connections:** sends new request to the server with the fewest active connections.
```
Good for: long-lived connections (websockets, file uploads) where request duration varies.
Bad for: very fast requests where counting connections adds overhead.
```

**IP Hash:** hash the client IP, always route to the same server.
```
Good for: sticky sessions without a session store.
Bad for: hot spots if many users share an IP (corporate NAT).
```

**Random:** pick a random server.
```
Surprisingly effective at scale. No coordination needed.
With many requests, distribution approaches even.
```

### Health checks

Load balancers continuously probe servers:

```
Active check (most common):
  Load balancer sends HTTP GET /health every 5 seconds
  Server responds 200 OK → healthy, stays in pool
  Server responds 5xx or times out → unhealthy, removed from pool

Passive check:
  Load balancer monitors real traffic.
  Server returns 5xx errors → ejected from pool.
  Good supplement to active checks.
```

### The two-tier load balancing architecture

```
DNS → Global Load Balancer (anycast routing → nearest datacenter)
                │
         Regional Load Balancer (within datacenter)
        /         │         \
   App Server  App Server  App Server
```

**Layer 4 for throughput, Layer 7 for intelligence:**

```
L4 (TCP/UDP):
  Routes by IP + port. Cannot inspect payload. Extremely fast.
  Use for: database connections, raw TCP services, UDP (game servers).

L7 (HTTP):
  Routes by URL, headers, cookies. Can modify requests.
  Use for: web traffic, API routing, A/B testing, canary deployments.
  Example: route /api/* to API servers, /static/* to CDN origin
```

---

## 8. Consistent Hashing — Distributing Load Without Reshuffling

### The problem with naive hashing

```
Naive: server = hash(key) % N   (N = number of servers)

If you have 3 servers and add a 4th:
  key "gautam" → was on server 1 (hash % 3 = 1)
  key "gautam" → now on server 2 (hash % 4 = 2)

Every key maps to a different server.
→ All cache entries are invalidated.
→ All database connections must re-route.
→ Thundering herd: DB gets hit with everything at once.
```

### Consistent hashing solution

Imagine a ring (0 to 2^32). Map both servers and keys onto the ring by their hash.

```
Ring (0 to 2^32):

          Key A (hash=100)
               ↓
0 ─────── Server 1 (hash=200) ─────── Server 2 (hash=500) ─────── Server 3 (hash=800) ─────── 2^32

A key maps to the first server clockwise on the ring.

Key A (hash=100) → Server 1 (hash=200, first server clockwise) ✓
```

**Adding a server:**

```
Add Server 4 (hash=350):
  Keys between 200 and 350 → move from Server 2 to Server 4
  All other keys: unchanged

Only ~1/N of keys need to move when a server is added. Not all of them.
```

**Virtual nodes:** add multiple hash positions per server to improve distribution.

```
Server 1 at positions: 100, 300, 600, 900
Server 2 at positions: 200, 450, 700, 1000
→ Even distribution even with varied numbers of servers
```

**Used by:** Amazon DynamoDB, Apache Cassandra, Redis Cluster, CDN routing.

---

## 9. Rate Limiting — Protecting Your System

Rate limiting prevents any single client from overwhelming your system.

### Algorithms

**Fixed Window Counter:**

```
Allow N requests per time window (e.g., 100 requests per minute).

minute 0: requests 1–100 → OK
minute 0: request 101    → REJECTED
minute 1: counter resets → 100 requests allowed again

Problem: burst at window boundary:
  99 requests at 12:00:59
  99 requests at 12:01:01
  = 198 requests in 2 seconds, both batches "allowed"
```

**Sliding Window Log:**

```
Store a timestamp for every request in a sorted set.
To check: count requests in the last 60 seconds.
If count < limit → allow, add timestamp.
If count >= limit → reject.

Accurate, but memory-intensive (stores every request timestamp).
```

**Token Bucket (most commonly used):**

```
Each client has a bucket with a max capacity of N tokens.
Tokens refill at a steady rate (e.g., 10 tokens/second).
Each request consumes 1 token.
If bucket is empty → request is rejected.

Allows short bursts up to N tokens.
Steady state limited to refill rate.

Redis implementation:
  DECR user:123:tokens  # atomic decrement
  if result < 0: reject and INCR back
```

**Sliding Window Counter (best balance):**

```
Combines fixed window efficiency with sliding window accuracy.
Track count in current window + weighted count from previous window.

current_rate = prev_window_count × (1 - elapsed_fraction) + current_window_count
```

### Rate limit response

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1717200000
```

---

## 10. API Design — REST, gRPC, and WebSockets

### REST

Representational State Transfer. Stateless HTTP API using standard HTTP methods.

```http
GET    /users/123          → fetch user 123
POST   /users              → create a new user
PUT    /users/123          → replace user 123 (full update)
PATCH  /users/123          → partial update user 123
DELETE /users/123          → delete user 123

GET    /users/123/posts    → fetch user 123's posts
POST   /users/123/posts    → create a post for user 123
```

**REST principles:**
- Stateless: every request contains all info the server needs (no server-side session)
- Resource-based: URLs are nouns (`/users`), not verbs (`/getUser`)
- Use HTTP status codes correctly:

```
200 OK               → success, response body has result
201 Created          → resource created, Location header has the URL
204 No Content       → success, no response body (e.g., DELETE)
400 Bad Request      → client sent invalid data
401 Unauthorized     → authentication required
403 Forbidden        → authenticated but not permitted
404 Not Found        → resource doesn't exist
409 Conflict         → e.g., duplicate resource
422 Unprocessable    → validation error
429 Too Many Requests → rate limited
500 Internal Error   → server bug
503 Service Unavailable → server is temporarily down
```

**Versioning:**

```
URL versioning (most common):
  /api/v1/users
  /api/v2/users

Header versioning:
  API-Version: 2024-01-01
```

### gRPC

Protocol Buffers over HTTP/2. Used for internal service-to-service communication.

```protobuf
// Define the service:
service UserService {
  rpc GetUser (GetUserRequest) returns (User);
  rpc CreateUser (CreateUserRequest) returns (User);
  rpc StreamPosts (StreamPostsRequest) returns (stream Post);  // server streaming
}

message User {
  string id = 1;
  string name = 2;
  int32 age = 3;
}
```

**Why gRPC over REST for internal services:**
- Binary serialization (Protocol Buffers) is 3–10× smaller and faster than JSON
- Strongly typed — breaking changes caught at compile time
- Native streaming support (bidirectional)
- Auto-generated client and server code in any language

**When to use REST vs gRPC:**

| | REST | gRPC |
|--|------|------|
| Client type | Browser, mobile, public API | Internal services |
| Protocol | HTTP/1.1 or HTTP/2 | HTTP/2 |
| Format | JSON (human readable) | Binary Protocol Buffers |
| Streaming | Limited (SSE, long-poll) | Native bidirectional |
| Schema | Optional (OpenAPI) | Required (proto file) |

### WebSockets

Full-duplex, persistent connection between client and server.

```
Normal HTTP:
  Client → Request → Server
  Server → Response → Client
  Connection closed. Client must request again.

WebSocket:
  Client → Upgrade: websocket → Server
  Connection stays open.
  Server → push data → Client  (anytime, no request needed)
  Client → push data → Server  (anytime)
```

**Use cases:** chat, real-time feeds, collaborative editing, live sports scores, trading dashboards.

**Alternative — Server-Sent Events (SSE):** server pushes to client only, client cannot push back. Simpler; built on HTTP. Good for live notifications, dashboards, feeds.

---

## 11. Microservices vs Monolith

### Monolith

All code deployed as one unit. One database. One codebase.

```
┌─────────────────────────────────────────────┐
│                  Monolith                    │
│  User Service  │  Post Service  │  Feed      │
│  Auth          │  Media         │  Search    │
│                  shared DB                   │
└─────────────────────────────────────────────┘
```

**Advantages:**
- Simple to develop, test, deploy, debug
- No network latency between components
- Easy transactions — one database, ACID guaranteed
- No distributed systems complexity

**Disadvantages:**
- Any part of the codebase can affect any other part
- Scaling the whole app when only one part needs more resources
- Long deploy times as the codebase grows
- Technology lock-in — entire app uses one language/framework

### Microservices

Small, independently deployable services, each owning its own data.

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│  User    │  │  Post    │  │  Feed    │  │  Media   │
│  Service │  │  Service │  │  Service │  │  Service │
│  DB      │  │  DB      │  │  Cache   │  │  S3      │
└──────────┘  └──────────┘  └──────────┘  └──────────┘
                    ↕ communicate via API or message queue
```

**Advantages:**
- Each service is independently deployable and scalable
- Teams can use different tech stacks per service
- Failure in one service doesn't bring down the whole system
- Small, focused codebases are easier to understand

**Disadvantages:**
- Distributed systems complexity (network failures, latency, partial failures)
- No cross-service ACID transactions (need distributed patterns)
- Harder to test end-to-end
- Operational overhead (many services to monitor, deploy, secure)

### The honest answer: start monolith, extract later

```
Start with a well-structured monolith.
  → Fast to build, easy to change, no distributed systems bugs.

When a specific part of the system has clearly different:
  - Scaling requirements (the image processing service needs 100× more CPU)
  - Team ownership boundaries
  - Technology requirements (ML model serving needs Python, rest is Go)

→ Extract that specific part into a service.
```

The biggest mistake in system design is prematurely breaking things into microservices before the system is understood.

---

## 12. Message Queues and Event-Driven Architecture

### Why queues

```
Without queue:
  User uploads image → API calls resize service synchronously
  If resize service is slow or down → API request fails or times out
  User gets an error or waits 30 seconds

With queue:
  User uploads image → API pushes job to queue → API returns "processing"
  Resize workers consume jobs at their own pace
  If workers are slow → jobs pile up in queue (buffering)
  If workers crash → jobs stay in queue, retried when worker recovers
```

### Core concepts

```
Producer: system that creates messages and publishes them
Consumer: system that reads and processes messages
Queue:    buffer between producer and consumer
Topic:    named channel; multiple consumers can subscribe
Partition: a queue can be split into partitions for parallelism
Offset:   position of a message in a partition (Kafka concept)
```

### Kafka vs SQS vs RabbitMQ

| | Kafka | AWS SQS | RabbitMQ |
|--|-------|---------|----------|
| Model | Distributed log (pub/sub) | Queue (point-to-point) | Queue + pub/sub |
| Message retention | Days to forever | Up to 14 days | Until consumed |
| Replay | Yes (rewind offset) | No | No |
| Throughput | Millions/sec | Thousands/sec | Thousands/sec |
| Use for | Event streaming, audit log, ETL | Task queues, decoupling | Complex routing, RPC |

**Kafka:** messages are retained even after consumption. Multiple consumer groups can independently read the same stream. Think of it as a distributed, durable append-only log.

```
Topic "user-events" with 3 partitions:

Partition 0: [login, login, signup, login]
Partition 1: [logout, view, view, login]
Partition 2: [signup, view, logout, view]

Consumer Group A (analytics): reads all partitions, tracks its own offset
Consumer Group B (email):     reads all partitions, tracks its own offset
Both groups see all messages independently.
```

**Patterns:**

```
Fan-out:
  One event → many consumers
  "OrderPlaced" event → (send receipt email) + (update inventory) + (notify warehouse)

Event sourcing:
  Every state change is an event. Events are the source of truth.
  Kafka is a natural fit — append-only, replayable.

Saga pattern (distributed transactions across services):
  Instead of a distributed transaction, choreograph events.
  OrderService: "OrderCreated" →
  PaymentService: charges card → "PaymentProcessed" →
  InventoryService: reserves item → "InventoryReserved" →
  ShippingService: creates shipment

  If any step fails, compensating events undo previous steps.
```

---

## 13. Distributed System Concepts

### CAP Theorem (full explanation in DATABASE_AT_SCALE.md)

You can guarantee at most 2 of: Consistency, Availability, Partition Tolerance.

Since partitions always happen in distributed systems, the real choice is **C or A during a partition**.

### Consistency Models

```
Strong Consistency:
  After a write, all reads see that write.
  "Gautam updated his age to 26. The next reader anywhere in the world sees 26."
  Cost: latency (must wait for all replicas to confirm)
  Examples: Postgres with sync replication, Zookeeper

Eventual Consistency:
  After a write, all reads will eventually see that write.
  "Gautam updated his age. It might take 200 ms for all replicas to catch up."
  Benefit: low latency, high availability
  Examples: DynamoDB, Cassandra, DNS

Read-Your-Own-Writes:
  You always see your own writes. Others might see stale data.
  "Gautam sees his updated profile. Alice might see the old one for a moment."
  Good balance for user-facing data.

Monotonic Read:
  You never see an older state after seeing a newer one.
  "If you saw Gautam's age as 26, you won't later see it as 25."

Causal Consistency:
  Causally related operations are seen in order.
  "If you see the reply to a comment, you will also see the comment."
```

### Distributed Transactions

Transactions across multiple services or databases.

**Two-Phase Commit (2PC):**

```
Phase 1 — Prepare:
  Coordinator asks all participants: "Can you commit this?"
  All participants: "Yes, ready" (or "No, abort")

Phase 2 — Commit:
  If all said Yes: Coordinator says "Commit!"
  If any said No:  Coordinator says "Abort!"

Problem: if coordinator crashes between phases, participants are stuck.
Use for: small clusters where blocking is acceptable.
```

**Saga Pattern:**

```
Break a transaction into a sequence of local transactions.
Each step publishes an event that triggers the next step.
If a step fails, compensating transactions undo previous steps.

Example — book a flight and hotel:
  Book flight     → success → Book hotel
  Book hotel      → fails   → Cancel flight (compensating transaction)
  
Types:
  Choreography: each service reacts to events independently (simpler, harder to track)
  Orchestration: a central saga orchestrator tells each service what to do (easier to track)
```

---

## 14. Reliability Patterns

These patterns make services survive failures gracefully.

### Circuit Breaker

Prevents cascading failures. If a downstream service is failing, stop calling it.

```
States:
  CLOSED   (normal):   requests pass through. Count failures.
  OPEN     (failing):  requests fail immediately (no actual call made).
                       Reset after a timeout.
  HALF-OPEN (testing): let one request through. If it succeeds → CLOSED.
                        If it fails → OPEN again.

Why: without circuit breaker, a slow service causes your service to slow down
     as all threads/workers are stuck waiting on it.
     With circuit breaker: fail fast, free up resources, give the service time to recover.
```

### Retry with Exponential Backoff

Retry failed requests, but wait longer between each retry.

```python
import asyncio
import random

async def call_with_retry(fn, max_retries=3):
    for attempt in range(max_retries):
        try:
            return await fn()
        except TemporaryError:
            if attempt == max_retries - 1:
                raise
            wait = (2 ** attempt) + random.uniform(0, 1)  # exponential + jitter
            await asyncio.sleep(wait)
# Attempt 1: fail → wait 1s
# Attempt 2: fail → wait 2s
# Attempt 3: fail → wait 4s
# Raise

# Jitter prevents thundering herd: without it, all retrying clients
# wake up at the same moment and slam the recovering service together.
```

### Bulkhead

Isolate resources so a failure in one area does not exhaust resources for everything.

```
Without bulkhead:
  One slow service consumes all 100 connection pool slots.
  All other requests are starved, even for fast/healthy services.

With bulkhead:
  10 connections reserved for Service A (slow)
  10 connections reserved for Service B (healthy)
  → Service A slowness can't affect Service B
```

Named after ship bulkheads: if one compartment floods, others are isolated.

### Timeout

Every network call must have a timeout. Never wait indefinitely.

```python
# Without timeout: your code hangs if the service never responds
response = await http.get(url)

# With timeout: fail fast, release resources
async with asyncio.timeout(5.0):  # 5 second timeout
    response = await http.get(url)

# Rule of thumb: timeout < your caller's timeout
# If user expects a response in 2 seconds, timeout downstream calls at 1.5s.
```

---

## 15. Observability — Metrics, Logs, Traces

You cannot fix what you cannot see. Observability tells you what your system is doing.

### The three pillars

**Metrics:** numeric measurements over time.

```
Request rate (requests/second)
Error rate (5xx errors / total requests)
Latency (p50, p95, p99 in milliseconds)
CPU usage (%)
Memory usage (bytes)
Queue depth (messages waiting to be processed)
Cache hit rate (%)

Tools: Prometheus + Grafana, DataDog, CloudWatch
```

**Logs:** text records of what happened and when.

```python
import logging
import structlog   # structured logging

log = structlog.get_logger()

# Structured log (JSON) — searchable, parseable:
log.info("user.login", user_id="gautam-123", ip="1.2.3.4", duration_ms=12)
log.error("db.query_failed", query="SELECT ...", error=str(e), user_id="gautam-123")

# Outputs:
# {"event": "user.login", "user_id": "gautam-123", "ip": "1.2.3.4", "duration_ms": 12}
# {"event": "db.query_failed", "error": "timeout", "user_id": "gautam-123"}

# Use structured (JSON) logs. They are searchable.
# Avoid: log.info(f"User {user_id} logged in from {ip} in {duration}ms")
# That string cannot be queried reliably.

Tools: ELK Stack (Elasticsearch + Logstash + Kibana), Loki + Grafana
```

**Traces:** follow a request as it flows through multiple services.

```
User request arrives at API gateway:
  trace_id = "abc-123"    ← same for entire request lifetime
  span_id  = "span-001"   ← for this specific hop

  API gateway → User Service (span-002, parent=span-001)
             → Post Service (span-003, parent=span-001)
             → Cache (span-004, parent=span-003)
             → DB (span-005, parent=span-003)

Trace viewer shows: total time = 120ms
  - API gateway: 5ms
  - User Service: 15ms
  - Post Service: 100ms
    → Cache miss: 2ms
    → DB query: 85ms   ← THIS IS THE BOTTLENECK
    → serialization: 13ms
```

Distributed tracing identifies exactly which service and which operation is slow.

Tools: Jaeger, Zipkin, AWS X-Ray, DataDog APM.

### Alerting

```
Alert when:
  Error rate > 1% for 5 minutes           → page on-call engineer
  p99 latency > 2 seconds for 2 minutes   → page on-call engineer
  CPU > 80% for 10 minutes                → warning (not critical yet)
  Disk usage > 85%                        → warning

Golden signals (4 things to always monitor):
  1. Latency:     how long requests take (p50, p95, p99)
  2. Traffic:     how many requests per second
  3. Errors:      rate of 5xx responses
  4. Saturation:  how full is the system (CPU, memory, disk, queue depth)
```

---

## 16. Common System Design Examples

### URL Shortener (like bit.ly)

**Requirements:**
- POST a long URL → get a short URL (`short.ly/abc123`)
- GET the short URL → redirect to the original URL
- Scale: 100M URLs stored, 1 billion redirects per day

**Estimation:**
```
Write: 100M URLs / (365 × 86400) ≈ 3 writes/second  (mostly read-heavy)
Read:  1B redirects / 86400 ≈ 11,574 reads/second
Reads : Writes ≈ 4000:1
Storage: 100M URLs × 500 bytes ≈ 50 GB (fits in memory)
```

**Design:**

```
POST /shorten:
  1. Generate a unique short key (6-8 chars from [a-zA-Z0-9])
     Method: hash(long_url + salt) → base62 encode → take first 7 chars
     OR: auto-increment ID → base62 encode → "abc123"
  2. Store in DB: short_key → long_url, created_at, user_id
  3. Cache: Redis SET short_key long_url EX 86400  (24h TTL)
  4. Return: https://short.ly/{short_key}

GET /{short_key}:
  1. Check Redis cache
     → cache hit: return 301 Redirect to long_url
  2. Cache miss: query DB
     → found: cache it, return 301 Redirect
     → not found: return 404

301 vs 302:
  301 Permanent Redirect: browser caches it → fewer requests to our server
  302 Temporary Redirect: browser always checks with us → we can track clicks
  → Use 302 if you need analytics on clicks
```

**Schema:**

```sql
CREATE TABLE urls (
    short_key   CHAR(8)       PRIMARY KEY,
    long_url    TEXT          NOT NULL,
    user_id     UUID,
    created_at  TIMESTAMPTZ   DEFAULT NOW(),
    click_count BIGINT        DEFAULT 0
);
CREATE INDEX idx_long_url ON urls (long_url);  -- for dedup check
```

---

### Social Media Feed (like Twitter)

**Requirements:**
- Users post tweets
- Users follow other users
- Feed shows recent tweets from followed users
- Scale: 300M DAU, 1000 tweets/second, 300,000 feed reads/second

**The core problem:** how do you generate a feed for a user with 1000 followers, when there are 300,000 feed reads per second?

**Approach 1: Pull on read (fan-in)**

```
When user A requests their feed:
  SELECT t.* FROM tweets t
  JOIN follows f ON t.author_id = f.following_id
  WHERE f.follower_id = 'user_a'
  ORDER BY t.created_at DESC
  LIMIT 20;

Problem: if user A follows 2000 people, this query joins 2000 rows of tweets.
At 300,000 reads/second, the database is destroyed.
```

**Approach 2: Push on write (fan-out)**

```
When user B posts a tweet:
  1. Insert tweet into tweets table
  2. Look up all followers of user B (say 1000 followers)
  3. For each follower, insert tweet_id into that follower's feed table
  
  feeds table:
    (user_id, tweet_id, created_at) for user A
    (user_id, tweet_id, created_at) for user C
    ...

When user A reads feed:
  SELECT tweet_id FROM feeds WHERE user_id = 'A' ORDER BY created_at DESC LIMIT 20;
  → fast, indexed, no joins

Problem: if a celebrity has 50M followers, one tweet = 50M insertions.
  At 1000 tweets/second across all celebrities → massive write load
```

**Approach 3: Hybrid (what Twitter actually does)**

```
Regular users (< 10k followers): fan-out on write
  → Pre-compute feed for all followers immediately

Celebrity users (> 10k followers): pull on read
  → Don't pre-compute. When reading, merge:
      Pre-computed feed (from regular users) + latest tweets from celebrity

Implementation:
  On feed read:
    1. Fetch user's pre-computed feed from Redis
    2. For each celebrity the user follows: fetch their recent tweets
    3. Merge and sort by time
    4. Return top 20
```

**Architecture:**

```
Tweet posting:
  POST /tweets → API server
  → write to DB (tweets table)
  → push task to message queue
  → fan-out worker reads queue
    → get follower list
    → write to Redis feed (SORTED SET by timestamp)
    → skip for users with >10k followers (they use pull)

Feed reading:
  GET /feed → API server
  → read from Redis: ZREVRANGE user:{id}:feed 0 19
  → for each celebrity followed: GET last 20 tweets from Redis
  → merge + sort + return

Redis feed structure:
  Key: "feed:{user_id}"
  Type: Sorted Set
  Score: timestamp (unix epoch)
  Member: tweet_id

  ZADD feed:gautam 1717200000 tweet_789
  ZREVRANGE feed:gautam 0 19        # newest 20 tweets
  ZREMRANGEBYRANK feed:gautam 0 -501 # trim to 500 items max
```

---

### Chat System (like WhatsApp)

**Requirements:**
- 1-on-1 messaging
- Group messaging (up to 500 members)
- Message delivery status (sent, delivered, read)
- Online/offline presence
- Scale: 1B users, 100B messages per day

**Core challenge:** push messages to receivers in real-time, even if they're on a different server.

**Architecture:**

```
Client connects via WebSocket to a Chat Server.
Chat Server is assigned per user (via consistent hashing).
Multiple Chat Servers behind a load balancer.

Message flow:
  Alice (on Server 1) → sends to Bob (on Server 3)

  1. Alice's WebSocket → Chat Server 1
  2. Chat Server 1 looks up: "which server is Bob connected to?"
     → Check Redis: "Bob is on Server 3"
  3. Chat Server 1 → publishes to Redis pub/sub: "message for Bob"
  4. Chat Server 3 → subscribed to "messages for Bob" → pushes via Bob's WebSocket

  If Bob is offline:
  3. Message stored in DB
  4. When Bob reconnects: fetch undelivered messages from DB
```

**Message storage:**

```
Cassandra is a common choice for chat message storage:
  - Write-heavy (100B messages per day)
  - Reads are mostly "get messages for conversation X, from time Y to Z"
  - Partition key: (conversation_id, time_bucket) → one Cassandra partition per conversation per day
  - Clustering key: message_id → sorted within partition

Schema:
  CREATE TABLE messages (
    conversation_id UUID,
    time_bucket     DATE,          -- partition by day
    message_id      UUID,
    sender_id       UUID,
    content         TEXT,
    created_at      TIMESTAMP,
    PRIMARY KEY ((conversation_id, time_bucket), message_id)
  ) WITH CLUSTERING ORDER BY (message_id ASC);
```

---

### File Storage (like Google Drive / S3)

**Requirements:**
- Upload files (up to 1 GB)
- Download files
- File versioning
- Sync across devices
- Share files with others
- Scale: 50M users, 1B files, 10 PB total storage

**Upload flow:**

```
Small files (< 5 MB): direct upload
  1. Client → POST /files/upload (with file in body)
  2. API server → stores file in object storage (S3)
  3. Record metadata in DB: (file_id, user_id, name, size, s3_key, created_at)
  4. Return file_id

Large files (> 5 MB): multipart/chunked upload
  1. Client → POST /files/init-upload → get upload_id + pre-signed S3 URLs
  2. Client splits file into 5 MB chunks
  3. Client → PUT each chunk directly to S3 (bypasses your server)
  4. Client → POST /files/complete-upload → you merge chunks in S3
  
  Why: uploading 1 GB through your server saturates your API server's network.
  Direct S3 upload bypasses your server entirely.
  S3 multipart upload handles chunking natively.
```

**Deduplication:**

```
Before storing, hash the file content (SHA-256 or MD5).
If hash already exists → file already stored.
Just add a new DB record pointing to the existing S3 object.
Space saving: if 100 users upload the same file, store it once.

files table:
  (file_id, user_id, filename, content_hash, s3_key, size, created_at)

SELECT s3_key FROM files WHERE content_hash = $1 LIMIT 1;
→ found: reuse S3 key (dedup)
→ not found: upload to S3
```

**Delta sync (like Dropbox):**

```
When a file is modified, send only the changed blocks, not the whole file.
1. Divide file into fixed-size chunks (4 MB each)
2. Track the hash of each chunk
3. On sync: compare chunk hashes
   → unchanged chunks: don't upload
   → changed chunks: upload only those
4. Reassemble on the client

Reduces sync bandwidth by 80–90% for incremental edits.
```

---

## 17. The Decision Framework

When designing any system, work through these questions in order:

```
1. What are the functional requirements?
   Be specific. "Users can post" is vague. "Users can post text up to 280 chars, 
   4 images, 1 video per post" is a design.

2. What are the scale requirements?
   - DAU / MAU
   - Read QPS vs Write QPS
   - Data size per record
   - Total storage in 5 years

3. What are the consistency requirements?
   - Is slightly stale data acceptable? (feeds: yes) (balance: no)
   - Do I need cross-service transactions? (use saga, not 2PC)
   - Is eventual consistency enough?

4. What is the latency requirement?
   - p50, p99 target?
   - Which operations must be fast? (feed read) Which can be slow? (report generation)

5. What is the availability requirement?
   - 99.9% (8.7 hours downtime/year) or 99.99% (52 minutes/year)?
   - Higher availability = more complexity, more cost.

6. What are the hotspots?
   - Celebrities posting (50M followers)
   - Event spikes (Super Bowl, product launch)
   - How do I handle 10× normal traffic without degrading?

7. What can I trade off?
   - Consistency for availability? (usually yes for non-financial data)
   - Accuracy for speed? (approximate counts with Redis INCR)
   - Storage for compute? (pre-compute feeds, denormalize)
   - Money for engineering? (managed services vs self-hosted)

8. What are the failure modes?
   - What happens when the cache goes down? (DB still works, just slower)
   - What happens when the queue consumer crashes? (messages sit in queue)
   - What happens when the DB is unavailable? (serve stale from cache)
   - Which failures are tolerable? Which are catastrophic?
```

### A mental model for scale

```
1 server:            1 app server + 1 DB — handles most apps up to ~10k users
10 servers:          add load balancer + read replicas + Redis cache
100 servers:         CDN + message queues + dedicated services per domain
1000 servers:        sharding + multiple data centers + global load balancing
10,000 servers:      custom hardware, custom protocols, multi-region active-active
```

Most companies never exceed "100 servers" in the real sense. Design for where you are and one order of magnitude above. Premature over-engineering is as dangerous as under-engineering.

---

*Cross-references:*
- *Database internals, indexing, MVCC, partitioning, CAP, ACID/BASE: see `DATABASE_AT_SCALE.md`*
- *Docker and containerization: see `docker/` folder*
- *Kubernetes orchestration: see `kubernetes/` folder*
