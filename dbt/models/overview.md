{% docs __overview__ %}

# olist-data-agent

Projet dbt du pipeline **olist-data-agent** : des CSV bruts du jeu
[Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
jusqu'à des tables métier interrogées par un agent IA en langage naturel.

## Les couches

| Schéma | Contenu | Matérialisation |
|---|---|---|
| `RAW` | Copie fidèle des 9 CSV, toutes les colonnes en texte (chargée par `ingestion/load_raw.py`) | tables |
| `STAGING` | Un modèle `stg_olist__*` par table : renommage, typage, nettoyage | vues |
| `MARTS` | Tables métier testées et documentées, lues par l'agent | tables |

## Les marts

- **`fct_orders`** : une ligne par commande (montants, délais, retard de livraison, note client, région).
- **`fct_payments`** : une ligne par paiement (moyen de paiement, échéances, paiement en plusieurs fois).
- **`dim_customers`** : une ligne par client réel (`customer_unique_id`).

## À savoir avant d'interroger les données

- `customer_id` change à chaque commande : pour compter des clients, utiliser `customer_unique_id`.
- `delivery_delay_days` est **négatif** quand la commande arrive en avance, ce qui est le cas le plus
  fréquent. Pour mesurer les retards, préférer le taux de commandes en retard (`is_late`).
- Les délais ne sont calculés que pour les commandes livrées (`is_delivered`).
- Les montants sont en réaux brésiliens (BRL).

Pour aller plus loin : `docs/data_profiling.md` (analyse des données brutes) et
`docs/data_model.md` (règles de calcul et contrôles) dans le dépôt GitHub.

{% enddocs %}
