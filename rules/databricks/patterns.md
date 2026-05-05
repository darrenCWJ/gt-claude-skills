---
paths:
  - "**/*.py"
  - "**/*.ipynb"
  - "**/*.sql"
  - "**/databricks.yml"
  - "**/.databricks/**"
---
# Databricks Patterns

> Applies when writing Databricks/Lakebase/Delta Lake code. Complements [common/patterns.md](../common/patterns.md).

## Connection

ALWAYS use `DatabricksSession` (not raw `SparkSession`) for Databricks Connect:

```python
# CORRECT
from databricks.connect import DatabricksSession
spark = DatabricksSession.builder.remote(
    host=os.environ["DATABRICKS_HOST"],
    token=os.environ["DATABRICKS_TOKEN"],
    cluster_id=os.environ["DATABRICKS_CLUSTER_ID"],
).getOrCreate()

# WRONG — bypasses Databricks auth and Unity Catalog
spark = SparkSession.builder.getOrCreate()
```

NEVER hardcode host, token, or cluster_id — always read from environment variables.

## Queries

### Prefer DataFrame API over raw SQL strings

```python
# CORRECT — type-safe, composable
df = spark.table("catalog.schema.my_table") \
    .filter(col("status") == "active") \
    .select("id", "name", "created_at")

# ACCEPTABLE for complex logic — use parameterized form
df = spark.sql("SELECT id, name FROM catalog.schema.my_table WHERE status = :status",
               args={"status": "active"})

# WRONG — string interpolation is SQL injection risk
df = spark.sql(f"SELECT * FROM my_table WHERE status = '{status}'")
```

### Always qualify table names with catalog and schema

```python
# CORRECT
df = spark.table("main.bronze.events")

# WRONG — ambiguous, environment-dependent
df = spark.table("events")
```

## Reading Data

```python
# Delta table (preferred)
df = spark.table("catalog.schema.table_name")

# Explicit Delta path (use only when table not registered)
df = spark.read.format("delta").load("/mnt/path/to/delta")

# With schema enforcement
df = spark.read.format("delta") \
    .option("enforceSchema", "true") \
    .load("/mnt/path/to/delta")
```

Always apply filters as early as possible — push predicates before joins or aggregations.

## Writing Data

```python
# Append to existing Delta table (most common)
df.write.format("delta").mode("append").saveAsTable("catalog.schema.table_name")

# Overwrite with schema evolution
df.write.format("delta") \
    .mode("overwrite") \
    .option("overwriteSchema", "true") \
    .saveAsTable("catalog.schema.table_name")

# WRONG — never use overwrite without explicit intent
df.write.mode("overwrite").saveAsTable("catalog.schema.table_name")
```

## Upserts (MERGE)

Use `DeltaTable.merge` for upserts — never DELETE + INSERT:

```python
from delta.tables import DeltaTable

target = DeltaTable.forName(spark, "catalog.schema.table_name")

target.alias("t").merge(
    source=updates_df.alias("s"),
    condition="t.id = s.id"
).whenMatchedUpdateAll() \
 .whenNotMatchedInsertAll() \
 .execute()
```

## Schema Evolution

```python
# Enable evolution explicitly per write — never globally
spark.conf.set("spark.databricks.delta.schema.autoMerge.enabled", "true")

df.write.format("delta") \
    .option("mergeSchema", "true") \
    .mode("append") \
    .saveAsTable("catalog.schema.table_name")
```

## Secrets

ALWAYS use Databricks Secrets — never hardcode credentials:

```python
# CORRECT (in Databricks notebooks/jobs)
token = dbutils.secrets.get(scope="my-scope", key="api-token")

# CORRECT (in local Databricks Connect scripts)
token = os.environ["DATABRICKS_TOKEN"]

# WRONG — hardcoded credential
token = "dapi1234abcd..."
```

## Error Handling

```python
from pyspark.errors import AnalysisException, PySparkException

try:
    df = spark.table("catalog.schema.table_name")
except AnalysisException as e:
    logger.error("Table not found or schema mismatch: %s", e)
    raise
except PySparkException as e:
    logger.error("Spark execution error: %s", e)
    raise
```

Never silently swallow Spark exceptions — always log and re-raise.

## Performance

- Partition large tables by date or high-cardinality key columns
- Use `ZORDER BY` on columns frequently used in filters
- Cache DataFrames only when reused multiple times in the same job
- Prefer `spark.read.table()` over raw Delta paths — Unity Catalog optimizes registered tables

```python
# Cache only when reused; always unpersist when done
df_cached = df.cache()
df_cached.count()  # trigger caching
# ... use df_cached multiple times ...
df_cached.unpersist()
```

## Code Smells to Avoid

| Pattern | Problem | Fix |
|---------|---------|-----|
| `spark.sql(f"...{var}...")` | SQL injection | Use `:param` binding or DataFrame API |
| Unqualified table names | Breaks across environments | Always use `catalog.schema.table` |
| `collect()` on large DataFrames | OOM risk | Use `.limit(n).collect()` or write to table |
| `.toPandas()` without filtering | OOM risk | Aggregate/filter in Spark first |
| Hardcoded tokens or host URLs | Security risk | Use `dbutils.secrets` or env vars |
