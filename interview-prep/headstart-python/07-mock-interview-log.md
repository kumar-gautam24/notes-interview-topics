# 07 · Mock Interview: 30 Questions, Simple Answers

**How to use this file**
- **Q1–Q15** are the questions from our mock round. Each one shows **what you said**, **what was missing**, and **what to say instead**.
- **Q16–Q30** are new questions the client is likely to ask, with answers written the same way.
- Every answer is in plain words first. Then, if they push, the **"If they ask more"** line gives you the next layer.
- **[fill: …]** means a fact only you know. Check every line about *your* work against what really happened before you use it.

**The one rule for every answer:** *answer in one line → explain simply → give one example from your work → say the trade-off.*

---

## Scorecard

| # | Question | Your score | The fix in one line |
|---|---|---|---|
| 1 | Tell me about your project | 2/5 | Say what it does and who uses it, then 2–3 things *you built* |
| 2 | What wouldn't exist without you? | 3/5 | Add one real bug your idea helped catch |
| 3 | Largest system, scaling problems | 2/5 | Never say "no scaling issues". Tell your 3 performance stories |
| 4 | Multithreading / multiprocessing | 1/5 | "Not in production, but here's how I'd choose" |
| 5 | Keeping company A away from company B's data | 2/5 | Roles ≠ data isolation. Filter every query by company id |
| 6 | Import a 2-million-row CSV | 2/5 | Queue *one* job, read the file in pieces |
| 7 | Fibonacci | — | Climb the ladder: slow → memo → loop → O(1) memory |
| 8 | Right-shift an array | 3.5/5 | Write the code, say the complexity |
| 9 | Send 1K vs 10M emails | — | Name what breaks at scale, fix each |
| 10 | Blocking code in async | 3/5 | "It freezes *every* request on that worker" + your story |
| 11 | Database indexes | — | Book index analogy + when not to use one |
| 12 | N+1 queries | 2.5/5 | It's 1 + N queries from a loop |
| 13 | Too many DB connections | 3/5 | Do the maths out loud |
| 14 | Change an API without breaking apps | 3/5 | Add, don't change. Version only as a last resort |
| 15 | Report went from 2s to 40s | 2/5 | Your "log every step" idea is right. Then check each slow part |

---

# Part 1 · The mock round (Q1–Q15)

## Q1 · "Tell me about your current backend project."

**What you said:**
> "I am working on Vaidya and Vaidya Insurance. In Vaidya I worked on Astra auth, then Vaidya API service, then Vaidya subscription with Razorpay, and Vaidya ABDM, ABHA, milestones. In insurance I built the platform API and a wrapper between the UI and the AI service APIs. Vaidya Insure APIs I built, auth was built, I debugged some issues and made changes as needed, same for the Vaidya API service. Subscription part I built and ABHA also."

**What was missing:** it's a list of service names. The interviewer doesn't learn what the product *does*, who uses it, or which part is *yours*. "Debugged some issues" makes your work sound small.

**Say this instead (about 60 seconds):**
> "I work on two healthcare products for Fractal Analytics: **Vaidya**, an AI health app, and **Vaidya Insurance**.
> On Vaidya, I built the **subscription billing** on Razorpay and the **ABDM integration**, which links a user's ABHA health ID, and I own the **auth service** that every other service trusts.
> On Vaidya Insurance, I built the **platform APIs**, including auth, and the **gateway between the app and the AI services**. The app never talks to the AI directly. Every request goes through my layer, which checks who you are, validates the input and handles errors.
> The part I'm proudest of is billing: I made the credit wallet safe when two payments happen at the same time, and made the payment webhooks safe to receive twice."

[fill: who uses it: doctors, hospitals, insurers, patients?] · [fill: check the ABDM line matches your work]

**Shape to remember:** *product → users → what I built (2–3 things) → the one I'm proudest of.*

---

## Q2 · "Which part would not exist without you?"

**What you said:**
> "In the Vaidya mobile app I added telemetry using Firebase Crashlytics, Analytics and Performance: non-fatals, events, to track API failures and app failures. Without this it would be guesswork why it's failing for a user: breadcrumbs, keys, events, and how many users failed. ABDM and Razorpay I owned, but anyone could have done those. The telemetry was my idea, I took ownership, informed the PM, and it later helped debug why some users got certain failures."

**What was good:** it was your idea, you owned it, you told the PM, and it solved a real problem. That's exactly what "ownership" questions look for.

**What was missing:**
1. A **real example** of a bug it caught.
2. It's called **observability** (or crash and performance monitoring), not OpenTelemetry. OpenTelemetry is a different tool, and a backend interviewer may notice.
3. **Never** say "anyone could have done" your work.

**Say this instead:**
> "When users reported a failure, we were guessing. We didn't know what they did before it broke or how many people it affected. So I proposed adding **monitoring** to the Vaidya app, took it to the PM and built it: crash reports, non-fatal errors with breadcrumbs and keys like user id and API endpoint, events for every failed API call, and performance tracking for slow requests.
> After that, we could see exactly which users failed and what happened just before. For example, **[fill: one real bug it helped find]**. It turned bug reports from guesswork into data."

**Keep a backend version ready** in case they say "something on the backend?": the wallet race-condition fix (Q25) or the event-loop fix (Q10).

---

## Q3 · "What's the largest system you've worked on? Any scaling problems?"

**What you said:**
> "Our users are roughly 1 million, and a slow user base, so not a scalability issue. When we faced it, we just increased the pods for our service."

