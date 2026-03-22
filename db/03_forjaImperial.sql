-- ═══════════════════════════════════════════════════════════════════════════════
--  ⚒  EL CATÁLOGO DEL HERRERO IMPERIAL  —  Base de datos sobre-normalizada
--     Schema: forja
--
--  PROPÓSITO PEDAGÓGICO:
--    Esta base de datos fue diseñada por un desarrollador que aplicó cada
--    regla de normalización al pie de la letra, sin considerar el uso real.
--    Está en 5FN. No tiene ningún error teórico. Y es casi inutilizable.
--
--  MODELA: El sistema de crafteo y comercio de ítems del reino.
--  PREGUNTA CENTRAL: ¿Cuántos JOINs necesitas para ver un ítem con sus stats?
--
--  ANTI-PATRONES PRESENTES (para descubrir en clase):
--    1. EAV — Entity-Attribute-Value: stats como filas en lugar de columnas
--    2. Over-splitting: cada "tipo" en su propia tabla con FK
--    3. Jerarquía de ubicación llevada al extremo (6 niveles)
--    4. Precios separados de la relación vendor-ítem
--    5. Nombres e i18n en tabla aparte (para un juego de un solo idioma)
--    6. Recetas de crafteo en 4 tablas donde bastarían 2
-- ═══════════════════════════════════════════════════════════════════════════════

CREATE SCHEMA IF NOT EXISTS forja;
SET search_path TO forja, public;


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 1 — TAXONOMÍA DE ÍTEMS
--  (3 tablas para lo que podría ser 2 columnas TEXT)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.categoria (
    categoria_id    SERIAL PRIMARY KEY,
    codigo          TEXT NOT NULL UNIQUE   -- 'WPN', 'ARM', 'ACC', 'CON', 'QST'
);

CREATE TABLE forja.subcategoria (
    subcategoria_id SERIAL PRIMARY KEY,
    categoria_id    INT NOT NULL REFERENCES forja.categoria(categoria_id),
    codigo          TEXT NOT NULL UNIQUE   -- 'SWORD', 'STAFF', 'CHEST', 'POTION'
);

CREATE TABLE forja.rareza (
    rareza_id       SERIAL PRIMARY KEY,
    nombre          TEXT NOT NULL UNIQUE,  -- 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary'
    multiplicador   NUMERIC(4,2) NOT NULL, -- factor de precio base
    color_hex       TEXT                   -- '#FFFFFF', '#1EFF00', etc.
);

INSERT INTO forja.categoria (codigo) VALUES
    ('WPN'), ('ARM'), ('ACC'), ('CON'), ('QST');

INSERT INTO forja.subcategoria (categoria_id, codigo) VALUES
    (1,'SWORD'),(1,'STAFF'),(1,'DAGGER'),(1,'AXE'),(1,'BOW'),
    (2,'CHEST'),(2,'HELM'),(2,'GLOVE'),(2,'BOOT'),(2,'CLOAK'),
    (3,'RING'),(3,'AMULET'),(3,'TRINKET'),
    (4,'POTION'),(4,'SCROLL'),(4,'FOOD'),
    (5,'TOKEN'),(5,'ARTIFACT');

INSERT INTO forja.rareza (nombre, multiplicador, color_hex) VALUES
    ('Common',    1.00, '#9D9D9D'),
    ('Uncommon',  1.50, '#1EFF00'),
    ('Rare',      2.00, '#0070DD'),
    ('Epic',      3.00, '#A335EE'),
    ('Legendary', 5.00, '#FF8000');


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 2 — ÍTEMS BASE
--  La tabla de ítems en sí NO tiene stats ni precios.
--  Tampoco tiene nombre legible — eso está en otra tabla.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.item (
    item_id         SERIAL PRIMARY KEY,
    subcategoria_id INT NOT NULL REFERENCES forja.subcategoria(subcategoria_id),
    rareza_id       INT NOT NULL REFERENCES forja.rareza(rareza_id),
    nivel_requerido INT NOT NULL DEFAULT 1,
    es_comerciable  BOOLEAN DEFAULT true,
    es_consumible   BOOLEAN DEFAULT false,
    creado_en       TIMESTAMPTZ DEFAULT NOW()
);

