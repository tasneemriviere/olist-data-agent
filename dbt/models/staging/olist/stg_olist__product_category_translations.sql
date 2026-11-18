{#
    Deux catégories présentes dans products n'ont pas de traduction dans la
    source : on les complète ici pour que chaque produit ait un libellé anglais.
#}
with source as (

    select
        lower(trim(product_category_name))           as product_category_name,
        lower(trim(product_category_name_english))   as product_category_name_english
    from {{ source('olist', 'product_category_name_translation') }}

),

missing_translations as (

    select column1 as product_category_name, column2 as product_category_name_english
    from values
        ('pc_gamer', 'pc_gamer'),
        ('portateis_cozinha_e_preparadores_de_alimentos', 'portable_kitchen_and_food_preparers')

)

select * from source

union all

select m.*
from missing_translations as m
where not exists (
    select 1 from source as s
    where s.product_category_name = m.product_category_name
)
