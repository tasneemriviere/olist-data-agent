-- Aucune commande ne doit être perdue ou dupliquée entre RAW et fct_orders.
-- Le test échoue s'il renvoie une ligne.
with counts as (

    select
        (select count(*) from {{ source('olist', 'orders') }})   as raw_orders,
        (select count(*) from {{ ref('fct_orders') }})           as mart_orders

)

select *
from counts
where raw_orders <> mart_orders
