# SQL Interview Questions and Answer Guide

## Introduction

This guide provides comprehensive coverage of SQL interview questions from basic to intermediate levels, with detailed explanations and examples. Use this as a quick reference for interview preparation or to build a solid foundation in SQL concepts.

## Table of Contents

1. [Basic SQL Concepts](#basic-sql-concepts)
2. [SQL Data Types](#sql-data-types)
3. [SQL Constraints](#sql-constraints)
4. [SQL Operators](#sql-operators)
5. [SQL Functions](#sql-functions)
6. [SQL Joins](#sql-joins)
7. [SQL Subqueries](#sql-subqueries)
8. [SQL Aggregation](#sql-aggregation)
9. [SQL Indexing and Performance](#sql-indexing-and-performance)
10. [SQL Stored Procedures and Functions](#sql-stored-procedures-and-functions)
11. [Practice Questions](#practice-questions)
12. [SQL Cheat Sheet](#sql-cheat-sheet)

## Basic SQL Concepts

### What is SQL?

**Answer**: SQL (Structured Query Language) is a standardized programming language specifically designed for managing and manipulating relational databases. It allows users to create, retrieve, update, and delete data, as well as manage database structures.

### What are the different subsets of SQL?

**Answer**: SQL is divided into several sublanguages:

1. **DDL (Data Definition Language)**: Commands that define the database structure
   - CREATE, ALTER, DROP, TRUNCATE

2. **DML (Data Manipulation Language)**: Commands that manipulate data
   - SELECT, INSERT, UPDATE, DELETE

3. **DCL (Data Control Language)**: Commands that control access
   - GRANT, REVOKE

4. **TCL (Transaction Control Language)**: Commands that manage transactions
   - COMMIT, ROLLBACK, SAVEPOINT

### What is the difference between DELETE, TRUNCATE, and DROP?

**Answer**:

- **DELETE**: DML command that removes rows from a table based on a WHERE condition. It's logged and can be rolled back.
  ```sql
  DELETE FROM employees WHERE department_id = 10;
  ```

- **TRUNCATE**: DDL command that removes all rows from a table. It's faster than DELETE, minimally logged, and typically can't be rolled back.
  ```sql
  TRUNCATE TABLE employees;
  ```

- **DROP**: DDL command that removes an entire database object (table, view, etc.) including its structure, indexes, constraints, etc.
  ```sql
  DROP TABLE employees;
  ```

### What is normalization and why is it important?

**Answer**: Normalization is a database design technique that reduces data redundancy and improves data integrity by organizing data into multiple related tables. It follows a series of rules (normal forms) to eliminate issues like insertion, update, and deletion anomalies.

The main benefits of normalization are:
- Minimized duplicate data
- Reduced data inconsistencies
- Improved query performance for certain operations
- Better database organization
- Easier maintenance and future changes

Common normal forms include 1NF, 2NF, 3NF, BCNF, 4NF, and 5NF, each adding more stringent rules to eliminate potential anomalies.

### What is denormalization and when would you use it?

**Answer**: Denormalization is the process of adding redundancy to a normalized database design to improve read performance. While normalization focuses on eliminating redundancy, denormalization strategically adds redundancy for performance benefits.

You would consider denormalization when:
- Read performance is critical and significantly outweighs write performance needs
- Complex joins are slowing down queries
- Aggregation operations are frequently performed
- The application is read-heavy with relatively few updates
- You need to support reporting and analytical workloads

Common denormalization techniques include:
- Duplicating columns across tables
- Pre-calculating and storing derived values
- Creating summary tables
- Combining tables that are frequently joined

## SQL Data Types

### What are the common data types in SQL?

**Answer**: Common SQL data types include:

**Numeric Types**:
- INTEGER/INT: Whole numbers
- SMALLINT: Small range whole numbers
- BIGINT: Large range whole numbers
- DECIMAL/NUMERIC(p,s): Exact numeric with precision and scale
- FLOAT/REAL/DOUBLE: Approximate numeric values

**String Types**:
- CHAR(n): Fixed-length character strings
- VARCHAR(n): Variable-length character strings
- TEXT: Variable unlimited length text

**Date and Time Types**:
- DATE: Date (YYYY-MM-DD)
- TIME: Time (HH:MM:SS)
- DATETIME/TIMESTAMP: Date and time combination

**Boolean Type**:
- BOOLEAN: True/False values

**Binary Types**:
- BINARY/VARBINARY: Binary strings
- BLOB: Binary large objects

**Other Types**:
- ENUM: List of permissible string values
- JSON: JSON document
- XML: XML document
- ARRAY: Collection of elements

### What is the difference between CHAR and VARCHAR?

**Answer**:

- **CHAR(n)**: Fixed-length character string that always uses n bytes of storage. If a shorter string is stored, it's padded with spaces to the specified length.
  
- **VARCHAR(n)**: Variable-length character string that uses only as much storage as needed for the actual string (plus some overhead), up to a maximum of n characters.

Key differences:
1. **Storage**: CHAR always uses fixed space, while VARCHAR uses variable space
2. **Performance**: CHAR can be faster for fixed-length values accessed frequently
3. **Space utilization**: VARCHAR is more space-efficient for variable-length data
4. **Padding**: CHAR values are padded with spaces, VARCHAR values are not

Example:
```sql
CREATE TABLE example (
    fixed_col CHAR(10),    -- Always uses 10 characters
    var_col VARCHAR(10)    -- Uses only what's needed, up to 10 characters
);
```

## SQL Constraints

### What are constraints in SQL?

**Answer**: Constraints in SQL are rules enforced on data columns to maintain accuracy and reliability of the data. They define certain conditions that must be met before data can be inserted, updated, or deleted.

### What are the different types of constraints?

**Answer**: The main types of constraints are:

1. **PRIMARY KEY**: Uniquely identifies each record in a table
   ```sql
   CREATE TABLE employees (
       employee_id INT PRIMARY KEY,
       name VARCHAR(100)
   );
   ```

2. **FOREIGN KEY**: Establishes and enforces a link between data in two tables
   ```sql
   CREATE TABLE orders (
       order_id INT PRIMARY KEY,
       customer_id INT,
       FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
   );
   ```

3. **UNIQUE**: Ensures all values in a column are different
   ```sql
   CREATE TABLE users (
       user_id INT PRIMARY KEY,
       email VARCHAR(100) UNIQUE
   );
   ```

4. **CHECK**: Ensures values in a column satisfy a specific condition
   ```sql
   CREATE TABLE products (
       product_id INT PRIMARY KEY,
       price DECIMAL(10,2) CHECK (price > 0)
   );
   ```

5. **NOT NULL**: Ensures a column cannot have NULL values
   ```sql
   CREATE TABLE customers (
       customer_id INT PRIMARY KEY,
       name VARCHAR(100) NOT NULL
   );
   ```

6. **DEFAULT**: Provides a default value when none is specified
   ```sql
   CREATE TABLE orders (
       order_id INT PRIMARY KEY,
       order_date DATE DEFAULT CURRENT_DATE
   );
   ```

### What is the difference between UNIQUE and PRIMARY KEY constraints?

**Answer**:

| Feature | PRIMARY KEY | UNIQUE |
|---------|-------------|--------|
| NULL values | Does not allow NULL values | Generally allows one NULL value (varies by DBMS) |
| Quantity per table | Only one per table | Multiple UNIQUE constraints allowed |
| Index | Creates a clustered index by default (SQL Server) | Creates a non-clustered index by default |
| Purpose | Main identifier for the table | Alternate identifier or business rule |
| Foreign Key reference | Typically referenced by foreign keys | Can be referenced but less common |

Both constraints ensure uniqueness of values in the column(s) they are applied to.

## SQL Operators

### What are the different types of operators in SQL?

**Answer**: SQL provides several types of operators:

1. **Arithmetic Operators**:
   - `+` (Addition)
   - `-` (Subtraction)
   - `*` (Multiplication)
   - `/` (Division)
   - `%` (Modulo)

2. **Comparison Operators**:
   - `=` (Equal to)
   - `<>` or `!=` (Not equal to)
   - `>` (Greater than)
   - `<` (Less than)
   - `>=` (Greater than or equal to)
   - `<=` (Less than or equal to)

3. **Logical Operators**:
   - `AND` (Logical AND)
   - `OR` (Logical OR)
   - `NOT` (Logical NOT)

4. **String Operators**:
   - `LIKE` (Pattern matching with wildcards)
   - `CONCAT` or `||` (String concatenation)

5. **Other Operators**:
   - `IN` (Check if a value is in a list)
   - `BETWEEN` (Check if a value is within a range)
   - `IS NULL` / `IS NOT NULL` (Check for NULL values)
   - `EXISTS` (Check if a subquery returns any rows)

### Explain the LIKE operator and its wildcards

**Answer**: The LIKE operator is used in a WHERE clause to search for a specific pattern in a column.

Wildcards used with LIKE:
- `%` - Represents zero, one, or multiple characters
- `_` - Represents a single character

Examples:
```sql
-- Names starting with 'J'
SELECT * FROM employees WHERE name LIKE 'J%';

-- Names ending with 'son'
SELECT * FROM employees WHERE name LIKE '%son';

-- Names containing 'an' anywhere
SELECT * FROM employees WHERE name LIKE '%an%';

-- Names with exactly 5 characters
SELECT * FROM employees WHERE name LIKE '_____';

-- Names with 'a' as the second character
SELECT * FROM employees WHERE name LIKE '_a%';
```

### What is the difference between IN and EXISTS?

**Answer**:

- **IN**: Compares a value to a list of specified values or a subquery result. It evaluates the entire subquery result first.
  ```sql
  SELECT * FROM employees 
  WHERE department_id IN (10, 20, 30);
  
  SELECT * FROM employees 
  WHERE department_id IN (SELECT department_id FROM departments WHERE location_id = 1700);
  ```

- **EXISTS**: Checks whether a subquery returns any rows. It stops evaluating as soon as a match is found.
  ```sql
  SELECT * FROM departments d
  WHERE EXISTS (SELECT 1 FROM employees e WHERE e.department_id = d.department_id);
  ```

Key differences:
1. **Performance**: EXISTS often performs better for large datasets as it can stop once a match is found
2. **NULL handling**: IN returns NULL when comparing with NULL values in the list, which may cause unexpected results
3. **Evaluation**: IN evaluates the entire subquery result, EXISTS checks for at least one match
4. **Use case**: IN is better for small, known lists; EXISTS is better for existence checks

## SQL Functions

### What are the main categories of SQL functions?

**Answer**: SQL functions are categorized into:

1. **Aggregate Functions**: Operate on multiple rows and return a single value
   - COUNT, SUM, AVG, MIN, MAX

2. **Scalar Functions**: Operate on each row individually
   - STRING functions: CONCAT, LENGTH, UPPER, LOWER, SUBSTRING
   - NUMERIC functions: ROUND, CEILING, FLOOR, ABS
   - DATE/TIME functions: CURRENT_DATE, EXTRACT, DATE_PART, DATEADD
   - CONVERSION functions: CAST, CONVERT
   
3. **Window Functions**: Perform calculations across rows related to the current row
   - ROW_NUMBER, RANK, DENSE_RANK, LEAD, LAG, SUM OVER, AVG OVER

4. **User-Defined Functions**: Custom functions created by users

### Explain the difference between COUNT(*), COUNT(column), and COUNT(DISTINCT column)

**Answer**:

- **COUNT(*)**: Counts all rows in a table, including duplicate rows and rows with NULL values
  ```sql
  SELECT COUNT(*) FROM employees;
  ```

- **COUNT(column)**: Counts all non-NULL values in the specified column
  ```sql
  SELECT COUNT(manager_id) FROM employees;
  ```

- **COUNT(DISTINCT column)**: Counts only unique non-NULL values in the specified column
  ```sql
  SELECT COUNT(DISTINCT department_id) FROM employees;
  ```

### What are window functions and how are they used?

**Answer**: Window functions perform calculations across a set of table rows related to the current row. Unlike regular aggregate functions, window functions don't cause rows to become grouped into a single output row.

Basic syntax:
```sql
function_name() OVER (
   [PARTITION BY column1, column2, ...]
   [ORDER BY column3, column4, ...]
   [ROWS/RANGE frame_clause]
)
```

Common window functions:
- **ROW_NUMBER()**: Assigns a unique sequential integer to each row
- **RANK()**: Assigns a rank with gaps for ties
- **DENSE_RANK()**: Assigns a rank without gaps for ties
- **LEAD()**: Accesses data from subsequent rows
- **LAG()**: Accesses data from previous rows
- **SUM(), AVG(), MIN(), MAX()**: Used as window functions over partitions

Example:
```sql
SELECT 
    employee_id,
    department_id,
    salary,
    ROW_NUMBER() OVER(ORDER BY salary DESC) AS overall_rank,
    RANK() OVER(PARTITION BY department_id ORDER BY salary DESC) AS dept_rank,
    AVG(salary) OVER(PARTITION BY department_id) AS dept_avg_salary
FROM employees;
```

## SQL Joins

### What are the different types of joins in SQL?

**Answer**: SQL provides several types of joins to combine rows from different tables:

1. **INNER JOIN**: Returns rows when there is a match in both tables
   ```sql
   SELECT e.name, d.department_name
   FROM employees e
   INNER JOIN departments d ON e.department_id = d.department_id;
   ```

2. **LEFT JOIN (LEFT OUTER JOIN)**: Returns all rows from the left table and matching rows from the right table
   ```sql
   SELECT e.name, d.department_name
   FROM employees e
   LEFT JOIN departments d ON e.department_id = d.department_id;
   ```

3. **RIGHT JOIN (RIGHT OUTER JOIN)**: Returns all rows from the right table and matching rows from the left table
   ```sql
   SELECT e.name, d.department_name
   FROM employees e
   RIGHT JOIN departments d ON e.department_id = d.department_id;
   ```

4. **FULL JOIN (FULL OUTER JOIN)**: Returns rows when there is a match in either table
   ```sql
   SELECT e.name, d.department_name
   FROM employees e
   FULL JOIN departments d ON e.department_id = d.department_id;
   ```

5. **CROSS JOIN**: Returns the Cartesian product of both tables
   ```sql
   SELECT e.name, d.department_name
   FROM employees e
   CROSS JOIN departments d;
   ```

6. **SELF JOIN**: Joining a table to itself
   ```sql
   SELECT e1.name AS employee, e2.name AS manager
   FROM employees e1
   JOIN employees e2 ON e1.manager_id = e2.employee_id;
   ```

### Visual Representation of SQL Joins

```
Table A       Table B
  o o          o o       
  o              o       
    o          o         

INNER JOIN      LEFT JOIN       RIGHT JOIN      FULL JOIN
  o o             o o            o o              o o
                  o                o              o o
                                   o                o
```

### What is a SELF JOIN and when would you use it?

**Answer**: A SELF JOIN is a join in which a table is joined with itself. It is used when you need to compare rows within the same table or query hierarchical data.

Common use cases for SELF JOIN:
1. **Hierarchical data**: Employee-manager relationships
2. **Finding pairs**: Customers who live in the same city
3. **Comparing rows**: Products with the same category but different prices
4. **Sequential analysis**: Finding consecutive events

Example (employee-manager relationship):
```sql
SELECT 
    e.employee_id,
    e.name AS employee_name,
    m.name AS manager_name
FROM 
    employees e
LEFT JOIN 
    employees m ON e.manager_id = m.employee_id;
```

## SQL Subqueries

### What is a subquery and what are its types?

**Answer**: A subquery (inner query or nested query) is a query nested within another SQL statement. It can return data that will be used in the main query as a condition to filter or manipulate data.

Types of subqueries:

1. **Single-row subquery**: Returns exactly one row and one column
   ```sql
   SELECT name
   FROM employees
   WHERE salary > (SELECT AVG(salary) FROM employees);
   ```

2. **Multiple-row subquery**: Returns multiple rows and one column
   ```sql
   SELECT name
   FROM employees
   WHERE department_id IN (SELECT department_id FROM departments WHERE location_id = 1700);
   ```

3. **Correlated subquery**: References columns from the outer query
   ```sql
   SELECT e.name
   FROM employees e
   WHERE salary > (SELECT AVG(salary) FROM employees WHERE department_id = e.department_id);
   ```

4. **Scalar subquery**: Returns a single value (one row, one column)
   ```sql
   SELECT name, salary, (SELECT AVG(salary) FROM employees) AS avg_salary
   FROM employees;
   ```

5. **Table subquery**: Used in the FROM clause to create a derived table
   ```sql
   SELECT dept_name, avg_salary
   FROM (
       SELECT department_id, AVG(salary) AS avg_salary
       FROM employees
       GROUP BY department_id
   ) dept_avg
   JOIN departments d ON dept_avg.department_id = d.department_id;
   ```

### When would you use a correlated subquery?

**Answer**: A correlated subquery references columns from the outer query and is reevaluated for each row processed by the outer query. You would use a correlated subquery when:

1. **Comparing a row value with an aggregate from related rows**
   ```sql
   -- Find employees with salary higher than their department average
   SELECT e1.name, e1.salary, e1.department_id
   FROM employees e1
   WHERE e1.salary > (
       SELECT AVG(e2.salary)
       FROM employees e2
       WHERE e2.department_id = e1.department_id
   );
   ```

2. **Checking for existence of related records**
   ```sql
   -- Find departments that have at least one employee
   SELECT department_name
   FROM departments d
   WHERE EXISTS (
       SELECT 1
       FROM employees e
       WHERE e.department_id = d.department_id
   );
   ```

3. **Row-by-row updates or deletes**
   ```sql
   -- Update employee salaries based on department averages
   UPDATE employees e1
   SET salary = salary * 1.1
   WHERE salary < (
       SELECT AVG(salary) * 0.9
       FROM employees e2
       WHERE e2.department_id = e1.department_id
   );
   ```

4. **Finding top N values within groups**
   ```sql
   -- Find the top 3 highest paid employees in each department
   SELECT name, department_id, salary
   FROM employees e1
   WHERE 3 > (
       SELECT COUNT(*)
       FROM employees e2
       WHERE e2.department_id = e1.department_id
       AND e2.salary > e1.salary
   );
   ```

### What is the difference between a subquery and a JOIN?

**Answer**:

| Aspect | Subquery | JOIN |
|--------|----------|------|
| Purpose | Returns data to be used as a filter or variable | Combines columns from multiple tables |
| Result set | Creates an intermediate result not directly visible | Creates a single combined result set |
| Performance | Can be slower for some operations | Often faster for retrieving data from multiple tables |
| Readability | Sometimes clearer for simple operations | Better for complex relationships |
| Data retrieval | Good for EXISTS and single-value comparisons | Better for retrieving data from multiple tables |
| Flexibility | Can be used in SELECT, FROM, WHERE, HAVING | Used in FROM clause |
| Case usage | Best for: aggregates, existence checks, dynamic values | Best for: combining multiple datasets, relationship queries |

Both approaches often can achieve the same result, but with different performance characteristics and readability.

Example comparison:
```sql
-- Using JOIN
SELECT e.name, d.department_name
FROM employees e
JOIN departments d ON e.department_id = d.department_id
WHERE d.location_id = 1700;

-- Using Subquery
SELECT e.name
FROM employees e
WHERE e.department_id IN (
    SELECT department_id 
    FROM departments 
    WHERE location_id = 1700
);
```

## SQL Aggregation

### What are aggregate functions and how are they used?

**Answer**: Aggregate functions perform a calculation on a set of values and return a single value. They are commonly used with the GROUP BY clause to perform calculations at a group level.

Common aggregate functions:

1. **COUNT()**: Counts rows or non-NULL values
   ```sql
   SELECT department_id, COUNT(*) AS employee_count
   FROM employees
   GROUP BY department_id;
   ```

2. **SUM()**: Calculates the sum of numeric values
   ```sql
   SELECT department_id, SUM(salary) AS total_salary
   FROM employees
   GROUP BY department_id;
   ```

3. **AVG()**: Calculates the average of numeric values
   ```sql
   SELECT department_id, AVG(salary) AS avg_salary
   FROM employees
   GROUP BY department_id;
   ```

4. **MIN()**: Returns the minimum value
   ```sql
   SELECT department_id, MIN(salary) AS min_salary
   FROM employees
   GROUP BY department_id;
   ```

5. **MAX()**: Returns the maximum value
   ```sql
   SELECT department_id, MAX(salary) AS max_salary
   FROM employees
   GROUP BY department_id;
   ```

6. **STDDEV()**: Calculates standard deviation
   ```sql
   SELECT department_id, STDDEV(salary) AS salary_stddev
   FROM employees
   GROUP BY department_id;
   ```

### What is the difference between WHERE and HAVING clauses?

**Answer**:

| Aspect | WHERE | HAVING |
|--------|-------|--------|
| Purpose | Filters rows before grouping | Filters groups after grouping |
| Works with | Individual rows | Groups |
| Position in query | Before GROUP BY | After GROUP BY |
| Can use aggregate functions | No | Yes |
| Affects | Which rows are considered for grouping | Which groups appear in final results |

Example:
```sql
SELECT 
    department_id, 
    AVG(salary) AS avg_salary
FROM 
    employees
WHERE 
    hire_date > '2020-01-01'  -- Filters individual rows before grouping
GROUP BY 
    department_id
HAVING 
    AVG(salary) > 50000;      -- Filters groups after grouping
```

### Explain the GROUP BY clause and how it works

**Answer**: The GROUP BY clause is used to group rows that have the same values in specified columns into summary rows. It's typically used with aggregate functions to perform calculations on each group.

How GROUP BY works:
1. Rows are divided into groups based on values in the GROUP BY columns
2. An aggregate function can be applied to each group
3. The query returns one row for each group
4. All selected columns must either be in the GROUP BY clause or be used with an aggregate function

Example:
```sql
SELECT 
    department_id,
    job_id,
    COUNT(*) AS employee_count,
    AVG(salary) AS avg_salary,
    MAX(salary) AS max_salary
FROM 
    employees
GROUP BY 
    department_id, job_id
ORDER BY 
    department_id, job_id;
```

Advanced features:
- **ROLLUP**: Generates subtotals and grand totals
  ```sql
  SELECT department_id, job_id, SUM(salary)
  FROM employees
  GROUP BY ROLLUP(department_id, job_id);
  ```

- **CUBE**: Generates all possible combinations of subtotals
  ```sql
  SELECT department_id, job_id, SUM(salary)
  FROM employees
  GROUP BY CUBE(department_id, job_id);
  ```

- **GROUPING SETS**: Specifies multiple grouping sets in a single query
  ```sql
  SELECT department_id, job_id, SUM(salary)
  FROM employees
  GROUP BY GROUPING SETS((department_id), (job_id), ());
  ```

## SQL Indexing and Performance

### What is an index and how does it improve performance?

**Answer**: An index is a database structure that improves the speed of data retrieval operations on a table. It works similar to an index in a book, allowing the database engine to find data quickly without scanning the entire table.

How indexes improve performance:
1. **Faster data retrieval**: Locate rows quickly without scanning the entire table
2. **Efficient sorting**: Avoid expensive sort operations for queries with ORDER BY
3. **Join optimization**: Speed up join operations by finding matching rows quickly
4. **Uniqueness enforcement**: Efficiently enforce unique constraints

Types of indexes:
- **B-tree index**: General-purpose index, good for equality and range conditions
- **Hash index**: Very fast for exact matches, not useful for ranges
- **Bitmap index**: Efficient for low-cardinality columns (few distinct values)
- **Full-text index**: Specialized for text search operations
- **Spatial index**: Optimized for geographic data

Example:
```sql
-- Create an index on the last_name column
CREATE INDEX idx_employees_last_name ON employees(last_name);

-- Create a composite index on department_id and job_id
CREATE INDEX idx_employees_dept_job ON employees(department_id, job_id);
```

### What types of indexes are there and when would you use each?

**Answer**:

1. **Single-Column Index**:
   - Indexes one column only
   - Best for queries that filter, join, or sort by a single column
   ```sql
   CREATE INDEX idx_employees_last_name ON employees(last_name);
   ```

2. **Composite/Multi-Column Index**:
   - Indexes multiple columns together
   - Useful for queries that filter, join, or sort by multiple columns
   - Order of columns matters significantly
   ```sql
   CREATE INDEX idx_employees_dept_job ON employees(department_id, job_id);
   ```

3. **Unique Index**:
   - Enforces uniqueness of the indexed column(s)
   - Creates both a constraint and an index
   ```sql
   CREATE UNIQUE INDEX idx_employees_email ON employees(email);
   ```

4. **Clustered Index**:
   - Determines the physical order of data in a table
   - Only one per table
   - Typically created automatically with primary key
   ```sql
   -- SQL Server syntax (implementation varies by DBMS)
   CREATE CLUSTERED INDEX idx_employees_id ON employees(employee_id);
   ```

5. **Non-Clustered Index**:
   - Creates a separate structure that points to the data
   - Multiple allowed per table
   - Default index type in most systems
   ```sql
   CREATE NONCLUSTERED INDEX idx_employees_hire_date ON employees(hire_date);
   ```

6. **Covering Index**:
   - Includes all columns needed by a query
   - Avoids table lookups entirely
   ```sql
   -- SQL Server syntax
   CREATE INDEX idx_employees_covering ON employees(department_id, job_id)
   INCLUDE(first_name, last_name, salary);
   ```

7. **Partial/Filtered Index**:
   - Only indexes a subset of rows based on a condition
   - Smaller and more efficient for specific queries
   ```sql
   -- PostgreSQL syntax
   CREATE INDEX idx_active_employees ON employees(employee_id)
   WHERE status = 'ACTIVE';
   ```

### What are some common query optimization techniques?

**Answer**: Common query optimization techniques include:

1. **Use appropriate indexes**:
   - Create indexes on columns used in WHERE, JOIN, ORDER BY, GROUP BY
   - Consider covering indexes for frequent queries
   - Avoid over-indexing (balance read vs. write performance)

2. **Write efficient SQL**:
   - Be specific (SELECT specific columns instead of SELECT *)
   - Limit results with WHERE clause early in the query
   - Use JOIN instead of subqueries when possible
   - Avoid functions on indexed columns in WHERE clauses

3. **Optimize JOIN operations**:
   - Join on indexed columns
   - Join smaller tables first where possible
   - Use appropriate join types
   - Consider denormalization for read-heavy workloads

4. **Efficient filtering**:
   - Use appropriate data types for comparison
   - Apply most restrictive filters first
   - Use EXISTS instead of IN for large subquery results
   - Avoid unnecessary DISTINCT operations

5. **Query structure improvements**:
   - Break complex queries into simpler ones
   - Use common table expressions (CTEs) for readability
   - Consider temporary tables for complex multi-step operations
   - Use UNION ALL instead of UNION when duplicates are acceptable

6. **Database maintenance**:
   - Keep statistics updated
   - Rebuild fragmented indexes
   - Properly size database and log files
   - Use appropriate isolation levels

7. **Optimize for specific patterns**:
   - Use windowing functions instead of self-joins
   - Consider materialized views for complex aggregations
   - Use OFFSET/FETCH or ROW_NUMBER() for pagination
   - Implement caching strategies for frequent queries

## SQL Stored Procedures and Functions

### What is a stored procedure?

**Answer**: A stored procedure is a prepared SQL code that can be saved and reused. It can accept parameters, perform operations, and return results. Stored procedures offer advantages like improved performance, reduced network traffic, better security, and code reusability.

Basic syntax (varies by DBMS):
```sql
-- SQL Server
CREATE PROCEDURE GetEmployeesByDepartment
    @DepartmentId INT
AS
BEGIN
    SELECT employee_id, first_name, last_name
    FROM employees
    WHERE department_id = @DepartmentId;
END;

-- Oracle
CREATE OR REPLACE PROCEDURE GetEmployeesByDepartment(
    p_department_id IN NUMBER
)
AS
BEGIN
    SELECT employee_id, first_name, last_name
    FROM employees
    WHERE department_id = p_department_id;
END;

-- MySQL
DELIMITER //
CREATE PROCEDURE GetEmployeesByDepartment(
    IN p_department_id INT
)
BEGIN
    SELECT employee_id, first_name, last_name
    FROM employees
    WHERE department_id = p_department_id;
END //
DELIMITER ;
```

### What is the difference between a stored procedure and a function?

**Answer**:

| Aspect | Stored Procedure | Function |
|--------|------------------|----------|
| Return value | Can return multiple results or none | Must return a single value |
| Usage | Called with EXECUTE/CALL | Used in SQL expressions |
| Parameters | IN, OUT, INOUT parameters | Input parameters only (typically) |
| DML statements | Can contain INSERT, UPDATE, DELETE | More restricted (varies by DBMS) |
| Transaction control | Can contain COMMIT, ROLLBACK | Usually cannot affect transactions |
| Calling context | Stand-alone call | Used in SELECT, WHERE, etc. |

Example of a function:
```sql
-- SQL Server
CREATE FUNCTION CalculateTax(@Amount DECIMAL(10,2))
RETURNS DECIMAL(10,2)
AS
BEGIN
    RETURN @Amount * 0.07;
END;

-- Usage
SELECT product_name, price, dbo.CalculateTax(price) AS tax
FROM products;
```

### What are triggers and when would you use them?

**Answer**: A trigger is a special type of stored procedure that automatically executes in response to certain events on a particular table or view, such as INSERT, UPDATE, or DELETE operations.

Types of triggers:
1. **BEFORE triggers**: Execute before the triggering action
2. **AFTER triggers**: Execute after the triggering action
3. **INSTEAD OF triggers**: Replace the triggering action with the trigger logic

Common use cases:
1. **Data validation**: Enforce complex business rules beyond simple constraints
2. **Audit trails**: Track changes to sensitive data
3. **Maintaining derived data**: Update summary tables or calculated fields
4. **Cross-table integrity**: Enforce relationships not covered by foreign keys
5. **Event logging**: Record system events or user actions

Example:
```sql
-- SQL Server syntax
CREATE TRIGGER trg_UpdateAudit
ON employees
AFTER UPDATE
AS
BEGIN
    INSERT INTO employee_audit (
        employee_id,
        field_changed,
        old_value,
        new_value,
        change_date
    )
    SELECT
        i.employee_id,
        'salary',
        d.salary,
        i.salary,
        GETDATE()
    FROM
        inserted i
        JOIN deleted d ON i.employee_id = d.employee_id
    WHERE
        i.salary <> d.salary;
END;
```

## Practice Questions

### Find the second highest salary

**Answer**:
```sql
-- Using subquery
SELECT MAX(salary) AS second_highest_salary
FROM employees
WHERE salary < (SELECT MAX(salary) FROM employees);

-- Using window functions
SELECT salary AS second_highest_salary
FROM (
    SELECT salary, 
           DENSE_RANK() OVER (ORDER BY salary DESC) AS rank
    FROM employees
) ranked
WHERE rank = 2;
```

### Find duplicate records in a table

**Answer**:
```sql
-- Find duplicate emails
SELECT email, COUNT(*) AS count
FROM employees
GROUP BY email
HAVING COUNT(*) > 1;

-- Find complete duplicate rows
SELECT employee_id, first_name, last_name, COUNT(*) AS count
FROM employees
GROUP BY employee_id, first_name, last_name
HAVING COUNT(*) > 1;
```

### Find departments with more than 5 employees

**Answer**:
```sql
SELECT d.department_id, d.department_name, COUNT(e.employee_id) AS employee_count
FROM departments d
JOIN employees e ON d.department_id = e.department_id
GROUP BY d.department_id, d.department_name
HAVING COUNT(e.employee_id) > 5
ORDER BY employee_count DESC;
```

### Find employees who earn more than their manager

**Answer**:
```sql
SELECT e.employee_id, e.first_name, e.last_name, e.salary AS employee_salary, 
       m.salary AS manager_salary
FROM employees e
JOIN employees m ON e.manager_id = m.employee_id
WHERE e.salary > m.salary;
```

### Update salaries for employees with salaries below the department average

**Answer**:
```sql
UPDATE employees e
SET salary = salary * 1.1
WHERE salary < (
    SELECT AVG(salary)
    FROM employees
    WHERE department_id = e.department_id
);
```

## SQL Cheat Sheet

### Basic Queries
```sql
-- Select all columns
SELECT * FROM table_name;

-- Select specific columns
SELECT column1, column2 FROM table_name;

-- Select with a condition
SELECT column1, column2 
FROM table_name
WHERE condition;

-- Select with ordering
SELECT column1, column2 
FROM table_name
ORDER BY column1 [ASC|DESC];

-- Select with LIMIT
SELECT column1, column2 
FROM table_name
LIMIT n;

-- Select distinct values
SELECT DISTINCT column1 
FROM table_name;
```

### Filtering Data
```sql
-- Multiple conditions
SELECT * FROM employees
WHERE department_id = 10 AND salary > 50000;

-- Range condition
SELECT * FROM employees
WHERE salary BETWEEN 50000 AND 100000;

-- List condition
SELECT * FROM employees
WHERE department_id IN (10, 20, 30);

-- Pattern matching
SELECT * FROM employees
WHERE last_name LIKE 'S%';

-- NULL values
SELECT * FROM employees
WHERE manager_id IS NULL;
```

### Joins
```sql
-- Inner join
SELECT e.name, d.department_name
FROM employees e
JOIN departments d
ON e.department_id = d.department_id;

-- Left join
SELECT e.name, d.department_name
FROM employees e
LEFT JOIN departments d
ON e.department_id = d.department_id;

-- Right join
SELECT e.name, d.department_name
FROM employees e
RIGHT JOIN departments d
ON e.department_id = d.department_id;

-- Full outer join
SELECT e.name, d.department_name
FROM employees e
FULL OUTER JOIN departments d
ON e.department_id = d.department_id;
```

### Aggregation
```sql
-- Simple counts
SELECT COUNT(*) FROM employees;

-- Group by with multiple aggregations
SELECT 
    department_id,
    COUNT(*) AS employee_count,
    AVG(salary) AS avg_salary,
    MAX(salary) AS max_salary,
    MIN(salary) AS min_salary
FROM employees
GROUP BY department_id;

-- Having clause
SELECT 
    department_id,
    AVG(salary) AS avg_salary
FROM employees
GROUP BY department_id
HAVING AVG(salary) > 50000;
```

### Subqueries
```sql
-- Subquery in WHERE
SELECT * 
FROM employees
WHERE department_id IN (
    SELECT department_id 
    FROM departments 
    WHERE location_id = 1700
);

-- Subquery in SELECT
SELECT 
    employee_id,
    first_name,
    last_name,
    salary,
    (SELECT AVG(salary) FROM employees) AS company_avg
FROM employees;

-- Correlated subquery
SELECT 
    department_id,
    department_name,
    (SELECT COUNT(*) FROM employees e 
     WHERE e.department_id = d.department_id) AS employee_count
FROM departments d;
```

### Data Modification
```sql
-- Insert a row
INSERT INTO employees (employee_id, first_name, last_name, email, hire_date, job_id)
VALUES (207, 'John', 'Doe', 'jdoe@example.com', '2023-01-15', 'IT_PROG');

-- Update rows
UPDATE employees
SET salary = salary * 1.1
WHERE department_id = 90;

-- Delete rows
DELETE FROM employees
WHERE hire_date < '2000-01-01';
```

### Table Creation and Modification
```sql
-- Create table
CREATE TABLE projects (
    project_id INT PRIMARY KEY,
    project_name VARCHAR(100) NOT NULL,
    start_date DATE,
    end_date DATE,
    budget DECIMAL(15,2),
    manager_id INT,
    FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
);

-- Add column
ALTER TABLE projects
ADD COLUMN status VARCHAR(20);

-- Modify column
ALTER TABLE projects
MODIFY COLUMN project_name VARCHAR(150);

-- Drop column
ALTER TABLE projects
DROP COLUMN status;
```

### Indexes
```sql
-- Create index
CREATE INDEX idx_projects_manager
ON projects(manager_id);

-- Create unique index
CREATE UNIQUE INDEX idx_projects_name
ON projects(project_name);

-- Drop index
DROP INDEX idx_projects_manager;
```
