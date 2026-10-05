-- Runs once, on first start (when the pgdata volume is empty).
CREATE TABLE items (
    id         BIGSERIAL PRIMARY KEY,   -- primary key = indexed
    name       TEXT NOT NULL,           -- deliberately NOT indexed (see /search)
    category   INT  NOT NULL,
    price      NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO items (name, category, price)
SELECT 'item-' || g,
       (random() * 100)::int,
       round((random() * 1000)::numeric, 2)
FROM generate_series(1, 1000000) AS g;

ANALYZE items;