-- Los NOMBRES del ítem están en una tabla separada "para i18n"
-- (el juego solo existe en un idioma)
CREATE TABLE forja.item_nombre (
    item_id     INT NOT NULL REFERENCES forja.item(item_id),
    idioma_id   INT NOT NULL DEFAULT 1,   -- siempre 1, nunca se añadió otro idioma
    nombre      TEXT NOT NULL,
    descripcion TEXT,
    PRIMARY KEY (item_id, idioma_id)
);

CREATE TABLE forja.idioma (
    idioma_id   SERIAL PRIMARY KEY,
    codigo      TEXT NOT NULL UNIQUE,   -- 'es', 'en', 'ja'
    nombre      TEXT NOT NULL
);

INSERT INTO forja.idioma VALUES (1, 'es', 'Español');

-- Insertar ítems
INSERT INTO forja.item (subcategoria_id, rareza_id, nivel_requerido, es_comerciable, es_consumible) VALUES
    (1, 5, 40, true,  false),  -- 1: Warblade of the Fallen
    (2, 5, 60, true,  false),  -- 2: Staff of Eternity
    (3, 4, 50, true,  false),  -- 3: Shadowfang Daggers
    (6, 3, 35, true,  false),  -- 4: Plate of the Crusader
    (6, 5, 65, true,  false),  -- 5: Robes of the Archmage
    (10,4, 45, true,  false),  -- 6: Cloak of Shadows
    (11,2, 20, true,  false),  -- 7: Ring of Vigor
    (14,1,  1, true,  true),   -- 8: Healing Potion
    (14,1,  1, true,  true),   -- 9: Mana Elixir
    (15,2, 10, true,  true),   -- 10: Scroll of Recall
    (1, 5, 50, true,  false),  -- 11: Holy Avenger
    (2, 4, 65, true,  false),  -- 12: Void Crystal Staff
    (4, 1,  1, true,  false);  -- 13: Crude Axe

INSERT INTO forja.item_nombre (item_id, idioma_id, nombre, descripcion) VALUES
    (1,  1, 'Warblade of the Fallen',  'Una espada forjada en las cenizas de los caídos.'),
    (2,  1, 'Staff of Eternity',        'Un bastón que contiene el tiempo congelado.'),
    (3,  1, 'Shadowfang Daggers',       'Dagas que nunca dejan de sangrar.'),
    (4,  1, 'Plate of the Crusader',    'Armadura bendecida por la Catedral del Alba.'),
    (5,  1, 'Robes of the Archmage',    'Robes tejidas con luz de estrella muerta.'),
    (6,  1, 'Cloak of Shadows',         'Una capa que dobla la luz a su alrededor.'),
    (7,  1, 'Ring of Vigor',            'Un anillo de bronce con runas de vitalidad.'),
    (8,  1, 'Healing Potion',           'Restaura 200 puntos de vida.'),
    (9,  1, 'Mana Elixir',              'Restaura 150 puntos de maná.'),
    (10, 1, 'Scroll of Recall',         'Te teletransporta a tu última posada.'),
    (11, 1, 'Holy Avenger',             'Una espada santa que destruye no-muertos.'),
    (12, 1, 'Void Crystal Staff',       'Un bastón con un cristal del vacío en su cima.'),
    (13, 1, 'Crude Axe',                'Un hacha mal forjada. Funciona, supone.');


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 3 — SISTEMA EAV DE STATS
--  En lugar de columnas (str, agi, int...), cada stat es una FILA.
--  Para ver todos los stats de un ítem necesitas pivotar o concatenar.
--  Este es el anti-patrón más costoso de esta base de datos.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.stat_tipo (
    stat_tipo_id    SERIAL PRIMARY KEY,
    codigo          TEXT NOT NULL UNIQUE,  -- 'STR', 'AGI', 'INT', 'VIT', 'DEF', 'CRIT'
    nombre_largo    TEXT NOT NULL,
    unidad          TEXT NOT NULL,         -- 'puntos', 'porcentaje'
    es_porcentaje   BOOLEAN DEFAULT false
);

