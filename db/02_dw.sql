-- ═══════════════════════════════════════════════════════════════════════════════════
--  ◈  THE SHATTERED DOMINION  —  Data Warehouse de Modelado Dimensional
--
--  Este archivo vive en el schema "dw" del mismo PostgreSQL.
--  El schema "public" contiene las tablas OLTP (Chronicles of the Broken Realm).
--  Este schema contiene el DW que DERIVARÍA de esas tablas en producción real.
--
--  CONCEPTOS QUE CUBRE ESTA BASE DE DATOS:
--    1. Esquema Estrella (Star Schema)
--    2. Esquema Copo de Nieve (Snowflake Schema) — ver dim_zona
--    3. Tablas de Dimensiones — tipos, atributos, surrogate keys
--    4. Slowly Changing Dimensions (SCD) Tipo 1, Tipo 2 y Tipo 3
--    5. Tablas de Hechos — transaccional, snapshot periódico, acumulativa
--    6. Grano (Grain) de una tabla de hechos
--    7. Métricas derivadas vs métricas aditivas
--    8. Desnormalización como decisión arquitectónica correcta
--    9. Dimensión de Tiempo (obligatoria en todo DW)
--   10. Dimensión degenerada y dimensión junk/basura
--
--  DIAGRAMA DE RELACIONES (Star Schema principal):
--
--              dim_tiempo
--                  │
--    dim_gremio ───┤
--    dim_zona   ───┼──── fact_combate ────── dim_personaje
--    dim_habilidad─┤
--                  │
--              dim_monstruo
--
--  ADVERTENCIA PEDAGÓGICA:
--    En un DW real, estas tablas se alimentarían desde el OLTP mediante un proceso
--    ETL (Extract, Transform, Load). Aquí los datos están pre-cargados para estudio.
-- ═══════════════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS dw;
SET search_path TO dw, public;


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 0 — DIMENSIÓN DE TIEMPO
--
--  La dimensión de tiempo es OBLIGATORIA en cualquier Data Warehouse.
--  NUNCA se hace JOIN a una tabla de fechas del sistema (NOW(), CURRENT_DATE).
--  En su lugar, se pre-populan todos los días del período de análisis.
--
--  PREGUNTA PARA LA CLASE:
--    ¿Por qué es mejor tener una fila por cada día que hacer EXTRACT(MONTH FROM fecha)?
--    Respuesta: Porque puedes agregar atributos de negocio: es_fin_de_semana,
--    es_temporada_alta, nombre_evento_especial, etc. Eso no lo da EXTRACT().
--
--  GRAIN: Una fila por día calendario.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_tiempo (
    tiempo_id           INT PRIMARY KEY,          -- surrogate key: YYYYMMDD
    fecha               DATE NOT NULL,
    anio                INT NOT NULL,
    trimestre           INT NOT NULL,             -- 1-4
    mes                 INT NOT NULL,             -- 1-12
    nombre_mes          TEXT NOT NULL,
    semana_del_anio     INT NOT NULL,
    dia_del_mes         INT NOT NULL,
    dia_de_semana       INT NOT NULL,             -- 1=lunes, 7=domingo
    nombre_dia          TEXT NOT NULL,
    es_fin_de_semana    BOOLEAN NOT NULL,
    es_evento_especial  BOOLEAN DEFAULT false,
    nombre_evento       TEXT                      -- 'Doble XP', 'Festival del Vacío', NULL
);

-- Poblar 90 días de datos (generado proceduralmente)
INSERT INTO dw.dim_tiempo
SELECT
    TO_CHAR(d, 'YYYYMMDD')::INT             AS tiempo_id,
    d::DATE                                  AS fecha,
    EXTRACT(YEAR  FROM d)::INT               AS anio,
    EXTRACT(QUARTER FROM d)::INT             AS trimestre,
    EXTRACT(MONTH FROM d)::INT               AS mes,
    TO_CHAR(d, 'TMMonth')                    AS nombre_mes,
    EXTRACT(WEEK  FROM d)::INT               AS semana_del_anio,
    EXTRACT(DAY   FROM d)::INT               AS dia_del_mes,
    EXTRACT(ISODOW FROM d)::INT              AS dia_de_semana,
    TO_CHAR(d, 'TMDay')                      AS nombre_dia,
    EXTRACT(ISODOW FROM d) IN (6,7)          AS es_fin_de_semana,
    -- Eventos especiales hardcodeados para análisis
    d::DATE IN (
        '2025-01-01','2025-01-15','2025-02-14',
        '2025-03-01','2025-03-15','2025-03-20'
    )                                        AS es_evento_especial,
    CASE d::DATE
        WHEN '2025-01-01' THEN 'Año Nuevo del Reino'
        WHEN '2025-01-15' THEN 'Doble XP Weekend'
        WHEN '2025-02-14' THEN 'Festival del Amor Eterno'
        WHEN '2025-03-01' THEN 'Invasión del Vacío'
        WHEN '2025-03-15' THEN 'Torneo de Campeones'
        WHEN '2025-03-20' THEN 'Equinoccio de Sangre'
        ELSE NULL
    END                                      AS nombre_evento
FROM GENERATE_SERIES(
    '2025-01-01'::TIMESTAMP,
    '2025-03-31'::TIMESTAMP,
    '1 day'::INTERVAL
) AS d;


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 1 — DIM_JUGADOR  (Slowly Changing Dimension — Tipo 2)
--
--  CONCEPTO SCD TIPO 2:
--    Cuando un atributo de un jugador cambia (sube de tier, cambia de región),
--    NO sobreescribimos la fila. En su lugar, "cerramos" la fila anterior
--    y creamos una fila nueva. Así conservamos el historial completo.
--
--  CLAVES:
--    jugador_sk  — Surrogate Key: clave artificial del DW. NUNCA es el ID del OLTP.
--    jugador_nk  — Natural Key: el ID del sistema origen (player_id del OLTP).
--    es_actual   — Flag que indica cuál es la versión vigente.
--    fecha_inicio / fecha_fin — Período de vigencia del registro.
--
--  PREGUNTA PARA LA CLASE:
--    Si un jugador cambió de 'Free' a 'Legendary' el 15 de enero,
--    ¿cuántas filas tiene en esta tabla? ¿Cuál tiene es_actual = true?
--    ¿Qué pasa con los hechos registrados ANTES del cambio de tier?
--
--  GRAIN: Una fila por versión de jugador (puede haber múltiples por jugador_nk).
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_jugador (
    jugador_sk          SERIAL PRIMARY KEY,       -- surrogate key (DW interno)
    jugador_nk          INT NOT NULL,             -- natural key (player_id del OLTP)
    username            TEXT NOT NULL,
    email               TEXT NOT NULL,
    pais                TEXT,
    region              TEXT,
    tier                TEXT,                     -- el atributo que cambia → genera nueva versión
    precio_mensual      NUMERIC(6,2),             -- desnormalizado desde tier (correcto en DW)
    -- Columnas de control SCD Tipo 2
    fecha_inicio        DATE NOT NULL,
    fecha_fin           DATE,                     -- NULL = registro vigente
    es_actual           BOOLEAN DEFAULT true,
    -- Columna SCD Tipo 3 bonus: guarda el tier ANTERIOR (solo 1 nivel de historia)
    tier_anterior       TEXT                      -- SCD Tipo 3: columna adicional para valor previo
);

INSERT INTO dw.dim_jugador
    (jugador_nk, username, email, pais, region, tier, precio_mensual,
     fecha_inicio, fecha_fin, es_actual, tier_anterior)
