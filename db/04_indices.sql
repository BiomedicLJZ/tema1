-- ═══════════════════════════════════════════════════════════════════════════════
--  ⚡  EL ARCHIVO DE GUERRA  —  Base de datos para Optimización de Consultas
--     Schema: guerra
--
--  PROPÓSITO PEDAGÓGICO:
--    Tablas con VOLUMEN MASIVO de datos (100K+ filas) para que EXPLAIN ANALYZE
--    muestre diferencias reales entre Sequential Scan e Index Scan.
--
--  TEMA 2.1 — FUNDAMENTOS DE OPTIMIZACIÓN DE CONSULTAS
--    2.1.1. Costo de operaciones de disco y CPU
--    2.1.2. Concepto de Índices: B-Tree, Hash, GIN, GiST, BRIN
--    2.1.3. Creación y Uso Eficiente: claves indexadas, columnas compuestas
--
--  AMBIENTACIÓN:
--    El Archivo de Guerra registra cada batalla, cada golpe, cada misión
--    y cada transacción comercial del reino. Es la base de datos más grande
--    del mundo de "Chronicles of the Broken Realm".
--
--  TABLAS:
--    guerra.combatientes    — 100,000 guerreros registrados
--    guerra.batallas        — 500,000 registros de combate
--    guerra.misiones        — 200,000 misiones completadas
--    guerra.transacciones   — 300,000 transacciones del mercado
--    guerra.bitacora_eventos— 250,000 eventos del servidor (para BRIN)
--
--  IMPORTANTE PARA EL PROFESOR:
--    Después de cargar este archivo, ejecutar las consultas de demostración
--    SIN índices primero (sequential scan), luego CREAR los índices y
--    repetir las mismas consultas para ver la diferencia.
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS guerra;
SET search_path TO guerra, public;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLA 1: combatientes
--  100,000 guerreros con atributos variados para filtrar
-- ─────────────────────────────────────────────────────────────────────────────

DROP TABLE IF EXISTS guerra.bitacora_eventos CASCADE;
DROP TABLE IF EXISTS guerra.transacciones CASCADE;
DROP TABLE IF EXISTS guerra.misiones CASCADE;
DROP TABLE IF EXISTS guerra.batallas CASCADE;
DROP TABLE IF EXISTS guerra.combatientes CASCADE;

CREATE TABLE guerra.combatientes (
    combatiente_id  SERIAL PRIMARY KEY,
    nombre          TEXT NOT NULL,
    clase           TEXT NOT NULL,       -- 'Guerrero','Mago','Pícaro','Clérigo','Ranger','Paladín','Bardo','Druida'
    raza            TEXT NOT NULL,       -- 'Humano','Elfo','Enano','Orco','Halfling','Gnomo','Dracónido','Tiefling'
    nivel           INT NOT NULL,        -- 1–100
    fuerza          INT NOT NULL,
    destreza        INT NOT NULL,
    inteligencia    INT NOT NULL,
    constitucion    INT NOT NULL,
    gremio          TEXT,                -- nombre del gremio (puede ser NULL)
    region          TEXT NOT NULL,       -- 'Norte','Sur','Este','Oeste','Centro'
    oro_total       NUMERIC(12,2) NOT NULL,
    esta_activo     BOOLEAN DEFAULT true,
    fecha_registro  DATE NOT NULL,
    ultimo_login    TIMESTAMPTZ NOT NULL
);

