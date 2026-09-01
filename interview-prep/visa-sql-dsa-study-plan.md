# 12-Hour SQL and DSA Study Plan for Software Engineering Interviews

## Overview
This 12-hour intensive study plan is designed for a software engineer with 0.5 years of experience preparing for technical interviews. The plan focuses 70% on SQL (8.5 hours) and 30% on DSA (3.5 hours), with hour-by-hour breakdowns, clear learning objectives, explanations, C++ code examples, and practice exercises.

## Quick Reference Guides

### SQL Quick Reference
```sql
-- Basic queries
SELECT column1, column2 FROM table WHERE condition ORDER BY column1;
SELECT column1, COUNT(*) FROM table GROUP BY column1 HAVING COUNT(*) > 5;

-- Joins
SELECT a.col, b.col FROM tableA a INNER JOIN tableB b ON a.id = b.id;
SELECT a.col, b.col FROM tableA a LEFT JOIN tableB b ON a.id = b.id;
SELECT a.col, b.col FROM tableA a RIGHT JOIN tableB b ON a.id = b.id;
SELECT a.col, b.col FROM tableA a FULL OUTER JOIN tableB b ON a.id = b.id;

-- Subqueries
SELECT * FROM employees WHERE salary > (SELECT AVG(salary) FROM employees);

-- Common Table Expressions (CTEs)
WITH high_salary AS (
    SELECT * FROM employees WHERE salary > 100000
)
SELECT * FROM high_salary WHERE dept = 'Engineering';

-- Window functions
SELECT name, salary, 
       RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS rank
FROM employees;
```

### DSA Quick Reference
```cpp
// Common time complexities
// O(1) - Constant
// O(log n) - Logarithmic
// O(n) - Linear
// O(n log n) - Linearithmic
// O(n²) - Quadratic
// O(2^n) - Exponential

// Two pointers technique
int twoSum(vector<int>& nums, int target) {
    int left = 0, right = nums.size() - 1;
    while (left < right) {
        int sum = nums[left] + nums[right];
        if (sum == target) return true;
        else if (sum < target) left++;
        else right--;
    }
    return false;
}

// BFS template
void bfs(Graph graph, int start) {
    queue<int> q;
    vector<bool> visited(graph.size(), false);
    q.push(start);
    visited[start] = true;
    
    while (!q.empty()) {
        int node = q.front();
        q.pop();
        
        for (int neighbor : graph.getNeighbors(node)) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                q.push(neighbor);
            }
        }
    }
}

// DFS template
void dfs(Graph graph, int node, vector<bool>& visited) {
    visited[node] = true;
    
    for (int neighbor : graph.getNeighbors(node)) {
        if (!visited[neighbor]) {
            dfs(graph, neighbor, visited);
        }
    }
}
```

## Hour-by-Hour Study Plan

### HOUR 1: SQL Basics - Retrieval and Filtering
**Learning Objectives:**
- Understand basic SQL syntax and structure
- Learn how to retrieve and filter data with SELECT and WHERE
- Practice writing simple queries

**Concepts:**
- **SQL Overview:**
  - SQL (Structured Query Language) is used to communicate with databases
  - Types of SQL commands: DDL, DML, DCL, TCL
  - Database structure: tables, rows, columns, keys

- **Basic SELECT:**
  - Syntax: `SELECT column1, column2 FROM table;`
  - Retrieving all columns: `SELECT * FROM table;`
  - Column aliases: `SELECT column AS alias FROM table;`

- **Filtering with WHERE:**
  - Comparison operators: `=`, `<>`, `<`, `>`, `<=`, `>=`
  - Logical operators: `AND`, `OR`, `NOT`
  - Pattern matching: `LIKE`, wildcards (`%`, `_`)
  - NULL values: `IS NULL`, `IS NOT NULL`

**C++ Integration Example:**
```cpp
#include <iostream>
#include <string>
#include <mysql/mysql.h>  // Using MySQL C++ connector

int main() {
    MYSQL* conn;
    MYSQL_RES* res;
    MYSQL_ROW row;
    
    // Initialize connection
    conn = mysql_init(NULL);
    if (conn == NULL) {
        std::cout << "MySQL initialization failed" << std::endl;
        return 1;
    }
    
    // Connect to database
    if (mysql_real_connect(conn, "hostname", "username", "password", 
                          "database", 0, NULL, 0) == NULL) {
        std::cout << "Connection failed: " << mysql_error(conn) << std::endl;
        return 1;
    }
    
    // Execute a basic SELECT query
    std::string query = "SELECT id, name, salary FROM employees WHERE salary > 50000";
    if (mysql_query(conn, query.c_str())) {
        std::cout << "Query failed: " << mysql_error(conn) << std::endl;
        return 1;
    }
    
    // Process results
    res = mysql_store_result(conn);
    while ((row = mysql_fetch_row(res)) != NULL) {
        std::cout << "ID: " << row[0] << ", Name: " << row[1] 
                 << ", Salary: " << row[2] << std::endl;
    }
    
    // Clean up
    mysql_free_result(res);
    mysql_close(conn);
    
    return 0;
}
```

**Practice Exercises:**
1. Write a query to select all employees from a specific department.
2. Find all products with price greater than $100 and in stock (quantity > 0).
3. List all customers whose names start with 'A' and have made purchases in the last 30 days.

**Solutions:**
```sql
-- Exercise 1
SELECT * FROM employees WHERE department = 'Engineering';

-- Exercise 2
SELECT * FROM products WHERE price > 100 AND quantity > 0;

-- Exercise 3
SELECT * FROM customers 
WHERE name LIKE 'A%' 
AND customer_id IN (SELECT customer_id FROM orders WHERE order_date >= DATEADD(day, -30, GETDATE()));
```

**Interview Questions:**
1. What's the difference between `WHERE` and `HAVING` clauses?
2. How would you find duplicate records in a table?
3. How can you retrieve only unique values from a column?

**Key Points:**
- Understand the basic structure of SQL queries
- Know how to filter data using multiple conditions
- Practice writing queries that combine different operators

### HOUR 2: SQL Intermediate - Sorting, Aggregation, and Grouping
**Learning Objectives:**
- Master data ordering with ORDER BY
- Learn aggregation functions and GROUP BY
- Understand the HAVING clause for filtering groups

**Concepts:**
- **Sorting with ORDER BY:**
  - Basic syntax: `ORDER BY column [ASC|DESC]`
  - Sorting by multiple columns
  - NULL handling in sorting

- **Aggregation Functions:**
  - COUNT(): Count rows or non-NULL values
  - SUM(): Sum of numeric values
  - AVG(): Average of numeric values
  - MIN()/MAX(): Minimum/maximum values
  - Standard deviation (STDDEV, STDDEV_POP)

- **Grouping with GROUP BY:**
  - Basic syntax: `GROUP BY column1, column2`
  - Grouping sets
  - ROLLUP and CUBE operators

- **Filtering groups with HAVING:**
  - Syntax: `HAVING aggregate_condition`
  - Differences from WHERE (operates on groups vs. rows)

**Practice Exercises:**
1. Find the average salary for each department and sort by highest to lowest average.
2. Count the number of orders placed by each customer in 2023, showing only customers with more than 5 orders.
3. Find the total sales amount per month, with subtotals for each quarter.

**Solutions:**
```sql
-- Exercise 1
SELECT department, AVG(salary) as avg_salary
FROM employees
GROUP BY department
ORDER BY avg_salary DESC;

-- Exercise 2
SELECT customer_id, COUNT(*) as order_count
FROM orders
WHERE YEAR(order_date) = 2023
GROUP BY customer_id
HAVING COUNT(*) > 5
ORDER BY order_count DESC;

-- Exercise 3
SELECT 
    YEAR(order_date) as year,
    QUARTER(order_date) as quarter,
    MONTH(order_date) as month,
    SUM(amount) as total_sales
FROM orders
GROUP BY YEAR(order_date), QUARTER(order_date), MONTH(order_date) WITH ROLLUP
ORDER BY year, quarter, month;
```

**Interview Questions:**
1. When would you use HAVING instead of WHERE?
2. How can you find the second highest salary in a table?
3. What's the difference between COUNT(*) and COUNT(column_name)?

**Key Points:**
- GROUP BY must include all non-aggregated columns in the SELECT clause
- HAVING filters after grouping, WHERE filters before grouping
- Aggregation functions ignore NULL values (except COUNT(*))

### HOUR 3: SQL Joins - Understanding Table Relationships
**Learning Objectives:**
- Master different types of SQL joins
- Understand when to use each join type
- Practice writing multi-table queries

**Concepts:**
- **Types of Joins:**
  - INNER JOIN: Returns rows when there's a match in both tables
  - LEFT JOIN: Returns all rows from left table and matching rows from right
  - RIGHT JOIN: Returns all rows from right table and matching rows from left
  - FULL OUTER JOIN: Returns rows when there's a match in one of the tables
  - CROSS JOIN: Returns the Cartesian product of two tables

- **Join Syntax:**
  - `FROM table1 JOIN_TYPE table2 ON table1.column = table2.column`
  - Using table aliases: `FROM table1 t1 JOIN table2 t2 ON t1.col = t2.col`
  - Multiple join conditions: `ON t1.col1 = t2.col1 AND t1.col2 = t2.col2`

- **Self-Joins:**
  - Joining a table to itself
  - Using different aliases for the same table

**Visual Explanation:**
```
Table A    Table B     INNER JOIN     LEFT JOIN      RIGHT JOIN     FULL OUTER JOIN
  o o        o o         o o            o o            o o              o o
  o              -->       <--         o              o                o o
    o        o               <--         o            o o                o
```

**C++ Integration Example:**
```cpp
// Example of processing join results in C++
void processJoinResults(MYSQL* conn) {
    std::string query = 
        "SELECT o.order_id, c.customer_name, o.order_date, o.total_amount "
        "FROM orders o "
        "INNER JOIN customers c ON o.customer_id = c.customer_id "
        "WHERE o.order_date >= '2023-01-01'";
        
    if (mysql_query(conn, query.c_str())) {
        std::cout << "Query failed: " << mysql_error(conn) << std::endl;
        return;
    }
    
    MYSQL_RES* res = mysql_store_result(conn);
    MYSQL_ROW row;
    
    // Create a map of order history per customer
    std::map<std::string, std::vector<std::pair<std::string, double>>> customerOrders;
    
    while ((row = mysql_fetch_row(res)) != NULL) {
        std::string orderId = row[0];
        std::string customerName = row[1];
        std::string orderDate = row[2];
        double amount = std::stod(row[3]);
        
        customerOrders[customerName].push_back({orderDate, amount});
    }
    
    // Process the joined data
    for (const auto& customer : customerOrders) {
        std::cout << "Customer: " << customer.first << std::endl;
        double total = 0.0;
        for (const auto& order : customer.second) {
            std::cout << "  " << order.first << ": $" << order.second << std::endl;
            total += order.second;
        }
        std::cout << "Total purchases: $" << total << std::endl;
    }
    
    mysql_free_result(res);
}
```

**Practice Exercises:**
1. List all customers and their orders, including customers who haven't placed any orders.
2. Find employees and their managers (self-join).
3. Show a list of products and their categories, including products without categories and categories without products.

