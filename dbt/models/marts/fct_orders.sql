{#
    Une ligne par commande : montants, paiements, délais et retard de livraison,
    note client et localisation du client.
#}
with orders as (

    select * from {{ ref('stg_olist__orders') }}

),

customers as (

    select * from {{ ref('stg_olist__customers') }}

),

states as (

    select * from {{ ref('brazil_states') }}

),

items as (

    select
        order_id,
        count(*)                        as items_count,
        count(distinct product_id)      as distinct_products_count,
        count(distinct seller_id)       as sellers_count,
        sum(item_price)                 as items_amount,
        sum(freight_value)              as freight_amount
    from {{ ref('stg_olist__order_items') }}
    group by order_id

),

payments as (

    select
        order_id,
        count(*)                        as payments_count,
        sum(payment_amount)             as payments_amount,
        max(installments_count)         as max_installments_count
    from {{ ref('stg_olist__order_payments') }}
    group by order_id

),

-- Une commande peut avoir plusieurs avis : on garde le plus récent.
latest_review as (

    select
        order_id,
        review_score
    from {{ ref('stg_olist__order_reviews') }}
    qualify row_number() over (
        partition by order_id
        order by review_answered_at desc nulls last, review_created_at desc, review_id
    ) = 1

),

joined as (

    select
        orders.order_id,
        orders.customer_id,
        customers.customer_unique_id,
        customers.customer_city,
        customers.customer_state,
        states.region                                       as customer_region,

        orders.order_status,
        orders.ordered_at,
        orders.ordered_at::date                             as order_date,
        orders.approved_at,
        orders.delivered_to_carrier_at,
        orders.delivered_to_customer_at,
        orders.estimated_delivery_date,

        coalesce(items.items_count, 0)                      as items_count,
        coalesce(items.distinct_products_count, 0)          as distinct_products_count,
        coalesce(items.sellers_count, 0)                    as sellers_count,
        coalesce(items.items_amount, 0)                     as items_amount,
        coalesce(items.freight_amount, 0)                   as freight_amount,
        coalesce(items.items_amount, 0)
            + coalesce(items.freight_amount, 0)             as order_amount,

        coalesce(payments.payments_count, 0)                as payments_count,
        coalesce(payments.payments_amount, 0)               as payments_amount,
        payments.max_installments_count,

        latest_review.review_score

    from orders
    left join customers      on customers.customer_id = orders.customer_id
    left join states         on states.state_code = customers.customer_state
    left join items          on items.order_id = orders.order_id
    left join payments       on payments.order_id = orders.order_id
    left join latest_review  on latest_review.order_id = orders.order_id

)

select
    *,

    -- Livrée = statut "delivered" ET date de livraison connue
    -- (8 commandes "delivered" n'ont pas de date : elles sont exclues des délais).
    order_status = 'delivered'
        and delivered_to_customer_at is not null            as is_delivered,

    -- Délai total entre l'achat et la livraison, en jours calendaires
    case when is_delivered
        then datediff('day', ordered_at::date, delivered_to_customer_at::date)
    end                                                     as delivery_days,

    -- Retard par rapport à la date promise : > 0 = en retard, <= 0 = à l'heure ou en avance
    case when is_delivered
        then datediff('day', estimated_delivery_date, delivered_to_customer_at::date)
    end                                                     as delivery_delay_days,

    case when is_delivered
        then delivery_delay_days > 0
    end                                                     as is_late

from joined
