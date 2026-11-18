with source as (

    select * from {{ source('olist', 'orders') }}

)

select
    order_id,
    customer_id,
    lower(trim(order_status))                                as order_status,
    try_to_timestamp_ntz(order_purchase_timestamp)           as ordered_at,
    try_to_timestamp_ntz(order_approved_at)                  as approved_at,
    try_to_timestamp_ntz(order_delivered_carrier_date)       as delivered_to_carrier_at,
    try_to_timestamp_ntz(order_delivered_customer_date)      as delivered_to_customer_at,
    try_to_date(order_estimated_delivery_date, 'YYYY-MM-DD HH24:MI:SS')
                                                             as estimated_delivery_date,
    _loaded_at

from source