**Solutions:**
```sql
-- Exercise 1
SELECT c.customer_id, c.customer_name, o.order_id, o.order_date
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
ORDER BY c.customer_name;

-- Exercise 2
SELECT e.employee_id, e.employee_name, m.employee_name as manager_name
FROM employees e
LEFT JOIN employees m ON e.manager_id = m.employee_id
ORDER BY e.employee_name;

-- Exercise 3
SELECT p.product_id, p.product_name, c.category_name
FROM products p
FULL OUTER JOIN categories c ON p.category_id = c.category_id
ORDER BY c.category_name, p.product_name;
```

**Interview Questions:**
1. What's the difference between INNER JOIN and LEFT JOIN?
2. When would you use a FULL OUTER JOIN?
3. How would you find records that exist in one table but not in another?

**Key Points:**
- Choose the right join type based on what data you need to include or exclude
- Use appropriate table aliases to make queries more readable
- Multiple joins can be chained together for complex queries

### HOUR 4: SQL Subqueries and CTEs
**Learning Objectives:**
- Master subqueries in different clauses (WHERE, FROM, SELECT)
- Understand Common Table Expressions (CTEs)
- Learn when to use subqueries vs. joins

**Concepts:**
- **Subquery Types:**
  - Scalar subqueries: Return a single value
  - Row subqueries: Return a single row
  - Table subqueries: Return multiple rows
  - Correlated subqueries: Reference outer query tables

- **Subquery Locations:**
  - WHERE clause: `WHERE column_name = (SELECT ...)`
  - FROM clause (derived tables): `FROM (SELECT ...) AS alias`
  - SELECT clause: `SELECT column1, (SELECT ...) AS calculated`
  - HAVING clause: `HAVING aggregate_function > (SELECT ...)`

- **Common Table Expressions (CTEs):**
  - Basic syntax: `WITH cte_name AS (SELECT ...) SELECT * FROM cte_name`
  - Multiple CTEs: `WITH cte1 AS (...), cte2 AS (...) SELECT ...`
  - Recursive CTEs for hierarchical data

**Practice Exercises:**
1. Find employees who earn more than the average salary of their department.
2. Use a CTE to find the top 3 customers by total purchase amount.
3. Write a recursive CTE to traverse an employee hierarchy.

**Solutions:**
```sql
-- Exercise 1
SELECT e1.employee_id, e1.employee_name, e1.salary, e1.department
FROM employees e1
WHERE e1.salary > (
    SELECT AVG(e2.salary)
    FROM employees e2
    WHERE e1.department = e2.department
);

-- Exercise 2
WITH customer_totals AS (
    SELECT 
        c.customer_id, 
        c.customer_name, 
        SUM(o.amount) as total_amount
    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    GROUP BY c.customer_id, c.customer_name
)
SELECT customer_id, customer_name, total_amount
FROM customer_totals
ORDER BY total_amount DESC
LIMIT 3;

-- Exercise 3
WITH RECURSIVE employee_hierarchy AS (
    -- Base case: top-level employees (no manager)
    SELECT employee_id, employee_name, manager_id, 0 AS level
    FROM employees
    WHERE manager_id IS NULL
    
    UNION ALL
    
    -- Recursive case: employees with managers
    SELECT e.employee_id, e.employee_name, e.manager_id, eh.level + 1
    FROM employees e
    JOIN employee_hierarchy eh ON e.manager_id = eh.employee_id
)
SELECT 
    employee_id, 
    CONCAT(REPEAT('    ', level), employee_name) AS hierarchy
FROM employee_hierarchy
ORDER BY level, employee_name;
```

**Interview Questions:**
1. What's the difference between a correlated and non-correlated subquery?
2. When would you use a CTE instead of a subquery?
3. How would you identify and fix a subquery that's causing performance issues?

**Key Points:**
- Use CTEs for complex queries that need to be broken down into simpler parts
- Correlated subqueries can be slower since they run once for each row in the outer query
- EXISTS is often more efficient than IN when checking existence in large tables

### HOUR 5: Advanced SQL - Window Functions
**Learning Objectives:**
- Understand window functions and their applications
- Master ranking, analytical, and aggregate window functions
- Apply window functions to solve complex problems

**Concepts:**
- **Window Function Basics:**
  - Syntax: `function_name() OVER ([PARTITION BY column] [ORDER BY column])`
  - PARTITION BY: Divide rows into groups
  - ORDER BY: Define the order within each partition
  - ROWS/RANGE: Define the window frame

- **Types of Window Functions:**
  - Ranking: ROW_NUMBER(), RANK(), DENSE_RANK(), NTILE()
  - Analytical: LEAD(), LAG(), FIRST_VALUE(), LAST_VALUE()
  - Aggregate: SUM(), AVG(), MIN(), MAX(), COUNT() as window functions

**Practice Exercises:**
1. For each employee, calculate their salary rank within their department.
2. Calculate running totals of sales by month.
3. Find the difference in sales amount compared to the previous month.

**Solutions:**
```sql
-- Exercise 1
SELECT 
    employee_id,
    employee_name,
    department,
    salary,
    RANK() OVER(PARTITION BY department ORDER BY salary DESC) as dept_salary_rank
FROM employees;

-- Exercise 2
SELECT 
    order_date,
    amount,
    SUM(amount) OVER(ORDER BY order_date) as running_total
FROM orders;

-- Exercise 3
SELECT 
    YEAR(order_date) as year,
    MONTH(order_date) as month,
    SUM(amount) as monthly_total,
    SUM(amount) - LAG(SUM(amount), 1, 0) OVER(ORDER BY YEAR(order_date), MONTH(order_date)) as diff_from_previous
FROM orders
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY year, month;
```

**Interview Questions:**
1. What's the difference between RANK() and DENSE_RANK()?
2. How would you find the median salary using window functions?
3. When would you use LAG() and LEAD() functions?

**Key Points:**
- Window functions perform calculations across a set of rows related to the current row
- Unlike GROUP BY, window functions don't collapse rows
- Window functions are processed after the WHERE, GROUP BY, and HAVING clauses

### HOUR 6: Database Design and Normalization
**Learning Objectives:**
- Understand database normalization principles
- Learn how to design efficient schemas
- Apply normalization techniques to real-world scenarios

**Concepts:**
- **Database Entities and Relationships:**
  - Entity-Relationship (ER) modeling
  - Relationship types: one-to-one, one-to-many, many-to-many
  - Cardinality and participation constraints

- **Normalization Forms:**
  - 1NF: Eliminate repeating groups
  - 2NF: Remove partial dependencies
  - 3NF: Remove transitive dependencies
  - BCNF: More rigorous 3NF
  - 4NF and 5NF: Advanced normalization

- **Keys and Constraints:**
  - Primary keys
  - Foreign keys
  - Unique constraints
  - CHECK constraints
  - DEFAULT values
  - NOT NULL constraints

**Practice Exercises:**
1. Normalize a denormalized table to 3NF:
   ```
   Order(OrderID, CustomerName, CustomerAddress, ProductID, ProductName, ProductPrice, Quantity, OrderDate)
   ```

2. Design a database schema for a payment processing system with customers, accounts, transactions, and merchants.

**Solutions:**
```sql
-- Exercise 1 Solution
-- 1NF, 2NF, 3NF Normalized Schema:

-- Customers table
CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    CustomerName VARCHAR(100) NOT NULL,
    CustomerAddress VARCHAR(200) NOT NULL
);

-- Products table
CREATE TABLE Products (
    ProductID INT PRIMARY KEY,
    ProductName VARCHAR(100) NOT NULL,
    ProductPrice DECIMAL(10, 2) NOT NULL
);

-- Orders table
CREATE TABLE Orders (
    OrderID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    OrderDate DATE NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

-- OrderDetails table
CREATE TABLE OrderDetails (
    OrderID INT,
    ProductID INT,
    Quantity INT NOT NULL,
    PRIMARY KEY (OrderID, ProductID),
    FOREIGN KEY (OrderID) REFERENCES Orders(OrderID),
    FOREIGN KEY (ProductID) REFERENCES Products(ProductID)
);

-- Exercise 2 Solution
-- Payment Processing System Schema:

CREATE TABLE Customers (
    CustomerID INT PRIMARY KEY,
    FirstName VARCHAR(50) NOT NULL,
    LastName VARCHAR(50) NOT NULL,
    Email VARCHAR(100) UNIQUE NOT NULL,
    Phone VARCHAR(20),
    RegistrationDate DATE NOT NULL
);

CREATE TABLE Accounts (
    AccountID INT PRIMARY KEY,
    CustomerID INT NOT NULL,
    AccountType VARCHAR(20) NOT NULL,
    AccountNumber VARCHAR(20) UNIQUE NOT NULL,
    Balance DECIMAL(15, 2) NOT NULL DEFAULT 0,
    Status VARCHAR(10) NOT NULL,
    CreationDate DATE NOT NULL,
    FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID)
);

CREATE TABLE Merchants (
    MerchantID INT PRIMARY KEY,
    MerchantName VARCHAR(100) NOT NULL,
    Category VARCHAR(50) NOT NULL,
    ContactEmail VARCHAR(100) NOT NULL,
    ContactPhone VARCHAR(20),
    Status VARCHAR(10) NOT NULL
);

CREATE TABLE Transactions (
    TransactionID INT PRIMARY KEY,
    AccountID INT NOT NULL,
    MerchantID INT NOT NULL,
    Amount DECIMAL(15, 2) NOT NULL,
    TransactionType VARCHAR(20) NOT NULL,
    TransactionDate DATETIME NOT NULL,
    Status VARCHAR(20) NOT NULL,
    ReferenceNumber VARCHAR(50) UNIQUE NOT NULL,
    FOREIGN KEY (AccountID) REFERENCES Accounts(AccountID),
    FOREIGN KEY (MerchantID) REFERENCES Merchants(MerchantID)
);

CREATE TABLE TransactionDetails (
    TransactionID INT,
    DetailType VARCHAR(50),
    DetailValue VARCHAR(200) NOT NULL,
    PRIMARY KEY (TransactionID, DetailType),
    FOREIGN KEY (TransactionID) REFERENCES Transactions(TransactionID)
);
```

**Interview Questions:**
1. What are the benefits of normalization?
2. When might you choose to denormalize a database?
3. How would you handle a many-to-many relationship in a database schema?

**Key Points:**
- Normalization reduces redundancy and improves data integrity
- Denormalization may be used for performance in read-heavy systems
- Use junction tables (associative entities) for many-to-many relationships

### HOUR 7: Indexing and Query Optimization
**Learning Objectives:**
- Understand database indexing concepts
- Learn to analyze and optimize SQL queries
- Master EXPLAIN and query execution plans

**Concepts:**
- **Index Types:**
  - B-tree indexes
  - Bitmap indexes
  - Hash indexes
  - Full-text indexes
  - Clustered vs. non-clustered indexes

- **Index Creation and Management:**
  - Creating indexes: `CREATE INDEX index_name ON table (column)`
  - Multi-column indexes and column order
  - When to index and when not to
  - Index maintenance and statistics

- **Query Optimization Techniques:**
  - Using EXPLAIN/EXPLAIN PLAN
  - Reading execution plans
  - Common performance issues
  - Query rewriting strategies

