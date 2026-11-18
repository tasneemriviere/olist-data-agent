{#
    Par défaut, dbt concatène le schéma du profil et le schéma personnalisé
    (STAGING + MARTS -> STAGING_MARTS). On veut utiliser exactement le nom
    configuré dans dbt_project.yml : STAGING ou MARTS.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