**What was missing:** "no scaling issues, we just add pods" ends the conversation and sounds like you never had to think about performance. But you *did* fix real performance problems. They're on your resume.

**Think of it like this:** scaling isn't only "more users". It's also "the system got slow or stuck". You fixed three of those.

**Say this instead:**
> "The biggest is Vaidya, with about **1 million users**, [fill: daily active users or requests per day]. When traffic grows we add pods. But I learned that adding pods doesn't fix everything, and my real problems were about speed, not user count:
> 1. **Every request slowed down together.** The cause was a database driver that wasn't async, used inside async code, so one slow query froze all requests on that server. We switched to an async driver.
> 2. **Requests were waiting for a database connection.** The pool was capped at 10 per service. Adding pods would have made it *worse*, because each pod opens its own connections and the database has a limit.
> 3. **OTP emails took 8–10 seconds.** The email was sent *during* the request. I moved it to a background job, and it dropped to about half a second."

[fill: is 1 million registered users or monthly active?]

---

## Q4 · "Have you used multithreading or multiprocessing?"

**What you said:**
> "No, I have not worked on it."

**What was missing:** a flat "no" scores 1/5. "No, but here's how I'd decide" scores 4/5.

**The idea in simple words:**
- **Threads** = several workers in the *same* office sharing one desk. In Python, only one can write at a time (that rule is called the **GIL**). But while one is *waiting* (for the database, the network), another can work. So threads help when your code **waits a lot**.
- **Processes** = separate offices, each with its own desk. They really work at the same time on different CPU cores. So processes help when your code **calculates a lot**.
- **async/await** = one very fast worker who never sits idle while waiting. It starts a task, and while waiting, switches to the next one. Best for **lots of waiting** (web APIs).

**Say this instead:**
> "Not in production, because my work is mostly **waiting**: database calls, Redis, AI APIs, webhooks. For that, **async** is the best tool. One server can handle thousands of requests that are waiting on the network.
> I still use these ideas indirectly. Our background workers run as **separate processes** from the API, and we run multiple pods.
> How I'd choose: if the work is **waiting** (network, database), use async, or threads if the library doesn't support async. If the work is **heavy calculation**, like parsing a huge CSV or making PDFs, use **multiprocessing**, because Python's GIL stops threads from calculating in parallel. Each process has its own GIL, so it can use all CPU cores. The cost is more memory."

**If they ask more:** `ThreadPoolExecutor` for blocking I/O, `ProcessPoolExecutor` for CPU work. Data sent between processes has to be copied (pickled), so send small things like ids.

**Homework (20 min):** run one heavy function 4 times: one by one, then with threads, then with processes. Threads won't be faster. Processes will be about 3–4× faster. Now you can say "I've measured it."

---

## Q5 · "How do you make sure company A never sees company B's data? What if one company becomes 100× bigger?"

**What you said:**
> "I add RBAC, role-based, and then based on role I fetch data, joins and all."