**C++ Integration Example:**
```cpp
// Example of creating an index programmatically
bool createIndex(MYSQL* conn, const std::string& tableName, 
                const std::string& columnName, const std::string& indexName) {
    std::string query = "CREATE INDEX " + indexName + " ON " 
                      + tableName + " (" + columnName + ")";
    
    if (mysql_query(conn, query.c_str())) {
        std::cerr << "Failed to create index: " << mysql_error(conn) << std::endl;
        return false;
    }
    
    std::cout << "Index created successfully" << std::endl;
    return true;
}

// Example of analyzing a slow query
void analyzeQuery(MYSQL* conn, const std::string& query) {
    std::string explainQuery = "EXPLAIN " + query;
    
    if (mysql_query(conn, explainQuery.c_str())) {
        std::cerr << "EXPLAIN failed: " << mysql_error(conn) << std::endl;
        return;
    }
    
    MYSQL_RES* res = mysql_store_result(conn);
    MYSQL_ROW row;
    
    // Print column names
    unsigned int numFields = mysql_num_fields(res);
    MYSQL_FIELD* fields = mysql_fetch_fields(res);
    
    for (unsigned int i = 0; i < numFields; i++) {
        std::cout << fields[i].name << "\t";
    }
    std::cout << std::endl;
    
    // Print execution plan
    while ((row = mysql_fetch_row(res)) != NULL) {
        for (unsigned int i = 0; i < numFields; i++) {
            std::cout << (row[i] ? row[i] : "NULL") << "\t";
        }
        std::cout << std::endl;
    }
    
    mysql_free_result(res);
}
```

**Practice Exercises:**
1. Create appropriate indexes for the payment processing schema from Hour 6.
2. Analyze the execution plan of a complex join query and identify optimization opportunities.
3. Rewrite a slow query to improve performance.

**Solutions:**
```sql
-- Exercise 1: Indexing the Payment Processing Schema
-- Primary key indexes are created automatically

-- Accounts table indexes
CREATE INDEX idx_accounts_customer ON Accounts(CustomerID);
CREATE INDEX idx_accounts_status ON Accounts(Status);
CREATE INDEX idx_accounts_type ON Accounts(AccountType);

-- Transactions table indexes
CREATE INDEX idx_transactions_account ON Transactions(AccountID);
CREATE INDEX idx_transactions_merchant ON Transactions(MerchantID);
CREATE INDEX idx_transactions_date ON Transactions(TransactionDate);
CREATE INDEX idx_transactions_type_status ON Transactions(TransactionType, Status);

-- Merchants table indexes
CREATE INDEX idx_merchants_category ON Merchants(Category);
CREATE INDEX idx_merchants_status ON Merchants(Status);

-- Exercise 2: Analyzing a complex join query
EXPLAIN
SELECT 
    c.CustomerID,
    CONCAT(c.FirstName, ' ', c.LastName) AS CustomerName,
    COUNT(t.TransactionID) AS TransactionCount,
    SUM(t.Amount) AS TotalAmount
FROM Customers c
JOIN Accounts a ON c.CustomerID = a.CustomerID
JOIN Transactions t ON a.AccountID = t.AccountID
JOIN Merchants m ON t.MerchantID = m.MerchantID
WHERE 
    t.TransactionDate >= '2023-01-01'
    AND t.Status = 'Completed'
    AND m.Category = 'Retail'
GROUP BY c.CustomerID, CustomerName
ORDER BY TotalAmount DESC;

-- Exercise 3: Rewriting a slow query
-- Original slow query:
SELECT 
    t.TransactionDate,
    m.MerchantName,
    t.Amount
FROM Transactions t
JOIN Merchants m ON t.MerchantID = m.MerchantID
WHERE 
    t.TransactionDate BETWEEN '2023-01-01' AND '2023-12-31'
    AND t.Status = 'Completed'
    AND m.Category IN ('Retail', 'Food', 'Entertainment')
ORDER BY t.TransactionDate DESC;

-- Optimized query:
SELECT 
    t.TransactionDate,
    m.MerchantName,
    t.Amount
FROM Transactions t
-- Use INNER JOIN (explicitly) as we only want matches
INNER JOIN Merchants m ON t.MerchantID = m.MerchantID
WHERE 
    -- More selective filter first
    t.Status = 'Completed'
    -- Use >= and <= instead of BETWEEN for better index usage
    AND t.TransactionDate >= '2023-01-01' 
    AND t.TransactionDate <= '2023-12-31'
    -- Create a covering index for this IN clause
    AND m.Category IN ('Retail', 'Food', 'Entertainment')
ORDER BY t.TransactionDate DESC
-- Add LIMIT if we only need top results
LIMIT 1000;

-- Additional index to support the query:
CREATE INDEX idx_transactions_status_date ON Transactions(Status, TransactionDate);
CREATE INDEX idx_merchants_category_name ON Merchants(Category, MerchantName);
```

**Interview Questions:**
1. How do you decide which columns to index in a database?
2. What's the difference between a clustered and non-clustered index?
3. What common issues can cause a query to perform poorly?

**Key Points:**
- Indexes improve SELECT performance but slow down INSERT/UPDATE/DELETE operations
- Order of columns in a multi-column index matters (most selective first)
- Use EXPLAIN to understand how the database executes a query
- Filter on indexed columns early in the WHERE clause

### HOUR 8: SQL Transactions and Concurrency
**Learning Objectives:**
- Understand transaction properties (ACID)
- Learn concurrency control mechanisms
- Master transaction isolation levels

**Concepts:**
- **ACID Properties:**
  - Atomicity: All or nothing
  - Consistency: Valid state to valid state
  - Isolation: Transactions don't interfere
  - Durability: Committed changes persist

- **Transaction Control:**
  - BEGIN/START TRANSACTION
  - COMMIT
  - ROLLBACK
  - SAVEPOINT and partial rollbacks

- **Concurrency Issues:**
  - Dirty reads
  - Non-repeatable reads
  - Phantom reads
  - Lost updates

- **Isolation Levels:**
  - READ UNCOMMITTED
  - READ COMMITTED
  - REPEATABLE READ
  - SERIALIZABLE

**C++ Integration Example:**
```cpp
// Example of transaction handling in C++
bool transferFunds(MYSQL* conn, int fromAccountId, int toAccountId, double amount) {
    // Start transaction
    mysql_query(conn, "START TRANSACTION");
    
    bool success = true;
    
    // Deduct from source account
    std::string updateSource = 
        "UPDATE Accounts SET Balance = Balance - " + std::to_string(amount) + 
        " WHERE AccountID = " + std::to_string(fromAccountId) + 
        " AND Balance >= " + std::to_string(amount);
    
    if (mysql_query(conn, updateSource.c_str())) {
        std::cerr << "Failed to update source account: " << mysql_error(conn) << std::endl;
        success = false;
    }
    
    // Check if the source update affected any rows (had sufficient balance)
    if (mysql_affected_rows(conn) == 0) {
        std::cerr << "Insufficient balance or account not found" << std::endl;
        success = false;
    }
    
    // Add to destination account
    if (success) {
        std::string updateDest = 
            "UPDATE Accounts SET Balance = Balance + " + std::to_string(amount) + 
            " WHERE AccountID = " + std::to_string(toAccountId);
        
        if (mysql_query(conn, updateDest.c_str())) {
            std::cerr << "Failed to update destination account: " << mysql_error(conn) << std::endl;
            success = false;
        }
        
        if (mysql_affected_rows(conn) == 0) {
            std::cerr << "Destination account not found" << std::endl;
            success = false;
        }
    }
    
    // Record the transaction
    if (success) {
        std::string insertTxn = 
            "INSERT INTO Transactions (AccountID, TransactionType, Amount, Status) "
            "VALUES (" + std::to_string(fromAccountId) + ", 'TRANSFER_OUT', " + 
            std::to_string(amount) + ", 'COMPLETED')";
        
        if (mysql_query(conn, insertTxn.c_str())) {
            std::cerr << "Failed to record source transaction: " << mysql_error(conn) << std::endl;
            success = false;
        }
        
        insertTxn = 
            "INSERT INTO Transactions (AccountID, TransactionType, Amount, Status) "
            "VALUES (" + std::to_string(toAccountId) + ", 'TRANSFER_IN', " + 
            std::to_string(amount) + ", 'COMPLETED')";
        
        if (mysql_query(conn, insertTxn.c_str())) {
            std::cerr << "Failed to record destination transaction: " << mysql_error(conn) << std::endl;
            success = false;
        }
    }
    
    // Commit or rollback based on success
    if (success) {
        mysql_query(conn, "COMMIT");
        std::cout << "Transaction completed successfully" << std::endl;
    } else {
        mysql_query(conn, "ROLLBACK");
        std::cout << "Transaction rolled back" << std::endl;
    }
    
    return success;
}
```

**Practice Exercises:**
1. Write a transaction to process a payment, updating account balance and recording transaction history.
2. Implement optimistic concurrency control using version numbers.
3. Write queries demonstrating the different isolation levels and their effects.

**Solutions:**
```sql
-- Exercise 1: Payment Processing Transaction
START TRANSACTION;

-- Validate customer account exists and has sufficient funds
SELECT @balance := Balance FROM Accounts 
WHERE AccountID = 123 FOR UPDATE;

IF @balance < 100.00 THEN
    ROLLBACK;
    SELECT 'Insufficient funds' as message;
ELSE
    -- Update account balance
    UPDATE Accounts 
    SET Balance = Balance - 100.00
    WHERE AccountID = 123;
    
    -- Record the transaction
    INSERT INTO Transactions (
        AccountID, MerchantID, Amount, TransactionType, 
        TransactionDate, Status, ReferenceNumber
    ) VALUES (
        123, 456, 100.00, 'PURCHASE', 
        NOW(), 'COMPLETED', CONCAT('REF-', UUID())
    );
    
    COMMIT;
    SELECT 'Payment processed successfully' as message;
END IF;

-- Exercise 2: Optimistic Concurrency Control
-- First, add a version column to the Accounts table
ALTER TABLE Accounts ADD COLUMN Version INT DEFAULT 0;

-- Update implementation with version check
START TRANSACTION;

-- Read the current version
SELECT @current_version := Version 
FROM Accounts WHERE AccountID = 123;

-- Try to update with version check
UPDATE Accounts 
SET 
    Balance = Balance - 100.00,
    Version = Version + 1
WHERE 
    AccountID = 123 
    AND Version = @current_version;

-- Check if update succeeded
IF ROW_COUNT() = 0 THEN
    ROLLBACK;
    SELECT 'Concurrency conflict detected' as message;
ELSE
    -- Record the transaction
    INSERT INTO Transactions (/* ... */) VALUES (/* ... */);
    
    COMMIT;
    SELECT 'Transaction completed successfully' as message;
END IF;

-- Exercise 3: Isolation Levels Demonstration

-- Setup
CREATE TABLE TestConcurrency (id INT PRIMARY KEY, value INT);
INSERT INTO TestConcurrency VALUES (1, 100);

-- Session 1: READ UNCOMMITTED
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
SELECT value FROM TestConcurrency WHERE id = 1; -- Returns 100
-- Session 2 updates and doesn't commit
SELECT value FROM TestConcurrency WHERE id = 1; -- Will return 200 (dirty read)
COMMIT;

-- Session 2: Concurrent update
SET SESSION TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
START TRANSACTION;
UPDATE TestConcurrency SET value = 200 WHERE id = 1;
-- Don't commit yet

-- Session 1: READ COMMITTED
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT value FROM TestConcurrency WHERE id = 1; -- Returns 100
-- Session 2 updates and commits
SELECT value FROM TestConcurrency WHERE id = 1; -- Returns 200 (non-repeatable read)
COMMIT;

-- Session 1: REPEATABLE READ
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT value FROM TestConcurrency WHERE id = 1; -- Returns 100
-- Session 2 inserts a new row and commits
SELECT * FROM TestConcurrency WHERE value > 50; -- May show phantom row
COMMIT;

-- Session 1: SERIALIZABLE
SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
START TRANSACTION;
SELECT value FROM TestConcurrency WHERE id = 1; -- Returns 100
-- Session 2 tries to update same row but will be blocked until Session 1 commits
COMMIT;
```

