{#
    Une ligne par client réel (customer_unique_id). Dans Olist, customer_id change
    à chaque commande : on regroupe donc les commandes d'une même personne.
    La localisation retenue est celle de la commande la plus récente.
#}
with orders as (

    select * from {{ ref('fct_orders') }}

),

customers as (

    select * from {{ ref('stg_olist__customers') }}

),

geolocation as (

    select * from {{ ref('stg_olist__geolocation') }}

),

states as (

    select * from {{ ref('brazil_states') }}

),

-- Adresse de la commande la plus récente de chaque client
latest_address as (

    select
        orders.customer_unique_id,
        customers.customer_zip_code_prefix,
        customers.customer_city,
        customers.customer_state
    from orders
    inner join customers on customers.customer_id = orders.customer_id
    qualify row_number() over (
        partition by orders.customer_unique_id
        order by orders.ordered_at desc, orders.order_id
    ) = 1

),

order_stats as (

    select
        customer_unique_id,
        min(ordered_at)                         as first_order_at,
        max(ordered_at)                         as last_order_at,
        count(*)                                as orders_count,
        count_if(is_delivered)                  as delivered_orders_count,
        count_if(order_status = 'canceled')     as canceled_orders_count,
        sum(order_amount)                       as total_order_amount,
        sum(payments_amount)                    as total_payments_amount,
        avg(review_score)                       as avg_review_score,
        count_if(is_late)                       as late_orders_count
    from orders
    group by customer_unique_id

)

select
    latest_address.customer_unique_id,
    latest_address.customer_zip_code_prefix,
    latest_address.customer_city,
    latest_address.customer_state,
    states.state_name                               as customer_state_name,
    states.region                                   as customer_region,
    -- 279 codes postaux sont absents de la géolocalisation : coordonnées nulles
    geolocation.latitude,
    geolocation.longitude,

    order_stats.first_order_at,
    order_stats.last_order_at,
    order_stats.orders_count,
    order_stats.delivered_orders_count,
    order_stats.canceled_orders_count,
    order_stats.late_orders_count,
    order_stats.total_order_amount,
    order_stats.total_payments_amount,
    round(order_stats.avg_review_score, 2)          as avg_review_score,
    order_stats.orders_count > 1                    as is_repeat_customer

from latest_address
inner join order_stats  on order_stats.customer_unique_id = latest_address.customer_unique_id
left join states        on states.state_code = latest_address.customer_state
left join geolocation   on geolocation.zip_code_prefix = latest_address.customer_zip_code_prefix