CREATE TABLE forja.stat_tipo_descripcion (
    stat_tipo_id    INT NOT NULL REFERENCES forja.stat_tipo(stat_tipo_id),
    idioma_id       INT NOT NULL DEFAULT 1,
    descripcion     TEXT NOT NULL,
    PRIMARY KEY (stat_tipo_id, idioma_id)
);

CREATE TABLE forja.item_stat (
    item_stat_id    SERIAL PRIMARY KEY,
    item_id         INT NOT NULL REFERENCES forja.item(item_id),
    stat_tipo_id    INT NOT NULL REFERENCES forja.stat_tipo(stat_tipo_id),
    valor           NUMERIC(8,2) NOT NULL,
    UNIQUE (item_id, stat_tipo_id)
);

INSERT INTO forja.stat_tipo (codigo, nombre_largo, unidad, es_porcentaje) VALUES
    ('STR',  'Fuerza',        'puntos',     false),
    ('AGI',  'Agilidad',      'puntos',     false),
    ('INT',  'Inteligencia',  'puntos',     false),
    ('VIT',  'Vitalidad',     'puntos',     false),
    ('DEF',  'Defensa',       'puntos',     false),
    ('CRIT', 'Probabilidad Crítico', 'porcentaje', true),
    ('LIFE', 'Robo de vida',  'porcentaje', true),
    ('VOID', 'Daño del Vacío','puntos',     false),
    ('HOLY', 'Daño Santo',    'puntos',     false),
    ('MANA', 'Maná bonus',    'puntos',     false);

INSERT INTO forja.stat_tipo_descripcion VALUES
    (1,1,'Aumenta el daño físico y la capacidad de carga.'),
    (2,1,'Aumenta la velocidad de ataque y la evasión.'),
    (3,1,'Aumenta el poder de hechizos y el maná máximo.'),
    (4,1,'Aumenta los puntos de vida máximos.'),
    (5,1,'Reduce el daño físico recibido.'),
    (6,1,'Probabilidad de infligir daño doble.'),
    (7,1,'Porcentaje del daño convertido en vida propia.'),
    (8,1,'Daño adicional de tipo vacío.'),
    (9,1,'Daño adicional de tipo santo.'),
    (10,1,'Maná adicional al equipar.');

-- Stats por ítem (lo que en Chronicles era un campo TEXT 'STR+30,VIT+15...')
INSERT INTO forja.item_stat (item_id, stat_tipo_id, valor) VALUES
    -- Warblade of the Fallen: STR+30, VIT+15, CRIT+8%, LIFE+5%
    (1,1,30),(1,4,15),(1,6,8),(1,7,5),
    -- Staff of Eternity: INT+45, MANA+200
    (2,3,45),(2,10,200),
    -- Shadowfang Daggers: AGI+25, CRIT+15%
    (3,2,25),(3,6,15),
    -- Plate of the Crusader: VIT+20, DEF+40
    (4,4,20),(4,5,40),
    -- Robes of the Archmage: INT+35, MANA+300
    (5,3,35),(5,10,300),
    -- Cloak of Shadows: AGI+20, CRIT+12%
    (6,2,20),(6,6,12),
    -- Ring of Vigor: VIT+10
    (7,4,10),
    -- Holy Avenger: STR+25, VIT+20, HOLY+40
    (11,1,25),(11,4,20),(11,9,40),
    -- Void Crystal Staff: INT+38, VOID+25
    (12,3,38),(12,8,25),
    -- Crude Axe: STR+2
    (13,1,2);


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 4 — JERARQUÍA DE UBICACIÓN (6 niveles para 3 que bastarían)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.mundo (
    mundo_id    SERIAL PRIMARY KEY,
    nombre      TEXT NOT NULL
);

CREATE TABLE forja.continente (
    continente_id   SERIAL PRIMARY KEY,
    mundo_id        INT NOT NULL REFERENCES forja.mundo(mundo_id),
    nombre          TEXT NOT NULL
);