**Interview Questions:**
1. Explain the differences between transaction isolation levels.
2. How would you handle a deadlock situation in a database?
3. What's the difference between pessimistic and optimistic concurrency control?

**Key Points:**
- Choose the appropriate isolation level based on your consistency requirements
- Be aware of the performance impact of higher isolation levels
- Always use transactions for operations that must be atomic
- Handle deadlocks gracefully in your application code

### HOUR 9: SQL in Payment Processing
**Learning Objectives:**
- Understand SQL application in financial systems
- Learn payment transaction data modeling
- Master fraud detection and reporting queries

**Concepts:**
- **Financial Data Management:**
  - Transaction logging and history
  - Account balance management
  - Audit trails and compliance
  - Reconciliation

- **Payment System Architecture:**
  - Authorization
  - Clearing and settlement
  - Dispute management
  - Merchant management

- **Security and Compliance:**
  - PCI DSS requirements
  - Data encryption
  - Sensitive data handling
  - Audit logging

**Practice Exercises:**
1. Write a query to find potentially fraudulent transactions based on unusual patterns.
2. Create a daily settlement report for merchants.
3. Design a stored procedure for handling chargebacks.

**Solutions:**
```sql
-- Exercise 1: Fraud Detection Query
-- Find multiple high-value transactions in short timeframe
SELECT 
    t.AccountID,
    a.CustomerID,
    COUNT(*) as transaction_count,
    SUM(t.Amount) as total_amount,
    MIN(t.TransactionDate) as first_transaction,
    MAX(t.TransactionDate) as last_transaction
FROM Transactions t
JOIN Accounts a ON t.AccountID = a.AccountID
WHERE 
    t.TransactionDate >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    AND t.Amount > 1000
GROUP BY t.AccountID, a.CustomerID
HAVING 
    COUNT(*) >= 3  -- Multiple transactions
    AND MAX(t.TransactionDate) - MIN(t.TransactionDate) <= 7200  -- Within 2 hours (in seconds)
ORDER BY total_amount DESC;

-- Find transactions from unusual locations
SELECT 
    t1.TransactionID,
    t1.AccountID,
    t1.Amount,
    t1.TransactionDate,
    t1.MerchantID,
    t1.Status,
    t1.ReferenceNumber,
    td1.DetailValue as CurrentLocation,
    td2.DetailValue as PreviousLocation,
    TIMESTAMPDIFF(MINUTE, t2.TransactionDate, t1.TransactionDate) as MinutesBetween
FROM 
    Transactions t1
JOIN TransactionDetails td1 
    ON t1.TransactionID = td1.TransactionID AND td1.DetailType = 'Location'
JOIN Transactions t2 
    ON t1.AccountID = t2.AccountID 
    AND t2.TransactionDate < t1.TransactionDate
JOIN TransactionDetails td2 
    ON t2.TransactionID = td2.TransactionID AND td2.DetailType = 'Location'
WHERE 
    t1.TransactionDate >= DATE_SUB(NOW(), INTERVAL 24 HOUR)
    AND td1.DetailValue != td2.DetailValue  -- Different locations
    AND TIMESTAMPDIFF(MINUTE, t2.TransactionDate, t1.TransactionDate) <= 180  -- Within 3 hours
    -- No other transactions between these two
    AND NOT EXISTS (
        SELECT 1 FROM Transactions t3
        WHERE t3.AccountID = t1.AccountID
        AND t3.TransactionDate > t2.TransactionDate
        AND t3.TransactionDate < t1.TransactionDate
    )
ORDER BY t1.TransactionDate;

-- Exercise 2: Daily Settlement Report
SELECT 
    m.MerchantID,
    m.MerchantName,
    COUNT(t.TransactionID) as transaction_count,
    SUM(CASE WHEN t.TransactionType = 'PURCHASE' THEN t.Amount ELSE 0 END) as total_purchases,
    SUM(CASE WHEN t.TransactionType = 'REFUND' THEN t.Amount ELSE 0 END) as total_refunds,
    SUM(CASE 
        WHEN t.TransactionType = 'PURCHASE' THEN t.Amount 
        WHEN t.TransactionType = 'REFUND' THEN -t.Amount
        ELSE 0 
    END) as net_settlement,
    SUM(CASE 
        WHEN t.TransactionType = 'PURCHASE' THEN t.Amount * 0.029  -- 2.9% fee
        ELSE 0 
    END) + COUNT(t.TransactionID) * 0.30 as processing_fees  -- $0.30 per transaction
FROM Merchants m
JOIN Transactions t ON m.MerchantID = t.MerchantID
WHERE 
    t.TransactionDate >= CURDATE()
    AND t.TransactionDate < DATE_ADD(CURDATE(), INTERVAL 1 DAY)
    AND t.Status = 'COMPLETED'
GROUP BY m.MerchantID, m.MerchantName
ORDER BY net_settlement DESC;

-- Exercise 3: Chargeback Stored Procedure
DELIMITER //

CREATE PROCEDURE ProcessChargeback(
    IN p_original_transaction_id INT,
    IN p_chargeback_amount DECIMAL(15, 2),
    IN p_chargeback_reason VARCHAR(100)
)
BEGIN
    DECLARE v_account_id INT;
    DECLARE v_merchant_id INT;
    DECLARE v_original_amount DECIMAL(15, 2);
    DECLARE v_reference_number VARCHAR(50);
    DECLARE v_new_transaction_id INT;
    
    -- Start transaction
    START TRANSACTION;
    
    -- Get details from original transaction
    SELECT 
        AccountID, 
        MerchantID, 
        Amount,
        ReferenceNumber
    INTO 
        v_account_id,
        v_merchant_id,
        v_original_amount,
        v_reference_number
    FROM Transactions
    WHERE TransactionID = p_original_transaction_id;
    
    -- Validate the chargeback amount doesn't exceed original
    IF p_chargeback_amount > v_original_amount THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Chargeback amount cannot exceed original transaction amount';
        ROLLBACK;
    ELSE
        -- Update original transaction status
        UPDATE Transactions
        SET Status = 'CHARGEBACK'
        WHERE TransactionID = p_original_transaction_id;
        
        -- Create chargeback transaction
        INSERT INTO Transactions (
            AccountID,
            MerchantID,
            Amount,
            TransactionType,
            TransactionDate,
            Status,
            ReferenceNumber
        ) VALUES (
            v_account_id,
            v_merchant_id,
            p_chargeback_amount,
            'CHARGEBACK',
            NOW(),
            'COMPLETED',
            CONCAT('CB-', v_reference_number)
        );
        
        -- Get the new transaction ID
        SET v_new_transaction_id = LAST_INSERT_ID();
        
        -- Add chargeback details
        INSERT INTO TransactionDetails (
            TransactionID,
            DetailType,
            DetailValue
        ) VALUES
        (v_new_transaction_id, 'CHARGEBACK_REASON', p_chargeback_reason),
        (v_new_transaction_id, 'ORIGINAL_TRANSACTION_ID', p_original_transaction_id);
        
        -- Refund money to customer account
        UPDATE Accounts
        SET Balance = Balance + p_chargeback_amount
        WHERE AccountID = v_account_id;
        
        -- Insert into dispute tracking table
        INSERT INTO Disputes (
            OriginalTransactionID,
            ChargebackTransactionID,
            DisputeAmount,
            DisputeReason,
            DisputeDate,
            Status
        ) VALUES (
            p_original_transaction_id,
            v_new_transaction_id,
            p_chargeback_amount,
            p_chargeback_reason,
            NOW(),
            'OPEN'
        );
        
        COMMIT;
    END IF;
END //

DELIMITER ;
```

**Interview Questions:**
1. How would you design a database schema for a payment processing system?
2. What SQL techniques would you use to detect fraudulent transactions?
3. How would you ensure data consistency in a high-volume payment system?

**Key Points:**
- Financial systems require high data integrity and strict transaction controls
- Performance optimization is critical for payment processing systems
- Security and compliance considerations must be built into the database design
- Complex fraud detection requires advanced SQL techniques like window functions and CTEs

### HOUR 9: Data Structures - Arrays and Linked Lists
**Learning Objectives:**
- Review array and linked list operations
- Understand time and space complexity
- Practice common interview problems

**Concepts:**
- **Arrays:**
  - Static vs. dynamic arrays
  - Random access: O(1)
  - Insertion/deletion at end: O(1) amortized
  - Insertion/deletion at middle: O(n)
  - Memory allocation: Contiguous

- **Linked Lists:**
  - Singly linked vs. doubly linked
  - Access: O(n)
  - Insertion/deletion at known position: O(1)
  - Memory allocation: Non-contiguous

**C++ Implementation:**
```cpp
// Implementing a singly linked list
template <typename T>
class LinkedList {
private:
    struct Node {
        T data;
        Node* next;
        Node(T value) : data(value), next(nullptr) {}
    };
    
    Node* head;
    Node* tail;
    size_t size;
    
public:
    LinkedList() : head(nullptr), tail(nullptr), size(0) {}
    
    ~LinkedList() {
        clear();
    }
    
    void push_front(T value) {
        Node* newNode = new Node(value);
        if (!head) {
            head = tail = newNode;
        } else {
            newNode->next = head;
            head = newNode;
        }
        size++;
    }
    
    void push_back(T value) {
        Node* newNode = new Node(value);
        if (!head) {
            head = tail = newNode;
        } else {
            tail->next = newNode;
            tail = newNode;
        }
        size++;
    }
    
    void pop_front() {
        if (!head) return;
        
        Node* temp = head;
        head = head->next;
        delete temp;
        size--;
        
        if (!head) tail = nullptr;
    }
    
    void insert(size_t position, T value) {
        if (position > size) return;
        
        if (position == 0) {
            push_front(value);
            return;
        }
        
        if (position == size) {
            push_back(value);
            return;
        }
        
        Node* current = head;
        for (size_t i = 0; i < position - 1; i++) {
            current = current->next;
        }
        
        Node* newNode = new Node(value);
        newNode->next = current->next;
        current->next = newNode;
        size++;
    }
    
    void clear() {
        while (head) {
            Node* temp = head;
            head = head->next;
            delete temp;
        }
        tail = nullptr;
        size = 0;
    }
    
    size_t getSize() const {
        return size;
    }
    
    bool isEmpty() const {
        return size == 0;
    }
    
    void display() const {
        Node* current = head;
        while (current) {
            std::cout << current->data << " -> ";
            current = current->next;
        }
        std::cout << "nullptr" << std::endl;
    }
};
```

**Practice Problems:**
1. Reverse a linked list
2. Detect a cycle in a linked list
3. Find the middle element of a linked list in one pass

