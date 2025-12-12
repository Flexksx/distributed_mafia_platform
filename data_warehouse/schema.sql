-- Data Warehouse Schema for Mafia Platform
-- This schema is designed for analytics and reporting purposes
-- It aggregates data from all operational databases

-- ============================================
-- DIMENSION TABLES (slowly changing)
-- ============================================

-- Dimension: Users
CREATE TABLE IF NOT EXISTS dim_users (
    user_id VARCHAR(255) PRIMARY KEY,
    username VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    created_at TIMESTAMP NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Slowly changing dimension tracking
    is_current BOOLEAN DEFAULT TRUE,
    valid_from TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    valid_to TIMESTAMP DEFAULT '9999-12-31 23:59:59'
);

-- Dimension: Lobbies
CREATE TABLE IF NOT EXISTS dim_lobbies (
    lobby_id VARCHAR(255) PRIMARY KEY,
    lobby_name VARCHAR(255) NOT NULL,
    max_players INTEGER NOT NULL,
    created_at TIMESTAMP NOT NULL,
    created_by_user_id VARCHAR(255),
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Dimension: Roles (game roles like Mafia, Citizen, etc.)
CREATE TABLE IF NOT EXISTS dim_roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE,
    role_type VARCHAR(50), -- 'mafia', 'citizen', 'neutral'
    description TEXT
);

-- Dimension: Time (for time-based analytics)
CREATE TABLE IF NOT EXISTS dim_time (
    time_id SERIAL PRIMARY KEY,
    full_date DATE NOT NULL UNIQUE,
    year INTEGER NOT NULL,
    quarter INTEGER NOT NULL,
    month INTEGER NOT NULL,
    week INTEGER NOT NULL,
    day_of_week INTEGER NOT NULL,
    day_of_month INTEGER NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

-- ============================================
-- FACT TABLES (transactional data)
-- ============================================

-- Fact: Games Played
CREATE TABLE IF NOT EXISTS fact_games (
    game_id SERIAL PRIMARY KEY,
    lobby_id VARCHAR(255) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP,
    duration_minutes INTEGER,
    total_players INTEGER NOT NULL,
    winner_faction VARCHAR(50), -- 'mafia', 'citizens', 'draw'
    total_cycles INTEGER,
    etl_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source_system VARCHAR(50) DEFAULT 'game_service'
);

-- Fact: Player Sessions (per game participation)
CREATE TABLE IF NOT EXISTS fact_player_sessions (
    session_id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    lobby_id VARCHAR(255) NOT NULL,
    game_id INTEGER REFERENCES fact_games(game_id),
    role_assigned VARCHAR(50),
    joined_at TIMESTAMP NOT NULL,
    left_at TIMESTAMP,
    is_winner BOOLEAN,
    survived_until_end BOOLEAN,
    actions_taken INTEGER DEFAULT 0,
    votes_cast INTEGER DEFAULT 0,
    etl_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Fact: Currency Transactions
CREATE TABLE IF NOT EXISTS fact_transactions (
    transaction_id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'purchase', 'reward', 'spend'
    amount DECIMAL(10, 2) NOT NULL,
    currency_type VARCHAR(50) DEFAULT 'coins',
    description TEXT,
    occurred_at TIMESTAMP NOT NULL,
    etl_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source_system VARCHAR(50) DEFAULT 'user_service'
);

-- Fact: User Access Events (logins, logouts)
CREATE TABLE IF NOT EXISTS fact_access_events (
    event_id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- 'login', 'logout', 'session_start'
    device_type VARCHAR(100),
    ip_address VARCHAR(45),
    occurred_at TIMESTAMP NOT NULL,
    etl_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    source_system VARCHAR(50) DEFAULT 'user_service'
);

-- Fact: Game Actions (kills, votes, abilities)
CREATE TABLE IF NOT EXISTS fact_game_actions (
    action_id SERIAL PRIMARY KEY,
    game_id INTEGER REFERENCES fact_games(game_id),
    lobby_id VARCHAR(255) NOT NULL,
    cycle_number INTEGER NOT NULL,
    cycle_type VARCHAR(20) NOT NULL, -- 'day', 'night'
    actor_user_id VARCHAR(255) NOT NULL,
    target_user_id VARCHAR(255),
    action_type VARCHAR(50) NOT NULL, -- 'vote', 'kill', 'investigate', 'heal'
    action_result VARCHAR(50), -- 'success', 'blocked', 'failed'
    occurred_at TIMESTAMP NOT NULL,
    etl_loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ============================================
-- ETL TRACKING TABLE
-- ============================================

CREATE TABLE IF NOT EXISTS etl_run_log (
    run_id SERIAL PRIMARY KEY,
    source_system VARCHAR(100) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    run_start_time TIMESTAMP NOT NULL,
    run_end_time TIMESTAMP,
    records_extracted INTEGER DEFAULT 0,
    records_loaded INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'running', -- 'running', 'success', 'failed'
    error_message TEXT,
    last_extracted_timestamp TIMESTAMP
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX IF NOT EXISTS idx_fact_games_lobby ON fact_games(lobby_id);
CREATE INDEX IF NOT EXISTS idx_fact_games_start ON fact_games(start_time);
CREATE INDEX IF NOT EXISTS idx_fact_sessions_user ON fact_player_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_fact_sessions_lobby ON fact_player_sessions(lobby_id);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_user ON fact_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_fact_transactions_date ON fact_transactions(occurred_at);
CREATE INDEX IF NOT EXISTS idx_fact_actions_game ON fact_game_actions(game_id);
CREATE INDEX IF NOT EXISTS idx_etl_log_source ON etl_run_log(source_system, table_name);

-- ============================================
-- INITIAL SEED DATA FOR DIMENSIONS
-- ============================================

-- Populate dim_roles with standard Mafia roles
INSERT INTO dim_roles (role_name, role_type, description) VALUES
    ('Citizen', 'citizen', 'Regular town member'),
    ('Mafia', 'mafia', 'Mafia team member'),
    ('Doctor', 'citizen', 'Can heal one player per night'),
    ('Detective', 'citizen', 'Can investigate one player per night'),
    ('Godfather', 'mafia', 'Mafia leader, appears innocent to investigation'),
    ('Serial Killer', 'neutral', 'Independent killer')
ON CONFLICT (role_name) DO NOTHING;

-- Populate dim_time for the next 2 years
INSERT INTO dim_time (full_date, year, quarter, month, week, day_of_week, day_of_month, is_weekend)
SELECT 
    d::date,
    EXTRACT(YEAR FROM d),
    EXTRACT(QUARTER FROM d),
    EXTRACT(MONTH FROM d),
    EXTRACT(WEEK FROM d),
    EXTRACT(DOW FROM d),
    EXTRACT(DAY FROM d),
    EXTRACT(DOW FROM d) IN (0, 6)
FROM generate_series('2024-01-01'::date, '2026-12-31'::date, '1 day'::interval) d
ON CONFLICT (full_date) DO NOTHING;
