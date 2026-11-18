{#
    La source contient environ 1 million de lignes pour 19 000 codes postaux
    (plusieurs points GPS par code). On ramène le grain à un code postal :
      - on écarte les points hors du Brésil (coordonnées aberrantes) ;
      - on prend la moyenne des coordonnées ;
      - on garde la ville et l'État les plus fréquents.
#}
with source as (

    select
        trim(geolocation_zip_code_prefix)    as zip_code_prefix,
        try_to_double(geolocation_lat)       as latitude,
        try_to_double(geolocation_lng)       as longitude,
        lower(trim(geolocation_city))        as city,
        upper(trim(geolocation_state))       as state
    from {{ source('olist', 'geolocation') }}

),

in_brazil as (

    select *
    from source
    where latitude between -34 and 6
      and longitude between -75 and -34

)

select
    zip_code_prefix,
    avg(latitude)       as latitude,
    avg(longitude)      as longitude,
    mode(city)          as city,
    mode(state)         as state,
    count(*)            as source_points_count

from in_brazil
group by zip_code_prefix