**Solutions:**
```cpp
// Problem 1: Reverse a linked list
ListNode* reverseList(ListNode* head) {
    ListNode* prev = nullptr;
    ListNode* current = head;
    
    while (current != nullptr) {
        ListNode* nextTemp = current->next;
        current->next = prev;
        prev = current;
        current = nextTemp;
    }
    
    return prev;
}

// Problem 2: Detect a cycle in a linked list (Floyd's Tortoise and Hare)
bool hasCycle(ListNode* head) {
    if (!head || !head->next) return false;
    
    ListNode* slow = head;
    ListNode* fast = head;
    
    while (fast && fast->next) {
        slow = slow->next;        // Move one step
        fast = fast->next->next;  // Move two steps
        
        if (slow == fast) return true;  // Cycle detected
    }
    
    return false;  // No cycle
}

// Problem 3: Find middle element of a linked list
ListNode* middleNode(ListNode* head) {
    ListNode* slow = head;
    ListNode* fast = head;
    
    while (fast && fast->next) {
        slow = slow->next;       // Move one step
        fast = fast->next->next; // Move two steps
    }
    
    return slow;  // When fast reaches end, slow is at middle
}
```

**Interview Questions:**
1. What's the difference between an array and a linked list?
2. When would you choose a linked list over an array?
3. How would you implement a queue using a linked list?

**Key Points:**
- Arrays have O(1) random access but O(n) insertion/deletion in the middle
- Linked lists have O(1) insertion/deletion at a known position but O(n) access
- The two-pointer technique is useful for many linked list problems
- Linked lists are better for frequent insertions/deletions, arrays for random access

### HOUR 10: Data Structures - Stacks, Queues, and Hash Tables
**Learning Objectives:**
- Review implementation and operations of stacks and queues
- Understand hash table concepts and collision resolution
- Apply these data structures to solve problems

**Concepts:**
- **Stacks:**
  - LIFO (Last In, First Out)
  - Operations: push, pop, peek - all O(1)
  - Applications: function calls, expression evaluation, backtracking

- **Queues:**
  - FIFO (First In, First Out)
  - Operations: enqueue, dequeue, peek - all O(1)
  - Applications: BFS, task scheduling, request processing

- **Hash Tables:**
  - Direct addressing using a hash function
  - Collision resolution: chaining, open addressing
  - Average O(1) for insert, delete, search
  - Applications: caching, indexing, counting

**C++ Implementations:**
```cpp
// Stack implementation using a dynamic array
template <typename T>
class Stack {
private:
    std::vector<T> elements;
    
public:
    void push(T value) {
        elements.push_back(value);
    }
    
    void pop() {
        if (!empty()) {
            elements.pop_back();
        }
    }
    
    T top() const {
        if (empty()) {
            throw std::out_of_range("Stack is empty");
        }
        return elements.back();
    }
    
    bool empty() const {
        return elements.empty();
    }
    
    size_t size() const {
        return elements.size();
    }
};

// Queue implementation using a linked list
template <typename T>
class Queue {
private:
    struct Node {
        T data;
        Node* next;
        Node(T value) : data(value), next(nullptr) {}
    };
    
    Node* front;
    Node* rear;
    size_t size_;
    
public:
    Queue() : front(nullptr), rear(nullptr), size_(0) {}
    
    ~Queue() {
        while (!empty()) {
            dequeue();
        }
    }
    
    void enqueue(T value) {
        Node* newNode = new Node(value);
        
        if (empty()) {
            front = rear = newNode;
        } else {
            rear->next = newNode;
            rear = newNode;
        }
        
        size_++;
    }
    
    void dequeue() {
        if (empty()) return;
        
        Node* temp = front;
        front = front->next;
        delete temp;
        
        size_--;
        
        if (front == nullptr) {
            rear = nullptr;
        }
    }
    
    T peek() const {
        if (empty()) {
            throw std::out_of_range("Queue is empty");
        }
        return front->data;
    }
    
    bool empty() const {
        return size_ == 0;
    }
    
    size_t size() const {
        return size_;
    }
};

// Simple hash table implementation with chaining
template <typename K, typename V>
class HashTable {
private:
    static const size_t DEFAULT_SIZE = 16;
    
    struct KeyValue {
        K key;
        V value;
        KeyValue(const K& k, const V& v) : key(k), value(v) {}
    };
    
    std::vector<std::list<KeyValue>> buckets;
    size_t count;
    
    size_t hash(const K& key) const {
        return std::hash<K>{}(key) % buckets.size();
    }
    
public:
    HashTable() : buckets(DEFAULT_SIZE), count(0) {}
    
    void insert(const K& key, const V& value) {
        size_t index = hash(key);
        
        // Check if key already exists
        for (auto& kv : buckets[index]) {
            if (kv.key == key) {
                kv.value = value;  // Update value
                return;
            }
        }
        
        // Insert new key-value pair
        buckets[index].push_back(KeyValue(key, value));
        count++;
        
        // Resize if load factor exceeds 0.75
        if (count > buckets.size() * 0.75) {
            resize();
        }
    }
    
    bool get(const K& key, V& value) const {
        size_t index = hash(key);
        
        for (const auto& kv : buckets[index]) {
            if (kv.key == key) {
                value = kv.value;
                return true;
            }
        }
        
        return false;
    }
    
    bool remove(const K& key) {
        size_t index = hash(key);
        
        auto& bucket = buckets[index];
        for (auto it = bucket.begin(); it != bucket.end(); ++it) {
            if (it->key == key) {
                bucket.erase(it);
                count--;
                return true;
            }
        }
        
        return false;
    }
    
    bool contains(const K& key) const {
        size_t index = hash(key);
        
        for (const auto& kv : buckets[index]) {
            if (kv.key == key) {
                return true;
            }
        }
        
        return false;
    }
    
    size_t size() const {
        return count;
    }
    
private:
    void resize() {
        std::vector<std::list<KeyValue>> old_buckets = buckets;
        buckets.clear();
        buckets.resize(old_buckets.size() * 2);
        count = 0;
        
        for (const auto& bucket : old_buckets) {
            for (const auto& kv : bucket) {
                insert(kv.key, kv.value);
            }
        }
    }
};
```

**Practice Problems:**
1. Implement a queue using two stacks
2. Check if parentheses are balanced in an expression
3. Find the first non-repeating character in a string

**Solutions:**
```cpp
// Problem 1: Implement a queue using two stacks
class MyQueue {
private:
    std::stack<int> stackNewest;  // for push
    std::stack<int> stackOldest;  // for pop/peek
    
    // Move elements from stackNewest to stackOldest when needed
    void shiftStacks() {
        if (stackOldest.empty()) {
            while (!stackNewest.empty()) {
                stackOldest.push(stackNewest.top());
                stackNewest.pop();
            }
        }
    }
    
public:
    void push(int x) {
        stackNewest.push(x);
    }
    
    int pop() {
        shiftStacks();
        int val = stackOldest.top();
        stackOldest.pop();
        return val;
    }
    
    int peek() {
        shiftStacks();
        return stackOldest.top();
    }
    
    bool empty() {
        return stackNewest.empty() && stackOldest.empty();
    }
};

// Problem 2: Check if parentheses are balanced
bool isBalanced(const std::string& s) {
    std::stack<char> stack;
    
    for (char c : s) {
        if (c == '(' || c == '[' || c == '{') {
            stack.push(c);
        } else if (c == ')' || c == ']' || c == '}') {
            if (stack.empty()) {
                return false;
            }
            
            char top = stack.top();
            if ((c == ')' && top != '(') ||
                (c == ']' && top != '[') ||
                (c == '}' && top != '{')) {
                return false;
            }
            
            stack.pop();
        }
    }
    
    return stack.empty();
}

// Problem 3: First non-repeating character
int firstNonRepeatingChar(const std::string& s) {
    std::unordered_map<char, int> charCount;
    
    // Count occurrences of each character
    for (char c : s) {
        charCount[c]++;
    }
    
    // Find the first non-repeating character
    for (int i = 0; i < s.length(); i++) {
        if (charCount[s[i]] == 1) {
            return i;
        }
    }
    
    return -1;  // No non-repeating character found
}
```

**Interview Questions:**
1. What's the difference between a stack and a queue?
2. How would you implement a LRU (Least Recently Used) cache?
3. What are hash collisions and how do you handle them?

**Key Points:**
- Stacks are useful for tracking state in recursive algorithms
- Queues are essential for breadth-first search and level-order traversal
- Hash tables provide average O(1) lookup but worst-case can be O(n)
- The load factor of a hash table affects performance

### HOUR 11: Trees and Graphs
**Learning Objectives:**
- Understand tree and graph properties
- Master tree and graph traversal algorithms
- Apply these data structures to solve problems

**Concepts:**
- **Trees:**
  - Binary trees, binary search trees, balanced trees
  - Tree traversals: in-order, pre-order, post-order, level-order
  - Tree operations: insert, delete, search, balance

- **Graphs:**
  - Directed vs. undirected, weighted vs. unweighted
  - Representation: adjacency matrix, adjacency list
  - Graph traversals: depth-first search (DFS), breadth-first search (BFS)
  - Applications: shortest path, connectivity, cycle detection

**C++ Implementations:**
```cpp
// Binary Search Tree implementation
template <typename T>
class BinarySearchTree {
private:
    struct Node {
        T data;
        Node* left;
        Node* right;
        
        Node(T value) : data(value), left(nullptr), right(nullptr) {}
    };
    
    Node* root;
    
    // Helper recursive methods
    Node* insertRecursive(Node* node, T value) {
        if (node == nullptr) {
            return new Node(value);
        }
        
        if (value < node->data) {
            node->left = insertRecursive(node->left, value);
        } else if (value > node->data) {
            node->right = insertRecursive(node->right, value);
        }
        
        return node;
    }
    
    bool searchRecursive(Node* node, T value) const {
        if (node == nullptr) {
            return false;
        }
        
        if (node->data == value) {
            return true;
        }
        
        if (value < node->data) {
            return searchRecursive(node->left, value);
        } else {
            return searchRecursive(node->right, value);
        }
    }
    
    void inOrderTraversalRecursive(Node* node, std::vector<T>& result) const {
        if (node == nullptr) return;
        
        inOrderTraversalRecursive(node->left, result);
        result.push_back(node->data);
        inOrderTraversalRecursive(node->right, result);
    }
    
    void destroyTree(Node* node) {
        if (node == nullptr) return;
        
        destroyTree(node->left);
        destroyTree(node->right);
        delete node;
    }
    
public:
    BinarySearchTree() : root(nullptr) {}
    
    ~BinarySearchTree() {
        destroyTree(root);
    }
    
    void insert(T value) {
        root = insertRecursive(root, value);
    }
    
    bool search(T value) const {
        return searchRecursive(root, value);
    }
    
    std::vector<T> inOrderTraversal() const {
        std::vector<T> result;
        inOrderTraversalRecursive(root, result);
        return result;
    }
};

// Graph implementation using adjacency list
class Graph {
private:
    int V;  // Number of vertices
    std::vector<std::vector<int>> adj;  // Adjacency list
    
public:
    Graph(int vertices) : V(vertices), adj(vertices) {}
    
    void addEdge(int u, int v) {
        adj[u].push_back(v);
    }
    
    void DFS(int start) const {
        std::vector<bool> visited(V, false);
        DFSUtil(start, visited);
    }
    
    void DFSUtil(int vertex, std::vector<bool>& visited) const {
        visited[vertex] = true;
        std::cout << vertex << " ";
        
        for (int neighbor : adj[vertex]) {
            if (!visited[neighbor]) {
                DFSUtil(neighbor, visited);
            }
        }
    }
    
    void BFS(int start) const {
        std::vector<bool> visited(V, false);
        std::queue<int> queue;
        
        visited[start] = true;
        queue.push(start);
        
        while (!queue.empty()) {
            int vertex = queue.front();
            queue.pop();
            std::cout << vertex << " ";
            
            for (int neighbor : adj[vertex]) {
                if (!visited[neighbor]) {
                    visited[neighbor] = true;
                    queue.push(neighbor);
                }
            }
        }
    }
    
    bool hasCycle() const {
        std::vector<bool> visited(V, false);
        std::vector<bool> recursionStack(V, false);
        
        for (int i = 0; i < V; i++) {
            if (hasCycleUtil(i, visited, recursionStack)) {
                return true;
            }
        }
        
        return false;
    }
    
    bool hasCycleUtil(int vertex, std::vector<bool>& visited, 
                      std::vector<bool>& recursionStack) const {
        if (!visited[vertex]) {
            visited[vertex] = true;
            recursionStack[vertex] = true;
            
            for (int neighbor : adj[vertex]) {
                if (!visited[neighbor] && hasCycleUtil(neighbor, visited, recursionStack)) {
                    return true;
                } else if (recursionStack[neighbor]) {
                    return true;
                }
            }
        }
        
        recursionStack[vertex] = false;
        return false;
    }
};
```