-- Generar 100,000 combatientes con distribución realista
INSERT INTO guerra.combatientes (
    nombre, clase, raza, nivel, fuerza, destreza, inteligencia, constitucion,
    gremio, region, oro_total, esta_activo, fecha_registro, ultimo_login
)
SELECT
    'Guerrero_' || gs AS nombre,

    (ARRAY['Guerrero','Mago','Pícaro','Clérigo','Ranger','Paladín','Bardo','Druida'])
        [1 + (gs * 7 + 13) % 8] AS clase,

    (ARRAY['Humano','Elfo','Enano','Orco','Halfling','Gnomo','Dracónido','Tiefling'])
        [1 + (gs * 11 + 3) % 8] AS raza,

    -- Nivel: distribución sesgada (muchos bajos, pocos altos)
    LEAST(100, GREATEST(1, (ln(gs::float + 1) * 15)::INT + (gs % 17))) AS nivel,

    -- Stats entre 3 y 20
    3 + (gs * 13 + 7) % 18 AS fuerza,
    3 + (gs * 17 + 11) % 18 AS destreza,
    3 + (gs * 19 + 5) % 18 AS inteligencia,
    3 + (gs * 23 + 3) % 18 AS constitucion,

    -- Gremio: ~70% tiene gremio, 30% es NULL (lobos solitarios)
    CASE WHEN gs % 10 < 7 THEN
        (ARRAY['Iron Vanguard','Crimson Eclipse','Silver Dawn','Shadow Pact',
               'Storm Riders','Frost Legion','Dragon Scale','Phoenix Order',
               'Blood Moon','Emerald Watch','Obsidian Guard','Celestial Choir',
               'Void Walkers','Thunder Hammer','Arcane Circle'])
            [1 + (gs * 3) % 15]
    ELSE NULL END AS gremio,

    (ARRAY['Norte','Sur','Este','Oeste','Centro'])[1 + gs % 5] AS region,

    -- Oro: entre 0 y 999,999 con distribución exponencial
    ROUND((random() * power(10, 1 + random() * 5))::NUMERIC, 2) AS oro_total,

    -- 90% activos, 10% inactivos
    gs % 10 != 0 AS esta_activo,

    -- Fecha registro: últimos 5 años
    '2021-01-01'::DATE + (gs % 1825) AS fecha_registro,

    -- Último login: últimos 365 días
    NOW() - ((gs % 365) || ' days')::INTERVAL - ((gs % 24) || ' hours')::INTERVAL
        AS ultimo_login

FROM generate_series(1, 100000) AS gs;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLA 2: batallas
--  500,000 registros de combate entre combatientes
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE guerra.batallas (
    batalla_id      SERIAL PRIMARY KEY,
    atacante_id     INT NOT NULL REFERENCES guerra.combatientes(combatiente_id),
    defensor_id     INT NOT NULL REFERENCES guerra.combatientes(combatiente_id),
    zona            TEXT NOT NULL,       -- 'Arena','Mazmorra','Campo Abierto','Bosque','Montaña','Pantano'
    tipo            TEXT NOT NULL,       -- 'PvP','PvE','Raid','Duelo','Torneo'
    danio_infligido INT NOT NULL,
    danio_recibido  INT NOT NULL,
    resultado       TEXT NOT NULL,       -- 'Victoria','Derrota','Empate'
    duracion_seg    INT NOT NULL,
    experiencia     INT NOT NULL,
    fecha_batalla   TIMESTAMPTZ NOT NULL
);

INSERT INTO guerra.batallas (
    atacante_id, defensor_id, zona, tipo,
    danio_infligido, danio_recibido, resultado,
    duracion_seg, experiencia, fecha_batalla
)
SELECT
    1 + (gs * 7) % 100000 AS atacante_id,
    1 + (gs * 13 + 51) % 100000 AS defensor_id,

    (ARRAY['Arena','Mazmorra','Campo Abierto','Bosque','Montaña','Pantano'])
        [1 + gs % 6] AS zona,

    (ARRAY['PvP','PvE','Raid','Duelo','Torneo'])
        [1 + gs % 5] AS tipo,

    50 + (gs * 17) % 9950 AS danio_infligido,
    30 + (gs * 23) % 9970 AS danio_recibido,

    (ARRAY['Victoria','Derrota','Empate'])[1 + gs % 3] AS resultado,

    10 + (gs * 11) % 3590 AS duracion_seg,

    10 + (gs * 7) % 990 AS experiencia,

    -- Fechas en los últimos 2 años
    NOW() - ((gs % 730) || ' days')::INTERVAL
         - ((gs % 24) || ' hours')::INTERVAL
         - ((gs % 60) || ' minutes')::INTERVAL
FROM generate_series(1, 500000) AS gs;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLA 3: misiones
--  200,000 misiones completadas con categorías y recompensas
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE guerra.misiones (
    mision_id       SERIAL PRIMARY KEY,
    combatiente_id  INT NOT NULL REFERENCES guerra.combatientes(combatiente_id),
    nombre_mision   TEXT NOT NULL,
    categoria       TEXT NOT NULL,       -- 'Principal','Secundaria','Diaria','Evento','Gremio'
    dificultad      TEXT NOT NULL,       -- 'Fácil','Normal','Difícil','Épica','Legendaria'
    recompensa_oro  NUMERIC(10,2) NOT NULL,
    recompensa_xp   INT NOT NULL,
    tiempo_min      INT NOT NULL,        -- minutos para completar
    completada      BOOLEAN NOT NULL DEFAULT true,
    fecha_inicio    TIMESTAMPTZ NOT NULL,
    fecha_fin       TIMESTAMPTZ
);