VALUES
-- Kael: siempre Legendary
(1,  'Kael_Stormborn',  'kael@realm.io',   'Mexico',  'LATAM', 'Legendary', 14.99, '2024-06-01', NULL,         true,  NULL),
-- Seraphina: siempre Legendary
(2,  'Seraphina',       'sera@realm.io',   'Mexico',  'LATAM', 'Legendary', 14.99, '2024-05-15', NULL,         true,  NULL),
-- DarkPaladin: subió de Free a Premium (versión antigua cerrada)
(3,  'DarkPaladin99',   'dp99@realm.io',   'USA',     'NA',    'Free',       0.00, '2024-08-01', '2025-01-14', false, NULL),
-- DarkPaladin: versión actual después del upgrade
(3,  'DarkPaladin99',   'dp99@realm.io',   'USA',     'NA',    'Premium',    9.99, '2025-01-15', NULL,         true,  'Free'),
-- Zyx: Free, luego Premium, luego volvió a Free (3 versiones)
(4,  'Zyx_the_Void',    'zyx@realm.io',    'Japan',   'APAC',  'Free',       0.00, '2024-07-01', '2024-11-30', false, NULL),
(4,  'Zyx_the_Void',    'zyx@realm.io',    'Japan',   'APAC',  'Premium',    9.99, '2024-12-01', '2025-02-28', false, 'Free'),
(4,  'Zyx_the_Void',    'zyx@realm.io',    'Japan',   'APAC',  'Free',       0.00, '2025-03-01', NULL,         true,  'Premium'),
-- Morrigan: siempre Legendary
(5,  'Morrigan',        'morri@realm.io',  'Japan',   'APAC',  'Legendary', 14.99, '2024-04-01', NULL,         true,  NULL),
-- Theron: Free → Premium
(6,  'Theron_Ashblade', 'theron@realm.io', 'Mexico',  'LATAM', 'Free',       0.00, '2024-09-01', '2025-02-28', false, NULL),
(6,  'Theron_Ashblade', 'theron@realm.io', 'Mexico',  'LATAM', 'Premium',    9.99, '2025-03-01', NULL,         true,  'Free'),
-- NightWalker: Free
(7,  'NightWalker',     'nw@realm.io',     'USA',     'NA',    'Free',       0.00, '2024-10-01', NULL,         true,  NULL),
-- Eldritch: Legendary desde siempre
(8,  'Eldritch_One',    'eld@realm.io',    'Germany', 'EU',    'Legendary', 14.99, '2023-01-01', NULL,         true,  NULL),
-- VoidReaper: Free → Premium → Legendary (3 versiones)
(9,  'VoidReaper',      'void@realm.io',   'Germany', 'EU',    'Free',       0.00, '2024-06-01', '2024-12-31', false, NULL),
(9,  'VoidReaper',      'void@realm.io',   'Germany', 'EU',    'Premium',    9.99, '2025-01-01', '2025-02-28', false, 'Free'),
(9,  'VoidReaper',      'void@realm.io',   'Germany', 'EU',    'Legendary', 14.99, '2025-03-01', NULL,         true,  'Premium'),
-- LostSoul: Free
(10, 'LostSoul42',      'lost@realm.io',   'Mexico',  'LATAM', 'Free',       0.00, '2025-01-10', NULL,         true,  NULL);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 2 — DIM_PERSONAJE  (SCD Tipo 1 — sobreescritura)
--
--  CONCEPTO SCD TIPO 1:
--    Cuando el personaje sube de nivel o cambia de gremio, simplemente
--    sobreescribimos el valor. NO se guarda historial. La dimensión siempre
--    refleja el estado ACTUAL del personaje.
--
--    Esto es correcto para atributos donde el historial no importa para el análisis
--    (nadie quiere saber que un personaje era nivel 5 hace 6 meses).
--    Pero sí importa para el tier del jugador → por eso dim_jugador es SCD2.
--
--  NOTA DE DISEÑO:
--    guild_name está DESNORMALIZADO aquí (podría ser FK a dim_gremio).
--    En un Star Schema puro, es válido desnormalizarlo para evitar JOINs en queries.
--    En un Snowflake Schema, sería una FK. Ambas decisiones son defensibles.
--
--  GRAIN: Una fila por personaje (versión actual).
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_personaje (
    personaje_sk        SERIAL PRIMARY KEY,
    personaje_nk        INT NOT NULL,             -- char_id del OLTP
    nombre              TEXT NOT NULL,
    raza                TEXT,
    clase               TEXT,
    nivel_actual        INT,
    -- Atributos desnormalizados de raza y clase (correcto en Star Schema)
    raza_homeland       TEXT,
    clase_stat_primario TEXT,
    -- Gremio desnormalizado (Star Schema) vs FK (Snowflake Schema)
    guild_name          TEXT,                     -- desnormalizado = Star Schema
    guild_id            INT,                      -- FK disponible si se quiere Snowflake
    -- Estadísticas acumuladas al momento del último ETL
    nivel_maximo_alcanzado INT,
    total_kills_historico  BIGINT DEFAULT 0,
    -- Control
    ultima_actualizacion TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO dw.dim_personaje
    (personaje_nk, nombre, raza, clase, nivel_actual, raza_homeland, clase_stat_primario,
     guild_name, guild_id, nivel_maximo_alcanzado, total_kills_historico)
VALUES
(1,  'Kael',         'Human', 'Warrior',  42, 'Stormhaven',       'Strength',     'Iron Vanguard',   1, 42,  2100),
(2,  'Seraphina',    'Elf',   'Mage',     67, 'Silverwood',       'Intelligence', 'Iron Vanguard',   1, 67,  4890),
(3,  'DarkPaladin',  'Human', 'Paladin',  35, 'Stormhaven',       'Strength',     'Iron Vanguard',   1, 35,   980),
(4,  'VoidZyx',      'Undead','Rogue',    58, 'Necropolis',       'Agility',      'Crimson Eclipse', 2, 58,  3300),
(5,  'Morrigan',     'Elf',   'Warlock',  71, 'Silverwood',       'Intelligence', 'Crimson Eclipse', 2, 71,  5210),
(6,  'Theron',       'Orc',   'Warrior',  29, 'Bloodmire Wastes', 'Strength',     'Crimson Eclipse', 2, 29,   540),
(7,  'Shadow',       'Human', 'Rogue',    22, 'Stormhaven',       'Agility',      'Silver Dawn',     3, 22,   210),
(8,  'Eldritch',     'Undead','Mage',     80, 'Necropolis',       'Intelligence', 'Silver Dawn',     3, 80,  8420),
(9,  'VoidReaper',   'Orc',   'Warrior',  15, 'Bloodmire Wastes', 'Strength',     NULL,           NULL, 15,    45),
(10, 'LostOne',      'Human', 'Mage',      3, 'Stormhaven',       'Intelligence', NULL,           NULL,  3,     2);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 3 — DIM_ZONA  (Snowflake Schema — dimensión normalizada en niveles)
--
--  CONCEPTO SNOWFLAKE:
--    En un Star Schema puro, todos los atributos de zona estarían en una sola tabla.
--    En un Snowflake Schema, dividimos la dimensión en subdimensiones:
--    dim_zona → dim_continente → dim_mundo
--
--    Esto reduce redundancia pero AÑADE JOINs a los queries analíticos.
--    La pregunta pedagógica: ¿vale la pena?
--    Respuesta: En la mayoría de los DW modernos, NO. El espacio en disco es barato.
--    Los JOINs extra son caros en queries de millones de filas.
--
--  ESTE ES EL ÚNICO LUGAR EN EL DW DONDE MOSTRAMOS EL SNOWFLAKE.
--  Todo lo demás es Star Schema para facilitar análisis.
-- ═══════════════════════════════════════════════════════════════════════════════════

-- Sub-dimensión: continentes del mundo
CREATE TABLE dw.dim_continente (
    continente_id   SERIAL PRIMARY KEY,
    nombre          TEXT NOT NULL,
    tipo_clima      TEXT,               -- 'Ártico','Tropical','Árido','Templado','Mágico'
    nivel_peligro   TEXT                -- 'Bajo','Medio','Alto','Extremo'
);

INSERT INTO dw.dim_continente (nombre, tipo_clima, nivel_peligro) VALUES
('Tierras del Norte',  'Ártico',   'Alto'),
('Imperio Central',    'Templado', 'Medio'),
('Desierto Ardiente',  'Árido',    'Alto'),
('Bosques Eternos',    'Tropical', 'Medio'),
('El Vacío Exterior',  'Mágico',   'Extremo');

-- Dimensión de zonas (apunta a continente → Snowflake)
CREATE TABLE dw.dim_zona (
    zona_sk         SERIAL PRIMARY KEY,
    zona_nk         TEXT NOT NULL,              -- nombre de zona como clave natural
    nombre_zona     TEXT NOT NULL,
    tipo_zona       TEXT,                       -- 'Dungeon','Ciudad','Campo','Raid','PvP'
    nivel_minimo    INT DEFAULT 1,
    nivel_maximo    INT DEFAULT 100,
    es_pvp          BOOLEAN DEFAULT false,
    es_raid         BOOLEAN DEFAULT false,
    continente_id   INT REFERENCES dw.dim_continente(continente_id),  -- FK al Snowflake
    -- Atributos de continente desnormalizados para facilitar queries (híbrido)
    continente_nombre TEXT,
    nivel_peligro   TEXT
);

INSERT INTO dw.dim_zona
    (zona_nk, nombre_zona, tipo_zona, nivel_minimo, nivel_maximo, es_pvp, es_raid, continente_id, continente_nombre, nivel_peligro)
VALUES
('iron_citadel',       'Iron Citadel',          'Dungeon',  35, 50,  false, false, 1, 'Tierras del Norte',  'Alto'),
('tower_of_echoes',    'Tower of Echoes',        'Raid',     55, 70,  false, true,  2, 'Imperio Central',    'Medio'),
('cathedral_of_dawn',  'Cathedral of Dawn',      'Dungeon',  25, 45,  false, false, 2, 'Imperio Central',    'Medio'),
('the_undercity',      'The Undercity',          'PvP',      45, 65,  true,  false, 1, 'Tierras del Norte',  'Alto'),
('cursed_sanctum',     'Cursed Sanctum',         'Raid',     60, 80,  false, true,  5, 'El Vacío Exterior',  'Extremo'),
('bloodmire_wastes',   'Bloodmire Wastes',       'Campo',    20, 40,  false, false, 3, 'Desierto Ardiente',  'Alto'),
('duskwood',           'Duskwood',               'Campo',    15, 30,  false, false, 4, 'Bosques Eternos',    'Medio'),
('void_rift',          'Void Rift',              'Raid',     70, 99,  false, true,  5, 'El Vacío Exterior',  'Extremo'),
('starting_village',   'Starting Village',       'Ciudad',    1, 10,  false, false, 2, 'Imperio Central',    'Bajo'),
('ashenvale',          'Ashenvale Forest',       'Campo',    10, 25,  false, false, 4, 'Bosques Eternos',    'Medio'),
('arena_champions',    'Arena de Campeones',     'PvP',       1, 99,  true,  false, 2, 'Imperio Central',    'Medio'),
('market_district',    'Distrito del Mercado',   'Ciudad',    1, 99,  false, false, 2, 'Imperio Central',    'Bajo');


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 4 — DIM_ITEM  (Dimensión de producto — muy usada en el fact de economía)
--
--  CONCEPTO DE DIMENSIÓN "GRUESA":
--    Una dimensión rica en atributos descriptivos NO relacionados entre sí.
--    No hay dependencias funcionales entre columnas → no hay nada que normalizar.
--    Esto es correcto en un DW. La redundancia es el precio por la velocidad de query.
--
--  stat_ataque, stat_defensa, etc.: en el OLTP esto era un campo TEXT con 'STR+15,VIT+10'
--  Aquí lo TRANSFORMAMOS (ETL) en columnas atómicas para poder agregarlas y filtrarlas.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_item (
    item_sk         SERIAL PRIMARY KEY,
    item_nk         INT NOT NULL,               -- item_id del OLTP
    nombre          TEXT NOT NULL,
    tipo            TEXT,
    subtipo         TEXT,
    rareza          TEXT,
    nivel_requerido INT,
    valor_base      INT,
    -- Stats atómicos (ETL transformó el campo CSV del OLTP)
    stat_fuerza     INT DEFAULT 0,
    stat_agilidad   INT DEFAULT 0,
    stat_inteligencia INT DEFAULT 0,
    stat_vitalidad  INT DEFAULT 0,
    stat_defensa    INT DEFAULT 0,
    stat_critico_pct NUMERIC(5,2) DEFAULT 0,
    -- Atributos de vendor desnormalizados (correcto en DW)
    vendor_nombre   TEXT,
    vendor_ciudad   TEXT,
    es_comerciable  BOOLEAN DEFAULT true,
    es_consumible   BOOLEAN DEFAULT false
);

INSERT INTO dw.dim_item
    (item_nk, nombre, tipo, subtipo, rareza, nivel_requerido, valor_base,
     stat_fuerza, stat_agilidad, stat_inteligencia, stat_vitalidad, stat_defensa, stat_critico_pct,
     vendor_nombre, vendor_ciudad, es_comerciable, es_consumible)
VALUES
(1,  'Warblade of the Fallen',  'Weapon',    'Longsword',  'Legendary', 40, 15000, 30, 0,  0,  15, 0,  8.0,  'Aldric the Armorer', 'Ironforge City', true,  false),
(2,  'Staff of Eternity',        'Weapon',    'Staff',      'Legendary', 60, 18000, 0,  0,  45, 0,  0,  0.0,  'Mystica',            'Arcane Spire',   true,  false),
(3,  'Shadowfang Daggers',       'Weapon',    'Dagger',     'Epic',      50,  9000, 0,  25, 0,  0,  0,  15.0, 'Shade Merchant',     'Undercroft',     true,  false),
(4,  'Plate of the Crusader',    'Armor',     'Chest',      'Rare',      35,  6000, 0,  0,  0,  20, 40, 0.0,  'Aldric the Armorer', 'Ironforge City', true,  false),
(5,  'Robes of the Archmage',    'Armor',     'Chest',      'Legendary', 65, 20000, 0,  0,  35, 0,  0,  0.0,  'Mystica',            'Arcane Spire',   true,  false),
(6,  'Cloak of Shadows',         'Armor',     'Cloak',      'Epic',      45,  8000, 0,  20, 0,  0,  0,  12.0, 'Shade Merchant',     'Undercroft',     true,  false),
(7,  'Ring of Vigor',            'Accessory', 'Ring',       'Uncommon',  20,  1200, 0,  0,  0,  10, 0,  0.0,  'Aldric the Armorer', 'Ironforge City', true,  false),
(8,  'Healing Potion',           'Consumable','Potion',     'Common',     1,    50, 0,  0,  0,  0,  0,  0.0,  'Mira',               'Crossroads',     true,  true),
(9,  'Mana Elixir',              'Consumable','Potion',     'Common',     1,    60, 0,  0,  0,  0,  0,  0.0,  'Mira',               'Crossroads',     true,  true),
(10, 'Scroll of Recall',         'Consumable','Scroll',     'Uncommon',  10,   200, 0,  0,  0,  0,  0,  0.0,  'Mira',               'Crossroads',     true,  true),
(11, 'Holy Avenger',             'Weapon',    'Longsword',  'Legendary', 50, 17000, 25, 0,  0,  20, 0,  0.0,  'Aldric the Armorer', 'Ironforge City', true,  false),
(12, 'Void Crystal Staff',       'Weapon',    'Staff',      'Epic',      65, 14000, 0,  0,  38, 0,  0,  0.0,  'Shade Merchant',     'Undercroft',     true,  false),
(13, 'Crude Axe',                'Weapon',    'Axe',        'Common',     1,    30, 2,  0,  0,  0,  0,  0.0,  'Mira',               'Crossroads',     true,  false);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 5 — DIM_MONSTRUO  (Dimensión auxiliar para fact_combate)
--
--  Algunos registros de combate son contra monstruos NPC, no contra otros jugadores.
--  Esta dimensión cubre esos casos. Los combates JcJ (jugador vs jugador) usarán
--  dim_personaje como dimensión del defensor.
--
--  CONCEPTO: DIMENSIÓN DE ROL MÚLTIPLE (Role-Playing Dimension)
--    dim_personaje puede actuar como "atacante" Y como "defensor" en fact_combate.
--    dim_monstruo cubre los NPC. Un FK puede apuntar a una u otra según el tipo de combate.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_monstruo (
    monstruo_sk     SERIAL PRIMARY KEY,
    nombre          TEXT NOT NULL,
    tipo            TEXT,               -- 'Humanoide','No-Muerto','Elemental','Dragón','Demonio'
    nivel           INT,
    vida_base       INT,
    es_jefe         BOOLEAN DEFAULT false,
    zona_nativa     TEXT,
    xp_recompensa   INT DEFAULT 0,
    oro_recompensa  INT DEFAULT 0
);

INSERT INTO dw.dim_monstruo
    (nombre, tipo, nivel, vida_base, es_jefe, zona_nativa, xp_recompensa, oro_recompensa)
VALUES
('Skeleton Warrior',  'No-Muerto',  38, 2400,  false, 'tower_of_echoes',   800,   45),
('Void Wraith',       'Elemental',  52, 3200,  false, 'tower_of_echoes',  1400,   80),
('Iron Golem',        'Construido', 45, 4800,  false, 'iron_citadel',     1200,  120),
('Undead Knight',     'No-Muerto',  40, 3600,  false, 'cathedral_of_dawn', 900,   55),
('Ancient Dragon',    'Dragón',     85, 95000, true,  'void_rift',       50000, 5000),
('Ice Elemental',     'Elemental',  60, 5800,  false, 'tower_of_echoes',  2800,  190),
('Boar',              'Bestia',     18,  480,  false, 'bloodmire_wastes',  120,    8),
('Bandit',            'Humanoide',  20,  620,  false, 'duskwood',          180,   22),
('Paladin NPC',       'Humanoide',  55, 6200,  false, 'cursed_sanctum',   2400,  310),
('Shadow Stalker',    'Demonio',    48, 4100,  false, 'the_undercity',    1600,  180),
('Flame Golem',       'Elemental',  42, 3900,  false, 'bloodmire_wastes', 1100,  100),
('Void Titan',        'Demonio',    90,120000, true,  'void_rift',       80000, 9000),
('Crystal Spider',    'Bestia',     28, 1200,  false, 'duskwood',          350,   30),
('Lich Herald',       'No-Muerto',  70, 22000, true,  'cursed_sanctum',  18000, 2200);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 6 — DIM_HABILIDAD  (Dimensión simple / de referencia)
--
--  Versión normalizada y limpia de lo que en el OLTP era character_skills con datos
--  duplicados por personaje. Aquí cada habilidad existe UNA SOLA VEZ.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_habilidad (
    habilidad_sk        SERIAL PRIMARY KEY,
    nombre              TEXT NOT NULL UNIQUE,
    escuela             TEXT,
    tipo_dano           TEXT,               -- 'fire','arcane','void','holy','physical',NULL
    es_aoe              BOOLEAN DEFAULT false,
    rango_max           INT DEFAULT 5,
    costo_mana_base     INT DEFAULT 0,
    tiene_cooldown      BOOLEAN DEFAULT true
);

INSERT INTO dw.dim_habilidad (nombre, escuela, tipo_dano, es_aoe, rango_max, costo_mana_base, tiene_cooldown) VALUES
('Cleave',         'Warrior',   'physical', true,  5, 20,  false),
('Shield Wall',    'Warrior',   NULL,       false, 5, 15,  true),
('Battle Cry',     'Warrior',   NULL,       true,  5, 25,  true),
('Fireball',       'Evocation', 'fire',     true,  5, 80,  false),
('Arcane Blast',   'Evocation', 'arcane',   false, 5, 60,  false),
('Mana Storm',     'Evocation', 'arcane',   true,  5,150,  true),
('Blink',          'Conjuration',NULL,      false, 3, 30,  true),
('Corruption',     'Warlock',   'void',     false, 5, 70,  false),
('Drain Soul',     'Warlock',   'void',     false, 5, 55,  false),
('Fel Armor',      'Warlock',   NULL,       false, 5, 40,  true),
('Oblivion Wave',  'Forbidden', 'void',     true,  5,200,  true),
('Soul Rend',      'Forbidden', 'void',     false, 5,180,  false),
('Void Collapse',  'Forbidden', 'void',     true,  5,350,  true),
('Shadowstep',     'Rogue',     NULL,       false, 5, 20,  true),
('Eviserate',      'Rogue',     'physical', false, 5, 35,  false),
('Holy Strike',    'Paladin',   'holy',     false, 5, 50,  false),
('Divine Shield',  'Paladin',   NULL,       false, 3, 80,  true),
('Melee',          NULL,        'physical', false, 1,  0,  false);  -- acción básica sin habilidad


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 7 — DIM_GREMIO  (SCD Tipo 1 — sin historial)
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.dim_gremio (
    gremio_sk       SERIAL PRIMARY KEY,
    gremio_nk       INT NOT NULL,
    nombre          TEXT NOT NULL,
    tag             TEXT,
    nivel           INT DEFAULT 1,
    servidor        TEXT,
    region          TEXT,
    total_miembros  INT DEFAULT 0       -- desnormalizado (debate: trigger vs COUNT)
);

INSERT INTO dw.dim_gremio (gremio_nk, nombre, tag, nivel, servidor, region, total_miembros) VALUES
(1, 'Iron Vanguard',   '[IRON]', 8,  'Realm-01', 'NA',   3),
(2, 'Crimson Eclipse', '[CRIM]', 12, 'Realm-02', 'APAC', 3),
(3, 'Silver Dawn',     '[SLVR]', 15, 'Realm-02', 'APAC', 2);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 8 — FACT_COMBATE
--
--  TIPO: Tabla de Hechos TRANSACCIONAL
--    Una fila por cada acción de combate individual (golpe, hechizo, etc.).
--    Es el tipo más común y el más granular.
--
--  GRAIN (GRANO): "Un registro por cada acción de combate ejecutada por un
--    personaje en una zona en un instante de tiempo."
--
--  MÉTRICAS:
--    - dano_infligido:  ADITIVA  — se puede sumar por cualquier dimensión
--    - es_critico:      NO ADITIVA — no tiene sentido sumar booleans
--    - costo_mana:      ADITIVA
--    - dano_por_segundo: SEMI-ADITIVA — se puede promediar pero no sumar (¡trampa!)
--
--  FOREIGN KEYS:
--    El defensor puede ser un personaje (combate JcJ) O un monstruo (JcE).
--    Solo uno de los dos tendrá valor; el otro será NULL.
--    Esto se llama "dimensión de rol múltiple" o "dimensión optativa".
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.fact_combate (
    -- Surrogate key de la tabla de hechos (opcional pero recomendado)
    combate_sk          BIGSERIAL PRIMARY KEY,
    -- Foreign Keys a dimensiones
    tiempo_id           INT  REFERENCES dw.dim_tiempo(tiempo_id),
    atacante_sk         INT  REFERENCES dw.dim_personaje(personaje_sk),
    defensor_pj_sk      INT  REFERENCES dw.dim_personaje(personaje_sk),   -- JcJ
    defensor_mob_sk     INT  REFERENCES dw.dim_monstruo(monstruo_sk),     -- JcE
    habilidad_sk        INT  REFERENCES dw.dim_habilidad(habilidad_sk),
    zona_sk             INT  REFERENCES dw.dim_zona(zona_sk),
    gremio_atacante_sk  INT  REFERENCES dw.dim_gremio(gremio_sk),
    -- Métricas (measures)
    dano_infligido      INT     DEFAULT 0,    -- ADITIVA ✓
    costo_mana          INT     DEFAULT 0,    -- ADITIVA ✓
    es_critico          BOOLEAN DEFAULT false,-- NO ADITIVA — usar COUNT o AVG
    es_golpe_fatal      BOOLEAN DEFAULT false,-- NO ADITIVA
    vida_restante_defensor INT,               -- SEMI-ADITIVA — no sumar, promediar/snapshot
    -- Dimensión degenerada: dato del OLTP que no amerita tabla propia
    tipo_combate        TEXT                  -- 'JcE','JcJ','Arena' — dimensión degenerada
);

-- Insertar ~80 registros de combate distribuidos en el tiempo
INSERT INTO dw.fact_combate
    (tiempo_id, atacante_sk, defensor_pj_sk, defensor_mob_sk, habilidad_sk, zona_sk, gremio_atacante_sk, dano_infligido, costo_mana, es_critico, es_golpe_fatal, vida_restante_defensor, tipo_combate)
VALUES
-- Enero — Seraphina farmea Tower of Echoes
(20250103, 2, NULL, 1, 4,  2, 1, 1240, 80,  true,  true,     0, 'JcE'),
(20250103, 2, NULL, 1, 5,  2, 1,  890, 60,  false, false,  310, 'JcE'),
(20250103, 2, NULL, 2, 4,  2, 1, 1680, 80,  true,  true,     0, 'JcE'),
(20250103, 2, NULL, 2, 6,  2, 1, 1420,150,  false, false,  580, 'JcE'),
(20250104, 2, NULL, 6, 4,  2, 1, 1680, 80,  true,  true,     0, 'JcE'),
(20250104, 2, NULL, 6, 5,  2, 1,  980, 60,  false, false,  180, 'JcE'),
(20250104, 2, NULL, 1, 6,  2, 1, 1350,150,  false, true,     0, 'JcE'),
-- Enero — Kael en Iron Citadel
(20250105, 1, NULL, 3, 18, 1, 1,  445,  0,  false, false, 1200, 'JcE'),
(20250105, 1, NULL, 3, 1,  1, 1,  680, 20,  false, false,  520, 'JcE'),
(20250105, 1, NULL, 3, 18, 1, 1,  890,  0,  true,  false,  310, 'JcE'),
(20250105, 1, NULL, 3, 18, 1, 1,  320,  0,  false, true,     0, 'JcE'),
(20250106, 1, NULL, 3, 2,  1, 1,    0, 15,  false, false, 3800, 'JcE'), -- Shield Wall
(20250106, 1, NULL, 3, 18, 1, 1,  560,  0,  false, false, 2100, 'JcE'),
(20250106, 1, NULL, 3, 1,  1, 1,  780, 20,  true,  false,  890, 'JcE'),
-- Enero — Morrigan en Cursed Sanctum
(20250108, 5, NULL, 9, 8,  5, 2,  555, 70,  false, false,    5, 'JcE'),
(20250108, 5, NULL, 9, 9,  5, 2,  480, 55,  false, false,  980, 'JcE'),
(20250109, 5, NULL,14, 8,  5, 2, 1200, 70,  true,  false, 8800, 'JcE'),
(20250109, 5, NULL,14, 9,  5, 2,  980, 55,  false, false, 7820, 'JcE'),
(20250109, 5, NULL,14,12,  5, 2, 1480,180,  false, false, 6340, 'JcE'),
(20250110, 5, NULL,14, 8,  5, 2, 1800, 70,  true,  true,     0, 'JcE'),
-- Enero evento especial (15 ene — Doble XP)
(20250115, 2, NULL, 1, 4,  2, 1, 2480, 80,  true,  true,     0, 'JcE'), -- daño doble
(20250115, 2, NULL, 6, 6,  2, 1, 2700,150,  true,  true,     0, 'JcE'),
(20250115, 1, NULL, 3, 18, 1, 1,  890,  0,  true,  false,  120, 'JcE'),
(20250115, 5, NULL,14, 8,  5, 2, 2200, 70,  true,  false,4400, 'JcE'),
(20250115, 8, NULL,12,11,  8, 3, 3200,200,  true,  false,25800,'JcE'),
(20250115, 8, NULL,12,13,  8, 3, 2800,180,  false, false,23000,'JcE'),
-- Febrero — Eldritch en Void Rift (boss fight)
(20250201, 8, NULL, 5, 11, 8, 3, 3200,200,  true,  false,28000,'JcE'),
(20250201, 8, NULL, 5, 12, 8, 3, 2800,180,  false, false,25200,'JcE'),
(20250201, 8, NULL, 5, 13, 8, 3, 4100,350,  true,  true,     0,'JcE'),
(20250202, 8, NULL,12, 11, 8, 3, 4800,200,  true,  false,78000,'JcE'),
(20250202, 8, NULL,12, 12, 8, 3, 3900,180,  false, false,74100,'JcE'),
(20250202, 8, NULL,12, 13, 8, 3, 5200,350,  true,  false,68900,'JcE'),
(20250202, 8, NULL,12, 11, 8, 3, 4200,200,  true,  false,64700,'JcE'),
(20250202, 8, NULL,12, 13, 8, 3, 6800,350,  true,  true,     0,'JcE'),
-- Febrero — VoidZyx vs Morrigan (JcJ en PvP)
(20250210, 4, 5,  NULL, 14, 4, 2,  480, 20,  false, false,  270,'JcJ'),
(20250210, 5, 4,  NULL,  8, 4, 2,  555, 70,  false, false,    5,'JcJ'),
(20250210, 4, 5,  NULL, 15, 4, 2,  820, 35,  true,  false,  150,'JcJ'),
(20250210, 5, 4,  NULL,  9, 4, 2,  480, 55,  false, true,     0,'JcJ'),
-- Febrero — Torneo en Arena (14 feb)
(20250214, 2, 8,  NULL,  4,11, 1, 2100, 80,  true,  false, 1800,'Arena'),
(20250214, 8, 2,  NULL, 11,11, 3, 3400,200,  true,  false,  580,'Arena'),
(20250214, 2, 8,  NULL,  6,11, 1, 1950,150,  false, false,  200,'Arena'),
(20250214, 8, 2,  NULL, 13,11, 3, 2800,350,  true,  true,     0,'Arena'),
-- Marzo — Invasión del Vacío (evento 01 mar)
(20250301, 8, NULL, 5, 11, 8, 3, 6400,200,  true,  false,85000,'JcE'),
(20250301, 5, NULL,12,  8, 5, 2, 2400, 70,  true,  false,92000,'JcE'),
(20250301, 2, NULL,12,  4, 2, 1, 3360, 80,  true,  false,88640,'JcE'),
(20250301, 1, NULL,12, 18, 1, 1,  890,  0,  false, false,87750,'JcE'),
(20250301, 5, NULL,12,  9, 5, 2, 1960, 55,  false, false,85790,'JcE'),
(20250301, 8, NULL,12, 13, 5, 3,10400,350,  true,  true,     0,'JcE'), -- raid kill
-- Marzo — DarkPaladin en Cathedral
(20250305, 3, NULL, 4, 16, 3, 1,  780, 50,  false, true,     0,'JcE'),
(20250305, 3, NULL, 1, 16, 3, 1,  820, 50,  true,  false,  580,'JcE'),
(20250306, 3, NULL, 4, 18, 3, 1,  340,  0,  false, false,  890,'JcE'),
(20250306, 3, NULL, 4, 16, 3, 1,  780, 50,  false, true,     0,'JcE'),
-- Marzo — Torneo de Campeones (15 mar)
(20250315, 8, 2,  NULL, 11,11, 3, 5100,200,  true,  false, 2400,'Arena'),
(20250315, 2, 8,  NULL,  4,11, 1, 3200, 80,  true,  false, 1400,'Arena'),
(20250315, 8, 2,  NULL, 12,11, 3, 4200,180,  true,  false,  800,'Arena'),
(20250315, 8, 2,  NULL, 13,11, 3, 2800,350,  false, true,     0,'Arena'),
(20250315, 5, 4,  NULL,  8,11, 2, 1980, 70,  false, false,  420,'Arena'),
(20250315, 4, 5,  NULL, 14,11, 2,  960, 20,  false, false,  180,'Arena'),
(20250315, 5, 4,  NULL,  9,11, 2, 1440, 55,  true,  true,     0,'Arena');


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 9 — FACT_TRANSACCION_ECONOMICA
--
--  TIPO: Tabla de Hechos TRANSACCIONAL (dominio económico)
--
--  GRAIN: "Una fila por cada transacción de compra/venta de un ítem."
--
--  CONCEPTOS CLAVE:
--    - comprador_sk y vendedor_sk usan la MISMA dimensión (dim_jugador) con dos roles.
--      Esto se llama "alias de dimensión" o "self-referencing dimension".
--    - vendedor_sk = NULL cuando la venta es a un NPC vendedor (no a otro jugador).
--    - precio_pagado vs valor_base: la diferencia es la ganancia/pérdida del jugador.
--    - Es imposible sumar precio_pagado con total_significado sin saber el contexto.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.fact_transaccion_economica (
    transaccion_sk      BIGSERIAL PRIMARY KEY,
    tiempo_id           INT  REFERENCES dw.dim_tiempo(tiempo_id),
    comprador_sk        INT  REFERENCES dw.dim_jugador(jugador_sk),
    vendedor_sk         INT  REFERENCES dw.dim_jugador(jugador_sk),  -- NULL = NPC vendor
    item_sk             INT  REFERENCES dw.dim_item(item_sk),
    zona_sk             INT  REFERENCES dw.dim_zona(zona_sk),
    -- Métricas
    cantidad            INT DEFAULT 1,
    precio_pagado       INT NOT NULL,               -- ADITIVA ✓
    valor_base_item     INT,                        -- ADITIVA ✓ (referencia ETL)
    diferencia_precio   INT,                        -- precio_pagado - valor_base (puede ser negativo)
    tipo_transaccion    TEXT  -- 'compra_vendor','venta_jugador','subasta','intercambio'
);

INSERT INTO dw.fact_transaccion_economica
    (tiempo_id, comprador_sk, vendedor_sk, item_sk, zona_sk, cantidad, precio_pagado, valor_base_item, diferencia_precio, tipo_transaccion)
VALUES
-- Enero — compras en vendor
(20250102, 1,  NULL, 8,  9, 5,   250,    50,   200, 'compra_vendor'),  -- Kael compra pociones
(20250102, 1,  NULL, 9,  9, 3,   180,    60,   120, 'compra_vendor'),
(20250103, 2,  NULL, 9,  9,10,   600,    60,   540, 'compra_vendor'),  -- Seraphina maná
(20250104, 3,  NULL, 8,  9, 3,   150,    50,   100, 'compra_vendor'),
(20250105, 1,  NULL,10,  9, 2,   400,   200,   200, 'compra_vendor'),  -- Scroll of Recall
(20250106, 5,  NULL, 9,  9,10,   600,    60,   540, 'compra_vendor'),
(20250108, 4,  NULL, 8,  9, 5,   250,    50,   200, 'compra_vendor'),
-- Enero — venta entre jugadores (precio inflado / deflactado)
(20250110, 3,  1,   4,  12,  1,  7500,  6000,  1500, 'venta_jugador'), -- Kael vende armadura
(20250112, 4,  5,   3,  12,  1, 10800,  9000,  1800, 'venta_jugador'), -- Morrigan vende daggers
(20250114, 1,  2,   7,  12,  1,   900,  1200,  -300, 'venta_jugador'), -- Seraphina vende anillo barato
-- Enero evento especial
(20250115, 2,  NULL, 9,  9,20,  1200,    60,  1140, 'compra_vendor'), -- stock up durante evento
(20250115, 5,  NULL, 9,  9,15,   900,    60,   840, 'compra_vendor'),
(20250115, 8,  NULL, 9,  9,10,   600,    60,   540, 'compra_vendor'),
-- Febrero — ítems épicos
(20250203, 7,  8,   1,  12,  1, 14000, 15000, -1000, 'venta_jugador'), -- Eldritch vende warblade
(20250205, 6,  NULL, 8,  9, 10,   500,    50,   450, 'compra_vendor'),
(20250210, 9,  NULL, 8,  9,  5,   250,    50,   200, 'compra_vendor'),
(20250214, 2,  NULL, 9,  9, 20,  1200,    60,  1140, 'compra_vendor'), -- prep torneo
(20250214, 8,  NULL,10,  9,  5,  1000,   200,   800, 'compra_vendor'),
(20250220, 3,  NULL,11,  12, 1, 18500, 17000,  1500, 'compra_vendor'), -- DarkPaladin big buy
-- Marzo — economía del evento
(20250301, 8,  NULL, 9,  9, 30,  1800,    60,  1740, 'compra_vendor'), -- raid preparation
(20250301, 5,  NULL, 9,  9, 20,  1200,    60,  1140, 'compra_vendor'),
(20250301, 2,  NULL, 9,  9, 20,  1200,    60,  1140, 'compra_vendor'),
(20250301, 1,  NULL, 8,  9, 10,   500,    50,   450, 'compra_vendor'),
(20250310, 9,  8,   2,  12,  1, 16000, 18000, -2000, 'venta_jugador'), -- VoidReaper compra staff
(20250315, 4,  NULL, 8,  9,  5,   250,    50,   200, 'compra_vendor'),
(20250318, 6,  3,   4,  12,  1,  5500,  6000,  -500, 'venta_jugador');


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 10 — FACT_SESION_JUGADOR
--
--  TIPO: Tabla de Hechos de SNAPSHOT PERIÓDICO — una fila por sesión de juego.
--
--  GRAIN: "Una fila por cada sesión de juego completada por un jugador."
--
--  DIFERENCIA CON SNAPSHOT DIARIO:
--    Este snapshot es por EVENTO (fin de sesión), no por período fijo.
--    Un snapshot diario puro sería: una fila por jugador por día, sin importar
--    si jugó o no (rellenas con ceros). Útil para análisis de retención.
--
--  MÉTRICA SEMI-ADITIVA: duracion_minutos
--    Puedes sumar duración por jugador (tiempo total jugado).
--    NO tiene sentido sumarla por fecha (no refleja actividad simultánea real).
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.fact_sesion_jugador (
    sesion_sk           BIGSERIAL PRIMARY KEY,
    tiempo_id           INT  REFERENCES dw.dim_tiempo(tiempo_id),
    jugador_sk          INT  REFERENCES dw.dim_jugador(jugador_sk),
    personaje_sk        INT  REFERENCES dw.dim_personaje(personaje_sk),
    zona_inicio_sk      INT  REFERENCES dw.dim_zona(zona_sk),
    -- Métricas de sesión
    duracion_minutos    INT DEFAULT 0,      -- SEMI-ADITIVA ⚠️
    xp_ganada           INT DEFAULT 0,      -- ADITIVA ✓
    oro_ganado          INT DEFAULT 0,      -- ADITIVA ✓
    oro_gastado         INT DEFAULT 0,      -- ADITIVA ✓
    monstruos_eliminados INT DEFAULT 0,     -- ADITIVA ✓
    muertes             INT DEFAULT 0,      -- ADITIVA ✓
    hechizos_lanzados   INT DEFAULT 0       -- ADITIVA ✓
);

INSERT INTO dw.fact_sesion_jugador
    (tiempo_id, jugador_sk, personaje_sk, zona_inicio_sk, duracion_minutos, xp_ganada, oro_ganado, oro_gastado, monstruos_eliminados, muertes, hechizos_lanzados)
VALUES
(20250102, 1, 1, 1,  120, 12000, 1200,  430,  8, 1, 45),
(20250102, 2, 2, 2,  240, 28000, 3400,  780, 14, 0,320),
(20250103, 1, 1, 1,   90,  8000,  800,  200,  5, 2, 28),
(20250103, 2, 2, 2,  180, 22000, 2800,  600, 11, 0,245),
(20250103, 5, 5, 5,  210, 25000, 2200,  600, 10, 1,280),
(20250104, 3, 3, 3,   60,  5500,  640,  150,  4, 3, 35),
(20250104, 2, 2, 2,  300, 35000, 4100,  600, 18, 0,410),
(20250105, 1, 1, 1,  150, 15000, 1800,  400,  9, 1, 62),
(20250105, 4, 4, 4,  120, 14000, 1500,  250,  7, 2, 88),
(20250106, 5, 5, 5,  180, 21000, 2100,  600,  9, 0,240),
(20250106, 1, 1, 1,   45,  3800,  420,    0,  2, 1, 14),
(20250107, 8, 8, 8,  360, 48000, 8200,  600, 22, 0,580),
(20250108, 5, 5, 5,  240, 28000, 2800,  600, 12, 1,310),
(20250108, 4, 4, 4,   90, 10000, 1200,  250,  5, 3, 60),
(20250109, 5, 5, 5,  300, 35000, 3800,  600, 16, 0,390),
(20250110, 8, 8, 8,  420, 55000, 9100,  600, 28, 0,680),
(20250110, 2, 2, 2,  180, 22000, 2200,  600, 10, 0,220),
-- Fin de semana sin eventos (pocos jugadores)
(20250111, 1, 1, 1,   30,  2400,  280,    0,  1, 1,  8),
(20250112, 3, 3, 3,   45,  3500,  480,    0,  3, 2, 22),
-- Evento Doble XP (15 ene) — picos de actividad
(20250115, 1, 1, 1,  300, 44000, 3600,  430, 16, 1,128),
(20250115, 2, 2, 2,  420, 72000, 7200, 1380, 28, 0,580),
(20250115, 3, 3, 3,  240, 32000, 3800,  150, 14, 2,180),
(20250115, 4, 4, 4,  180, 25000, 2800,  250, 11, 1,190),
(20250115, 5, 5, 5,  360, 60000, 6200,  600, 24, 0,480),
(20250115, 6, 6, 6,  120, 14000, 1600,  500,  8, 3, 55),
(20250115, 7, 7, 7,   90,  8000,  800,    0,  4, 4, 32),
(20250115, 8, 8, 8,  480, 88000,12000,  600, 34, 0,820),
(20250115, 9, 9, 9,  150, 16000, 1800,  250,  9, 2, 48),
(20250115,10,10, 9,   60,  2800,  180,    0,  2, 5, 12),
-- Semanas de febrero
(20250201, 8, 8, 8,  360, 50000, 9800,  600, 26, 0,640),
(20250201, 5, 5, 5,  210, 24000, 2600,  600, 11, 1,260),
(20250202, 8, 8, 8,  480, 65000,12400,  600, 32, 0,780),
(20250205, 2, 2, 2,  180, 20000, 2200,  600,  9, 0,198),
(20250205, 6, 6, 6,   90,  8000,  900,  500,  5, 4, 38),
(20250210, 4, 4, 4,  150, 16000, 1800,  250,  8, 2,110),
(20250210, 5, 5, 5,  240, 28000, 3200,  600, 13, 0,310),
-- Festival (14 feb) — pico moderado
(20250214, 1, 1, 1,  200, 22000, 2400,  400, 10, 1, 72),
(20250214, 2, 2,11,  300, 35000, 4200, 1380, 15, 1,420),
(20250214, 5, 5,11,  240, 28000, 3400,  600, 12, 0,320),
(20250214, 8, 8,11,  420, 52000,10800,  600, 24, 0,680),
-- Marzo — Invasión del Vacío (gran evento)
(20250301, 1, 1, 8,  360, 46000, 4800,  500, 18, 2,145),
(20250301, 2, 2, 8,  480, 72000, 8400, 1380, 26, 0,620),
(20250301, 5, 5, 8,  420, 62000, 7200,  600, 22, 1,540),
(20250301, 8, 8, 8,  540, 98000,16000,  600, 38, 0,960),
(20250301, 3, 3, 3,  180, 20000, 2200,  150, 10, 2,120),
(20250301, 4, 4, 4,  240, 28000, 3200,  250, 14, 1,196),
(20250301, 6, 6, 6,  150, 14000, 1600,  500,  8, 3, 62),
(20250301, 9, 9, 1,  210, 22000, 2400,  250, 11, 2, 75),
-- Torneo (15 mar)
(20250315, 2, 2,11,  300, 32000, 4800, 1380, 12, 2,480),
(20250315, 4, 4,11,  180, 18000, 2200,  250,  8, 3,155),
(20250315, 5, 5,11,  240, 24000, 3200,  600, 10, 1,320),
(20250315, 8, 8,11,  420, 48000,11200,  600, 18, 0,780);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 11 — FACT_PROGRESION_PERSONAJE
--
--  TIPO: Tabla de Hechos de SNAPSHOT PERIÓDICO DIARIO
--
--  GRAIN: "Una fila por personaje por día."
--    Si un personaje no jugó ese día, igual existe la fila (con valores del día anterior).
--    Esto permite análisis de retención y progresión sin gaps en la serie de tiempo.
--
--  MÉTRICAS SEMI-ADITIVAS:
--    nivel, oro_actual, experiencia_total — NO se suman a través del tiempo
--    (no tiene sentido decir "nivel total acumulado de enero").
--    Sí se comparan entre fechas (¿cuánto subió de nivel entre semanas?).
--    Sí se promedian dentro de una fecha (nivel promedio del servidor ese día).
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.fact_progresion_personaje (
    progresion_sk       BIGSERIAL PRIMARY KEY,
    tiempo_id           INT  REFERENCES dw.dim_tiempo(tiempo_id),
    personaje_sk        INT  REFERENCES dw.dim_personaje(personaje_sk),
    gremio_sk           INT  REFERENCES dw.dim_gremio(gremio_sk),
    -- Métricas SEMI-ADITIVAS (snapshot del estado en ese día)
    nivel               INT,        -- SEMI-ADITIVA ⚠️ — no sumar a través del tiempo
    experiencia_total   BIGINT,     -- SEMI-ADITIVA ⚠️
    oro_actual          INT,        -- SEMI-ADITIVA ⚠️
    -- Métricas ADITIVAS (delta diario — lo ganado ESE día)
    xp_ganada_hoy       INT DEFAULT 0,   -- ADITIVA ✓
    oro_ganado_hoy      INT DEFAULT 0,   -- ADITIVA ✓
    kills_hoy           INT DEFAULT 0,   -- ADITIVA ✓
    muertes_hoy         INT DEFAULT 0    -- ADITIVA ✓
);

INSERT INTO dw.fact_progresion_personaje
    (tiempo_id, personaje_sk, gremio_sk, nivel, experiencia_total, oro_actual, xp_ganada_hoy, oro_ganado_hoy, kills_hoy, muertes_hoy)
VALUES
-- Snapshot semanal: 1 enero
(20250101,1,1,42,980000, 45000, 0,    0, 0,0),
(20250101,2,1,67,4200000,128000,0,    0, 0,0),
(20250101,3,1,35,550000, 12000, 0,    0, 0,0),
(20250101,4,2,58,2800000,89000, 0,    0, 0,0),
(20250101,5,2,71,5100000,240000,0,    0, 0,0),
(20250101,6,2,29,320000, 8000,  0,    0, 0,0),
(20250101,7,3,22,180000, 4000,  0,    0, 0,0),
(20250101,8,3,80,9999999,890000,0,    0, 0,0),
-- Snapshot 15 enero (evento — todos suben más)
(20250115,1,1,42,1024000,46770, 44000, 1770, 16,1),
(20250115,2,1,68,4272000,130020,72000, 2020, 28,0),
(20250115,3,1,36,582000, 15650, 32000, 3650, 14,2),
(20250115,4,2,59,2825000,91550, 25000, 2550, 11,1),
(20250115,5,2,72,5160000,245800,60000, 5800, 24,0),
(20250115,6,2,30,334000,  9600, 14000, 1600,  8,3),
(20250115,7,3,23,188000,  4800,  8000,  800,  4,4),
(20250115,8,3,80,9999999,901600,88000,11600, 34,0),
-- Snapshot 1 febrero
(20250201,1,1,43,1100000,48500, 76000, 1730, 48,4),
(20250201,2,1,69,4420000,134800,220000,6780,108,0),
(20250201,3,1,36,610000, 18200, 28000, 2550, 20,5),
(20250201,4,2,59,2900000,93800, 75000, 2250, 38,6),
(20250201,5,2,73,5320000,251400,220000,11600,72,1),
(20250201,6,2,31,360000, 11200, 26000, 1600, 18,8),
(20250201,7,3,23,198000,  5400,  10000, 600,  6,6),
(20250201,8,3,80,9999999,946200,88000,44600,128,0),
-- Snapshot 1 marzo (evento — gran salto)
(20250301,1,1,44,1280000,53300, 180000,4800, 84,7),
(20250301,2,1,70,4800000,146580,720000,11780,280,1),
(20250301,3,1,37,680000, 22000, 70000, 3800, 52,9),
(20250301,4,2,60,3100000,97000, 200000,3200,110,5),
(20250301,5,2,74,5680000,265000,720000,13600,198,2),
(20250301,6,2,32,400000, 13400, 40000, 2200, 36,11),
(20250301,7,3,24,220000,  6200,  22000,  800, 16,12),
(20250301,8,3,80,9999999,1008000,98000,61800,264,0),
(20250301,9,NULL,16,102000,11200, 22000, 2400, 11,2);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  BLOQUE 12 — TABLA AGREGADA (Aggregate Table / Summary Table)
--
--  CONCEPTO:
--    En un DW real con millones de filas en fact_combate, las queries de resumen
--    (daño total por mes por gremio) serían lentas. Se construyen tablas
--    pre-agregadas que el ETL actualiza periódicamente.
--
--    Esto es desnormalización INTENCIONAL y CORRECTA:
--    sacrificamos espacio y frescura de datos por velocidad de consulta.
--    Las herramientas modernas (dbt, Redshift, Snowflake, BigQuery) lo llaman
--    "materialized views" o "aggregate tables".
--
--  GRAIN: Una fila por gremio por mes.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE TABLE dw.agg_combate_mensual_gremio (
    anio                INT NOT NULL,
    mes                 INT NOT NULL,
    nombre_mes          TEXT,
    gremio_sk           INT REFERENCES dw.dim_gremio(gremio_sk),
    gremio_nombre       TEXT,               -- desnormalizado a propósito para velocidad
    -- Métricas pre-agregadas
    total_acciones      INT DEFAULT 0,
    total_dano          BIGINT DEFAULT 0,
    dano_promedio       NUMERIC(10,2),
    golpe_maximo        INT DEFAULT 0,
    total_criticos      INT DEFAULT 0,
    pct_criticos        NUMERIC(5,2),
    total_golpes_fatales INT DEFAULT 0,
    personajes_activos  INT DEFAULT 0,
    -- Auditoría ETL
    generado_en         TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO dw.agg_combate_mensual_gremio
    (anio, mes, nombre_mes, gremio_sk, gremio_nombre, total_acciones, total_dano, dano_promedio, golpe_maximo, total_criticos, pct_criticos, total_golpes_fatales, personajes_activos)
VALUES
(2025, 1, 'January',  1, 'Iron Vanguard',   14,  13185, 941.79,  1680, 6, 42.86, 5, 2),
(2025, 1, 'January',  2, 'Crimson Eclipse', 10,  10043,1004.30,  1800, 4, 40.00, 3, 2),
(2025, 1, 'January',  3, 'Silver Dawn',      9,  24700,2744.44,  4100, 4, 44.44, 1, 1),
(2025, 2, 'February', 1, 'Iron Vanguard',    4,   5540,1385.00,  2100, 1, 25.00, 1, 1),
(2025, 2, 'February', 2, 'Crimson Eclipse',  6,   5475, 912.50,  1440, 2, 33.33, 2, 2),
(2025, 2, 'February', 3, 'Silver Dawn',     12,  42700,3558.33,  6800, 7, 58.33, 2, 1),
(2025, 3, 'March',    1, 'Iron Vanguard',    8,  12430,1553.75,  3360, 3, 37.50, 2, 2),
(2025, 3, 'March',    2, 'Crimson Eclipse', 12,  24160,2013.33,  5100, 6, 50.00, 3, 2),
(2025, 3, 'March',    3, 'Silver Dawn',     13,  58900,4530.77, 10400, 7, 53.85, 3, 1);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  ÍNDICES DE SOPORTE PARA PERFORMANCE
--  En un DW, los índices van en las FKs de las tablas de hechos.
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE INDEX idx_fact_combate_tiempo      ON dw.fact_combate(tiempo_id);
CREATE INDEX idx_fact_combate_atacante    ON dw.fact_combate(atacante_sk);
CREATE INDEX idx_fact_combate_zona        ON dw.fact_combate(zona_sk);
CREATE INDEX idx_fact_sesion_tiempo       ON dw.fact_sesion_jugador(tiempo_id);
CREATE INDEX idx_fact_sesion_jugador      ON dw.fact_sesion_jugador(jugador_sk);
CREATE INDEX idx_fact_transac_tiempo      ON dw.fact_transaccion_economica(tiempo_id);
CREATE INDEX idx_fact_progresion_tiempo   ON dw.fact_progresion_personaje(tiempo_id);
CREATE INDEX idx_fact_progresion_pj       ON dw.fact_progresion_personaje(personaje_sk);


-- ═══════════════════════════════════════════════════════════════════════════════════
--  VISTA DE REFERENCIA: Mapa del DW
-- ═══════════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW dw.v_catalogo_dw AS
SELECT
    schemaname,
    tablename,
    CASE
        WHEN tablename LIKE 'dim_%'  THEN '📐 Dimensión'
        WHEN tablename LIKE 'fact_%' THEN '📊 Tabla de Hechos'
        WHEN tablename LIKE 'agg_%'  THEN '⚡ Tabla Agregada'
        ELSE '🔍 Vista'
    END AS tipo,
    (SELECT COUNT(*) FROM information_schema.columns c
     WHERE c.table_schema = t.schemaname AND c.table_name = t.tablename) AS num_columnas
FROM pg_tables t
WHERE schemaname = 'dw'
ORDER BY tipo, tablename;


-- ═══════════════════════════════════════════════════════════════════════════════════
--  QUERIES DE REFERENCIA RÁPIDA
--  (descomentar y pegar en QueryForge para explorar)
-- ═══════════════════════════════════════════════════════════════════════════════════
/*
-- Ver el catálogo del DW
SELECT * FROM dw.v_catalogo_dw;

-- Cómo se ve una query típica de Star Schema (una sola tabla de hechos + dims)
SELECT
    t.nombre_mes,
    t.anio,
    p.nombre             AS personaje,
    p.clase,
    z.nombre_zona,
    SUM(fc.dano_infligido) AS dano_total,
    COUNT(*)               AS acciones,
    SUM(CASE WHEN fc.es_critico THEN 1 ELSE 0 END) AS criticos
FROM dw.fact_combate fc
JOIN dw.dim_tiempo    t  ON t.tiempo_id    = fc.tiempo_id
JOIN dw.dim_personaje p  ON p.personaje_sk = fc.atacante_sk
JOIN dw.dim_zona      z  ON z.zona_sk      = fc.zona_sk
GROUP BY t.nombre_mes, t.anio, p.nombre, p.clase, z.nombre_zona
ORDER BY dano_total DESC;

-- La pregunta SCD2: ¿cuántas versiones de cuenta tiene Zyx?
SELECT jugador_nk, username, tier, tier_anterior, fecha_inicio, fecha_fin, es_actual
FROM dw.dim_jugador
WHERE jugador_nk = 4
ORDER BY fecha_inicio;
*/