**Practice Problems:**
1. Check if a binary tree is a binary search tree (BST)
2. Find the lowest common ancestor of two nodes in a binary tree
3. Implement topological sort for a directed acyclic graph (DAG)

**Solutions:**
```cpp
// Problem 1: Check if a binary tree is a BST
bool isBSTUtil(TreeNode* node, long min, long max) {
    if (node == nullptr) return true;
    
    if (node->val <= min || node->val >= max) return false;
    
    return isBSTUtil(node->left, min, node->val) &&
           isBSTUtil(node->right, node->val, max);
}

bool isBST(TreeNode* root) {
    return isBSTUtil(root, LONG_MIN, LONG_MAX);
}

// Problem 2: Lowest Common Ancestor
TreeNode* lowestCommonAncestor(TreeNode* root, TreeNode* p, TreeNode* q) {
    if (!root || root == p || root == q) return root;
    
    TreeNode* left = lowestCommonAncestor(root->left, p, q);
    TreeNode* right = lowestCommonAncestor(root->right, p, q);
    
    if (left && right) return root;  // p and q are on different sides
    
    return left ? left : right;  // Either one of p or q is in a subtree, or none
}

// Problem 3: Topological Sort
std::vector<int> topologicalSort(const Graph& graph, int V) {
    std::vector<int> result;
    std::vector<bool> visited(V, false);
    std::stack<int> stack;
    
    // Helper function for DFS
    std::function<void(int)> topologicalSortUtil = [&](int vertex) {
        visited[vertex] = true;
        
        // Recur for all adjacent vertices
        for (int neighbor : graph.getAdjacencyList()[vertex]) {
            if (!visited[neighbor]) {
                topologicalSortUtil(neighbor);
            }
        }
        
        // Push current vertex to stack after all its neighbors
        stack.push(vertex);
    };
    
    // Call the util function for all vertices
    for (int i = 0; i < V; i++) {
        if (!visited[i]) {
            topologicalSortUtil(i);
        }
    }
    
    // Pop from stack to get topological order
    while (!stack.empty()) {
        result.push_back(stack.top());
        stack.pop();
    }
    
    return result;
}
```

**Interview Questions:**
1. What's the difference between BFS and DFS traversal?
2. How would you detect a cycle in a directed graph?
3. What makes a binary search tree efficient for lookups?

**Key Points:**
- Tree traversals have different applications: in-order for sorted order, level-order for breadth-first, etc.
- Balanced trees (AVL, Red-Black) maintain O(log n) height for efficient operations
- Graph algorithms often use BFS for shortest paths in unweighted graphs
- Topological sort is useful for scheduling and dependency resolution

### HOUR 12: Algorithm Patterns and Problem Solving
**Learning Objectives:**
- Master common algorithm patterns for interviews
- Understand time and space complexity analysis
- Apply problem-solving strategies to new challenges

**Concepts:**
- **Common Algorithm Patterns:**
  - Two pointers
  - Sliding window
  - Binary search
  - Dynamic programming
  - Greedy algorithms
  - Backtracking

- **Problem-Solving Approach:**
  - Understand the problem
  - Identify relevant patterns
  - Formulate a solution
  - Analyze complexity
  - Test and optimize

**C++ Problem Patterns:**
```cpp
// Two Pointers pattern
bool isPalindrome(const std::string& s) {
    int left = 0, right = s.length() - 1;
    
    while (left < right) {
        if (s[left] != s[right]) {
            return false;
        }
        left++;
        right--;
    }
    
    return true;
}

// Sliding Window pattern
int maxSumSubarray(const std::vector<int>& nums, int k) {
    int n = nums.size();
    if (n < k) return -1;
    
    // Compute sum of first window
    int windowSum = 0;
    for (int i = 0; i < k; i++) {
        windowSum += nums[i];
    }
    
    int maxSum = windowSum;
    
    // Slide the window and update maxSum
    for (int i = k; i < n; i++) {
        windowSum = windowSum - nums[i - k] + nums[i];
        maxSum = std::max(maxSum, windowSum);
    }
    
    return maxSum;
}

// Binary Search pattern
int binarySearch(const std::vector<int>& nums, int target) {
    int left = 0, right = nums.size() - 1;
    
    while (left <= right) {
        int mid = left + (right - left) / 2;
        
        if (nums[mid] == target) {
            return mid;
        } else if (nums[mid] < target) {
            left = mid + 1;
        } else {
            right = mid - 1;
        }
    }
    
    return -1;  // Target not found
}

// Dynamic Programming - Memoization
int fibMemoized(int n, std::unordered_map<int, int>& memo) {
    if (n <= 1) return n;
    
    // Check if already computed
    if (memo.find(n) != memo.end()) {
        return memo[n];
    }
    
    // Calculate and store
    memo[n] = fibMemoized(n - 1, memo) + fibMemoized(n - 2, memo);
    return memo[n];
}

// Dynamic Programming - Tabulation
int fibTabulation(int n) {
    if (n <= 1) return n;
    
    std::vector<int> dp(n + 1);
    dp[0] = 0;
    dp[1] = 1;
    
    for (int i = 2; i <= n; i++) {
        dp[i] = dp[i - 1] + dp[i - 2];
    }
    
    return dp[n];
}
```

**Practice Problems:**
1. Find all pairs in an array that sum to a given target (Two Pointers)
2. Find the longest substring without repeating characters (Sliding Window)
3. Implement 0/1 Knapsack problem (Dynamic Programming)

**Solutions:**
```cpp
// Problem 1: Find all pairs with given sum
std::vector<std::pair<int, int>> findPairs(std::vector<int>& nums, int target) {
    std::vector<std::pair<int, int>> result;
    std::sort(nums.begin(), nums.end());
    
    int left = 0, right = nums.size() - 1;
    
    while (left < right) {
        int sum = nums[left] + nums[right];
        
        if (sum == target) {
            result.push_back({nums[left], nums[right]});
            left++;
            right--;
            
            // Skip duplicates
            while (left < right && nums[left] == nums[left - 1]) left++;
            while (left < right && nums[right] == nums[right + 1]) right--;
        } else if (sum < target) {
            left++;
        } else {
            right--;
        }
    }
    
    return result;
}

// Problem 2: Longest substring without repeating characters
int lengthOfLongestSubstring(const std::string& s) {
    int n = s.length();
    std::unordered_map<char, int> charIndex;
    int maxLength = 0;
    
    // Sliding window [left, right]
    for (int right = 0, left = 0; right < n; right++) {
        // If character is already in current window
        if (charIndex.find(s[right]) != charIndex.end()) {
            // Move left pointer to position after the same character
            left = std::max(left, charIndex[s[right]] + 1);
        }
        
        // Update character index
        charIndex[s[right]] = right;
        
        // Update max length
        maxLength = std::max(maxLength, right - left + 1);
    }
    
    return maxLength;
}

// Problem 3: 0/1 Knapsack
int knapsack(const std::vector<int>& weights, const std::vector<int>& values, int capacity) {
    int n = weights.size();
    std::vector<std::vector<int>> dp(n + 1, std::vector<int>(capacity + 1, 0));
    
    for (int i = 1; i <= n; i++) {
        for (int w = 1; w <= capacity; w++) {
            // If current item can fit in knapsack
            if (weights[i - 1] <= w) {
                // Max of including or excluding current item
                dp[i][w] = std::max(
                    values[i - 1] + dp[i - 1][w - weights[i - 1]],  // Include item
                    dp[i - 1][w]  // Exclude item
                );
            } else {
                // Item can't fit, so exclude it
                dp[i][w] = dp[i - 1][w];
            }
        }
    }
    
    return dp[n][capacity];
}
```

**Interview Questions:**
1. How would you approach a problem that seems to require checking all possible combinations?
2. What's the difference between greedy algorithms and dynamic programming?
3. When would you use recursion versus iteration in problem-solving?

**Key Points:**
- Identify patterns in problems to apply known techniques
- Time and space complexity are critical considerations
- Optimize solutions by exploring multiple approaches
- Test solutions with edge cases and large inputs

## 20 Most Common SQL Interview Questions

1. **What is the difference between DELETE and TRUNCATE?**
   - DELETE: DML command, can use WHERE clause, slower, logs individual row deletions
   - TRUNCATE: DDL command, removes all rows, faster, logs page deallocations, resets identity

2. **Explain the different types of JOINs in SQL.**
   - INNER JOIN: Returns rows when there are matches in both tables
   - LEFT JOIN: Returns all rows from left table and matching rows from right
   - RIGHT JOIN: Returns all rows from right table and matching rows from left
   - FULL OUTER JOIN: Returns rows when there's a match in one of the tables

3. **What are the differences between PRIMARY KEY and UNIQUE constraints?**
   - PRIMARY KEY: Cannot have NULL values, only one per table, creates clustered index by default
   - UNIQUE: Can have one NULL value, multiple per table, creates non-clustered index by default

4. **What is database normalization and what are the normal forms?**
   - Process of organizing data to minimize redundancy
   - 1NF: Eliminate repeating groups, atomic values
   - 2NF: Meet 1NF and remove partial dependencies
   - 3NF: Meet 2NF and remove transitive dependencies
   - BCNF: More stringent 3NF

5. **What is the difference between a clustered and non-clustered index?**
   - Clustered: Determines physical order of data in table, only one per table
   - Non-clustered: Doesn't alter physical order, maintains logical order with pointers, multiple per table

6. **Explain the difference between a view and a materialized view.**
   - View: Virtual table, query executed each time view is accessed
   - Materialized View: Physical copy of data, periodically refreshed, faster access

7. **What is a subquery? What are the types of subqueries?**
   - A query nested inside another query
   - Types: Scalar (returns single value), Row (single row), Table (multiple rows), Correlated (references outer query)

8. **What are window functions in SQL?**
   - Functions that perform calculations across rows related to current row
   - Examples: ROW_NUMBER(), RANK(), DENSE_RANK(), LEAD(), LAG()

9. **What is the difference between UNION and UNION ALL?**
   - UNION: Combines results and removes duplicates
   - UNION ALL: Combines results and keeps duplicates (faster)

10. **What is a CTE (Common Table Expression)?**
    - Named temporary result set within execution scope of a statement
    - Defined using WITH clause, can be recursive

11. **How can you avoid SQL injection?**
    - Use parameterized queries/prepared statements
    - Input validation
    - Escape special characters
    - Limit privileges of database account