INSERT INTO guerra.misiones (
    combatiente_id, nombre_mision, categoria, dificultad,
    recompensa_oro, recompensa_xp, tiempo_min, completada,
    fecha_inicio, fecha_fin
)
SELECT
    1 + (gs * 11) % 100000 AS combatiente_id,

    'Misión_' || (ARRAY['Caza','Escolta','Recolección','Exploración','Defensa',
                         'Asalto','Rescate','Infiltración','Diplomacia','Forja'])
        [1 + gs % 10] || '_' || gs AS nombre_mision,

    (ARRAY['Principal','Secundaria','Diaria','Evento','Gremio'])
        [1 + gs % 5] AS categoria,

    (ARRAY['Fácil','Normal','Difícil','Épica','Legendaria'])
        [1 + (gs * 3) % 5] AS dificultad,

    ROUND((10 + (gs * 7) % 9990)::NUMERIC, 2) AS recompensa_oro,
    50 + (gs * 13) % 4950 AS recompensa_xp,
    5 + (gs * 3) % 175 AS tiempo_min,

    -- 85% completadas, 15% abandonadas
    gs % 20 < 17 AS completada,

    NOW() - ((gs % 730) || ' days')::INTERVAL AS fecha_inicio,

    CASE WHEN gs % 20 < 17
         THEN NOW() - ((gs % 730) || ' days')::INTERVAL + ((5 + (gs * 3) % 175) || ' minutes')::INTERVAL
         ELSE NULL
    END AS fecha_fin

FROM generate_series(1, 200000) AS gs;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLA 4: transacciones
--  300,000 transacciones del mercado (compra/venta de ítems)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE guerra.transacciones (
    transaccion_id  SERIAL PRIMARY KEY,
    vendedor_id     INT NOT NULL REFERENCES guerra.combatientes(combatiente_id),
    comprador_id    INT NOT NULL REFERENCES guerra.combatientes(combatiente_id),
    item_nombre     TEXT NOT NULL,
    item_categoria  TEXT NOT NULL,       -- 'Arma','Armadura','Poción','Pergamino','Material','Gema'
    item_rareza     TEXT NOT NULL,       -- 'Común','Infrecuente','Rara','Épica','Legendaria'
    cantidad        INT NOT NULL,
    precio_unitario NUMERIC(10,2) NOT NULL,
    precio_total    NUMERIC(12,2) NOT NULL,
    metodo_pago     TEXT NOT NULL,       -- 'Oro','Trueque','Crédito_Gremio','Subasta'
    fecha           TIMESTAMPTZ NOT NULL
);

INSERT INTO guerra.transacciones (
    vendedor_id, comprador_id, item_nombre, item_categoria, item_rareza,
    cantidad, precio_unitario, precio_total, metodo_pago, fecha
)
SELECT
    1 + (gs * 7) % 100000 AS vendedor_id,
    1 + (gs * 13 + 99) % 100000 AS comprador_id,

    (ARRAY['Espada de Fuego','Escudo de Hielo','Poción de Vida','Pergamino de Teletransporte',
           'Mineral de Mithril','Gema del Alma','Daga Sombría','Casco de Dragón',
           'Báculo Arcano','Anillo del Poder','Botas de Velocidad','Capa de Invisibilidad',
           'Hacha de Trueno','Arco Élfico','Martillo Sagrado','Amuleto Oscuro',
           'Guantes de Fuerza','Cinturón de Gigante','Varita de Rayos','Orbe Místico'])
        [1 + gs % 20] AS item_nombre,

    (ARRAY['Arma','Armadura','Poción','Pergamino','Material','Gema'])
        [1 + gs % 6] AS item_categoria,

    (ARRAY['Común','Infrecuente','Rara','Épica','Legendaria'])
        [1 + (gs * 3) % 5] AS item_rareza,

    1 + gs % 99 AS cantidad,
    ROUND((1 + (gs * 17) % 9999)::NUMERIC, 2) AS precio_unitario,
    ROUND(((1 + gs % 99) * (1 + (gs * 17) % 9999))::NUMERIC, 2) AS precio_total,

    (ARRAY['Oro','Trueque','Crédito_Gremio','Subasta'])[1 + gs % 4] AS metodo_pago,

    NOW() - ((gs % 730) || ' days')::INTERVAL
         - ((gs % 24) || ' hours')::INTERVAL
