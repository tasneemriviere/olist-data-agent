{#
    Dans Olist, customer_id est créé à chaque commande. Le vrai identifiant
    d'une personne est customer_unique_id.
#}
with source as (

    select * from {{ source('olist', 'customers') }}

)

select
    customer_id,
    customer_unique_id,
    -- gardé en texte pour conserver les zéros en tête (ex. 01310)
    trim(customer_zip_code_prefix)       as customer_zip_code_prefix,
    lower(trim(customer_city))           as customer_city,
    upper(trim(customer_state))          as customer_state,
    _loaded_at

from source