**What was missing:** roles and data isolation are **two different things**:
- **Roles (RBAC)** answer: *what can this person do?* (admin can delete, viewer can only read)
- **Tenant isolation** answers: *whose data can this person see?* (only their own company's rows)

You need both.

**Think of it like an apartment building:** your key (company id) decides **which flat** you can enter. Your role decides **what you can do inside** that flat.

**Say this instead:**
> "In my Manpower project, every table has a **company_id** column. Three rules keep data separate:
> 1. **The company comes from the login token**, never from the request. A user can't type in another company's id.
> 2. **Every query filters by company_id**, including joins. If someone asks for another company's record, we say *not found* (404), so we don't even confirm it exists.
> 3. **Roles sit on top.** Inside their own company, the 4 role levels decide what each user can do.
> **If one company becomes 100× bigger:** first protect the others with per-company rate limits and separate job queues, so their big import doesn't slow everyone. Then make their queries fast with indexes that start with company_id. If they're still too big, move just that company to its own database."

[fill: confirm your tables have `company_id` and that it comes from the token]

**If they ask more:** the three setups are *shared tables with a company column* (cheapest), *a separate schema per company*, and *a separate database per company* (strongest isolation, most expensive). Postgres **row-level security** can enforce the filter inside the database as a safety net.

---

## Q6 · "A college uploads a CSV of 2 million students. How do you import it?"

**What you said:**
> "I would use a queue here. I would take some and process, then continue taking from the queue."

**What was good:** right instinct. Don't do it inside the request, use a queue, process in parts.
**What was missing:** the steps. Also, **don't put 2 million rows into the queue**. Put **one job** in the queue, and let the worker read the file in pieces.

**Think of it like this:** you don't carry 2 million bricks in one trip. You carry them in small loads, write down how many you've moved, and if you stop for lunch you continue from where you left off.

**Say this instead:**
> "1. **Upload goes straight to storage** (S3 or R2) with a signed link, so the big file never passes through my API.
> 2. **The API creates a job and replies straight away** with a job id. It doesn't wait for the import.
> 3. **A background worker reads the file in small pieces**, say 5,000 rows at a time, so memory stays small.
> 4. **Each row is checked.** Bad rows are saved in an error list with their line number, so one bad row doesn't stop everything.
> 5. **Rows are saved in bulk**, one big insert per piece, with 'insert or update', so a retry never creates duplicates.
> 6. **After each piece, it saves progress.** If the worker crashes, it continues from there. The user sees the progress percentage.
> 7. **At the end:** a report of imported, updated and failed rows, with a downloadable error file."

**Memory hook for any big-data question:** *don't block the request → read in pieces → save in bulk → safe to retry → save progress → run in parallel if needed.*

---

## Q7 · "Write a function for the nth Fibonacci number." (C++)

**What you said:** you asked me to do it. This is the exact question the screener marked you down on, so **type all four versions from memory twice before the interview.**

**The idea:** F(n) = F(n−1) + F(n−2), with F(0)=0 and F(1)=1.

**Step 1: plain recursion. Say why it's slow.**
```cpp
long long fib(int n) {
    if (n < 2) return n;
    return fib(n - 1) + fib(n - 2);
}
```
> "This is **O(2ⁿ)**. It recalculates the same numbers again and again: fib(5) calculates fib(3) twice and fib(2) three times."

**Step 2: memoization. Remember answers you've already calculated.**
```cpp
long long go(int n, vector<long long>& memo) {
    if (n < 2) return n;
    if (memo[n] != -1) return memo[n];          // already know it
    return memo[n] = go(n - 1, memo) + go(n - 2, memo);
}
long long fib(int n) {
    vector<long long> memo(max(n + 1, 2), -1);
    return go(n, memo);
}
```
> "Each number is calculated once: **O(n) time, O(n) memory**."

**Step 3: loop from the bottom. No recursion.**
```cpp
long long fib(int n) {
    if (n < 2) return n;
    vector<long long> dp(n + 1);
    dp[0] = 0; dp[1] = 1;
    for (int i = 2; i <= n; ++i) dp[i] = dp[i - 1] + dp[i - 2];
    return dp[n];
}
```

**Step 4: keep only the last two numbers. This is your final answer.**
```cpp
long long fib(int n) {
    long long a = 0, b = 1;
    for (int i = 0; i < n; ++i) {
        long long next = a + b;
        a = b;
        b = next;
    }
    return a;
}
```
> "**O(n) time, O(1) memory.** `long long` overflows after F(92), so for big n we usually return the answer mod 1e9+7."

**Just mention, don't code unless asked:** "It can be done in **O(log n)** with matrix power." Code is in [01-dsa-cpp.md](01-dsa-cpp.md).

---

## Q8 · "Right-shift an array by one: [1,2,3,4,5] → [5,1,2,3,4]." (C++)

**What you said:**
> "First approach: create a new array and fill the data there. Second approach: use a variable to store data and keep swapping."

**What was good:** two approaches, simple one first. That's the right habit.
**What was missing:** the code and the complexity of each.

**Approach 1: new array. O(n) time, O(n) extra memory.**
```cpp
vector<int> rightShift(const vector<int>& a) {
    int n = a.size();
    vector<int> res(n);
    for (int i = 0; i < n; ++i) res[(i + 1) % n] = a[i];   // each item moves one step right
    return res;
}
```

**Approach 2: save the last item, shift the rest, put it at the front. O(n) time, O(1) memory.** (This is your "store in a variable" idea, done cleanly.)
```cpp
void rightShift(vector<int>& a) {
    if (a.size() < 2) return;
    int last = a.back();                          // save the last item
    for (int i = a.size() - 1; i > 0; --i)        // go BACKWARDS
        a[i] = a[i - 1];
    a[0] = last;
}
```
> "I go **backwards** because going forwards would overwrite a value before I've moved it."

**Likely follow-up, "shift by k":** doing it k times is slow, O(n·k). Instead: `k = k % n`, then **reverse the whole array, reverse the first k, reverse the rest**. O(n) time, O(1) memory.
`[1,2,3,4,5]`, k=2 → `[5,4,3,2,1]` → `[4,5,3,2,1]` → `[4,5,1,2,3]` ✓

---

## Q9 · "Design sending a campaign email to 1,000 students. What changes at 10 million?"

**What you said:**
> "No idea."

**You know more than you think.** Your OTP fix (moving the email out of the request into a background job) *is* the 1,000-email answer.

**The trick:** ask *"what breaks when the number gets huge?"* Four things break:
1. **Time:** it takes hours.
2. **Limits:** email providers only allow so many emails per second.
3. **Failures:** some sends fail and need a retry.
4. **Duplicates:** a retry must not email someone twice.

Then give one fix for each.

**Say this instead:**
> "**For 1,000:** the API saves the campaign and replies straight away. One background job loops through the students and sends through a provider like SES, retrying failures and marking each one sent or failed. Done in a minute or two. It's the same as my OTP fix, which went from 8–10 seconds to half a second.
> **For 10 million**, one loop is too slow and a crash would lose everything, so:
> - **Split the work:** a planner job puts **batches of about 1,000 students** on a queue, and **many workers** send them in parallel.
> - **Respect the provider's limit** with a shared counter in Redis. At 1,000 per second, 10 million takes about 3 hours. I'd say that number up front.
> - **No duplicates:** a 'sent' table with one row per student per campaign. A retried batch skips anyone already sent.
> - **Retries** for temporary errors, no retries for bad addresses, and a 'failed' queue for the rest.
> - **A separate queue**, so a big campaign never delays OTP or password-reset emails.
> - **Unsubscribes and bounces** come back from the provider and are never emailed again.
> - **Progress screen:** sent, failed, bounced, with pause and cancel."

**One-line summary:** *"1,000 is a loop in a background job. 10 million is a pipeline: batches, many workers, a rate limit, no duplicates, and a separate queue."*

**Your follow-up questions, answered simply:**
- **"What if the same webhook comes twice?"** Save each event's id in a table where it must be unique. If saving fails because it's already there, it's a duplicate: reply OK and do nothing. You built this for Razorpay.
- **"What if the queue or a batch fails halfway?"** The worker only marks a message done *after* finishing it, so a crashed batch is delivered again. The 'sent' table makes the retry skip people already emailed. If Redis is down when adding the job, first save the job in the database (an **outbox** table) and let a small process push it to the queue later.
- **"3 hours is too long for a sale?"** That's a business choice, so say so. Options: ask the provider for a higher limit, send to the most active students first, prepare emails and discount codes before launch, use push or SMS for urgent messages. And sending gradually is *good*: 10 million clicks at the same second could crash the sale page.

---

## Q10 · "What happens if you put blocking code in an async FastAPI app?"

**What you said:**
> "Use async/await. If not using await, use sync. FastAPI moves that to a worker."

**What was right:** a normal `def` endpoint (not `async def`) is run by FastAPI in a **thread pool**, so blocking code there is OK.
**What was missing:** the main point (what actually goes wrong) and your production story.

**Think of it like this:** async is one waiter serving 100 tables. While one table looks at the menu, he serves others. If one table makes him stand and wait 5 minutes (**blocking code**), *all 100 tables* wait.

**Say this instead:**
> "In async FastAPI, each worker has **one event loop**, like one waiter serving everyone. If an `async def` endpoint does something blocking, like a normal database driver or `time.sleep`, the loop stops, and **every request on that worker freezes**, not just the slow one.
> I hit this in production. A non-async database driver was being used inside async endpoints, and everything slowed down together.
> Fixes: use an **async driver** like asyncpg; or run the blocking call in a thread with `await asyncio.to_thread(...)`; or make the endpoint a plain `def` so FastAPI runs it in its thread pool; or move heavy work to a background worker."

---

## Q11 · "How does a database index work? When should you not use one?"

**What you said:** you asked me to teach it. Full lesson: [05-indexing-deep-dive.md](05-indexing-deep-dive.md).

**Think of it like a book index:** to find "recursion" in an 800-page book, you don't read every page. You look it up in the sorted index at the back, which says "page 412". A database index is the same: a **sorted list of values pointing to where each row is**.

**Say this instead:**
> "Without an index, the database reads **every row** to find a match. That's a full table scan. An index is a separate **sorted** structure, usually a **B-tree**, that points to the rows, so it can jump straight there. Even with millions of rows, it's only 3–4 steps.
> Because it's sorted, it also helps with **ranges** (`created_at > last week`) and **sorting** (`ORDER BY`).
> For an index on more than one column, like **(company_id, status, created_at)**, order matters. It works for queries on company, or company + status, but **not** for status alone, like a phone book sorted by surname can't find everyone named 'Rahul'.
> **When not to add one:**
> - **small tables**, where reading everything is already fast
> - **columns with few values**, like true/false
> - **tables that are mostly written to**, like logs, because every insert also has to update every index
> - **columns you never search or sort by**, and **duplicate indexes**
> I always check with `EXPLAIN ANALYZE` to see if the index is actually used."

**Your experience to add:** you use soft delete (`deleted_at`), so mention an index **only on non-deleted rows**: `WHERE deleted_at IS NULL`.

---

## Q12 · "What is the N+1 query problem?"

**What you said:**
> "Fix is to use a join. It's like when data is in two tables and it goes to read the whole table for each query."

**What was right:** the fix (JOIN).
**What was wrong:** it's not about reading the whole table.

**Think of it like shopping:** you go to the shop once to get your shopping list (1 trip), then make **a separate trip for every item** on it (N trips). 100 items = 101 trips. Each trip is short, but together they're slow.

**Say this instead:**
> "N+1 is when you run **one query to get a list**, then **one more query for each item** in a loop. 100 leads, then each lead's counsellor separately: **101 queries** instead of 1 or 2.
> **How I spot it:** the number of queries per request grows with the number of rows. Or in code review: a database call inside a loop.
> **How I fix it:** one **JOIN**, or a second query that gets all the related rows at once with `WHERE id = ANY(list_of_ids)`. In Django it's `select_related` / `prefetch_related`."

```python
# N+1: 1 query + 1 per lead
leads = await conn.fetch("SELECT id, name, counsellor_id FROM leads")
for lead in leads:
    counsellor = await conn.fetchrow("SELECT name FROM users WHERE id = $1", lead["counsellor_id"])

# Fixed: 1 query
rows = await conn.fetch("""
    SELECT l.id, l.name, u.name AS counsellor
    FROM leads l LEFT JOIN users u ON u.id = l.counsellor_id""")
```

---

## Q13 · "3 pods × 4 workers × pool of 20 connections. Postgres allows 100. What goes wrong?"

**What you said:**
> "Use PgBouncer. It goes wrong when all connections are occupied as the system grows or replicates under load."

**What was right:** PgBouncer, and yes, it breaks under load.
**What was missing:** do the maths out loud, say what the user sees, give more than one fix.

**Say this instead:**
> "3 × 4 × 20 = **240 connections**, but Postgres allows **100**. At low traffic it works, because pools open connections only when needed. Under load it **breaks**: Postgres refuses new connections, and users get errors or very slow responses. Adding more pods makes it *worse*.
> **Fixes, simplest first:**
> 1. **Smaller pools:** keep about 90 for the app, 90 ÷ 12 workers ≈ **7 each**. That's usually plenty if queries are quick.
> 2. **PgBouncer**: it lets many app connections share a few real database connections.
> 3. **Give connections back quickly**: short transactions, and never hold a connection while calling a slow external API.
> 4. **Limit how many pods** can be added, and use a read-only copy of the database for heavy reports.
> I saw the opposite side in Vaidya: our pool was capped at 10, and requests waited in line for a connection."

**Pattern for any capacity question:** *numbers → what breaks → fixes, simplest first → your story.*

---

## Q14 · "The API is used by web and mobile apps. The response must change. How do you avoid breaking them?"

**What you said:**
> "The API should use versioning, so a new version doesn't affect the existing one, and I can also keep backward compatibility."

**What was right:** both keywords.
**What was missing:** versioning is the **last** option, not the first. Say *how* you stay compatible, and *why* mobile is the hard part.

**Say this instead:**
> "Mobile is the hard part: the website updates instantly, but old app versions stay on phones for months.
> 1. **Add, don't change.** Add new fields, never rename or remove old ones. Old apps ignore fields they don't know. If a field's shape changes, add a new field next to it.
> 2. **Version only if you really must break it:** a new `/v2` endpoint, with `/v1` kept running. Both use the same business code.
> 3. **Retire the old version slowly:** mark it deprecated, track which app versions still call it, ask users to update, and switch it off only when almost nobody uses it.
> 4. **Make the app tolerant too.** In our Flutter apps, every model field is nullable and unknown fields are ignored, so a missing or new field doesn't crash old versions."

That last point comes from your Flutter work, and most backend candidates can't make it. Use it.

---

## Q15 · "A report API used to take 2 seconds. Now it takes 40. How do you investigate?"

**What you said:**
> "I'd log each step, then check which step takes what time, then look at each step."

**What was right:** this is exactly the right first move. You **measure** before guessing.
**What was missing:** what to look for once you find the slow step.

**Think of it like a slow car journey:** first ask "what changed?" (new route? traffic?). Then time each part of the trip. Then fix the slowest part.

**Say this instead:**
> "1. **What changed?** A new deploy, more data, a new filter, more users, or a big background job running at the same time.
> 2. **Measure each step.** I log how long each step takes, with the request id, and also **how many database queries** the request makes. Tracing tools show this timeline automatically.
> 3. **Fix based on which step is slow:**
>    - **One slow query:** run `EXPLAIN ANALYZE`. Usually a missing index, or it's reading the whole table.
>    - **Many small queries:** that's N+1. Use a JOIN.
>    - **A slow external API call:** add a timeout, call it in parallel, or cache it.
>    - **Slow Python code:** do the totals in SQL with `GROUP BY` instead of in a Python loop.
>    - **Waiting between steps:** no free database connection, or a lock.
> 4. **If the report is just heavy:** pre-calculate it on a schedule, cache it, or make it a download job ('we'll email you when it's ready').
> 5. **Stop it happening again:** an alert when this endpoint gets slow."

```python
import time, logging
from contextlib import contextmanager

@contextmanager
def step(name, request_id):
    start = time.perf_counter()
    try:
        yield
    finally:
        logging.info("step=%s ms=%.1f request_id=%s", name, (time.perf_counter() - start) * 1000, request_id)

with step("load_rows", rid):
    rows = await repo.fetch_report_rows(...)
with step("build_report", rid):
    report = build_report(rows)
```

**Memory hook:** *what changed → measure → fix the slowest step → prevent.*

---

# Part 2 · New questions (Q16–Q30)

Try each one out loud **before** reading the answer.

## Q16 · "Give a real example of OOP in your Python work."

**Think of OOP as four ideas:**
- **Encapsulation:** hide the details inside a class (a repository hides the SQL).
- **Abstraction:** show *what* it does, not *how* (`upload_file()`, without caring if it's S3 or R2).
- **Inheritance:** a child class reuses a parent class (`NotFoundError` is a kind of `AppError`).
- **Polymorphism:** different classes, same method name, used the same way (every AI tool has a `run()`).

**Say this:**
> "My backends use Clean Architecture with the repository pattern, so OOP is how I separate the layers.
> **Abstraction:** file storage is behind one interface with methods like upload and get a signed link. When we moved documents in Manpower from the database to Cloudflare R2, I wrote a new storage class, and the rest of the code didn't change.
> **Encapsulation:** each table has a repository class that hides the SQL. Services get the repository passed in, so in tests I pass a fake one.
> **Polymorphism:** in Vaidya's AI pipeline, every tool has the same shape: a name, an input schema and a `run` method. The turn manager calls any tool the same way.
> **Inheritance** where it's natural: my error classes, `NotFoundError` and `ConflictError`, both extend `AppError`."

[fill: confirm each example matches your actual code. Two true examples beat three where one falls apart.]

**If they ask more:** abstract class = `abc.ABC` + `@abstractmethod`. `@classmethod` gets the class (used for alternative constructors), `@staticmethod` gets nothing (a helper function grouped with the class). Prefer **composition** (a class *has* another) over deep inheritance.

---

## Q17 · "How do you handle exceptions in production? What happens if an unexpected error happens inside an API?"

**Think of it as three nets:**
1. **Inside the code:** catch only errors you can actually handle.
2. **At the API edge:** turn known errors into the right status code with a clean message.
3. **Last net:** catch anything unexpected, log it fully, and show the user a safe message.

**Say this:**
> "I create my own error classes, like `NotFoundError` or `InsufficientCreditsError`. The business code raises them, and an **exception handler** in FastAPI turns each one into the right status code (404, 409, 402) with the same JSON shape every time: an error code, a message and a **request id**.
> For anything unexpected, a **catch-all handler** logs the full error with the request id and returns a plain 500, 'something went wrong', **without showing internal details**. Monitoring like Sentry alerts us. If a database transaction was open, it rolls back.
> I never use a bare `except:`, and I only retry temporary errors like timeouts, never errors caused by bad input."

**If they ask more:** `try / except / else / finally`. `raise NewError(...) from e` keeps the original cause in the logs.

---

## Q18 · "Where have you used decorators?"

**Think of a decorator as gift wrapping:** the gift (your function) stays the same, but the wrapping adds something around it, like timing, logging or retrying.

**Say this:**
> "A decorator is a function that wraps another function to add behaviour before or after it, without changing its code.
> I use them all the time in FastAPI: `@app.get` and `@router.post` register routes, `@field_validator` in Pydantic checks fields, and `@lru_cache` caches settings.
> I've written ones like a **timer** that logs how long a function takes, and a **retry** for flaky external calls. I always use `functools.wraps`, so the function keeps its name and signature. FastAPI needs that signature to know the parameters.
> For **auth** I don't use a decorator. I use FastAPI's `Depends`, because it shows up in the API docs and is easy to replace in tests."

```python
import functools, time, logging

def timed(fn):
    @functools.wraps(fn)
    async def wrapper(*args, **kwargs):
        start = time.perf_counter()
        try:
            return await fn(*args, **kwargs)
        finally:
            logging.info("%s took %.1fms", fn.__name__, (time.perf_counter() - start) * 1000)
    return wrapper
```

---

## Q19 · "You need to process millions of records but can't load them all into memory. How?"

**Think of it like reading a long book:** you don't photocopy the whole book. You read one page at a time.

**Say this:**
> "I'd process them **in pieces**, never all at once.
> In Python, a **generator** helps: a function with `yield` gives back one item or one batch at a time, so memory stays small however big the data is.
> From the database, I read in pages using the last id (`WHERE id > last_id ORDER BY id LIMIT 5000`), which stays fast even deep into the table. From a file, I read line by line.
> I save results in **bulk**, one insert per batch, and save progress after each batch so a crash can resume. If it's heavy calculation, I spread batches across several processes."

```python
def read_in_batches(path, size=5000):
    batch = []
    with open(path) as f:
        for line in f:                # reads one line at a time
            batch.append(line)
            if len(batch) == size:
                yield batch           # hand back one batch, then pause
                batch = []
    if batch:
        yield batch

for batch in read_in_batches("students.csv"):
    save_to_db(batch)
```

**If they ask more:** why not `OFFSET`? `OFFSET 1000000` makes the database skip a million rows every time, so it gets slower and slower. `WHERE id > last_id` jumps straight there using the index.

---

## Q20 · "Explain the roles of async/await, Redis and Celery."

**Think of a restaurant:**
- **async/await** = a waiter who takes many orders without standing idle (handles many requests *inside* the API).
- **Celery** = the kitchen staff who cook *after* the order is taken (work done *outside* the request, in separate workers).
- **Redis** = the order board between waiter and kitchen (the queue), and also a fast notepad (cache).

**Say this:**
> "They do different jobs.
> **async/await** lets one API server handle thousands of requests that are waiting on the database or network. But it doesn't make work happen *later*, and if the server restarts, that work is lost.
> **Celery** runs work in **separate worker processes**, outside the request, with retries and scheduling. Good for emails, imports and reports.
> **Redis** connects them: it's Celery's **queue** (the broker). It's also used for caching, rate limits and locks.
> Example: an OTP request. The async endpoint saves the code in Redis with a 5-minute expiry, puts a 'send OTP' task on the queue, and replies straight away. A worker sends the email with retries. That's how I took OTP from 8–10 seconds to half a second."

[Honest note: you've used Redis queues with your own workers, not Celery itself. Say: "I've built the same pattern with Redis queues and workers. Celery packages it with retries, scheduling and monitoring built in."]

---

## Q21 · "What are the practical differences between MongoDB and SQL databases?"

**Think of it like this:** SQL is a set of **strict spreadsheets** linked together. MongoDB is a **folder of flexible JSON documents**.

**Say this:**
> "I've worked mainly with **PostgreSQL**. I haven't used MongoDB in production, but here are the real trade-offs:
> - **Structure:** SQL has a fixed schema, and the database enforces rules like unique and not-null. Mongo documents can each have different fields, which is useful for things like custom form fields that differ per college. But checking has to happen in the app.
> - **Relationships:** SQL joins tables. In Mongo you usually **store related data together** in one document, like a student with their notes, because joins are limited.
> - **Transactions:** Postgres can safely update many rows at once by default. In Mongo, a single document update is safe, and multi-document transactions exist but cost more.
> - **Scaling:** Mongo has built-in sharding across machines. Postgres usually scales up first, then with read copies.
> - **Middle ground:** Postgres has **JSONB** columns, so you can store flexible JSON *inside* SQL. That's often the practical choice."

**Avoid saying:** "Mongo is faster" or "SQL is more reliable." They want trade-offs, not slogans.

---

## Q22 · "What are Django signals?" (Django: you haven't used it, so open honestly)

**Open with this, every time a Django question comes:**
> "I haven't worked with Django. My production work is FastAPI. But I know the concept, and here's how I solve the same problem in FastAPI."

That's honest, and it moves the conversation onto ground where you're strong. They asked earlier candidates Django questions, so have the concept ready, but always bridge to FastAPI.

**Think of signals like a doorbell:** when something happens (a student is saved), any code listening for the bell runs automatically. It's the **Observer pattern** ([08-design-patterns.md P10](08-design-patterns.md)).

**Say this:**
> "I haven't used Django, but signals are its built-in Observer pattern: `post_save` runs after a model is saved, `pre_delete` before a delete, and you connect a function with `@receiver`. They're used for things like creating a profile on sign-up or clearing a cache.
> The known downsides: they run in the same request, so a slow one slows the request; they don't fire on bulk updates; and they hide logic.
> **In FastAPI, I get the same result explicitly:** the service publishes an event like `lead.created`, and listeners handle the audit log and welcome email. Anything slow goes onto a **background queue**, and only after the database commit succeeds, so we never email someone about a save that rolled back."

**Django → FastAPI map** (to bridge any Django question):

| Django | What you use in FastAPI |
|---|---|
| Signals | Explicit service calls, an event bus, or a queue task after commit |
| Django ORM, `select_related` | SQLAlchemy `joinedload`, or raw SQL with JOIN (asyncpg, your way) |
| Django REST Framework serializers | Pydantic models + `response_model` |
| Middleware | Starlette middleware (`@app.middleware`, `add_middleware`) |
| Django Channels | FastAPI's built-in WebSockets + Redis pub/sub |
| Celery with Django | Same Celery, or arq / RQ / your own Redis workers |
| Django admin | No built-in admin. You build admin APIs (you own the Vaidya admin service) |
| `manage.py migrate` | Alembic, or hand-written SQL migrations (your Recurring setup) |

---

## Q23 · "WebSockets vs Django Channels: what's the difference?" (answer from the FastAPI side)

**Think of it like this:** a **WebSocket** is the phone line (the technology). **Django Channels** is Django's switchboard for phone lines (a library). FastAPI has the switchboard built in.

**Say this:**
> "A **WebSocket** is a connection that stays open, so the server and the browser can both send messages at any time. It starts as a normal HTTP request that gets upgraded, with a '101 Switching Protocols' response.
> I haven't used Django, but **Django Channels** is the library that adds WebSockets to Django, because plain Django only does one request, one response. It uses a Redis 'channel layer' so a message can reach users connected to different servers.
> **In FastAPI, WebSockets are built in:** `@app.websocket("/ws")`, then `accept`, `receive` and `send`. For broadcasting to users on different servers, like 'seat booked' to everyone watching an event, I'd use **Redis pub/sub**, which is the same job Channels' layer does. And when updates only go server → client, like progress, I use **SSE**, which is simpler. I used SSE for the Vaidya pipeline progress."

```python
from fastapi import WebSocket, WebSocketDisconnect

@app.websocket("/ws/events/{event_id}")
async def seat_updates(ws: WebSocket, event_id: int):
    await ws.accept()
    await manager.join(event_id, ws)            # manager forwards Redis pub/sub messages
    try:
        while True:
            await ws.receive_text()             # keep the connection alive
    except WebSocketDisconnect:
        manager.leave(event_id, ws)
```

**If they ask about auth on sockets:** browsers can't send an Authorization header on a WebSocket, so use an HttpOnly cookie (and check the `Origin` header), or a short-lived ticket in the URL. Details in [06-fastapi-rapid-fire.md section P](06-fastapi-rapid-fire.md).

---

## Q24 · "Design a ticket booking system. How do you stop two people booking the same seat?"

**Think of it like this:** two people grab the same seat at the same moment. Only one can win, and the database must decide, not your Python code.

**Say this:**
> "The main problem is two users booking **the same seat** at the same time.
> **Flow:** the user picks a seat → we **hold** it for about 10 minutes → they pay → the payment webhook confirms → the seat becomes **booked**. If they don't pay in time, a job releases it.
> **Stopping double booking, simplest way:** one database statement that only succeeds if the seat is still free:
> `UPDATE seats SET status='HELD', user_id=$1 WHERE seat_id=$2 AND status='AVAILABLE'`
> If it updated 0 rows, someone else got it first. The check and the change happen in **one step**, so there's no gap for a second user. That's the same trick I used for the Vaidya credit wallet.
> A **unique constraint** on (event, seat) in the bookings table is the final safety net.
> **For a huge sale with 100k people:** a virtual waiting room that lets people in gradually, a rate limit per user, and live seat updates over WebSocket."

**If they ask more:** other options are `SELECT ... FOR UPDATE` (lock the row while deciding), or a `version` column (fail if someone changed it first).

---

## Q25 · "What's a race condition? Have you fixed one?" (your strong story)

**Think of a shared bank account:** two people check the balance (₹100) at the same moment, both see enough money, and both withdraw ₹80. Now the balance is −₹60.

**Say this:**
> "A race condition is when two requests read and change the same data at the same time, and the result depends on who finishes first.
> In Vaidya's credit wallet, the risky pattern was **read the balance → check it in Python → write the new balance**. Two requests at once could both pass the check and overdraw the wallet.
> I fixed it with **one atomic SQL statement**:
> `UPDATE wallets SET balance = balance - $1 WHERE user_id = $2 AND balance >= $1`
> The check and the update happen together in the database. If it updates 0 rows, there wasn't enough balance. Two requests can't both win."

**If they ask more:** other fixes are a row lock (`SELECT ... FOR UPDATE`) or a version check. In Python (in memory), use a `threading.Lock`.

---

## Q26 · "How do you handle payment webhooks safely?" (your strong story)

**Say this:**
> "Four things, all from my Razorpay work:
> 1. **Verify it's really from Razorpay:** check the **HMAC-SHA256 signature** on the raw body with our secret. Reject if it doesn't match.
> 2. **Handle duplicates:** providers can send the same event more than once, so I save the event id as unique. If it's already there, reply 200 and skip.
> 3. **Handle wrong order:** a late or old event mustn't undo a newer state. I used a **state machine** in Postgres that only allows valid forward moves, like *created → active → cancelled*, never back.
> 4. **Handle missing events:** a **reconciliation job** regularly asks Razorpay for the real status and fixes anything we missed.
> I also reply quickly and do heavy work in a background job, so the provider doesn't time out and resend."

---

## Q27 · "How do you use Redis for caching? What about stale data?"

**Think of a cache like a notepad on your desk:** faster than walking to the filing cabinet (database), but it can be out of date.

**Say this:**
> "I use **cache-aside**: check Redis first. If it's there, return it. If not, read the database, save the result in Redis with an **expiry time** (TTL), and return it.
> **Stale data** is the main risk, so when the data changes, I **delete the cache key**, and the next read refreshes it. The TTL is a backup in case a delete is missed.
> In a multi-tenant app, I put the company id in the key, like `company:42:dashboard`, so data never mixes.
> **When not to cache:** data that must always be exact, like a wallet balance, or data that changes every second."

**If they ask more:** a **cache stampede** is when a popular key expires and 1,000 requests all hit the database at once. Fix: let only one request refresh it (a short lock) while others wait or get the old value.

---

## Q28 · "How does JWT authentication work? How do you log someone out?"

**Think of a JWT like a signed concert wristband:** staff can check it's real without calling the office, but once it's given out, you can't easily take it back before it expires.

**Say this:**
> "On login, I check the password hash (argon2) and issue two tokens:
> - a **short-lived access token** (about 15 minutes): a JWT signed by the server, holding the user id, role and company
> - a **long-lived refresh token**, stored hashed in the database
> Every request sends the access token. The server **checks the signature and expiry**, with no database call needed. When it expires, the app uses the refresh token to get a new one, and I **rotate** the refresh token each time.
> A JWT is **signed, not encrypted**, so I never put secrets in it.
> **Logout:** delete the refresh token in the database, and for instant logout, add the access token's id to a **Redis block-list** until it expires. Changing the password revokes all sessions. I built this in my Recurring app."

**Your real bug to mention:** Apple Sign-In users got locked out because the logout block-list was keyed on a token id that Apple reuses, unlike Google. That shows you understand the details.

---

## Q29 · "Monolith or microservices?"

**Think of it like this:** a monolith is one big shop. Microservices are separate small shops: each runs independently, but they have to phone each other.

**Say this:**
> "A **monolith** is one app and one deploy. It's simple to build, test and debug, and transactions are easy. It's the right start for most teams.
> **Microservices** split the system into separate services, like auth, billing and AI. Each can be deployed and scaled on its own, and owned by a different team. The cost: network calls can fail, data lives in different places, and debugging across services is harder.
> At Vaidya we have separate services: I own auth, admin and billing, and the auth service issues the token every other service checks. What I learned: you need **shared contracts** (like the token format), **timeouts and retries** between services, **idempotency**, and a **request id** passed along so you can trace one request across all services.
> My rule: start with a well-organised monolith, and split out a service only when there's a real reason, like a different scaling need or team ownership."

---

## Q30 · "What do you look for in a code review?"

**Say this:**
> "In order of importance:
> 1. **Correctness:** does it do what the ticket says? Edge cases: empty input, duplicates, two requests at once.
> 2. **Security:** auth on every route, company filter on every query, input validation, no secrets in code or logs.
> 3. **Database:** N+1 queries, missing indexes, transactions where needed, safe migrations.
> 4. **Errors and logs:** errors handled properly, useful logs with the request id.
> 5. **Performance:** no blocking calls in async code, no queries without limits.
> 6. **Readability:** clear names, small functions, business logic out of the route handlers.
> 7. **Tests:** especially failure cases: wrong user, wrong company, bad input.
> 8. **Compatibility:** does an API change break existing app versions?
> I keep comments kind and specific: I say *why*, suggest a fix, and mark small things as 'nit' so the author knows what's optional."

---

## Final practice plan

1. **Tonight:** say Q1, Q2 and Q3 out loud until each is under 90 seconds. Fill in every [fill: …].
2. **Code:** type Fibonacci (Q7) and right-shift (Q8) from memory, twice, in C++.
3. **Weak areas:** Q4, Q5, Q6, Q9. Say them aloud without reading.
4. **Strong stories, ready to use anywhere:** wallet race condition (Q25), webhooks (Q26), event-loop fix (Q10), OTP speed-up (Q3), Apple Sign-In bug (Q28).
5. **The day before:** read only the scorecard and the "Say this instead" parts.