FROM generate_series(1, 300000) AS gs;


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLA 5: bitacora_eventos
--  250,000 eventos del servidor en orden cronológico (ideal para BRIN)
--
--  [NOTA PARA CLASE]: BRIN funciona porque los datos están NATURALMENTE
--  ordenados por fecha. Un B-Tree aquí funcionaría, pero BRIN ocupa
--  mucho menos espacio en disco.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE guerra.bitacora_eventos (
    evento_id       BIGSERIAL PRIMARY KEY,
    tipo_evento     TEXT NOT NULL,       -- 'LOGIN','LOGOUT','COMBATE','TRADE','QUEST','ERROR','CHAT','ACHIEVEMENT'
    severidad       TEXT NOT NULL,       -- 'INFO','WARNING','ERROR','CRITICAL'
    combatiente_id  INT REFERENCES guerra.combatientes(combatiente_id),
    descripcion     TEXT NOT NULL,
    ip_origen       TEXT,
    servidor        TEXT NOT NULL,       -- 'Realm-01' a 'Realm-10'
    timestamp_evento TIMESTAMPTZ NOT NULL
);

INSERT INTO guerra.bitacora_eventos (
    tipo_evento, severidad, combatiente_id, descripcion,
    ip_origen, servidor, timestamp_evento
)
SELECT
    (ARRAY['LOGIN','LOGOUT','COMBATE','TRADE','QUEST','ERROR','CHAT','ACHIEVEMENT'])
        [1 + gs % 8] AS tipo_evento,

    -- Mayoría INFO, pocos CRITICAL (distribución realista de logs)
    CASE
        WHEN gs % 100 < 70 THEN 'INFO'
        WHEN gs % 100 < 90 THEN 'WARNING'
        WHEN gs % 100 < 98 THEN 'ERROR'
        ELSE 'CRITICAL'
    END AS severidad,

    1 + (gs * 7) % 100000 AS combatiente_id,

    'Evento del sistema: ' || gs AS descripcion,

    -- IP simulada
    ((gs % 256)::TEXT || '.' || ((gs * 3) % 256)::TEXT || '.'
     || ((gs * 7) % 256)::TEXT || '.' || ((gs * 11) % 256)::TEXT) AS ip_origen,

    'Realm-' || LPAD((1 + gs % 10)::TEXT, 2, '0') AS servidor,

    -- CRUCIAL: los timestamps están en ORDEN CRONOLÓGICO (para BRIN)
    '2024-01-01 00:00:00+00'::TIMESTAMPTZ + (gs || ' seconds')::INTERVAL
        AS timestamp_evento

FROM generate_series(1, 250000) AS gs;


-- ═══════════════════════════════════════════════════════════════════════════════
--  ESTADÍSTICAS — Actualizar para que el query planner tenga datos frescos
-- ═══════════════════════════════════════════════════════════════════════════════

ANALYZE guerra.combatientes;
ANALYZE guerra.batallas;
ANALYZE guerra.misiones;
ANALYZE guerra.transacciones;
ANALYZE guerra.bitacora_eventos;


-- ═══════════════════════════════════════════════════════════════════════════════
--  ██████████████████████████████████████████████████████████████████████████████
--  █                                                                          █
--  █   ¡¡¡ NO CREAR ÍNDICES AQUÍ !!!                                          █
--  █                                                                          █
--  █   Los índices se crean EN VIVO durante la clase para demostrar           █
--  █   el ANTES y DESPUÉS con EXPLAIN ANALYZE.                                █
--  █                                                                          █
--  █   Ver el guión de clase para el orden de creación.                        █
--  █                                                                          █
--  ██████████████████████████████████████████████████████████████████████████████
-- ═══════════════════════════════════════════════════════════════════════════════


