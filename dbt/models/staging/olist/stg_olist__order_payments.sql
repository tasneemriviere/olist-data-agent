with source as (

    select * from {{ source('olist', 'order_payments') }}

)

select
    order_id,
    try_to_number(payment_sequential)            as payment_sequential,
    lower(trim(payment_type))                    as payment_type,
    -- 2 paiements par carte ont 0 échéance dans la source : on garde la valeur brute,
    -- l'indicateur "paiement en plusieurs fois" est calculé dans le mart.
    try_to_number(payment_installments)          as installments_count,
    try_to_decimal(payment_value, 12, 2)         as payment_amount,
    _loaded_at

from source
