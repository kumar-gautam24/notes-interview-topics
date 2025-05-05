# SQL From Scratch: The Complete Command Guide


# SQL Keywords and Usage Reference Guide

## Table of Contents
1. [Data Types](#data-types)
2. [Constraints](#constraints)
3. [Database Objects Management](#database-objects-management)
4. [Table Operations](#table-operations)
5. [Column Modifications](#column-modifications)
6. [Checking Object Existence](#checking-object-existence)
7. [Query Building Keywords](#query-building-keywords)
8. [Transaction Control](#transaction-control)

## Data Types

### String Data Types

| Data Type | Description | Syntax | Example |
|-----------|-------------|--------|---------|
| `CHAR` | Fixed-length string | `CHAR(size)` | `CHAR(10)` - Stores exactly 10 characters, padded with spaces if needed |
| `VARCHAR` | Variable-length string | `VARCHAR(max_size)` | `VARCHAR(100)` - Stores up to 100 characters, uses only needed space |
| `TEXT` | Large text data | `TEXT` | Used for large documents, comments, etc. |
| `ENUM` | String object with value from allowed list | `ENUM('value1', 'value2', ...)` | `ENUM('small', 'medium', 'large')` |

**Notes on VARCHAR**:
- `VARCHAR` is the most commonly used string type
- Only uses the space actually needed (plus 1-2 bytes to store length)
- Maximum size varies by database system (MySQL: up to 65,535 characters)
- More efficient than `CHAR` for columns with variable length content

### Numeric Data Types

| Data Type | Description | Syntax | Example |
|-----------|-------------|--------|---------|
| `INT` | Integer (whole number) | `INT` | Typically -2^31 to 2^31-1 |
| `TINYINT` | Very small integer | `TINYINT` | -128 to 127 |
| `SMALLINT` | Small integer | `SMALLINT` | -32,768 to 32,767 |
| `MEDIUMINT` | Medium integer | `MEDIUMINT` | -8,388,608 to 8,388,607 |
| `BIGINT` | Large integer | `BIGINT` | -2^63 to 2^63-1 |
| `DECIMAL` | Fixed-point number | `DECIMAL(p,s)` | `DECIMAL(10,2)` - Up to 10 digits with 2 after decimal point |
| `FLOAT` | Single-precision float | `FLOAT(p)` | Approximate numeric values |
| `DOUBLE` | Double-precision float | `DOUBLE(p,s)` | Higher precision than FLOAT |

**Notes on DECIMAL**:
- `DECIMAL(10,2)` can store values from -99999999.99 to 99999999.99
- First parameter (p) is precision - total number of digits
- Second parameter (s) is scale - digits after decimal point

### Date and Time Data Types

| Data Type | Description | Format | Example |
|-----------|-------------|--------|---------|
| `DATE` | Date only | 'YYYY-MM-DD' | '2023-05-15' |
| `TIME` | Time only | 'HH:MM:SS' | '14:30:00' |
| `DATETIME` | Date and time | 'YYYY-MM-DD HH:MM:SS' | '2023-05-15 14:30:00' |
| `TIMESTAMP` | Date and time, stored as seconds from epoch | 'YYYY-MM-DD HH:MM:SS' | Automatically updates on record changes |
| `YEAR` | Year only | YYYY | 2023 |

### Other Data Types

| Data Type | Description | Example Use Case |
|-----------|-------------|-----------------|
| `BOOLEAN/BOOL` | True or False | Flags, status indicators |
| `BLOB` | Binary Large Object | Store binary data like images |
| `JSON` | JSON formatted data | Store structured data |
| `UUID` | Universally Unique Identifier | Globally unique identifiers |

## Constraints

### PRIMARY KEY
Makes a column (or set of columns) the unique identifier for the table. Cannot contain NULL values.

```sql
CREATE TABLE employees (
    employee_id INT PRIMARY KEY,  -- Single column primary key
    first_name VARCHAR(50)
);

-- OR --

CREATE TABLE order_items (
    order_id INT,
    product_id INT,
    quantity INT,
    PRIMARY KEY (order_id, product_id)  -- Composite primary key
);
```

### AUTO_INCREMENT
Automatically generates a unique number when a new record is inserted. Used with the PRIMARY KEY constraint.

```sql
CREATE TABLE employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,  -- Will automatically assign 1, 2, 3, etc.
    name VARCHAR(100)
);
```

**How AUTO_INCREMENT works**:
- Starts at 1 by default (can be changed)
- Increments by 1 for each new record
- If a row is deleted, its number is not reused (by default)
- Different syntax in other database systems:
  - SQL Server: `IDENTITY(seed, increment)`
  - PostgreSQL: `SERIAL` or `GENERATED AS IDENTITY`
  - Oracle: Sequence objects or `IDENTITY` (12c+)

### NOT NULL
Ensures a column cannot contain NULL values.

```sql
CREATE TABLE employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,  -- Must always have a value
    middle_name VARCHAR(50),          -- Can be NULL (optional)
    last_name VARCHAR(50) NOT NULL    -- Must always have a value
);
```

**When to use NOT NULL**:
- Required fields that must have a value
- Fields used in calculations or important operations
- Improves query performance (no need to check for NULL)
- Makes database design more robust

### UNIQUE
Ensures all values in a column are unique.

```sql
CREATE TABLE users (
    user_id INT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(100) UNIQUE,  -- No two users can have the same email
    username VARCHAR(50) UNIQUE  -- No two users can have the same username
);
```

### DEFAULT
Provides a default value when no value is specified.

```sql
CREATE TABLE orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT NOT NULL,
    order_date DATETIME DEFAULT CURRENT_TIMESTAMP,  -- Uses current time if not specified
    status VARCHAR(20) DEFAULT 'Pending'  -- Uses 'Pending' if not specified
);
```

### CHECK
Ensures values in a column meet a specific condition.

```sql
CREATE TABLE products (
    product_id INT PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(100) NOT NULL,
    price DECIMAL(10, 2) CHECK (price > 0),  -- Price must be positive
    stock INT CHECK (stock >= 0)  -- Stock cannot be negative
);
```

### FOREIGN KEY
Creates a link between tables by referencing a PRIMARY KEY in another table.

```sql
CREATE TABLE orders (
    order_id INT PRIMARY KEY AUTO_INCREMENT,
    customer_id INT,
    order_date DATE,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);
```

## Database Objects Management

### Creating a Database

```sql
-- Basic create
CREATE DATABASE my_database;

-- With character set and collation
CREATE DATABASE my_database
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

-- Create only if it doesn't exist
CREATE DATABASE IF NOT EXISTS my_database;
```

### Dropping a Database

```sql
-- Delete database
DROP DATABASE my_database;

-- Delete only if it exists
DROP DATABASE IF EXISTS my_database;
```

### Creating a Table

```sql
CREATE TABLE employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL,
    last_name VARCHAR(50) NOT NULL,
    email VARCHAR(100) UNIQUE,
    hire_date DATE,
    department VARCHAR(50),
    salary DECIMAL(10, 2)
);
```

### Dropping a Table

```sql
-- Remove table
DROP TABLE employees;

-- Remove only if it exists
DROP TABLE IF EXISTS employees;
```

### Truncating a Table
Removes all data but keeps the structure.

```sql
TRUNCATE TABLE employees;
```

## Table Operations

### Altering Tables

```sql
-- Add a new column
ALTER TABLE employees ADD COLUMN phone VARCHAR(20);

-- Drop a column
ALTER TABLE employees DROP COLUMN phone;

-- Modify a column
ALTER TABLE employees MODIFY COLUMN last_name VARCHAR(100) NOT NULL;

-- Rename a table
RENAME TABLE employees TO staff;
-- OR
ALTER TABLE employees RENAME TO staff;
```

### Creating Indexes

```sql
-- Create a basic index
CREATE INDEX idx_lastname ON employees(last_name);

-- Create a unique index
CREATE UNIQUE INDEX idx_email ON employees(email);

-- Create a composite index
CREATE INDEX idx_name ON employees(last_name, first_name);
```

### Dropping Indexes

```sql
DROP INDEX idx_lastname ON employees;
```

## Column Modifications

### Adding Constraints

```sql
-- Add primary key
ALTER TABLE employees ADD PRIMARY KEY (employee_id);

-- Add foreign key
ALTER TABLE employees 
ADD CONSTRAINT fk_department 
FOREIGN KEY (department_id) REFERENCES departments(department_id);

-- Add unique constraint
ALTER TABLE employees ADD CONSTRAINT uc_email UNIQUE (email);

-- Add check constraint
ALTER TABLE employees ADD CONSTRAINT chk_salary CHECK (salary > 0);
```

### Dropping Constraints

```sql
-- Drop primary key
ALTER TABLE employees DROP PRIMARY KEY;

-- Drop foreign key
ALTER TABLE employees DROP FOREIGN KEY fk_department;

-- Drop unique constraint
ALTER TABLE employees DROP CONSTRAINT uc_email;

-- Drop check constraint
ALTER TABLE employees DROP CONSTRAINT chk_salary;
```

## Checking Object Existence

### Checking Database Existence

```sql
-- MySQL approach
SELECT SCHEMA_NAME 
FROM INFORMATION_SCHEMA.SCHEMATA 
WHERE SCHEMA_NAME = 'database_name';

-- Alternative approach
SHOW DATABASES LIKE 'database_name';

-- In procedural code (MySQL)
IF EXISTS (SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = 'database_name') THEN
    -- Database exists
ELSE
    -- Database doesn't exist
END IF;
```

### Checking Table Existence

```sql
-- Standard SQL approach
SELECT TABLE_NAME 
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'database_name' 
AND TABLE_NAME = 'table_name';

-- MySQL approach
SHOW TABLES LIKE 'table_name';

-- In procedural code or scripts
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
           WHERE TABLE_SCHEMA = 'database_name' 
           AND TABLE_NAME = 'table_name') THEN
    -- Table exists
ELSE
    -- Table doesn't exist
END IF;
```

### Checking Column Existence

```sql
-- Standard SQL approach
SELECT COLUMN_NAME 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_SCHEMA = 'database_name' 
AND TABLE_NAME = 'table_name' 
AND COLUMN_NAME = 'column_name';

-- MySQL approach for listing all columns
SHOW COLUMNS FROM table_name LIKE 'column_name';

-- In conditional operations
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS 
           WHERE TABLE_SCHEMA = 'database_name' 
           AND TABLE_NAME = 'table_name' 
           AND COLUMN_NAME = 'column_name') THEN
    -- Column exists
ELSE
    -- Column doesn't exist
END IF;
```

### Creating Objects Conditionally

```sql
-- Create table only if it doesn't exist
CREATE TABLE IF NOT EXISTS employees (
    employee_id INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(50) NOT NULL
);

-- Add column only if it doesn't exist (using procedure)
DELIMITER //
CREATE PROCEDURE add_column_if_not_exists()
BEGIN
    IF NOT EXISTS (
        SELECT * FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'employees' 
        AND COLUMN_NAME = 'phone'
    ) THEN
        ALTER TABLE employees ADD COLUMN phone VARCHAR(20);
    END IF;
END //
DELIMITER ;

CALL add_column_if_not_exists();
```

## Query Building Keywords

### SELECT Statement Components

```sql
SELECT column1, column2
FROM table_name
WHERE condition
GROUP BY column_name
HAVING group_condition
ORDER BY column_name [ASC|DESC]
LIMIT row_count OFFSET offset_value;
```

### JOIN Types

```sql
-- Inner join
SELECT e.name, d.department_name
FROM employees e
INNER JOIN departments d ON e.department_id = d.department_id;

-- Left join
SELECT e.name, d.department_name
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id;

-- Right join
SELECT e.name, d.department_name
FROM employees e
RIGHT JOIN departments d ON e.department_id = d.department_id;

-- Full outer join (not in MySQL, can be simulated)
SELECT e.name, d.department_name
FROM employees e
LEFT JOIN departments d ON e.department_id = d.department_id
UNION
SELECT e.name, d.department_name
FROM employees e
RIGHT JOIN departments d ON e.department_id = d.department_id
WHERE e.department_id IS NULL;
```

### Subqueries

```sql
-- Subquery in WHERE
SELECT name 
FROM employees
WHERE department_id IN (SELECT department_id FROM departments WHERE location = 'New York');

-- Subquery in FROM
SELECT avg_dept.department_id, avg_dept.avg_salary
FROM (
    SELECT department_id, AVG(salary) as avg_salary
    FROM employees
    GROUP BY department_id
) AS avg_dept;

-- Correlated subquery
SELECT e1.name, e1.salary
FROM employees e1
WHERE salary > (
    SELECT AVG(salary)
    FROM employees e2
    WHERE e2.department_id = e1.department_id
);
```

## Transaction Control

### Managing Transactions

```sql
-- Start a transaction
START TRANSACTION;

-- Execute statements
INSERT INTO accounts (account_id, balance) VALUES (1, 1000);
UPDATE accounts SET balance = balance - 500 WHERE account_id = 1;
INSERT INTO transactions (account_id, amount, type) VALUES (1, 500, 'withdrawal');

-- Commit if all succeeds
COMMIT;

-- Or rollback if there's an issue
ROLLBACK;
```

### Savepoints

```sql
START TRANSACTION;

INSERT INTO accounts (account_id, balance) VALUES (1, 1000);

SAVEPOINT step1;

UPDATE accounts SET balance = balance - 500 WHERE account_id = 1;

-- If needed, rollback to savepoint
ROLLBACK TO step1;

-- Or commit all changes
COMMIT;
```

### Transaction Isolation Levels

```sql
-- Set transaction isolation level
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Available levels:
-- READ UNCOMMITTED - Lowest isolation, dirty reads possible
-- READ COMMITTED - Prevents dirty reads
-- REPEATABLE READ - Prevents non-repeatable reads
-- SERIALIZABLE - Highest isolation, prevents phantom reads
```

## Introduction

SQL (Structured Query Language) is the standard language for managing and manipulating relational databases. This guide will take you from absolute beginner to proficient SQL user with detailed explanations, examples, and optimization tips for every major SQL command.

## Table of Contents
- [Basic Queries](#basic-queries)
- [Filtering Data](#filtering-data)
- [Sorting and Limiting](#sorting-and-limiting)
- [Joins](#joins)
- [Aggregation Functions](#aggregation-functions)
- [Grouping Data](#grouping-data)
- [Subqueries](#subqueries)
- [Common Table Expressions](#common-table-expressions)
- [Window Functions](#window-functions)
- [Data Manipulation](#data-manipulation)
- [Data Definition](#data-definition)
- [Indexes](#indexes)
- [Transactions](#transactions)
- [Views](#views)
- [Stored Procedures](#stored-procedures)
- [Optimization Techniques](#optimization-techniques)

## Basic Queries

### SELECT Statement

The `SELECT` statement is the cornerstone of SQL queries. It retrieves data from one or more tables.

**Basic Syntax:**
```sql
SELECT column1, column2, ... 
FROM table_name;
```

**Selecting All Columns:**
```sql
SELECT * FROM employees;
```

**Selecting Specific Columns:**
```sql
SELECT employee_id, first_name, last_name FROM employees;
```

**Column Aliases:**
```sql
SELECT 
    first_name AS "First Name",
    last_name AS "Last Name",
    hire_date AS "Start Date"
FROM employees;
```

**Computed Columns:**
```sql
SELECT 
    product_name,
    unit_price,
    units_in_stock,
    unit_price * units_in_stock AS inventory_value
FROM products;
```

**DISTINCT Keyword:**
Removes duplicate values from the result set.
```sql
SELECT DISTINCT department FROM employees;
```

**Concatenation:**
```sql
-- MySQL/PostgreSQL
SELECT 
    CONCAT(first_name, ' ', last_name) AS full_name
FROM employees;

-- Oracle
SELECT 
    first_name || ' ' || last_name AS full_name
FROM employees;

-- SQL Server
SELECT 
    first_name + ' ' + last_name AS full_name
FROM employees;
```

**Tips:**
- Avoid `SELECT *` in production code - specify only needed columns
- Use descriptive column aliases for clarity
- DISTINCT can be resource-intensive on large tables

## Filtering Data

### WHERE Clause

The `WHERE` clause filters results based on specified conditions.

**Basic Syntax:**
```sql
SELECT column1, column2, ...
FROM table_name
WHERE condition;
```

**Comparison Operators:**
```sql
-- Equal to
SELECT * FROM products WHERE category_id = 1;

-- Not equal to
SELECT * FROM products WHERE category_id <> 1;

-- Greater than
SELECT * FROM products WHERE unit_price > 20;

-- Less than
SELECT * FROM products WHERE unit_price < 20;

-- Greater than or equal to
SELECT * FROM products WHERE unit_price >= 20;

-- Less than or equal to
SELECT * FROM products WHERE unit_price <= 20;
```

**Logical Operators:**
```sql
-- AND
SELECT * 
FROM products 
WHERE category_id = 1 AND unit_price > 20;

-- OR
SELECT * 
FROM products 
WHERE category_id = 1 OR category_id = 2;

-- NOT
SELECT * 
FROM products 
WHERE NOT category_id = 1;
```

**BETWEEN Operator:**
```sql
SELECT * 
FROM products 
WHERE unit_price BETWEEN 10 AND 20;
```

**IN Operator:**
```sql
SELECT * 
FROM products 
WHERE category_id IN (1, 2, 3);
```

**LIKE Operator:**
```sql
-- Names starting with 'A'
SELECT * 
FROM employees 
WHERE last_name LIKE 'A%';

-- Names ending with 'son'
SELECT * 
FROM employees 
WHERE last_name LIKE '%son';

-- Names containing 'an'
SELECT * 
FROM employees 
WHERE last_name LIKE '%an%';

-- Names with exactly 5 characters
SELECT * 
FROM employees 
WHERE last_name LIKE '_____';

-- Second character is 'a'
SELECT * 
FROM employees 
WHERE last_name LIKE '_a%';
```

**IS NULL / IS NOT NULL:**
```sql
-- Find employees without a manager
SELECT * 
FROM employees 
WHERE manager_id IS NULL;

-- Find employees with a manager
SELECT * 
FROM employees 
WHERE manager_id IS NOT NULL;
```

**Tips:**
- Place most restrictive conditions first for better performance
- Consider using EXISTS instead of IN for subqueries
- Avoid functions on columns in WHERE clauses as they prevent index usage
- Use parameterized queries to prevent SQL injection

## Sorting and Limiting

### ORDER BY Clause

The `ORDER BY` clause sorts the result set.

**Basic Syntax:**
```sql
SELECT column1, column2, ...
FROM table_name
ORDER BY column1 [ASC|DESC], column2 [ASC|DESC], ...;
```

**Sorting Examples:**
```sql
-- Sort by last name in ascending order (default)
SELECT * FROM employees ORDER BY last_name;

-- Sort by last name in descending order
SELECT * FROM employees ORDER BY last_name DESC;

-- Multiple sort criteria
SELECT * 
FROM employees 
ORDER BY department ASC, salary DESC;

-- Sort by column position
SELECT employee_id, first_name, last_name
FROM employees
ORDER BY 3; -- Sorts by last_name (3rd column)

-- Sort by alias
SELECT first_name, last_name, first_name || ' ' || last_name AS full_name
FROM employees
ORDER BY full_name;

-- Sort with NULL values
SELECT * 
FROM employees 
ORDER BY hire_date NULLS FIRST; -- PostgreSQL, Oracle
```

### LIMIT / OFFSET (TOP / FETCH)

These clauses limit the number of rows returned.

**MySQL, PostgreSQL, SQLite:**
```sql
-- Return first 10 rows
SELECT * FROM employees LIMIT 10;

-- Skip 10 rows and return next 10
SELECT * FROM employees LIMIT 10 OFFSET 10;
```

**SQL Server:**
```sql
-- SQL Server 2012+
SELECT * FROM employees
ORDER BY employee_id
OFFSET 10 ROWS
FETCH NEXT 10 ROWS ONLY;

-- Older SQL Server
SELECT TOP 10 * FROM employees;
```

**Oracle:**
```sql
-- Oracle 12c+
SELECT * FROM employees
FETCH FIRST 10 ROWS ONLY;

-- Skip 10 rows and return next 10
SELECT * FROM employees
OFFSET 10 ROWS FETCH NEXT 10 ROWS ONLY;

-- Older Oracle
SELECT * FROM employees
WHERE ROWNUM <= 10;
```

**Tips:**
- Always include ORDER BY with LIMIT for consistent results
- Use LIMIT with OFFSET for pagination
- Be careful with large OFFSET values (performance degrades)

## Joins

Joins combine rows from two or more tables based on a related column.

### INNER JOIN

Returns rows when there is a match in both tables.

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM 
    employees e
INNER JOIN 
    departments d ON e.department_id = d.department_id;
```

### LEFT JOIN (LEFT OUTER JOIN)

Returns all rows from the left table and matched rows from the right table.

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM 
    employees e
LEFT JOIN 
    departments d ON e.department_id = d.department_id;
```

### RIGHT JOIN (RIGHT OUTER JOIN)

Returns all rows from the right table and matched rows from the left table.

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM 
    employees e
RIGHT JOIN 
    departments d ON e.department_id = d.department_id;
```

### FULL JOIN (FULL OUTER JOIN)

Returns rows when there is a match in one of the tables.

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM 
    employees e
FULL JOIN 
    departments d ON e.department_id = d.department_id;
```

### CROSS JOIN

Returns the Cartesian product of two tables.

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    d.department_name
FROM 
    employees e
CROSS JOIN 
    departments d;
```

### SELF JOIN

A join of a table to itself.

```sql
SELECT 
    e.first_name || ' ' || e.last_name AS employee,
    m.first_name || ' ' || m.last_name AS manager
FROM 
    employees e
LEFT JOIN 
    employees m ON e.manager_id = m.employee_id;
```

### Multiple Joins

```sql
SELECT 
    o.order_id,
    c.customer_name,
    e.first_name || ' ' || e.last_name AS employee,
    p.product_name,
    od.quantity,
    od.unit_price
FROM 
    orders o
JOIN 
    customers c ON o.customer_id = c.customer_id
JOIN 
    employees e ON o.employee_id = e.employee_id
JOIN 
    order_details od ON o.order_id = od.order_id
JOIN 
    products p ON od.product_id = p.product_id;
```

### NATURAL JOIN

Joins tables based on columns with the same name.

```sql
SELECT * 
FROM employees 
NATURAL JOIN departments;
```

**Tips:**
- Always use table aliases in joins for readability
- Be careful with NATURAL JOINs as they can lead to unexpected results
- LEFT JOIN is often safer than INNER JOIN when data integrity isn't guaranteed
- Consider indexing join columns for performance
- Use multiple smaller joins rather than one large join when possible

## Aggregation Functions

Aggregation functions perform calculations on a set of values and return a single value.

### COUNT

Counts the number of rows.

```sql
-- Count all rows
SELECT COUNT(*) FROM employees;

-- Count non-NULL values in a column
SELECT COUNT(manager_id) FROM employees;

-- Count distinct values
SELECT COUNT(DISTINCT department_id) FROM employees;
```

### SUM

Calculates the sum of a numeric column.

```sql
SELECT SUM(salary) FROM employees;

-- With condition
SELECT SUM(salary) 
FROM employees 
WHERE department_id = 10;
```

### AVG

Calculates the average of a numeric column.

```sql
SELECT AVG(salary) FROM employees;

-- Handling NULL values
SELECT AVG(COALESCE(commission_pct, 0)) FROM employees;
```

### MIN and MAX

Find minimum and maximum values.

```sql
SELECT 
    MIN(salary) AS lowest_salary,
    MAX(salary) AS highest_salary
FROM employees;

-- Works with dates too
SELECT 
    MIN(hire_date) AS earliest_hire,
    MAX(hire_date) AS latest_hire
FROM employees;
```

### Statistical Functions

```sql
-- Standard deviation
SELECT STDDEV(salary) FROM employees;

-- Variance
SELECT VARIANCE(salary) FROM employees;

-- Population standard deviation
SELECT STDDEV_POP(salary) FROM employees;

-- Sample standard deviation
SELECT STDDEV_SAMP(salary) FROM employees;
```

**Tips:**
- Aggregate functions ignore NULL values (except COUNT(*))
- Use COALESCE or IFNULL to handle NULL values
- Consider performance impact of DISTINCT with aggregates
- Create indexes on commonly used aggregation columns

## Grouping Data

### GROUP BY Clause

Groups rows that have the same values into summary rows.

```sql
SELECT 
    department_id,
    COUNT(*) AS employee_count
FROM 
    employees
GROUP BY 
    department_id;
```

**Multiple Grouping Columns:**
```sql
SELECT 
    department_id,
    job_id,
    COUNT(*) AS employee_count,
    AVG(salary) AS avg_salary
FROM 
    employees
GROUP BY 
    department_id, job_id;
```

**Grouping with Expressions:**
```sql
-- Group by year
SELECT 
    EXTRACT(YEAR FROM hire_date) AS hire_year,
    COUNT(*) AS employee_count
FROM 
    employees
GROUP BY 
    EXTRACT(YEAR FROM hire_date);
```

### HAVING Clause

Filters groups based on aggregate conditions.

```sql
SELECT 
    department_id,
    COUNT(*) AS employee_count
FROM 
    employees
GROUP BY 
    department_id
HAVING 
    COUNT(*) > 5;
```

**Combining WHERE and HAVING:**
```sql
SELECT 
    department_id,
    AVG(salary) AS avg_salary
FROM 
    employees
WHERE 
    job_id <> 'IT_PROG'
GROUP BY 
    department_id
HAVING 
    AVG(salary) > 8000;
```

### ROLLUP

Generates subtotals and grand totals.

```sql
SELECT 
    department_id,
    job_id,
    SUM(salary) AS total_salary
FROM 
    employees
GROUP BY 
    ROLLUP(department_id, job_id);
```

### CUBE

Generates subtotals and grand totals for all combinations of grouping columns.

```sql
SELECT 
    department_id,
    job_id,
    SUM(salary) AS total_salary
FROM 
    employees
GROUP BY 
    CUBE(department_id, job_id);
```

### GROUPING SETS

Specifies multiple grouping sets in a single query.

```sql
SELECT 
    department_id,
    job_id,
    SUM(salary) AS total_salary
FROM 
    employees
GROUP BY 
    GROUPING SETS (
        (department_id, job_id),
        (department_id),
        (job_id),
        ()
    );
```

**Tips:**
- Use WHERE to filter rows before grouping
- Use HAVING to filter groups after grouping
- Always include all non-aggregated columns in GROUP BY
- For complex groupings, consider using CTEs first for clarity
- ROLLUP, CUBE, and GROUPING SETS are not available in all DBMS

## Subqueries

A subquery is a query nested inside another query.

### Subqueries in WHERE Clause

```sql
-- Employees with salary higher than average
SELECT employee_id, first_name, last_name, salary
FROM employees
WHERE salary > (SELECT AVG(salary) FROM employees);

-- Employees in the Sales department
SELECT employee_id, first_name, last_name
FROM employees
WHERE department_id = (
    SELECT department_id 
    FROM departments 
    WHERE department_name = 'Sales'
);
```

### Subqueries with IN, ANY, ALL

```sql
-- Employees in IT or HR departments
SELECT employee_id, first_name, last_name
FROM employees
WHERE department_id IN (
    SELECT department_id 
    FROM departments 
    WHERE department_name IN ('IT', 'HR')
);

-- Employees with salary greater than ANY sales employee
SELECT employee_id, first_name, last_name, salary
FROM employees
WHERE salary > ANY (
    SELECT salary 
    FROM employees 
    WHERE department_id = 80
);

-- Employees with salary greater than ALL sales employees
SELECT employee_id, first_name, last_name, salary
FROM employees
WHERE salary > ALL (
    SELECT salary 
    FROM employees 
    WHERE department_id = 80
);
```

### Correlated Subqueries

Subqueries that reference columns from the outer query.

```sql
-- Employees with salary higher than their department average
SELECT e1.employee_id, e1.first_name, e1.last_name, e1.salary
FROM employees e1
WHERE e1.salary > (
    SELECT AVG(e2.salary)
    FROM employees e2
    WHERE e2.department_id = e1.department_id
);
```

### Subqueries in FROM Clause

```sql
-- Department salary statistics
SELECT 
    d.department_name,
    dept_stats.employee_count,
    dept_stats.avg_salary
FROM 
    departments d
JOIN (
    SELECT 
        department_id,
        COUNT(*) AS employee_count,
        AVG(salary) AS avg_salary
    FROM employees
    GROUP BY department_id
) dept_stats ON d.department_id = dept_stats.department_id;
```

### Subqueries in SELECT Clause

```sql
SELECT 
    e.employee_id,
    e.first_name,
    e.last_name,
    e.salary,
    (SELECT AVG(salary) FROM employees) AS company_avg_salary,
    e.salary - (SELECT AVG(salary) FROM employees) AS salary_diff
FROM employees e;
```

### EXISTS and NOT EXISTS

```sql
-- Departments with at least one employee
SELECT department_id, department_name
FROM departments d
WHERE EXISTS (
    SELECT 1 
    FROM employees e 
    WHERE e.department_id = d.department_id
);

-- Departments with no employees
SELECT department_id, department_name
FROM departments d
WHERE NOT EXISTS (
    SELECT 1 
    FROM employees e 
    WHERE e.department_id = d.department_id
);
```

**Tips:**
- Use EXISTS instead of IN for checking existence (usually more efficient)
- Correlated subqueries can be performance-intensive
- Consider using JOINs instead of subqueries in the FROM clause
- Scalar subqueries (returning a single value) are often more efficient than row subqueries

## Common Table Expressions

Common Table Expressions (CTEs) provide a way to create named temporary result sets.

### Basic CTE

```sql
WITH employee_counts AS (
    SELECT 
        department_id,
        COUNT(*) AS employee_count
    FROM employees
    GROUP BY department_id
)
SELECT 
    d.department_name,
    ec.employee_count
FROM 
    departments d
JOIN 
    employee_counts ec ON d.department_id = ec.department_id
ORDER BY 
    ec.employee_count DESC;
```

### Multiple CTEs

```sql
WITH 
    dept_counts AS (
        SELECT 
            department_id,
            COUNT(*) AS employee_count
        FROM employees
        GROUP BY department_id
    ),
    dept_salaries AS (
        SELECT 
            department_id,
            SUM(salary) AS total_salary,
            AVG(salary) AS avg_salary
        FROM employees
        GROUP BY department_id
    )
SELECT 
    d.department_name,
    dc.employee_count,
    ds.total_salary,
    ds.avg_salary
FROM 
    departments d
JOIN 
    dept_counts dc ON d.department_id = dc.department_id
JOIN 
    dept_salaries ds ON d.department_id = ds.department_id;
```

### Recursive CTEs

Used for hierarchical or recursive queries.

```sql
-- Employee hierarchy
WITH RECURSIVE emp_hierarchy AS (
    -- Base case: top-level employees (no manager)
    SELECT 
        employee_id, 
        first_name, 
        last_name, 
        manager_id, 
        1 AS level
    FROM employees
    WHERE manager_id IS NULL
    
    UNION ALL
    
    -- Recursive case: employees with managers
    SELECT 
        e.employee_id, 
        e.first_name, 
        e.last_name, 
        e.manager_id, 
        eh.level + 1
    FROM 
        employees e
    JOIN 
        emp_hierarchy eh ON e.manager_id = eh.employee_id
)
SELECT 
    employee_id,
    CONCAT(REPEAT('    ', level - 1), first_name, ' ', last_name) AS employee_hierarchy
FROM 
    emp_hierarchy
ORDER BY 
    level, first_name, last_name;
```

**Tips:**
- Use CTEs to break down complex queries into simpler parts
- CTEs can improve readability compared to nested subqueries
- Be careful with recursive CTEs - always include a termination condition
- CTEs are calculated for each reference, unlike views or temporary tables
- Consider materializing large CTEs into temporary tables for repeated use

## Window Functions

Window functions perform calculations across rows related to the current row.

### Window Function Basics

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    salary,
    AVG(salary) OVER() AS avg_company_salary
FROM 
    employees;
```

### PARTITION BY

Divides rows into partitions.

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    salary,
    AVG(salary) OVER(PARTITION BY department_id) AS avg_department_salary,
    salary - AVG(salary) OVER(PARTITION BY department_id) AS diff_from_avg
FROM 
    employees;
```

### ORDER BY in Window Functions

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    hire_date,
    salary,
    SUM(salary) OVER(ORDER BY hire_date) AS running_total_salary
FROM 
    employees;
```

### Combining PARTITION BY and ORDER BY

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    hire_date,
    salary,
    SUM(salary) OVER(
        PARTITION BY department_id 
        ORDER BY hire_date
    ) AS dept_running_total
FROM 
    employees;
```

### Window Frame Clause

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    hire_date,
    salary,
    AVG(salary) OVER(
        PARTITION BY department_id 
        ORDER BY hire_date
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ) AS moving_avg_salary
FROM 
    employees;
```

### Ranking Functions

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    salary,
    RANK() OVER(PARTITION BY department_id ORDER BY salary DESC) AS dept_salary_rank,
    DENSE_RANK() OVER(PARTITION BY department_id ORDER BY salary DESC) AS dept_salary_dense_rank,
    ROW_NUMBER() OVER(PARTITION BY department_id ORDER BY salary DESC) AS dept_salary_row_num
FROM 
    employees;
```

### Analytic Functions

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    hire_date,
    salary,
    LEAD(salary, 1) OVER(PARTITION BY department_id ORDER BY hire_date) AS next_hire_salary,
    LAG(salary, 1) OVER(PARTITION BY department_id ORDER BY hire_date) AS prev_hire_salary,
    FIRST_VALUE(salary) OVER(PARTITION BY department_id ORDER BY hire_date) AS first_hire_salary,
    LAST_VALUE(salary) OVER(
        PARTITION BY department_id 
        ORDER BY hire_date
        RANGE BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_hire_salary
FROM 
    employees;
```

### NTILE Function

Divides rows into specified number of groups.

```sql
SELECT 
    employee_id,
    first_name,
    last_name,
    department_id,
    salary,
    NTILE(4) OVER(ORDER BY salary) AS salary_quartile
FROM 
    employees;
```

**Tips:**
- Window functions are calculated after WHERE, GROUP BY, and HAVING
- Use appropriate window frames for correct results
- Window functions can often replace self-joins and complex subqueries
- RANGE vs ROWS: RANGE is logical, ROWS is physical
- Consider performance implications for large datasets

## Data Manipulation

### INSERT Statement

Adds new rows to a table.

```sql
-- Insert a single row
INSERT INTO employees (
    employee_id,
    first_name,
    last_name,
    email,
    hire_date,
    job_id,
    salary
) VALUES (
    207,
    'John',
    'Doe',
    'JDOE',
    '2023-01-15',
    'IT_PROG',
    6000
);

-- Insert multiple rows
INSERT INTO employees (
    employee_id,
    first_name,
    last_name,
    email,
    hire_date,
    job_id,
    salary
) VALUES 
    (207, 'John', 'Doe', 'JDOE', '2023-01-15', 'IT_PROG', 6000),
    (208, 'Jane', 'Smith', 'JSMITH', '2023-01-20', 'IT_PROG', 6200);

-- Insert with select
INSERT INTO employee_archive
SELECT * FROM employees
WHERE termination_date IS NOT NULL;
```

### UPDATE Statement

Modifies existing rows.

```sql
-- Update all rows
UPDATE employees
SET salary = salary * 1.1;

-- Update with condition
UPDATE employees
SET 
    salary = salary * 1.1,
    commission_pct = commission_pct + 0.05
WHERE 
    department_id = 80;

-- Update with subquery
UPDATE employees
SET salary = (
    SELECT AVG(salary) FROM employees
    WHERE department_id = 80
)
WHERE job_id = 'SA_REP';

-- Update with join (syntax varies by DBMS)
-- MySQL/MariaDB
UPDATE employees e
JOIN departments d ON e.department_id = d.department_id
SET e.salary = e.salary * 1.15
WHERE d.department_name = 'IT';

-- SQL Server
UPDATE e
SET e.salary = e.salary * 1.15
FROM employees e
JOIN departments d ON e.department_id = d.department_id
WHERE d.department_name = 'IT';
```

### DELETE Statement

Removes rows from a table.

```sql
-- Delete all rows
DELETE FROM temp_employees;

-- Delete with condition
DELETE FROM employees
WHERE hire_date < '2000-01-01';

-- Delete with subquery
DELETE FROM employees
WHERE department_id IN (
    SELECT department_id
    FROM departments
    WHERE department_name LIKE '%Temp%'
);

-- Delete with join (syntax varies by DBMS)
-- MySQL/MariaDB
DELETE e
FROM employees e
JOIN departments d ON e.department_id = d.department_id
WHERE d.location_id = 1700;

-- SQL Server
DELETE e
FROM employees e
JOIN departments d ON e.department_id = d.department_id
WHERE d.location_id = 1700;
```

### MERGE Statement

Performs insert, update, or delete operations based on a condition.

```sql
-- Oracle, SQL Server, DB2
MERGE INTO employees e
USING employee_updates u
ON (e.employee_id = u.employee_id)
WHEN MATCHED THEN
    UPDATE SET
        e.salary = u.salary,
        e.commission_pct = u.commission_pct,
        e.manager_id = u.manager_id
WHEN NOT MATCHED THEN
    INSERT (employee_id, first_name, last_name, email, hire_date, job_id, salary)
    VALUES (u.employee_id, u.first_name, u.last_name, u.email, u.hire_date, u.job_id, u.salary);
```

**Tips:**
- Use transactions for complex data modifications
- Consider impact on constraints and triggers
- MERGE is more efficient than separate INSERT/UPDATE operations
- Use batch operations for large data modifications
- Consider using prepared statements for performance

## Data Definition

### CREATE TABLE

Creates a new table.

```sql
CREATE TABLE employees (
    employee_id NUMBER(6) PRIMARY KEY,
    first_name VARCHAR2(20),
    last_name VARCHAR2(25) NOT NULL,
    email VARCHAR2(25) UNIQUE,
    phone_number VARCHAR2(20),
    hire_date DATE NOT NULL,
    job_id VARCHAR2(10) NOT NULL,
    salary NUMBER(8,2) CHECK (salary > 0),
    commission_pct NUMBER(2,2),
    manager_id NUMBER(6) REFERENCES employees(employee_id),
    department_id NUMBER(4) REFERENCES departments(department_id)
);
```

### Create Table As Select (CTAS)

```sql
CREATE TABLE employee_archive AS
SELECT * FROM employees
WHERE hire_date < '2000-01-01';
```

### ALTER TABLE

Modifies an existing table structure.

```sql
-- Add column
ALTER TABLE employees
ADD (last_login_date DATE);

-- Modify column
ALTER TABLE employees
MODIFY (last_name VARCHAR2(50));

-- Drop column
ALTER TABLE employees
DROP COLUMN last_login_date;

-- Rename column
ALTER TABLE employees
RENAME COLUMN phone_number TO contact_number;

-- Add constraint
ALTER TABLE employees
ADD CONSTRAINT fk_dept
FOREIGN KEY (department_id)
REFERENCES departments(department_id);

-- Drop constraint
ALTER TABLE employees
DROP CONSTRAINT fk_dept;
```

### DROP TABLE

Removes a table.

```sql
DROP TABLE employee_temp;

-- If exists (PostgreSQL, MySQL)
DROP TABLE IF EXISTS employee_temp;

-- With cascading constraints
DROP TABLE departments CASCADE CONSTRAINTS;
```

### TRUNCATE TABLE

Quickly removes all rows from a table.

```sql
TRUNCATE TABLE employee_temp;

-- Cascade (Oracle, PostgreSQL)
TRUNCATE TABLE departments CASCADE;
```

**Tips:**
- Always include constraints in CREATE TABLE statements
- Use CTAS for table prototyping
- Be cautious with DROP and TRUNCATE - they are not easily undone
- Consider deferred constraints for complex table relationships
- Prefer ALTER TABLE ADD CONSTRAINT over inline constraints for clarity

## Indexes

Indexes improve query performance by allowing the database to find rows quickly.

### CREATE INDEX

```sql
-- Basic index
CREATE INDEX idx_employees_name
ON employees(last_name, first_name);

-- Unique index
CREATE UNIQUE INDEX idx_employees_email
ON employees(email);

-- Functional index
CREATE INDEX idx_employees_upper_last_name
ON employees(UPPER(last_name));

-- Descending index
CREATE INDEX idx_employees_hire_date
ON employees(hire_date DESC);
```

### ALTER INDEX

```sql
-- Rename index (Oracle)
ALTER INDEX idx_employees_name
RENAME TO idx_emp_name;

-- Make index unusable (Oracle)
ALTER INDEX idx_employees_name UNUSABLE;

-- Rebuild index
ALTER INDEX idx_employees_name REBUILD;
```

### DROP INDEX

```sql
DROP INDEX idx_employees_name;

-- If exists (PostgreSQL, MySQL)
DROP INDEX IF EXISTS idx_employees_name;
```

**Tips:**
- Create indexes on columns used in JOIN, WHERE, and ORDER BY
- Consider composite indexes for queries with multiple conditions
- Don't over-index - each index adds overhead to INSERT/UPDATE/DELETE
- Use EXPLAIN/EXPLAIN PLAN to verify index usage
- Consider partial/filtered indexes for large tables
- Regularly rebuild indexes to maintain performance

## Transactions

Transactions ensure that a set of SQL statements either all succeed or all fail.

### Transaction Control

```sql
-- Begin transaction
BEGIN TRANSACTION;  -- SQL Server, PostgreSQL
START TRANSACTION;  -- MySQL, MariaDB
BEGIN;              -- Oracle, PostgreSQL

-- Commit transaction
COMMIT;

-- Rollback transaction
ROLLBACK;

-- Savepoint
SAVEPOINT sp1;
-- SQL statements
ROLLBACK TO SAVEPOINT sp1;
```

### Transaction Isolation Levels

```sql
-- Set isolation level
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
SET TRANSACTION ISOLATION LEVEL REPEATABLE READ;
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;
```

### Locking Hints

```sql
-- SQL Server
SELECT * FROM employees WITH (HOLDLOCK)
WHERE department_id = 10;

-- Oracle
SELECT * FROM employees FOR UPDATE
WHERE department_id = 10;

-- MySQL
SELECT * FROM employees
WHERE department_id = 10
FOR UPDATE;
```

**Tips:**
- Keep transactions as short as possible
- Be aware of deadlocks in concurrent transactions
- Choose appropriate isolation levels based on requirements
- Consider using optimistic concurrency for read-heavy workloads
- Use savepoints for complex transactions that might need partial rollbacks

## Views

Views are virtual tables based on query results.

### CREATE VIEW

```sql
CREATE VIEW employee_details AS
SELECT 
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.email,
    e.phone_number,
    d.department_name,
    l.city,
    c.country_name,
    r.region_name
FROM 
    employees e
JOIN 
    departments d ON e.department_id = d.department_id
JOIN 
    locations l ON d.location_id = l.location_id
JOIN 
    countries c ON l.country_id = c.country_id
JOIN 
    regions r ON c.region_id = r.region_id;
```

### CREATE OR REPLACE VIEW

```sql
CREATE OR REPLACE VIEW employee_details AS
SELECT 
    e.employee_id,
    e.first_name || ' ' || e.last_name AS full_name,
    e.email,
    e.phone_number,
    e.hire_date,
    d.department_name,
    l.city,
    c.country_name,
    r.region_name
FROM 
    employees e
JOIN 
    departments d ON e.department_id = d.department_id
JOIN 
    locations l ON d.location_id = l.location_id
JOIN 
    countries c ON l.country_id = c.country_id
JOIN 
    regions r ON c.region_id = r.region_id;
```

### Updatable Views

```sql
CREATE OR REPLACE VIEW it_employees AS
SELECT employee_id, first_name, last_name, email, job_id, department_id
FROM employees
WHERE department_id = 60
WITH CHECK OPTION;
```

### Materialized Views

```sql
-- Oracle
CREATE MATERIALIZED VIEW dept_salary_mv
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT 
    d.department_id,
    d.department_name,
    COUNT(*) AS employee_count,
    SUM(e.salary) AS total_salary,
    AVG(e.salary) AS avg_salary
FROM 
    employees e
JOIN 
    departments d ON e.department_id = d.department_id
GROUP BY 
    d.department_id, d.department_name;

-- Refresh materialized view
EXECUTE DBMS_MVIEW.REFRESH('dept_salary_mv');

-- PostgreSQL
CREATE MATERIALIZED VIEW dept_salary_mv AS
SELECT 
    d.department_id,
    d.department_name,
    COUNT(*) AS employee_count,
    SUM(e.salary) AS total_salary,
    AVG(e.salary) AS avg_salary
FROM 
    employees e
JOIN 
    departments d ON e.department_id = d.department_id
GROUP BY 
    d.department_id, d.department_name;

-- Refresh materialized view
REFRESH MATERIALIZED VIEW dept_salary_mv;
```

### DROP VIEW

```sql
DROP VIEW employee_details;

-- If exists
DROP VIEW IF EXISTS employee_details;
```

**Tips:**
- Use views to simplify complex queries
- Consider security implications - views can restrict access to underlying tables
- WITH CHECK OPTION ensures data integrity for updatable views
- Use materialized views for complex reports and analysis
- Regularly refresh materialized views for up-to-date data

## Stored Procedures

Stored procedures are reusable SQL code blocks.

### CREATE PROCEDURE

```sql
-- Oracle
CREATE OR REPLACE PROCEDURE update_employee_salary(
    p_employee_id IN NUMBER,
    p_percent IN NUMBER
)
IS
BEGIN
    UPDATE employees
    SET salary = salary * (1 + p_percent/100)
    WHERE employee_id = p_employee_id;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        RAISE;
END;
/

-- SQL Server
CREATE PROCEDURE update_employee_salary
    @employee_id INT,
    @percent DECIMAL(5,2)
AS
BEGIN
    BEGIN TRY
        BEGIN TRANSACTION;
        
        UPDATE employees
        SET salary = salary * (1 + @percent/100)
        WHERE employee_id = @employee_id;
        
        COMMIT;
    END TRY
    BEGIN CATCH
        ROLLBACK;
        THROW;
    END CATCH
END;

-- MySQL
DELIMITER //
CREATE PROCEDURE update_employee_salary(
    IN p_employee_id INT,
    IN p_percent DECIMAL(5,2)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    UPDATE employees
    SET salary = salary * (1 + p_percent/100)
    WHERE employee_id = p_employee_id;
    
    COMMIT;
END //
DELIMITER ;
```

### EXECUTE/CALL PROCEDURE

```sql
-- Oracle
BEGIN
    update_employee_salary(100, 10);
END;
/

-- SQL Server
EXEC update_employee_salary 100, 10;

-- MySQL
CALL update_employee_salary(100, 10);
```

### DROP PROCEDURE

```sql
-- Oracle, SQL Server
DROP PROCEDURE update_employee_salary;

-- MySQL
DROP PROCEDURE IF EXISTS update_employee_salary;
```

**Tips:**
- Use parameters with appropriate data types
- Include error handling in procedures
- Use transactions for data integrity
- Document procedure parameters and purpose
- Consider performance implications of complex procedures

## Optimization Techniques

### Query Optimization

1. **Use the right JOIN type**
   ```sql
   -- Use INNER JOIN when both tables must have matching rows
   -- Use LEFT JOIN when you need all rows from the left table
   ```

2. **Filter early**
   ```sql
   -- Bad: Filter after join
   SELECT e.employee_id, e.first_name, e.last_name
   FROM employees e
   JOIN departments d ON e.department_id = d.department_id
   WHERE d.department_name = 'IT';
   
   -- Good: Filter before join
   SELECT e.employee_id, e.first_name, e.last_name
   FROM employees e
   JOIN (
       SELECT department_id 
       FROM departments 
       WHERE department_name = 'IT'
   ) d ON e.department_id = d.department_id;
   ```

3. **Avoid SELECT ***
   ```sql
   -- Bad: Select all columns
   SELECT * FROM employees;
   
   -- Good: Select only needed columns
   SELECT employee_id, first_name, last_name FROM employees;
   ```

4. **Use EXISTS instead of IN for subqueries**
   ```sql
   -- Less efficient with large datasets
   SELECT department_id, department_name
   FROM departments
   WHERE department_id IN (
       SELECT DISTINCT department_id 
       FROM employees
   );
   
   -- More efficient
   SELECT department_id, department_name
   FROM departments d
   WHERE EXISTS (
       SELECT 1 
       FROM employees e 
       WHERE e.department_id = d.department_id
   );
   ```

5. **Use indexable conditions**
   ```sql
   -- Bad: Function on indexed column
   SELECT * FROM employees WHERE UPPER(last_name) = 'SMITH';
   
   -- Good: Index can be used
   SELECT * FROM employees WHERE last_name = 'Smith';
   ```

6. **Avoid DISTINCT if possible**
   ```sql
   -- Potentially less efficient
   SELECT DISTINCT department_id FROM employees;
   
   -- Better if you need counts
   SELECT department_id, COUNT(*)
   FROM employees
   GROUP BY department_id;
   ```

### Advanced Optimization Techniques

1. **Partitioning**
   ```sql
   -- Create partitioned table (Oracle)
   CREATE TABLE sales (
       sale_id NUMBER,
       sale_date DATE,
       customer_id NUMBER,
       amount NUMBER
   )
   PARTITION BY RANGE (sale_date) (
       PARTITION sales_q1_2023 VALUES LESS THAN (TO_DATE('01-APR-2023', 'DD-MON-YYYY')),
       PARTITION sales_q2_2023 VALUES LESS THAN (TO_DATE('01-JUL-2023', 'DD-MON-YYYY')),
       PARTITION sales_q3_2023 VALUES LESS THAN (TO_DATE('01-OCT-2023', 'DD-MON-YYYY')),
       PARTITION sales_q4_2023 VALUES LESS THAN (TO_DATE('01-JAN-2024', 'DD-MON-YYYY'))
   );
   
   -- Query with partition pruning
   SELECT * FROM sales
   WHERE sale_date BETWEEN TO_DATE('01-APR-2023', 'DD-MON-YYYY')
     AND TO_DATE('30-JUN-2023', 'DD-MON-YYYY');
   ```

2. **Parallelism**
   ```sql
   -- Oracle
   SELECT /*+ PARALLEL(4) */ * FROM large_table;
   
   -- SQL Server
   SELECT * FROM large_table OPTION (MAXDOP 4);
   ```

3. **Temp Tables vs. CTEs**
   ```sql
   -- Temp table
   CREATE TEMPORARY TABLE temp_emps AS
   SELECT employee_id, department_id
   FROM employees
   WHERE salary > 10000;
   
   SELECT * FROM temp_emps;
   
   -- CTE (calculated each time)
   WITH high_paid_emps AS (
       SELECT employee_id, department_id
       FROM employees
       WHERE salary > 10000
   )
   SELECT * FROM high_paid_emps;
   ```

4. **Query Hints**
   ```sql
   -- Oracle
   SELECT /*+ INDEX(employees emp_name_idx) */ *
   FROM employees
   WHERE last_name = 'Smith';
   
   -- SQL Server
   SELECT *
   FROM employees WITH (INDEX(emp_name_idx))
   WHERE last_name = 'Smith';
   ```

5. **Use EXPLAIN/EXECUTION PLAN**
   ```sql
   -- Oracle
   EXPLAIN PLAN FOR
   SELECT * FROM employees WHERE department_id = 90;
   
   SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);
   
   -- MySQL
   EXPLAIN
   SELECT * FROM employees WHERE department_id = 90;
   
   -- PostgreSQL
   EXPLAIN ANALYZE
   SELECT * FROM employees WHERE department_id = 90;
   
   -- SQL Server
   SET SHOWPLAN_TEXT ON;
   SELECT * FROM employees WHERE department_id = 90;
   SET SHOWPLAN_TEXT OFF;
   ```

**Tips:**
- Regularly analyze and update statistics
- Test queries on representative data volumes
- Monitor query execution times
- Consider denormalization for read-heavy workloads
- Use query optimization tools provided by your database system