12. **What is a transaction? Explain ACID properties.**
    - Unit of work that bundles multiple operations
    - ACID: Atomicity (all or nothing), Consistency (valid state to valid state), Isolation (transactions don't interfere), Durability (committed changes persist)

13. **What are the different transaction isolation levels?**
    - READ UNCOMMITTED: Allows dirty reads
    - READ COMMITTED: Prevents dirty reads
    - REPEATABLE READ: Prevents non-repeatable reads
    - SERIALIZABLE: Prevents phantom reads

14. **How do you optimize SQL queries?**
    - Use appropriate indexes
    - Avoid SELECT *
    - Use JOINs instead of subqueries when possible
    - Limit result sets
    - Optimize WHERE clauses

15. **What is a self-join? When would you use it?**
    - Joining a table to itself
    - Used for hierarchical data (employee-manager), comparing rows within same table

16. **Explain the difference between HAVING and WHERE clauses.**
    - WHERE: Filters individual rows before grouping
    - HAVING: Filters groups after GROUP BY clause

17. **What is a stored procedure? What are its advantages?**
    - Precompiled SQL statements stored in database
    - Advantages: Reusability, security, modularity, performance

18. **How would you find duplicate values in a table?**
    ```sql
    SELECT column, COUNT(column)
    FROM table
    GROUP BY column
    HAVING COUNT(column) > 1;
    ```

19. **What is an index? How does it improve performance?**
    - Data structure that improves speed of data retrieval
    - Creates a reference structure using B-tree, bitmap, or hash table
    - Improves performance by reducing disk I/O and full table scans

20. **How would you get the Nth highest salary from a table?**
    ```sql
    -- Using OFFSET
    SELECT salary
    FROM (
        SELECT DISTINCT salary
        FROM employees
        ORDER BY salary DESC
        LIMIT 1 OFFSET N-1
    ) AS result;
    
    -- Using subquery count
    SELECT salary
    FROM employees e1
    WHERE N-1 = (
        SELECT COUNT(DISTINCT salary)
        FROM employees e2
        WHERE e2.salary > e1.salary
    );
    ```

## 10 Practical SQL Problems

1. **Find employees who earn more than their manager:**
   ```sql
   SELECT e.employee_name
   FROM employees e
   JOIN employees m ON e.manager_id = m.employee_id
   WHERE e.salary > m.salary;
   ```

2. **Calculate the running total of orders by date:**
   ```sql
   SELECT 
       order_date,
       amount,
       SUM(amount) OVER (ORDER BY order_date) as running_total
   FROM orders;
   ```

3. **Find departments with more than 10 employees:**
   ```sql
   SELECT department, COUNT(*) as employee_count
   FROM employees
   GROUP BY department
   HAVING COUNT(*) > 10;
   ```

4. **Find customers who haven't placed an order in the last 3 months:**
   ```sql
   SELECT c.customer_id, c.customer_name
   FROM customers c
   LEFT JOIN orders o ON c.customer_id = o.customer_id
   AND o.order_date >= DATE_SUB(CURDATE(), INTERVAL 3 MONTH)
   WHERE o.order_id IS NULL;
   ```

5. **Calculate the median salary for each department:**
   ```sql
   -- MySQL
   SELECT 
       department,
       x.salary as median_salary
   FROM 
       (SELECT 
           department,
           salary,
           ROW_NUMBER() OVER (PARTITION BY department ORDER BY salary) as row_num,
           COUNT(*) OVER (PARTITION BY department) as cnt
       FROM employees) as x
   WHERE 
       x.row_num IN (FLOOR((x.cnt+1)/2), CEIL((x.cnt+1)/2));
   ```

6. **Find products that have been ordered by all customers:**
   ```sql
   SELECT p.product_id, p.product_name
   FROM products p
   WHERE NOT EXISTS (
       SELECT c.customer_id
       FROM customers c
       WHERE NOT EXISTS (
           SELECT o.order_id
           FROM orders o
           JOIN order_details od ON o.order_id = od.order_id
           WHERE o.customer_id = c.customer_id
           AND od.product_id = p.product_id
       )
   );
   ```

7. **Identify dormant accounts (no activity in the last 6 months):**
   ```sql
   SELECT a.account_id, a.customer_id
   FROM accounts a
   LEFT JOIN transactions t ON a.account_id = t.account_id
   AND t.transaction_date >= DATE_SUB(CURDATE(), INTERVAL 6 MONTH)
   WHERE t.transaction_id IS NULL
   AND a.status = 'Active';
   ```

8. **Find the top 3 selling products in each category:**
   ```sql
   WITH product_sales AS (
       SELECT 
           p.product_id,
           p.product_name,
           p.category_id,
           SUM(od.quantity) as total_quantity,
           DENSE_RANK() OVER (PARTITION BY p.category_id ORDER BY SUM(od.quantity) DESC) as rank
       FROM products p
       JOIN order_details od ON p.product_id = od.product_id
       GROUP BY p.product_id, p.product_name, p.category_id
   )
   SELECT 
       product_id,
       product_name,
       category_id,
       total_quantity
   FROM product_sales
   WHERE rank <= 3
   ORDER BY category_id, rank;
   ```

9. **Find customers who have spent more than average:**
   ```sql
   WITH customer_spending AS (
       SELECT 
           c.customer_id,
           c.customer_name,
           SUM(o.amount) as total_spent
       FROM customers c
       JOIN orders o ON c.customer_id = o.customer_id
       GROUP BY c.customer_id, c.customer_name
   ),
   avg_spending AS (
       SELECT AVG(total_spent) as avg_amount
       FROM customer_spending
   )
   SELECT 
       cs.customer_id,
       cs.customer_name,
       cs.total_spent
   FROM customer_spending cs, avg_spending
   WHERE cs.total_spent > avg_spending.avg_amount
   ORDER BY cs.total_spent DESC;
   ```

10. **Calculate month-over-month growth rate for each product:**
    ```sql
    WITH monthly_sales AS (
        SELECT 
            EXTRACT(YEAR FROM o.order_date) as year,
            EXTRACT(MONTH FROM o.order_date) as month,
            p.product_id,
            p.product_name,
            SUM(od.quantity * od.unit_price) as monthly_revenue
        FROM orders o
        JOIN order_details od ON o.order_id = od.order_id
        JOIN products p ON od.product_id = p.product_id
        GROUP BY year, month, p.product_id, p.product_name
    )
    SELECT 
        current_month.year,
        current_month.month,
        current_month.product_id,
        current_month.product_name,
        current_month.monthly_revenue,
        prev_month.monthly_revenue as prev_month_revenue,
        CASE 
            WHEN prev_month.monthly_revenue IS NULL OR prev_month.monthly_revenue = 0 
            THEN NULL
            ELSE (current_month.monthly_revenue - prev_month.monthly_revenue) / prev_month.monthly_revenue * 100 
        END as growth_rate
    FROM monthly_sales current_month
    LEFT JOIN monthly_sales prev_month ON
        current_month.product_id = prev_month.product_id
        AND (
            (current_month.month = prev_month.month + 1 AND current_month.year = prev_month.year)
            OR
            (current_month.month = 1 AND prev_month.month = 12 AND current_month.year = prev_month.year + 1)
        )
    ORDER BY current_month.year, current_month.month, growth_rate DESC;
    ```

## 5 Database Design Scenarios

1. **E-commerce Platform:**
   - Entities: Users, Products, Categories, Orders, Order_Items, Reviews, Payments, Shipping
   - Relationships:
     - Users place many Orders (1:M)
     - Products belong to Categories (M:M via Category_Products)
     - Orders contain Order_Items (1:M)
     - Products have Reviews (1:M)
     - Orders have Payments (1:M)
     - Orders have Shipping information (1:1)

2. **Hospital Management System:**
   - Entities: Patients, Doctors, Departments, Appointments, Medical_Records, Medications, Prescriptions
   - Relationships:
     - Patients schedule Appointments with Doctors (M:M)
     - Doctors belong to Departments (M:1)
     - Patients have Medical_Records (1:M)
     - Doctors write Prescriptions for Patients (M:M)
     - Prescriptions include Medications (M:M via Prescription_Medications)

3. **Financial Payment Processing System:**
   - Entities: Customers, Accounts, Transactions, Merchants, Cards, Fees, Disputes
   - Relationships:
     - Customers own Accounts (1:M)
     - Accounts have Transactions (1:M)
     - Merchants receive Transactions (1:M)
     - Accounts have Cards (1:M)
     - Transactions may have Fees (1:M)
     - Transactions may have Disputes (1:1)

4. **Library Management System:**
   - Entities: Books, Authors, Members, Loans, Reservations, Publishers, Categories
   - Relationships:
     - Books are written by Authors (M:M via Book_Authors)
     - Members borrow Books through Loans (M:M)
     - Members make Reservations for Books (M:M)
     - Books are published by Publishers (M:1)
     - Books belong to Categories (M:M via Book_Categories)

5. **Project Management System:**
   - Entities: Projects, Tasks, Users, Teams, Comments, Attachments, Time_Entries
   - Relationships:
     - Projects contain Tasks (1:M)
     - Users are assigned to Tasks (M:M via Task_Assignments)
     - Users belong to Teams (M:M via Team_Members)
     - Tasks have Comments (1:M)
     - Tasks have Attachments (1:M)
     - Users log Time_Entries for Tasks (1:M)

## SQL Cheat Sheet

### Basic Queries
```sql
-- Select all columns
SELECT * FROM table_name;

-- Select specific columns
SELECT column1, column2 FROM table_name;

-- Select with condition
SELECT column1, column2 FROM table_name WHERE condition;

-- Select with ordering
SELECT column1, column2 FROM table_name ORDER BY column1 [ASC|DESC];

-- Select with limit
SELECT column1, column2 FROM table_name LIMIT n;

-- Select distinct values
SELECT DISTINCT column FROM table_name;

-- Count rows
SELECT COUNT(*) FROM table_name;

-- Group by with aggregation
SELECT column1, COUNT(*) FROM table_name GROUP BY column1;

-- Having clause
SELECT column1, COUNT(*) FROM table_name GROUP BY column1 HAVING COUNT(*) > 5;
```

### Joins
```sql
-- Inner join
SELECT a.column, b.column
FROM table_a a
INNER JOIN table_b b ON a.key = b.key;

-- Left join
SELECT a.column, b.column
FROM table_a a
LEFT JOIN table_b b ON a.key = b.key;

-- Right join
SELECT a.column, b.column
FROM table_a a
RIGHT JOIN table_b b ON a.key = b.key;

-- Full outer join
SELECT a.column, b.column
FROM table_a a
FULL OUTER JOIN table_b b ON a.key = b.key;

-- Self join
SELECT a.column, b.column
FROM table_name a
JOIN table_name b ON a.key = b.parent_key;
```

### Subqueries
```sql
-- Subquery in WHERE
SELECT column
FROM table_name
WHERE column = (SELECT MAX(column) FROM table_name);

-- Subquery in FROM
SELECT avg_value
FROM (SELECT AVG(column) as avg_value FROM table_name GROUP BY group_column) as derived;

-- Subquery in SELECT
SELECT column1, (SELECT COUNT(*) FROM table_b WHERE table_b.key = table_a.key) as count
FROM table_a;

-- EXISTS subquery
SELECT column
FROM table_a
WHERE EXISTS (SELECT 1 FROM table_b WHERE table_b.key = table_a.key);
```

### Common Table Expressions (CTEs)
```sql
-- Basic CTE
WITH cte_name AS (
    SELECT column1, column2
    FROM table_name
    WHERE condition
)
SELECT * FROM cte_name;

-- Multiple CTEs
WITH cte1 AS (
    SELECT column1, column2 FROM table1
),
cte2 AS (
    SELECT column1, column2 FROM table2
)
SELECT cte1.column1, cte2.column2
FROM cte1
JOIN cte2 ON cte1.key = cte2.key;

-- Recursive CTE
WITH RECURSIVE cte_name AS (
    -- Base case
    SELECT column1, column2
    FROM table_name
    WHERE condition
    
    UNION ALL
    
    -- Recursive case
    SELECT t.column1, t.column2
    FROM table_name t
    JOIN cte_name c ON t.parent_key = c.key
)
SELECT * FROM cte_name;
```

### Window Functions
```sql
-- Basic window function
SELECT 
    column1,
    column2,
    AVG(column2) OVER() as overall_avg
FROM table_name;

-- Window function with PARTITION BY
SELECT 
    column1,
    column2,
    AVG(column2) OVER(PARTITION BY column1) as group_avg
FROM table_name;

-- Window function with ORDER BY
SELECT 
    column1,
    column2,
    SUM(column2) OVER(ORDER BY column1) as running_total
FROM table_name;

-- Ranking functions
SELECT 
    column1,
    column2,
    ROW_NUMBER() OVER(PARTITION BY column1 ORDER BY column2) as row_num,
    RANK() OVER(PARTITION BY column1 ORDER BY column2) as rank,
    DENSE_RANK() OVER(PARTITION BY column1 ORDER BY column2) as dense_rank
FROM table_name;

-- Lead and lag functions
SELECT 
    column1,
    column2,
    LEAD(column2, 1) OVER(ORDER BY column1) as next_value,
    LAG(column2, 1) OVER(ORDER BY column1) as prev_value
FROM table_name;
```

### Transactions
```sql
-- Basic transaction
START TRANSACTION;
-- SQL statements
COMMIT;

-- Transaction with rollback
START TRANSACTION;
-- SQL statements
IF error_condition THEN
    ROLLBACK;
ELSE
    COMMIT;
END IF;

-- Transaction with savepoint
START TRANSACTION;
-- SQL statements
SAVEPOINT my_savepoint;
-- More SQL statements
ROLLBACK TO my_savepoint;
-- More SQL statements
COMMIT;
```

### Indexes
```sql
-- Create index
CREATE INDEX index_name ON table_name (column);

-- Create unique index
CREATE UNIQUE INDEX index_name ON table_name (column);

-- Create composite index
CREATE INDEX index_name ON table_name (column1, column2);

-- Drop index
DROP INDEX index_name ON table_name;
```

### Views
```sql
-- Create view
CREATE VIEW view_name AS
SELECT column1, column2
FROM table_name
WHERE condition;

-- Create or replace view
CREATE OR REPLACE VIEW view_name AS
SELECT column1, column2
FROM table_name
WHERE condition;

-- Drop view
DROP VIEW view_name;
```

## DSA Quick Reference

### Time Complexity
```
O(1)      - Constant time: Array access, simple calculations
O(log n)  - Logarithmic: Binary search, balanced BST operations
O(n)      - Linear: Simple loops, linear search
O(n log n)- Linearithmic: Efficient sorting (merge sort, heap sort)
O(n²)     - Quadratic: Nested loops, bubble/insertion/selection sort
O(2^n)    - Exponential: Recursive solutions without memoization
```

### Array Operations
```cpp
// Initialize arrays
int arr[5] = {1, 2, 3, 4, 5};
vector<int> vec = {1, 2, 3, 4, 5};

// Common vector operations
vec.push_back(6);        // Add element to end
vec.pop_back();          // Remove last element
vec.size();              // Get size
vec.empty();             // Check if empty
vec.insert(vec.begin() + 2, 10);  // Insert at position
vec.erase(vec.begin() + 2);       // Erase at position
vec.clear();             // Remove all elements

// Sorting
sort(vec.begin(), vec.end());                  // Ascending
sort(vec.begin(), vec.end(), greater<int>());  // Descending

// Searching
bool found = binary_search(vec.begin(), vec.end(), value);
auto it = find(vec.begin(), vec.end(), value);
int count = count(vec.begin(), vec.end(), value);

// Min/max elements
auto min_it = min_element(vec.begin(), vec.end());
auto max_it = max_element(vec.begin(), vec.end());
```

### Linked List Operations
```cpp
// Definition for singly-linked list
struct ListNode {
    int val;
    ListNode *next;
    ListNode() : val(0), next(nullptr) {}
    ListNode(int x) : val(x), next(nullptr) {}
    ListNode(int x, ListNode *next) : val(x), next(next) {}
};

// Traversal
void traverse(ListNode* head) {
    while (head) {
        cout << head->val << " ";
        head = head->next;
    }
}

// Insert at beginning
ListNode* insertBegin(ListNode* head, int val) {
    ListNode* newNode = new ListNode(val);
    newNode->next = head;
    return newNode;
}

// Insert at end
ListNode* insertEnd(ListNode* head, int val) {
    ListNode* newNode = new ListNode(val);
    if (!head) return newNode;
    
    ListNode* curr = head;
    while (curr->next) {
        curr = curr->next;
    }
    curr->next = newNode;
    return head;
}

// Delete a node (not tail) in O(1)
void deleteNode(ListNode* node) {
    node->val = node->next->val;
    ListNode* temp = node->next;
    node->next = node->next->next;
    delete temp;
}
```

### Stack and Queue Operations
```cpp
// Stack
stack<int> s;
s.push(1);       // Add to top
s.pop();         // Remove from top
s.top();         // Access top
s.empty();       // Check if empty
s.size();        // Get size

// Queue
queue<int> q;
q.push(1);       // Add to back
q.pop();         // Remove from front
q.front();       // Access front
q.back();        // Access back
q.empty();       // Check if empty
q.size();        // Get size

// Priority Queue (default: max heap)
priority_queue<int> maxHeap;
maxHeap.push(1);     // Add element
maxHeap.top();       // Access top (max element)
maxHeap.pop();       // Remove top

// Min heap
priority_queue<int, vector<int>, greater<int>> minHeap;
```

### Tree Operations
```cpp
// Definition for binary tree
struct TreeNode {
    int val;
    TreeNode *left;
    TreeNode *right;
    TreeNode() : val(0), left(nullptr), right(nullptr) {}
    TreeNode(int x) : val(x), left(nullptr), right(nullptr) {}
    TreeNode(int x, TreeNode *left, TreeNode *right) : val(x), left(left), right(right) {}
};

// Tree traversals
void inorderTraversal(TreeNode* root) {
    if (!root) return;
    inorderTraversal(root->left);
    cout << root->val << " ";
    inorderTraversal(root->right);
}

void preorderTraversal(TreeNode* root) {
    if (!root) return;
    cout << root->val << " ";
    preorderTraversal(root->left);
    preorderTraversal(root->right);
}

void postorderTraversal(TreeNode* root) {
    if (!root) return;
    postorderTraversal(root->left);
    postorderTraversal(root->right);
    cout << root->val << " ";
}

// Level order traversal (BFS)
vector<vector<int>> levelOrder(TreeNode* root) {
    vector<vector<int>> result;
    if (!root) return result;
    
    queue<TreeNode*> q;
    q.push(root);
    
    while (!q.empty()) {
        int size = q.size();
        vector<int> level;
        
        for (int i = 0; i < size; i++) {
            TreeNode* node = q.front();
            q.pop();
            
            level.push_back(node->val);
            
            if (node->left) q.push(node->left);
            if (node->right) q.push(node->right);
        }
        
        result.push_back(level);
    }
    
    return result;
}
```

### Graph Operations
```cpp
// Adjacency list representation
vector<vector<int>> adjList(n);
adjList[0].push_back(1);  // Edge from 0 to 1

// DFS
void dfs(vector<vector<int>>& adjList, int node, vector<bool>& visited) {
    visited[node] = true;
    cout << node << " ";
    
    for (int neighbor : adjList[node]) {
        if (!visited[neighbor]) {
            dfs(adjList, neighbor, visited);
        }
    }
}

// BFS
void bfs(vector<vector<int>>& adjList, int start) {
    vector<bool> visited(adjList.size(), false);
    queue<int> q;
    
    visited[start] = true;
    q.push(start);
    
    while (!q.empty()) {
        int node = q.front();
        q.pop();
        cout << node << " ";
        
        for (int neighbor : adjList[node]) {
            if (!visited[neighbor]) {
                visited[neighbor] = true;
                q.push(neighbor);
            }
        }
    }
}
```

### Common Algorithm Patterns

#### 1. Two Pointers
```cpp
// Find if a sorted array has a pair with target sum
bool hasPairWithSum(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size() - 1;
    
    while (left < right) {
        int sum = nums[left] + nums[right];
        
        if (sum == target) {
            return true;
        } else if (sum < target) {
            left++;
        } else {
            right--;
        }
    }
    
    return false;
}
```

#### 2. Sliding Window
```cpp
// Find maximum sum subarray of size k
int maxSumSubarray(vector<int>& nums, int k) {
    int n = nums.size();
    if (n < k) return -1;
    
    int maxSum = 0;
    int windowSum = 0;
    
    // Compute sum of first window
    for (int i = 0; i < k; i++) {
        windowSum += nums[i];
    }
    
    maxSum = windowSum;
    
    // Slide window and update maxSum
    for (int i = k; i < n; i++) {
        windowSum = windowSum - nums[i - k] + nums[i];
        maxSum = max(maxSum, windowSum);
    }
    
    return maxSum;
}
```

#### 3. Binary Search
```cpp
// Binary search in sorted array
int binarySearch(vector<int>& nums, int target) {
    int left = 0;
    int right = nums.size() - 1;
    
    while (left <= right) {
        int mid = left + (right - left) / 2;
        
        if (nums[mid] == target) {
            return mid;  // Target found
        } else if (nums[mid] < target) {
            left = mid + 1;  // Search right half
        } else {
            right = mid - 1;  // Search left half
        }
    }
    
    return -1;  // Target not found
}
```

#### 4. Dynamic Programming
```cpp
// 0/1 Knapsack problem
int knapsack(vector<int>& weights, vector<int>& values, int capacity) {
    int n = weights.size();
    vector<vector<int>> dp(n + 1, vector<int>(capacity + 1, 0));
    
    for (int i = 1; i <= n; i++) {
        for (int w = 1; w <= capacity; w++) {
            // If current item can fit
            if (weights[i - 1] <= w) {
                // Max of including or excluding current item
                dp[i][w] = max(
                    values[i - 1] + dp[i - 1][w - weights[i - 1]], // Include
                    dp[i - 1][w]  // Exclude
                );
            } else {
                // Item can't fit, so exclude it
                dp[i][w] = dp[i - 1][w];
            }
        }
    }
    
    return dp[n][capacity];
}
```

#### 5. Backtracking
```cpp
// Generate all subsets
void generateSubsets(vector<int>& nums, vector<vector<int>>& result, vector<int>& subset, int index) {
    result.push_back(subset);
    
    for (int i = index; i < nums.size(); i++) {
        // Include current element
        subset.push_back(nums[i]);
        
        // Recurse with next index
        generateSubsets(nums, result, subset, i + 1);
        
        // Backtrack (exclude current element)
        subset.pop_back();
    }
}

vector<vector<int>> subsets(vector<int>& nums) {
    vector<vector<int>> result;
    vector<int> subset;
    generateSubsets(nums, result, subset, 0);
    return result;
}
```
