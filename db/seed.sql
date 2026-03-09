-- ═══════════════════════════════════════════════════════════════════════════════
--  ⚔  CHRONICLES OF THE BROKEN REALM  — Teaching Database
--  A deliberately imperfect MMORPG schema for studying normalization
--
--  Each table is annotated with:
--    [PROBLEM]   — what normalization issue exists and which Normal Form it breaks
--    [FIX]       — what the normalized version would look like
--    [VERDICT]   — whether normalizing is actually better, worse, or debatable
-- ═══════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 1: players
--
--  [PROBLEM - 3NF / Transitive Dependency]
--    guild_name and guild_leader depend on guild_id, not on player_id.
--    If the guild renames itself, you must UPDATE every single row of this table.
--    guild_leader_email is even worse — it depends on guild_leader, not on the key.
--
--  [FIX]  Extract a guilds(guild_id, guild_name, guild_leader, guild_leader_email)
--         table and replace the columns here with just guild_id FK.
--
--  [VERDICT]  ✅ Normalize — classic textbook 3NF violation.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS players CASCADE;
CREATE TABLE players (
    player_id       SERIAL PRIMARY KEY,
    username        TEXT NOT NULL UNIQUE,
    email           TEXT NOT NULL UNIQUE,
    password_hash   TEXT NOT NULL,
    account_country TEXT,              -- 'Mexico', 'USA', 'Japan'
    account_region  TEXT,              -- 'LATAM', 'NA', 'APAC'  ← depends on country, not player
    account_tier    TEXT DEFAULT 'Free', -- 'Free', 'Premium', 'Legendary'
    monthly_price   NUMERIC(6,2),      -- depends on account_tier, NOT on player_id  ← 3NF violation
    guild_id        INT,
    guild_name      TEXT,              -- ← transitive: guild_id → guild_name
    guild_leader    TEXT,              -- ← transitive: guild_id → guild_leader
    guild_leader_email TEXT,           -- ← transitive: guild_leader → guild_leader_email (chained!)
    joined_at       TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO players
    (username, email, password_hash, account_country, account_region, account_tier, monthly_price,
     guild_id, guild_name, guild_leader, guild_leader_email)
VALUES
    ('Kael_Stormborn',   'kael@realm.io',    'hash1', 'Mexico',  'LATAM', 'Legendary', 14.99, 1, 'Iron Vanguard',   'Seraphina',    'sera@realm.io'),
    ('Seraphina',        'sera@realm.io',    'hash2', 'Mexico',  'LATAM', 'Legendary', 14.99, 1, 'Iron Vanguard',   'Seraphina',    'sera@realm.io'),
    ('DarkPaladin99',    'dp99@realm.io',    'hash3', 'USA',     'NA',    'Premium',    9.99, 1, 'Iron Vanguard',   'Seraphina',    'sera@realm.io'),
    ('Zyx_the_Void',     'zyx@realm.io',     'hash4', 'Japan',   'APAC',  'Free',       0.00, 2, 'Crimson Eclipse', 'Morrigan',     'morri@realm.io'),
    ('Morrigan',         'morri@realm.io',   'hash5', 'Japan',   'APAC',  'Legendary', 14.99, 2, 'Crimson Eclipse', 'Morrigan',     'morri@realm.io'),
    ('Theron_Ashblade',  'theron@realm.io',  'hash6', 'Mexico',  'LATAM', 'Premium',    9.99, 2, 'Crimson Eclipse', 'Morrigan',     'morri@realm.io'),
    ('NightWalker',      'nw@realm.io',      'hash7', 'USA',     'NA',    'Free',       0.00, 3, 'Silver Dawn',     'Eldritch_One', 'eld@realm.io'),
    ('Eldritch_One',     'eld@realm.io',     'hash8', 'Germany', 'EU',    'Legendary', 14.99, 3, 'Silver Dawn',     'Eldritch_One', 'eld@realm.io'),
    ('VoidReaper',       'void@realm.io',    'hash9', 'Germany', 'EU',    'Premium',    9.99, NULL, NULL,           NULL,           NULL),
    ('LostSoul42',       'lost@realm.io',    'hash0', 'Mexico',  'LATAM', 'Free',       0.00, NULL, NULL,           NULL,           NULL);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 2: characters
--
--  [PROBLEM - 1NF violation + 2NF issues]
--    'equipped_items' stores a comma-separated list of item names in one column.
--    This violates 1NF (atomicity): you cannot query "find all characters with a
--    Sword of Kas equipped" without using string matching hacks like ILIKE '%Sword%'.
--
--    'active_buffs' is the same anti-pattern.
--
--    'race_homeland' is a transitive dependency: race → homeland, not char_id → homeland.
--    'class_primary_stat' similarly: class → primary_stat.
--
--  [FIX]
--    - character_equipment(char_id, slot, item_id) table
--    - character_buffs(char_id, buff_id, expires_at) table
--    - races(race_id, race_name, homeland) table
--    - classes(class_id, class_name, primary_stat) table
--
--  [VERDICT]  ✅ Normalize — the comma-list is a disaster for any real query.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS characters CASCADE;
CREATE TABLE characters (
    char_id         SERIAL PRIMARY KEY,
    player_id       INT REFERENCES players(player_id),
    char_name       TEXT NOT NULL,
    race            TEXT NOT NULL,     -- 'Elf', 'Orc', 'Human', 'Undead'
    race_homeland   TEXT,              -- transitive: race → homeland
    class           TEXT NOT NULL,     -- 'Warrior', 'Mage', 'Rogue'
    class_primary_stat TEXT,           -- transitive: class → primary_stat
    level           INT DEFAULT 1,
    experience      BIGINT DEFAULT 0,
    health_current  INT,
    health_max      INT,
    mana_current    INT,
    mana_max        INT,
    strength        INT,
    agility         INT,
    intelligence    INT,
    equipped_items  TEXT,   -- ← 1NF BOMB: 'Iron Sword,Leather Armor,Shadow Ring'
    active_buffs    TEXT,   -- ← 1NF BOMB: 'Haste,Strength+10,Invisibility'
    last_location   TEXT,   -- 'Ashenvale Forest'
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO characters
    (player_id, char_name, race, race_homeland, class, class_primary_stat,
     level, experience, health_current, health_max, mana_current, mana_max,
     strength, agility, intelligence, equipped_items, active_buffs, last_location)
VALUES
    (1,  'Kael',         'Human', 'Stormhaven',        'Warrior', 'Strength',     42, 980000,  820, 820,  100, 100, 88, 55, 30, 'Warblade of the Fallen,Plate of the Crusader,Ring of Vigor', 'Haste,Fortify', 'Iron Citadel'),
    (2,  'Seraphina',    'Elf',   'Silverwood',        'Mage',    'Intelligence', 67, 4200000, 440, 440,  900, 900, 20, 45, 99, 'Staff of Eternity,Robes of the Archmage',                   'Mana Shield,Arcane Surge', 'Tower of Echoes'),
    (3,  'DarkPaladin',  'Human', 'Stormhaven',        'Paladin', 'Strength',     35, 550000,  700, 700,  300, 300, 70, 40, 60, 'Holy Avenger,Shield of Faith,Amulet of Light',              'Blessing,Divine Shield', 'Cathedral of Dawn'),
    (4,  'VoidZyx',      'Undead','Necropolis',        'Rogue',   'Agility',      58, 2800000, 560, 560,  200, 200, 40, 95, 35, 'Shadowfang Daggers,Cloak of Shadows,Boots of Silence',      'Evasion,Shadow Step', 'The Undercity'),
    (5,  'Morrigan',     'Elf',   'Silverwood',        'Warlock', 'Intelligence', 71, 5100000, 480, 480,  850, 850, 25, 50, 97, 'Tome of Dark Pacts,Void Crystal Staff,Cursed Ring',         'Soul Drain,Fel Armor', 'Cursed Sanctum'),
    (6,  'Theron',       'Orc',   'Bloodmire Wastes',  'Warrior', 'Strength',     29, 320000,  660, 660,   80,  80, 92, 60, 18, 'Orcish Cleaver,Spiked Pauldrons',                           'Berserker Rage', 'Bloodmire Wastes'),
    (7,  'Shadow',       'Human', 'Stormhaven',        'Rogue',   'Agility',      22, 180000,  400, 400,  150, 150, 35, 80, 28, 'Iron Dagger,Leather Gloves',                                NULL, 'Duskwood'),
    (8,  'Eldritch',     'Undead','Necropolis',        'Mage',    'Intelligence', 80, 9999999, 420, 420, 1000,1000, 15, 40,110, 'Void Staff,Lich Robes,Phylactery,Death Crown,Dark Ring',    'Undying,Mana Overload,Time Warp', 'Void Rift'),
    (9,  'VoidReaper',   'Orc',   'Bloodmire Wastes',  'Warrior', 'Strength',     15,  80000,  310, 310,   50,  50, 55, 48, 12, 'Crude Axe',                                                 NULL, 'Starting Village'),
    (10, 'LostOne',      'Human', 'Stormhaven',        'Mage',    'Intelligence',  3,   1200,  120, 120,   90,  90, 10, 12, 22, NULL,                                                        NULL, 'Starting Village');


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 3: quests
--
--  [PROBLEM - 2NF Partial Key Dependency]
--    Primary key is composite: (quest_id, char_id)
--    BUT: quest_name, quest_description, required_level, reward_gold, reward_xp
--    all depend ONLY on quest_id, not on the full composite key.
--    This means quest_name is stored once per CHARACTER that accepts the quest —
--    massive redundancy and update anomaly risk.
--
--  [FIX]
--    quests(quest_id, quest_name, description, required_level, reward_gold, reward_xp)
--    character_quests(quest_id FK, char_id FK, status, accepted_at, completed_at)
--
--  [VERDICT]  ✅ Normalize — this is the canonical 2NF example.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS quests CASCADE;
CREATE TABLE quests (
    quest_id        INT NOT NULL,
    char_id         INT NOT NULL REFERENCES characters(char_id),
    -- ↓ These depend only on quest_id, not on (quest_id, char_id)  ← 2NF VIOLATION
    quest_name      TEXT NOT NULL,
    quest_giver     TEXT,
    quest_zone      TEXT,
    required_level  INT,
    reward_gold     INT,
    reward_xp       INT,
    reward_item     TEXT,
    -- ↓ These legitimately depend on the composite key
    status          TEXT DEFAULT 'active', -- 'active','completed','abandoned'
    progress        TEXT,  -- '3/10 wolves killed'
    accepted_at     TIMESTAMPTZ DEFAULT NOW(),
    completed_at    TIMESTAMPTZ,
    PRIMARY KEY (quest_id, char_id)
);

INSERT INTO quests VALUES
    (101, 1, 'The Iron Siege',       'Commander Varek', 'Iron Citadel',    40, 500, 12000, 'Siege Medal',      'completed', '1/1',   NOW()-'10 days'::interval, NOW()-'8 days'::interval),
    (101, 3, 'The Iron Siege',       'Commander Varek', 'Iron Citadel',    40, 500, 12000, 'Siege Medal',      'active',    '0/1',   NOW()-'2 days'::interval,  NULL),
    (101, 6, 'The Iron Siege',       'Commander Varek', 'Iron Citadel',    40, 500, 12000, 'Siege Medal',      'abandoned', '0/1',   NOW()-'5 days'::interval,  NULL),
    (102, 2, 'Echoes of Eternity',   'Archmage Sorel',  'Tower of Echoes', 60, 900, 25000, 'Arcane Codex',     'active',    '2/5',   NOW()-'1 day'::interval,   NULL),
    (102, 5, 'Echoes of Eternity',   'Archmage Sorel',  'Tower of Echoes', 60, 900, 25000, 'Arcane Codex',     'active',    '1/5',   NOW()-'3 days'::interval,  NULL),
    (103, 4, 'Shadows of the Pact',  'Shade Karynn',    'The Undercity',   50, 700, 18000, 'Void Shard',       'completed', '5/5',   NOW()-'7 days'::interval,  NOW()-'6 days'::interval),
    (103, 7, 'Shadows of the Pact',  'Shade Karynn',    'The Undercity',   50, 700, 18000, 'Void Shard',       'active',    '1/5',   NOW()-'1 day'::interval,   NULL),
    (104, 8, 'Beyond the Void Rift', 'The Nameless',    'Void Rift',       75,1500, 50000, 'Fragment of End',  'active',    '0/3',   NOW()-'12 hours'::interval,NULL),
    (105, 9, 'First Steps',          'Village Elder',   'Starting Village', 1,  20,   500, 'Rookie Sword',     'active',    '2/5',   NOW()-'1 day'::interval,   NULL),
    (105,10, 'First Steps',          'Village Elder',   'Starting Village', 1,  20,   500, 'Rookie Sword',     'active',    '0/5',   NOW()-'2 hours'::interval, NULL);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 4: items
--
--  [PROBLEM - Mixed 2NF + questionable design]
--    'vendor_name' and 'vendor_city' describe the vendor, not the item.
--    If a vendor moves cities or renames, you update every item they sell.
--    'stat_block' is a JSON-ish string — queryable only with pain.
--    'item_type' and 'item_subtype' have a dependency: subtype → type
--    (a 'Longsword' is always a 'Weapon'; a 'Healing Potion' is always 'Consumable')
--
--  [FIX]
--    vendors(vendor_id, vendor_name, vendor_city, vendor_zone)
--    item_types(subtype, parent_type)
--    items(item_id, item_name, subtype FK, base_value, ...) + actual stat columns
--
--  [VERDICT]  ✅ Normalize vendor — debatable whether to split item_type/subtype
--             for a small fixed enum. The stat_block column is definitely wrong.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS items CASCADE;
CREATE TABLE items (
    item_id         SERIAL PRIMARY KEY,
    item_name       TEXT NOT NULL,
    item_type       TEXT NOT NULL,    -- 'Weapon', 'Armor', 'Consumable', 'Quest'
    item_subtype    TEXT,             -- 'Longsword', 'Staff', 'Chest Armor', 'Potion'
    rarity          TEXT DEFAULT 'Common', -- 'Common','Uncommon','Rare','Epic','Legendary'
    required_level  INT DEFAULT 1,
    base_value      INT DEFAULT 0,    -- gold value
    stat_block      TEXT,             -- ← 1NF BOMB: 'STR+15,VIT+10,CRIT+5%'
    vendor_id       INT,
    vendor_name     TEXT,             -- ← transitive: vendor_id → vendor_name
    vendor_city     TEXT,             -- ← transitive: vendor_id → vendor_city
    vendor_zone     TEXT,             -- ← transitive: vendor_id → vendor_zone
    is_tradeable    BOOLEAN DEFAULT true,
    is_consumable   BOOLEAN DEFAULT false
);

INSERT INTO items
    (item_name, item_type, item_subtype, rarity, required_level, base_value, stat_block,
     vendor_id, vendor_name, vendor_city, vendor_zone, is_tradeable, is_consumable)
VALUES
    ('Warblade of the Fallen',   'Weapon',    'Longsword',    'Legendary', 40, 15000, 'STR+30,VIT+15,CRIT+8%,LifeSteal+5%',  1, 'Aldric the Armorer', 'Ironforge City', 'Iron Citadel',    true,  false),
    ('Staff of Eternity',         'Weapon',    'Staff',        'Legendary', 60, 18000, 'INT+45,MANA+200,SpellPower+30%',       2, 'Mystica',            'Arcane Spire',   'Tower of Echoes', true,  false),
    ('Shadowfang Daggers',        'Weapon',    'Dagger',       'Epic',      50,  9000, 'AGI+25,CRIT+15%,PoisonChance+20%',    3, 'Shade Merchant',     'Undercroft',     'The Undercity',   true,  false),
    ('Plate of the Crusader',     'Armor',     'Chest Armor',  'Rare',      35,  6000, 'VIT+20,DEF+40,HolyRes+15%',           1, 'Aldric the Armorer', 'Ironforge City', 'Iron Citadel',    true,  false),
    ('Robes of the Archmage',     'Armor',     'Chest Armor',  'Legendary', 65,  20000,'INT+35,MANA+300,CastSpeed+20%',       2, 'Mystica',            'Arcane Spire',   'Tower of Echoes', true,  false),
    ('Cloak of Shadows',          'Armor',     'Cloak',        'Epic',      45,  8000, 'AGI+20,Stealth+30,DodgeChance+12%',   3, 'Shade Merchant',     'Undercroft',     'The Undercity',   true,  false),
    ('Ring of Vigor',             'Accessory', 'Ring',         'Uncommon',  20,  1200, 'VIT+10,HealthRegen+5',                1, 'Aldric the Armorer', 'Ironforge City', 'Iron Citadel',    true,  false),
    ('Healing Potion',            'Consumable','Potion',       'Common',     1,    50, 'Heal+200',                            4, 'Mira the Merchant',  'Crossroads',     'Ashenvale',       true,  true),
    ('Mana Elixir',               'Consumable','Potion',       'Common',     1,    60, 'Mana+150',                            4, 'Mira the Merchant',  'Crossroads',     'Ashenvale',       true,  true),
    ('Scroll of Recall',          'Consumable','Scroll',       'Uncommon',  10,   200, 'TeleportHome',                        4, 'Mira the Merchant',  'Crossroads',     'Ashenvale',       true,  true),
    ('Holy Avenger',              'Weapon',    'Longsword',    'Legendary', 50, 17000, 'STR+25,VIT+20,HolyDmg+40,Undead+80%', 1,'Aldric the Armorer', 'Ironforge City', 'Iron Citadel',    true,  false),
    ('Void Crystal Staff',        'Weapon',    'Staff',        'Epic',      65, 14000, 'INT+38,VoidDmg+25,SoulDrain+10%',     3, 'Shade Merchant',     'Undercroft',     'The Undercity',   true,  false),
    ('Crude Axe',                 'Weapon',    'Axe',          'Common',     1,    30, 'STR+2',                               4, 'Mira the Merchant',  'Crossroads',     'Ashenvale',       true,  false),
    ('Siege Medal',               'Quest',     'Token',        'Uncommon',  40,     0, NULL,                                  NULL, NULL,             NULL,             NULL,              false, false),
    ('Fragment of End',           'Quest',     'Artifact',     'Legendary', 75,     0, NULL,                                  NULL, NULL,             NULL,             NULL,              false, false);


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 5: combat_log
--
--  [PROBLEM?]  Actually this is intentionally denormalized.
--    attacker_name and defender_name are duplicated from the characters table.
--    spell_name is duplicated from a spells table that doesn't exist yet.
--    In a normalized world, you'd store only IDs and JOIN to get names.
--
--  [WHY DENORMALIZATION WINS HERE]
--    1. This is an append-only event log — rows are NEVER updated.
--    2. Characters can be deleted; the log should still show their name.
--    3. This table will have MILLIONS of rows. Every query is a range scan
--       on 'logged_at'. Adding 2 JOINs per row read would destroy performance.
--    4. Analytics on this table (damage graphs, reports) need flat fast reads.
--    This is the same pattern used by Kafka, ClickHouse, and every real game
--    telemetry system on the planet.
--
--  [VERDICT]  ❌ Do NOT normalize — this is a write-once event store.
--             Denormalization here is an intentional architectural decision.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS combat_log CASCADE;
CREATE TABLE combat_log (
    log_id          BIGSERIAL PRIMARY KEY,
    logged_at       TIMESTAMPTZ DEFAULT NOW(),
    attacker_id     INT,
    attacker_name   TEXT,   -- ← intentional redundancy: survives character deletion
    defender_id     INT,
    defender_name   TEXT,   -- ← intentional redundancy
    action_type     TEXT,   -- 'spell', 'melee', 'ranged', 'item'
    spell_name      TEXT,   -- ← intentional redundancy: spell balance may change
    damage_dealt    INT DEFAULT 0,
    damage_type     TEXT,   -- 'fire','physical','void','holy'
    is_critical     BOOLEAN DEFAULT false,
    is_killing_blow BOOLEAN DEFAULT false,
    defender_hp_remaining INT,
    zone            TEXT
);

INSERT INTO combat_log
    (attacker_id, attacker_name, defender_id, defender_name, action_type, spell_name,
     damage_dealt, damage_type, is_critical, is_killing_blow, defender_hp_remaining, zone)
VALUES
    (2, 'Seraphina',  NULL, 'Skeleton Warrior',  'spell',  'Fireball',        1240, 'fire',     true,  true,    0,   'Tower of Echoes'),
    (2, 'Seraphina',  NULL, 'Void Wraith',        'spell',  'Arcane Blast',     890, 'arcane',   false, false,  310,  'Tower of Echoes'),
    (1, 'Kael',       NULL, 'Iron Golem',         'melee',  NULL,               445, 'physical', false, false,  1200, 'Iron Citadel'),
    (1, 'Kael',       NULL, 'Iron Golem',         'melee',  NULL,               890, 'physical', true,  false,   310, 'Iron Citadel'),
    (1, 'Kael',       NULL, 'Iron Golem',         'melee',  NULL,               320, 'physical', false, true,      0, 'Iron Citadel'),
    (5, 'Morrigan',   4,    'VoidZyx',            'spell',  'Corruption',       555, 'void',     false, false,    5,  'Cursed Sanctum'),
    (4, 'VoidZyx',    5,    'Morrigan',           'melee',  NULL,               210, 'physical', false, false,  270,  'Cursed Sanctum'),
    (8, 'Eldritch',   NULL, 'Ancient Dragon',     'spell',  'Oblivion Wave',   3200, 'void',     true,  false, 28000, 'Void Rift'),
    (8, 'Eldritch',   NULL, 'Ancient Dragon',     'spell',  'Soul Rend',       2800, 'void',     false, false, 25200, 'Void Rift'),
    (3, 'DarkPaladin',NULL, 'Undead Knight',      'spell',  'Holy Strike',      780, 'holy',     false, true,      0, 'Cathedral of Dawn'),
    (6, 'Theron',     NULL, 'Boar',               'melee',  NULL,               320, 'physical', false, true,      0, 'Bloodmire Wastes'),
    (7, 'Shadow',     NULL, 'Bandit',             'melee',  NULL,               180, 'physical', false, false,   90, 'Duskwood'),
    (2, 'Seraphina',  NULL, 'Ice Elemental',      'spell',  'Mana Storm',      1680, 'arcane',   true,  true,     0, 'Tower of Echoes'),
    (5, 'Morrigan',   NULL, 'Paladin NPC',        'spell',  'Drain Soul',       440, 'void',     false, false,  160, 'Cursed Sanctum'),
    (8, 'Eldritch',   NULL, 'Ancient Dragon',     'spell',  'Void Collapse',   4100, 'void',     true,  true,     0, 'Void Rift');


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 6: guilds
--
--  [PROBLEM - 2NF + Redundancy with players table]
--    guild_leader_class and guild_leader_level are facts about a character,
--    not about the guild. They'll go stale the moment the leader levels up.
--    guild_server_region arguably depends on guild_server, not guild_id.
--    total_members is a DERIVED value — it can always be computed with COUNT().
--    Storing it here means it must be manually kept in sync.
--
--  [FIX]
--    Remove guild_leader_class, guild_leader_level (query characters table).
--    Remove total_members (use SELECT COUNT(*)).
--    Potentially: servers(server_id, server_name, region).
--
--  [VERDICT]  ⚠️  DEBATABLE for total_members:
--    In a game with millions of players, COUNT(*) on every page load is expensive.
--    Many real systems cache this exact value denormalized. The question is whether
--    you maintain it with triggers or accept eventual consistency.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS guilds CASCADE;
CREATE TABLE guilds (
    guild_id            SERIAL PRIMARY KEY,
    guild_name          TEXT NOT NULL UNIQUE,
    guild_tag           TEXT NOT NULL UNIQUE,  -- [IRON], [CRIM], [SLVR]
    guild_leader_id     INT REFERENCES characters(char_id),
    guild_leader_name   TEXT,       -- ← redundant: can JOIN characters
    guild_leader_class  TEXT,       -- ← transitive: guild_leader_id → class (will go stale!)
    guild_leader_level  INT,        -- ← transitive: guild_leader_id → level (will go stale!)
    guild_level         INT DEFAULT 1,
    total_members       INT DEFAULT 0,   -- ← DERIVED: should be COUNT(*) from players
    guild_bank_gold     BIGINT DEFAULT 0,
    guild_server        TEXT,       -- 'Realm-01', 'Realm-02'
    guild_server_region TEXT,       -- ← transitive: server → region ('NA','LATAM','EU','APAC')
    founded_at          TIMESTAMPTZ DEFAULT NOW(),
    guild_motto         TEXT
);

INSERT INTO guilds
    (guild_name, guild_tag, guild_leader_id, guild_leader_name, guild_leader_class,
     guild_leader_level, guild_level, total_members, guild_bank_gold,
     guild_server, guild_server_region, guild_motto)
VALUES
    ('Iron Vanguard',   '[IRON]', 1, 'Kael',     'Warrior', 42, 8, 3, 250000, 'Realm-01', 'NA',   'Strength through iron'),
    ('Crimson Eclipse', '[CRIM]', 5, 'Morrigan', 'Warlock', 71, 12, 3, 890000, 'Realm-02', 'APAC', 'The end justifies the void'),
    ('Silver Dawn',     '[SLVR]', 8, 'Eldritch', 'Mage',    80, 15, 2, 4200000,'Realm-02', 'APAC', 'Knowledge is eternal');


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 7: leaderboard
--
--  [PROBLEM?]  Again intentional denormalization — but this one is trickier.
--    character_class and guild_name are duplicated from other tables.
--    rank is a derived/computed value.
--    last_kill_name is arguably event data.
--
--  [WHY THIS IS A GREY AREA]
--    This table is a SNAPSHOT — it's rebuilt periodically (e.g. every hour).
--    It exists purely for fast reads of the top-N display. Think of it as a
--    "materialized view" baked into a table. Normalizing it would mean either:
--    a) Expensive JOIN queries on the hot path (homepage loads)
--    b) Building a materialized view anyway (which is just normalized + cached)
--    The interesting question: is there even a PRIMARY KEY that makes sense?
--
--  [VERDICT]  ⚠️  DEBATABLE — this is a reporting/cache table, not a source of truth.
--             Teach students the difference between OLTP tables (normalize) and
--             OLAP/reporting tables (denormalize for read speed).
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS leaderboard CASCADE;
CREATE TABLE leaderboard (
    rank                INT NOT NULL,
    char_id             INT REFERENCES characters(char_id),
    char_name           TEXT,       -- ← redundant snapshot
    character_class     TEXT,       -- ← redundant snapshot
    character_level     INT,        -- ← redundant snapshot (stale between updates)
    guild_name          TEXT,       -- ← redundant snapshot
    total_kills         INT DEFAULT 0,
    total_deaths        INT DEFAULT 0,
    kd_ratio            NUMERIC(6,2), -- ← DERIVED: kills/deaths
    total_damage_dealt  BIGINT DEFAULT 0,
    highest_damage_hit  INT DEFAULT 0,
    last_kill_name      TEXT,       -- ← event data living in wrong table
    snapshot_taken_at   TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO leaderboard VALUES
    (1,  8, 'Eldritch',    'Mage',    80, 'Silver Dawn',     8420, 12,  701.67, 98500000, 4100, 'Ancient Dragon',  NOW()),
    (2,  5, 'Morrigan',    'Warlock', 71, 'Crimson Eclipse', 5210, 88,   59.20, 54200000, 2400, 'Paladin NPC',     NOW()),
    (3,  2, 'Seraphina',   'Mage',    67, 'Iron Vanguard',   4890, 120,  40.75, 48900000, 1680, 'Ice Elemental',   NOW()),
    (4,  4, 'VoidZyx',     'Rogue',   58, 'Crimson Eclipse', 3300, 210,  15.71, 31000000, 1200, NULL,              NOW()),
    (5,  1, 'Kael',        'Warrior', 42, 'Iron Vanguard',   2100, 340,   6.18, 18500000,  890, 'Iron Golem',      NOW()),
    (6,  3, 'DarkPaladin', 'Paladin', 35, 'Iron Vanguard',    980, 290,   3.38,  8200000,  780, 'Undead Knight',   NOW()),
    (7,  6, 'Theron',      'Warrior', 29, 'Crimson Eclipse',  540, 410,   1.32,  4100000,  320, 'Boar',            NOW()),
    (8,  7, 'Shadow',      'Rogue',   22, 'Silver Dawn',      210, 380,   0.55,  1800000,  180, 'Bandit',          NOW());


-- ─────────────────────────────────────────────────────────────────────────────
--  TABLE 8: character_skills
--
--  [PROBLEM - BCNF violation + multi-valued dependency]
--    (char_id, skill_name) → skill_rank: fine.
--    BUT skill_description, skill_max_rank, skill_school depend ONLY on skill_name.
--    If you rename a skill or change its description, you update every character
--    that has learned it.
--    Also: unlocked_by_skill is a self-referential dependency within the skill
--    domain — this is crying out for a skill tree structure.
--
--  [FIX]
--    skills(skill_id, skill_name, description, max_rank, school, unlocked_by FK)
--    character_skills(char_id FK, skill_id FK, current_rank)
--
--  [VERDICT]  ✅ Normalize — the skill definition data is duplicated per character.
-- ─────────────────────────────────────────────────────────────────────────────
DROP TABLE IF EXISTS character_skills CASCADE;
CREATE TABLE character_skills (
    char_id             INT REFERENCES characters(char_id),
    skill_name          TEXT NOT NULL,
    skill_rank          INT DEFAULT 1,
    -- ↓ These depend only on skill_name, not on (char_id, skill_name)
    skill_description   TEXT,       -- ← will drift if skill is reworked
    skill_max_rank      INT,        -- ← same for every character
    skill_school        TEXT,       -- ← same for every character
    unlocked_by_skill   TEXT,       -- ← same for every character (prerequisite tree)
    -- ↓ These legitimately vary per character
    is_hotbarred        BOOLEAN DEFAULT false,
    times_used          INT DEFAULT 0,
    last_used_at        TIMESTAMPTZ,
    PRIMARY KEY (char_id, skill_name)
);

INSERT INTO character_skills VALUES
    (1, 'Cleave',           3, 'Strike multiple enemies in a cone.',         5, 'Warrior', NULL,         true,  1240, NOW()-'1 hour'::interval),
    (1, 'Shield Wall',      5, 'Reduce incoming damage for 8 seconds.',      5, 'Warrior', 'Cleave',     true,   890, NOW()-'30 min'::interval),
    (1, 'Battle Cry',       2, 'Increase party STR by 20% for 30 seconds.',  5, 'Warrior', 'Cleave',     false,  310, NOW()-'2 hours'::interval),
    (2, 'Fireball',         5, 'Hurl a sphere of fire dealing 8d6 damage.',  5, 'Evocation', NULL,       true,  4200, NOW()-'20 min'::interval),
    (2, 'Arcane Blast',     5, 'Raw arcane force bolt.',                     5, 'Evocation', NULL,       true,  3100, NOW()-'40 min'::interval),
    (2, 'Mana Storm',       4, 'Channel arcane energy in an AoE.',           5, 'Evocation', 'Fireball', true,  2800, NOW()-'1 hour'::interval),
    (2, 'Blink',            3, 'Teleport 20 yards instantly.',               3, 'Conjuration','Fireball',false, 1200, NOW()-'3 hours'::interval),
    (5, 'Corruption',       5, 'Afflict target with void decay.',            5, 'Warlock',  NULL,        true,  5100, NOW()-'15 min'::interval),
    (5, 'Drain Soul',       5, 'Drain lifeforce, healing self.',             5, 'Warlock',  'Corruption',true, 4800, NOW()-'10 min'::interval),
    (5, 'Fel Armor',        4, 'Convert % spell damage to self-healing.',    5, 'Warlock',  NULL,        true,  2200, NOW()-'2 hours'::interval),
    (8, 'Oblivion Wave',    5, 'Unleash a wave of void that erases matter.', 5, 'Forbidden','Drain Soul', true, 8420, NOW()-'5 min'::interval),
    (8, 'Soul Rend',        5, 'Tear the soul from a target.',               5, 'Forbidden','Oblivion Wave',true,7900,NOW()-'8 min'::interval),
    (8, 'Void Collapse',    5, 'Collapse local space into a singularity.',   5, 'Forbidden','Soul Rend',  true, 8420, NOW()-'5 min'::interval),
    (4, 'Shadowstep',       4, 'Instantly move behind target.',              5, 'Rogue',    NULL,        true,  3300, NOW()-'25 min'::interval),
    (4, 'Eviserate',        5, 'Spend combo points for massive damage.',     5, 'Rogue',    'Shadowstep',true, 3100, NOW()-'30 min'::interval);


-- ─────────────────────────────────────────────────────────────────────────────
--  SUMMARY VIEW — useful for classroom queries
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW v_anomaly_demo AS
SELECT
    p.username,
    p.guild_name        AS players_guild_name,
    g.guild_name        AS guilds_guild_name,
    p.guild_leader       AS players_guild_leader,
    c.char_name,
    c.equipped_items    AS items_as_csv,
    l.rank              AS leaderboard_rank,
    l.kd_ratio
FROM players p
LEFT JOIN characters c ON c.player_id = p.player_id
LEFT JOIN guilds g ON g.guild_id = p.guild_id
LEFT JOIN leaderboard l ON l.char_id = c.char_id
ORDER BY l.rank;

-- ─────────────────────────────────────────────────────────────────────────────
--  QUICK REFERENCE QUERIES (paste these into QueryForge to explore!)
-- ─────────────────────────────────────────────────────────────────────────────
/*
-- 1. Show the update anomaly in players (what happens when Iron Vanguard renames?)
SELECT player_id, username, guild_id, guild_name, guild_leader FROM players WHERE guild_id = 1;

-- 2. Prove the 2NF violation in quests — quest_name is the same across all chars
SELECT quest_id, quest_name, reward_gold, COUNT(*) as accepted_by_n_chars
FROM quests GROUP BY quest_id, quest_name, reward_gold ORDER BY quest_id;

-- 3. Feel the pain of 1NF in characters — try to find everyone with a staff
SELECT char_name, equipped_items FROM characters WHERE equipped_items ILIKE '%staff%';
-- vs what a proper character_equipment table query would look like:
-- SELECT c.char_name FROM characters c JOIN character_equipment e ON ... WHERE e.item_id = ...

-- 4. Show the stale-data risk in guilds — leader level won't update automatically
SELECT g.guild_name, g.guild_leader_level AS guild_says, c.level AS actual_level
FROM guilds g JOIN characters c ON c.char_id = g.guild_leader_id;

-- 5. Demonstrate why combat_log redundancy is OK — find all kills even if char deleted
SELECT attacker_name, defender_name, damage_dealt, is_killing_blow
FROM combat_log WHERE is_killing_blow = true ORDER BY damage_dealt DESC;

-- 6. Show the derived-value problem — total_members might be wrong
SELECT g.guild_name, g.total_members AS stored, COUNT(p.player_id) AS real_count
FROM guilds g LEFT JOIN players p ON p.guild_id = g.guild_id GROUP BY g.guild_id, g.guild_name, g.total_members;

-- 7. Skill redundancy — how many times is 'Fireball' described?
SELECT skill_name, skill_description, COUNT(*) as repeated_for_n_chars
FROM character_skills GROUP BY skill_name, skill_description ORDER BY repeated_for_n_chars DESC;
*/