CREATE TABLE forja.region (
    region_id       SERIAL PRIMARY KEY,
    continente_id   INT NOT NULL REFERENCES forja.continente(continente_id),
    nombre          TEXT NOT NULL,
    nivel_peligro   TEXT NOT NULL DEFAULT 'Bajo'
);

CREATE TABLE forja.zona (
    zona_id         SERIAL PRIMARY KEY,
    region_id       INT NOT NULL REFERENCES forja.region(region_id),
    nombre          TEXT NOT NULL,
    tipo_zona       TEXT NOT NULL
);

CREATE TABLE forja.distrito (
    distrito_id     SERIAL PRIMARY KEY,
    zona_id         INT NOT NULL REFERENCES forja.zona(zona_id),
    nombre          TEXT NOT NULL
);

CREATE TABLE forja.punto_venta (
    punto_venta_id  SERIAL PRIMARY KEY,
    distrito_id     INT NOT NULL REFERENCES forja.distrito(distrito_id),
    nombre          TEXT NOT NULL,
    es_subasta      BOOLEAN DEFAULT false
);

INSERT INTO forja.mundo VALUES (1, 'El Reino Fragmentado');

INSERT INTO forja.continente VALUES
    (1,1,'Tierras del Norte'),
    (2,1,'Imperio Central');

INSERT INTO forja.region VALUES
    (1,1,'Páramos de Hierro','Alto'),
    (2,2,'Llanuras Centrales','Medio'),
    (3,2,'Corazón del Imperio','Bajo');

INSERT INTO forja.zona VALUES
    (1,1,'Iron Citadel','Dungeon'),
    (2,2,'Torre de los Ecos','Raid'),
    (3,3,'Ironforge City','Ciudad'),
    (4,3,'Arcane Spire','Ciudad'),
    (5,3,'The Undercity','PvP'),
    (6,3,'Crossroads','Ciudad');

INSERT INTO forja.distrito VALUES
    (1,3,'Barrio del Mercado'),
    (2,3,'Barrio de la Forja'),
    (3,4,'Distrito Arcano'),
    (4,5,'Mercado Negro'),
    (5,6,'Cruce Central');

INSERT INTO forja.punto_venta VALUES
    (1,2,'Aldric the Armorer',  false),
    (2,3,'Mystica',             false),
    (3,4,'Shade Merchant',      false),
    (4,5,'Mira the Merchant',   false),
    (5,1,'Casa de Subastas',    true);


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 5 — PRECIOS Y DISPONIBILIDAD
--  Los precios están en su propia tabla separada de la relación vendor-ítem.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.vendor_item (
    vendor_item_id      SERIAL PRIMARY KEY,
    punto_venta_id      INT NOT NULL REFERENCES forja.punto_venta(punto_venta_id),
    item_id             INT NOT NULL REFERENCES forja.item(item_id),
    stock_disponible    INT DEFAULT -1,  -- -1 = ilimitado
    activo              BOOLEAN DEFAULT true,
    UNIQUE(punto_venta_id, item_id)
);

CREATE TABLE forja.precio (
    precio_id           SERIAL PRIMARY KEY,
    vendor_item_id      INT NOT NULL REFERENCES forja.vendor_item(vendor_item_id),
    tipo_precio         TEXT NOT NULL,  -- 'compra', 'venta_al_vendor'
    monto               INT NOT NULL,
    moneda              TEXT NOT NULL DEFAULT 'oro',
    vigente_desde       DATE NOT NULL DEFAULT CURRENT_DATE,
    vigente_hasta       DATE          -- NULL = vigente hoy
);

INSERT INTO forja.vendor_item (punto_venta_id, item_id, stock_disponible, activo) VALUES
    (1,1,-1,true),(1,4,-1,true),(1,7,-1,true),(1,11,-1,true),
    (2,2,-1,true),(2,5,-1,true),(2,12,-1,true),
    (3,3,-1,true),(3,6,-1,true),(3,12,-1,true),
    (4,8,999,true),(4,9,999,true),(4,10,500,true),(4,13,-1,true);

