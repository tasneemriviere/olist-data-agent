{#
    Une ligne par paiement. Une commande peut être réglée en plusieurs paiements
    (par exemple un bon d'achat + une carte de crédit).
#}
with payments as (

    select * from {{ ref('stg_olist__order_payments') }}

),

orders as (

    select
        order_id,
        customer_unique_id,
        customer_state,
        customer_region,
        order_status,
        ordered_at,
        order_date
    from {{ ref('fct_orders') }}

)

select
    payments.order_id || '-' || payments.payment_sequential    as payment_id,
    payments.order_id,
    payments.payment_sequential,
    payments.payment_type,
    payments.installments_count,
    payments.payment_amount,

    -- Paiement en plusieurs fois : plus d'une échéance
    -- (2 paiements par carte ont 0 échéance dans la source : comptés comme paiement en une fois).
    coalesce(payments.installments_count, 1) > 1              as is_installment,

    orders.customer_unique_id,
    orders.customer_state,
    orders.customer_region,
    orders.order_status,
    orders.ordered_at,
    orders.order_date

from payments
inner join orders on orders.order_id = payments.order_id
