-- =============================================================================
-- olist-data-agent : mise en place de Snowflake
-- =============================================================================
-- À exécuter une fois, dans un worksheet Snowsight, avec "Run All"
-- (Cmd+Maj+Entrée). Le script est idempotent : on peut le relancer sans risque.
--
-- Prérequis : avoir généré une paire de clés (voir README) et remplacer
-- <CLE_PUBLIQUE> à la fin du script par le contenu de ~/.snowflake/rsa_key.pub,
-- sans les lignes BEGIN/END.
-- =============================================================================

USE ROLE ACCOUNTADMIN;

-- -----------------------------------------------------------------------------
-- 1. Warehouse : taille minimale, suspension automatique après 60 s
-- -----------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS OLIST_WH
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE;

-- -----------------------------------------------------------------------------
-- 2. Base et schémas des trois couches
-- -----------------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS OLIST;
CREATE SCHEMA IF NOT EXISTS OLIST.RAW;      -- copie fidèle des CSV (ingestion Python)
CREATE SCHEMA IF NOT EXISTS OLIST.STAGING;  -- modèles dbt de staging
CREATE SCHEMA IF NOT EXISTS OLIST.MARTS;    -- tables métier dbt, lues par l'agent

-- -----------------------------------------------------------------------------
-- 3. Rôle du pipeline (ingestion, dbt, Airflow)
-- -----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS OLIST_PIPELINE;
GRANT USAGE ON WAREHOUSE OLIST_WH TO ROLE OLIST_PIPELINE;
GRANT ALL ON DATABASE OLIST TO ROLE OLIST_PIPELINE;
GRANT ALL ON ALL SCHEMAS IN DATABASE OLIST TO ROLE OLIST_PIPELINE;
GRANT ROLE OLIST_PIPELINE TO ROLE SYSADMIN;

-- -----------------------------------------------------------------------------
-- 4. Utilisateur technique (authentification par paire de clés, sans MFA)
-- -----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS OLIST_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = OLIST_PIPELINE
  DEFAULT_WAREHOUSE = OLIST_WH;
GRANT ROLE OLIST_PIPELINE TO USER OLIST_SVC;

-- Remplacer <CLE_PUBLIQUE> avant d'exécuter cette ligne
ALTER USER OLIST_SVC SET RSA_PUBLIC_KEY = '<CLE_PUBLIQUE>';

-- -----------------------------------------------------------------------------
-- 5. Vérifications
-- -----------------------------------------------------------------------------
SHOW GRANTS TO USER OLIST_SVC;   -- doit afficher OLIST_PIPELINE
SHOW GRANTS TO ROLE OLIST_PIPELINE;

-- Après l'ingestion (python ingestion/load_raw.py) :
-- SELECT table_name, row_count
-- FROM OLIST.INFORMATION_SCHEMA.TABLES
-- WHERE table_schema = 'RAW'
-- ORDER BY table_name;