INSERT INTO forja.precio (vendor_item_id, tipo_precio, monto, moneda, vigente_desde) VALUES
    (1, 'compra',          15000,'oro','2025-01-01'),
    (1, 'venta_al_vendor',  7500,'oro','2025-01-01'),
    (2, 'compra',           6000,'oro','2025-01-01'),
    (2, 'venta_al_vendor',  3000,'oro','2025-01-01'),
    (3, 'compra',           1200,'oro','2025-01-01'),
    (3, 'venta_al_vendor',   600,'oro','2025-01-01'),
    (4, 'compra',          17000,'oro','2025-01-01'),
    (4, 'venta_al_vendor',  8500,'oro','2025-01-01'),
    (5, 'compra',          18000,'oro','2025-01-01'),
    (5, 'venta_al_vendor',  9000,'oro','2025-01-01'),
    (6, 'compra',           9000,'oro','2025-01-01'),
    (6, 'venta_al_vendor',  4500,'oro','2025-01-01'),
    (7, 'compra',           8000,'oro','2025-01-01'),
    (7, 'venta_al_vendor',  4000,'oro','2025-01-01'),
    (8, 'compra',           9000,'oro','2025-01-01'),
    (9, 'compra',             50,'oro','2025-01-01'),
    (9, 'venta_al_vendor',    25,'oro','2025-01-01'),
    (10,'compra',             60,'oro','2025-01-01'),
    (10,'venta_al_vendor',    30,'oro','2025-01-01'),
    (11,'compra',            200,'oro','2025-01-01'),
    (11,'venta_al_vendor',   100,'oro','2025-01-01'),
    (12,'compra',             30,'oro','2025-01-01'),
    (12,'venta_al_vendor',    15,'oro','2025-01-01');


-- ─────────────────────────────────────────────────────────────────────────────
--  CAPA 6 — SISTEMA DE CRAFTEO (4 tablas para lo que serían 2)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE forja.receta (
    receta_id           SERIAL PRIMARY KEY,
    item_resultado_id   INT NOT NULL REFERENCES forja.item(item_id),
    nombre_receta       TEXT,
    nivel_artesano_req  INT DEFAULT 1,
    tiempo_crafteo_seg  INT DEFAULT 30
);

CREATE TABLE forja.receta_paso (
    paso_id             SERIAL PRIMARY KEY,
    receta_id           INT NOT NULL REFERENCES forja.receta(receta_id),
    numero_paso         INT NOT NULL,
    descripcion_paso    TEXT,
    UNIQUE(receta_id, numero_paso)
);

CREATE TABLE forja.receta_ingrediente (
    ingrediente_id      SERIAL PRIMARY KEY,
    receta_id           INT NOT NULL REFERENCES forja.receta(receta_id),
    item_insumo_id      INT NOT NULL REFERENCES forja.item(item_id)
);

-- La CANTIDAD del ingrediente está en tabla aparte "para auditoría"
CREATE TABLE forja.ingrediente_cantidad (
    ingrediente_id      INT NOT NULL REFERENCES forja.receta_ingrediente(ingrediente_id),
    cantidad            INT NOT NULL DEFAULT 1,
    es_opcional         BOOLEAN DEFAULT false,
    puede_sustituir_con INT REFERENCES forja.item(item_id),
    PRIMARY KEY (ingrediente_id)
);

INSERT INTO forja.receta (item_resultado_id, nombre_receta, nivel_artesano_req, tiempo_crafteo_seg) VALUES
    (4,  'Forja de Cruzado',     15, 120),
    (11, 'Consagración del Vengador', 20, 180),
    (13, 'Hacha Básica',          1,  15);

INSERT INTO forja.receta_paso VALUES
    (1, 1, 1, 'Calentar el metal a temperatura de fusión'),
    (2, 1, 2, 'Moldear en forma de peto'),
    (3, 1, 3, 'Aplicar encantamiento de bendición'),
    (4, 2, 1, 'Purificar el metal con agua bendita'),
    (5, 2, 2, 'Forjar la hoja con el martillo sagrado'),
    (6, 2, 3, 'Inscribir los sellos de justicia'),
    (7, 3, 1, 'Fundir hierro crudo'),
    (8, 3, 2, 'Dar forma de hacha');

