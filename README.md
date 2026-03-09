# QueryForge 🔥

A self-contained SQL workbench: PostgreSQL + FastAPI backend + browser UI — all in Docker.

## Stack

| Layer    | Technology              | Port  |
|----------|-------------------------|-------|
| Database | PostgreSQL 16           | 5432  |
| Backend  | Python 3.12 + FastAPI   | 8000  |
| Frontend | HTML/CSS/JS + nginx     | 3000  |

## Quick Start

```bash
# 1. Clone / unzip this folder, then:
cp .env.example .env          # optionally edit credentials

# 2. Build & start everything
docker compose up --build

# 3. Open the UI
open http://localhost:3000
```

The DB is pre-seeded with `spells` and `casters` tables — great for learning!

## Using the UI

- **Sidebar** — lists all tables; click one to see its schema and auto-fill a SELECT
- **Editor** — type any SQL; `Ctrl+Enter` to run
- **Results** — tabular display with row count and execution time
- **Status dot** (top-right) — green = backend connected

## API Endpoints

| Method | Path                       | Description             |
|--------|----------------------------|-------------------------|
| GET    | /health                    | DB connectivity check   |
| GET    | /tables                    | List all tables         |
| GET    | /tables/{name}/schema      | Column info             |
| GET    | /tables/{name}/preview     | First 20 rows           |
| POST   | /query                     | Run arbitrary SQL       |

**POST /query body:**
```json
{ "sql": "SELECT * FROM spells WHERE level >= 3" }
```

## Persistence

Data lives in the Docker volume `queryforge_pgdata`.  
`docker compose down` keeps the data.  
`docker compose down -v` removes it.

## Live Reload

Backend code in `./backend/` is volume-mounted — save `main.py` and FastAPI reloads instantly (no rebuild needed).

## Sample Queries to Try

```sql
-- All evocation spells
SELECT name, level, damage_die FROM spells WHERE school = 'Evocation' ORDER BY level;

-- Average spell level by school
SELECT school, AVG(level)::NUMERIC(4,2) AS avg_level, COUNT(*) AS total
FROM spells GROUP BY school ORDER BY avg_level DESC;

-- Create your own table
CREATE TABLE artifacts (
  id SERIAL PRIMARY KEY,
  name TEXT,
  rarity TEXT,
  attunement BOOLEAN DEFAULT false
);

INSERT INTO artifacts (name, rarity, attunement)
VALUES ('Sword of Kas', 'Artifact', true),
       ('Wand of Orcus', 'Artifact', true),
       ('Bag of Holding', 'Uncommon', false);

SELECT * FROM artifacts;
```
