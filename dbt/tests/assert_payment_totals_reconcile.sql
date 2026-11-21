-- Le montant total payé doit être identique dans les trois couches :
-- paiements en staging, fct_payments et la somme des payments_amount de fct_orders.
-- Le test échoue s'il renvoie une ligne.
with totals as (

    select
        (select sum(payment_amount)  from {{ ref('stg_olist__order_payments') }})  as staging_total,
        (select sum(payment_amount)  from {{ ref('fct_payments') }})               as fct_payments_total,
        (select sum(payments_amount) from {{ ref('fct_orders') }})                 as fct_orders_total

)

select *
from totals
where staging_total <> fct_payments_total
   or staging_total <> fct_orders_total
