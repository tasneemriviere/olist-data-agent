{#
    review_id n'est pas unique dans la source : un même avis peut porter sur
    plusieurs commandes. Le grain réel est le couple (review_id, order_id),
    qui lui est unique. On garde donc toutes les lignes.
#}
with source as (

    select * from {{ source('olist', 'order_reviews') }}

)

select
    review_id,
    order_id,
    try_to_number(review_score)                         as review_score,
    nullif(trim(review_comment_title), '')              as review_comment_title,
    nullif(trim(review_comment_message), '')            as review_comment_message,
    try_to_timestamp_ntz(review_creation_date)          as review_created_at,
    try_to_timestamp_ntz(review_answer_timestamp)       as review_answered_at,
    _loaded_at

from source