-- ═══════════════════════════════════════════════════════════════════════════════
--  SCRIPT DE REFERENCIA PARA EL PROFESOR
--  (Copiar y pegar durante la clase, NO se ejecuta automáticamente)
--
--  Estas son las consultas de demostración y los índices que se crearán
--  en vivo durante la clase. Están comentados para que no se ejecuten
--  en la inicialización de la base de datos.
-- ═══════════════════════════════════════════════════════════════════════════════

/*
-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 1: SEQUENTIAL SCAN vs INDEX SCAN (B-Tree)
--  Buscar un combatiente por nombre exacto
-- ═══════════════════════════════════════════════════════════════════════════

-- ANTES (sin índice) — Sequential Scan ~15-30ms
EXPLAIN ANALYZE
SELECT * FROM guerra.combatientes WHERE nombre = 'Guerrero_42000';

-- Crear índice B-Tree en nombre
CREATE INDEX idx_combatientes_nombre ON guerra.combatientes(nombre);

-- DESPUÉS (con índice) — Index Scan ~0.1ms
EXPLAIN ANALYZE
SELECT * FROM guerra.combatientes WHERE nombre = 'Guerrero_42000';


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 2: COSTO DE OPERACIONES — Comparar costos en EXPLAIN
--  Buscar batallas por rango de fechas
-- ═══════════════════════════════════════════════════════════════════════════

-- ANTES — Sequential Scan completo sobre 500K filas
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*), AVG(danio_infligido)
FROM guerra.batallas
WHERE fecha_batalla BETWEEN '2025-01-01' AND '2025-06-30';

-- Crear índice en fecha
CREATE INDEX idx_batallas_fecha ON guerra.batallas(fecha_batalla);

-- DESPUÉS — Index Scan con rango
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT COUNT(*), AVG(danio_infligido)
FROM guerra.batallas
WHERE fecha_batalla BETWEEN '2025-01-01' AND '2025-06-30';


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 3: HASH INDEX vs B-TREE
--  Búsqueda por igualdad exacta (Hash es ideal para =, no para rangos)
-- ═══════════════════════════════════════════════════════════════════════════

-- Primero, crear un Hash Index en la columna 'zona' de batallas
CREATE INDEX idx_batallas_zona_hash ON guerra.batallas USING HASH (zona);

-- Consulta con = (Hash funciona perfecto)
EXPLAIN ANALYZE
SELECT COUNT(*) FROM guerra.batallas WHERE zona = 'Arena';

-- Consulta con rango (Hash NO sirve, caerá en Seq Scan)
EXPLAIN ANALYZE
SELECT COUNT(*) FROM guerra.batallas WHERE zona >= 'B' AND zona <= 'M';

-- Comparar: crear un B-Tree en la misma columna
CREATE INDEX idx_batallas_zona_btree ON guerra.batallas USING BTREE (zona);

-- Ahora el rango SÍ usa índice
EXPLAIN ANALYZE
SELECT COUNT(*) FROM guerra.batallas WHERE zona >= 'B' AND zona <= 'M';


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 4: ÍNDICE COMPUESTO (Composite/Multi-column Index)
--  Buscar transacciones por categoría Y rareza — dos columnas juntas
-- ═══════════════════════════════════════════════════════════════════════════

-- ANTES — Sequential Scan sobre 300K filas
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(precio_total)
FROM guerra.transacciones
WHERE item_categoria = 'Arma' AND item_rareza = 'Legendaria';

-- Índice compuesto (el ORDEN de las columnas importa)
CREATE INDEX idx_trans_cat_rareza ON guerra.transacciones(item_categoria, item_rareza);

-- DESPUÉS — Index Scan eficiente
EXPLAIN ANALYZE
SELECT COUNT(*), SUM(precio_total)
FROM guerra.transacciones
WHERE item_categoria = 'Arma' AND item_rareza = 'Legendaria';

-- PREGUNTA PARA LA CLASE: ¿Esta consulta usa el índice compuesto?
-- Solo filtra por la SEGUNDA columna del índice
EXPLAIN ANALYZE
SELECT COUNT(*) FROM guerra.transacciones WHERE item_rareza = 'Legendaria';
-- Respuesta: NO (o ineficientemente). El índice compuesto sigue el orden
-- de izquierda a derecha. Si no filtras por la primera columna, no sirve.


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 5: BRIN INDEX — Ideal para datos ordenados cronológicamente
--  La bitácora de eventos está naturalmente ordenada por timestamp
-- ═══════════════════════════════════════════════════════════════════════════

-- ANTES — Seq Scan sobre 250K filas
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM guerra.bitacora_eventos
WHERE timestamp_evento BETWEEN '2024-03-01' AND '2024-03-31';

-- BRIN: Block Range INdex (almacena min/max por bloque de páginas)
CREATE INDEX idx_bitacora_brin ON guerra.bitacora_eventos
    USING BRIN (timestamp_evento) WITH (pages_per_range = 32);

-- DESPUÉS — BRIN Scan (mucho más pequeño que B-Tree)
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM guerra.bitacora_eventos
WHERE timestamp_evento BETWEEN '2024-03-01' AND '2024-03-31';

-- Comparar tamaño: BRIN vs B-Tree hipotético
SELECT pg_size_pretty(pg_relation_size('idx_bitacora_brin')) AS tamano_brin;

CREATE INDEX idx_bitacora_btree ON guerra.bitacora_eventos(timestamp_evento);
SELECT pg_size_pretty(pg_relation_size('idx_bitacora_btree')) AS tamano_btree;
-- BRIN será ~100x más pequeño


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 6: PARTIAL INDEX — Índice solo para un subconjunto de filas
--  Solo nos interesan los combatientes activos de alto nivel
-- ═══════════════════════════════════════════════════════════════════════════

-- Sin índice parcial — escanea TODOS los 100K combatientes
EXPLAIN ANALYZE
SELECT * FROM guerra.combatientes
WHERE esta_activo = true AND nivel > 80
ORDER BY nivel DESC;

-- Índice parcial: solo indexa filas donde esta_activo = true Y nivel > 80
CREATE INDEX idx_combatientes_elite ON guerra.combatientes(nivel DESC)
    WHERE esta_activo = true AND nivel > 80;

-- Ahora: solo recorre el subconjunto pequeño
EXPLAIN ANALYZE
SELECT * FROM guerra.combatientes
WHERE esta_activo = true AND nivel > 80
ORDER BY nivel DESC;


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 7: COVERING INDEX (INCLUDE) — Evitar el viaje de vuelta a la tabla
--  Index-Only Scan: toda la info está EN el índice
-- ═══════════════════════════════════════════════════════════════════════════

-- Queremos nombre y nivel de los guerreros
EXPLAIN ANALYZE
SELECT nombre, nivel FROM guerra.combatientes WHERE clase = 'Guerrero';

-- Covering index: incluye nombre y nivel DENTRO del índice
CREATE INDEX idx_combatientes_clase_cover ON guerra.combatientes(clase)
    INCLUDE (nombre, nivel);

-- Ahora: Index-Only Scan (no toca la tabla heap)
EXPLAIN ANALYZE
SELECT nombre, nivel FROM guerra.combatientes WHERE clase = 'Guerrero';


-- ═══════════════════════════════════════════════════════════════════════════
--  DEMO 8: TAMAÑO DE ÍNDICES — El costo de espacio en disco
--  Ver cuánto espacio ocupa cada índice
-- ═══════════════════════════════════════════════════════════════════════════

SELECT
    indexname,
    pg_size_pretty(pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(indexname))) AS tamano,
    pg_size_pretty(pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(tablename))) AS tamano_tabla
FROM pg_indexes
WHERE schemaname = 'guerra'
ORDER BY pg_relation_size(quote_ident(schemaname) || '.' || quote_ident(indexname)) DESC;

*/

-- ═══════════════════════════════════════════════════════════════════════════════
--  VISTA DE RESUMEN — Para verificar que los datos se cargaron correctamente
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW guerra.resumen_archivo AS
SELECT 'combatientes' AS tabla, COUNT(*) AS filas FROM guerra.combatientes
UNION ALL
SELECT 'batallas', COUNT(*) FROM guerra.batallas
UNION ALL
SELECT 'misiones', COUNT(*) FROM guerra.misiones
UNION ALL
SELECT 'transacciones', COUNT(*) FROM guerra.transacciones
UNION ALL
SELECT 'bitacora_eventos', COUNT(*) FROM guerra.bitacora_eventos;

-- Mostrar resumen al cargar
SELECT * FROM guerra.resumen_archivo;