-- Ingredientes para Plate of the Crusader (item 4)
INSERT INTO forja.receta_ingrediente (receta_id, item_insumo_id) VALUES
    (1, 8),   -- Healing Potion como componente (lore: se usa en el temple)
    (1, 10);  -- Scroll of Recall como componente mágico

INSERT INTO forja.ingrediente_cantidad VALUES
    (1, 3, false, NULL),   -- 3x Healing Potion
    (2, 1, false, NULL);   -- 1x Scroll of Recall

-- Ingredientes para Holy Avenger (item 11)
INSERT INTO forja.receta_ingrediente (receta_id, item_insumo_id) VALUES
    (2, 7),   -- Ring of Vigor se funde
    (2, 9),   -- Mana Elixir para el temple
    (2, 10);  -- Scroll of Recall

INSERT INTO forja.ingrediente_cantidad VALUES
    (3, 1, false, NULL),   -- 1x Ring of Vigor
    (4, 5, false, NULL),   -- 5x Mana Elixir
    (5, 2, true,  8);      -- 2x Scroll of Recall, puede sustituir con Mana Elixir

-- Ingredientes para Crude Axe (item 13)
INSERT INTO forja.receta_ingrediente (receta_id, item_insumo_id) VALUES
    (3, 13);  -- Crude Axe se "mejora" a sí misma (meta-referencia)

INSERT INTO forja.ingrediente_cantidad VALUES
    (6, 1, false, NULL);


-- ─────────────────────────────────────────────────────────────────────────────
--  QUERY DE REFERENCIA — La "query simple" que todo lo expone
--
--  TAREA: Muestra todos los ítems de tipo arma (WPN) con:
--    - nombre del ítem
--    - rareza
--    - sus stats (todos)
--    - precio de compra
--    - nombre del vendor
--    - nombre de la zona donde se vende
--
--  ¿Cuántos JOINs necesitas? Cuenta antes de ejecutar.
-- ─────────────────────────────────────────────────────────────────────────────
/*
SELECT
    n.nombre            AS item,
    r.nombre            AS rareza,
    st.codigo           AS stat,
    ist.valor,
    st.es_porcentaje,
    p.monto             AS precio_compra,
    pv.nombre           AS vendor,
    z.nombre            AS zona,
    reg.nombre          AS region,
    c.nombre            AS continente
FROM forja.item i
-- nombre
JOIN forja.item_nombre       n    ON n.item_id        = i.item_id    AND n.idioma_id = 1
-- taxonomía
JOIN forja.subcategoria      sc   ON sc.subcategoria_id = i.subcategoria_id
JOIN forja.categoria         cat  ON cat.categoria_id   = sc.categoria_id
-- rareza
JOIN forja.rareza             r    ON r.rareza_id       = i.rareza_id
-- stats (EAV — genera múltiples filas por ítem)
LEFT JOIN forja.item_stat    ist  ON ist.item_id        = i.item_id
LEFT JOIN forja.stat_tipo    st   ON st.stat_tipo_id    = ist.stat_tipo_id
-- vendor y precio
LEFT JOIN forja.vendor_item  vi   ON vi.item_id         = i.item_id   AND vi.activo = true
LEFT JOIN forja.precio        p    ON p.vendor_item_id   = vi.vendor_item_id
                                   AND p.tipo_precio = 'compra'
                                   AND p.vigente_hasta IS NULL
-- jerarquía de ubicación (6 niveles)
LEFT JOIN forja.punto_venta  pv   ON pv.punto_venta_id  = vi.punto_venta_id
LEFT JOIN forja.distrito      d    ON d.distrito_id      = pv.distrito_id
LEFT JOIN forja.zona          z    ON z.zona_id          = d.zona_id
LEFT JOIN forja.region        reg  ON reg.region_id      = z.region_id
LEFT JOIN forja.continente    c    ON c.continente_id    = reg.continente_id
WHERE cat.codigo = 'WPN'
ORDER BY r.multiplicador DESC, n.nombre, st.codigo;
*/
