# Analyse des données brutes Olist

Ce document présente le profilage des 9 tables du schéma `RAW`, réalisé avant d'écrire les
modèles dbt de staging. Pour chaque table : ce qui a été vérifié, ce qui a été trouvé, et la
décision de modélisation qui en découle.

[← Retour au README](../README.md)

## Sommaire

- [Méthode](#méthode)
- [1. Commandes](#1-commandes-orders)
- [2. Paiements](#2-paiements-order_payments)
- [3. Articles](#3-articles-order_items)
- [4. Avis clients](#4-avis-clients-order_reviews)
- [5. Clients](#5-clients-customers)
- [6. Vendeurs](#6-vendeurs-sellers)
- [7. Produits](#7-produits-products)
- [8. Géolocalisation](#8-géolocalisation-geolocation)
- [9. Contrôles après le staging](#9-contrôles-après-le-staging)
- [Récapitulatif des décisions](#récapitulatif-des-décisions)

---

## Méthode

Toutes les colonnes de `RAW` sont chargées en `VARCHAR` (voir `ingestion/load_raw.py`).
Le profilage repose donc sur les fonctions `TRY_TO_*` de Snowflake, qui renvoient `NULL` au lieu
d'échouer quand une valeur ne peut pas être convertie. Une valeur non vide dont la conversion
renvoie `NULL` signale une donnée invalide.

Les contrôles portent sur cinq points :

| Contrôle | Question posée |
|---|---|
| Volumétrie | Combien de lignes, combien de valeurs distinctes ? |
| Unicité | La clé supposée est-elle vraiment unique ? |
| Typage | Toutes les valeurs se convertissent-elles en date ou en nombre ? |
| Valeurs | Quelles sont les valeurs possibles des colonnes catégorielles ? Y a-t-il des valeurs aberrantes ? |
| Cohérence | Les références entre tables sont-elles valides ? |

---

## 1. Commandes (`ORDERS`)

**99 441 lignes.**

### Statuts

```sql
select order_status, count(*) from orders group by 1 order by 2 desc;
```

| Statut | Commandes |
|---|---:|
| delivered | 96 478 (97 %) |
| shipped | 1 107 |
| canceled | 625 |
| unavailable | 609 |
| invoiced | 314 |
| processing | 301 |
| created | 5 |
| approved | 2 |

Les 8 valeurs sont propres. Elles servent de liste de référence au test `accepted_values`.

### Dates

```sql
select
    count_if(order_purchase_timestamp is not null
             and try_to_timestamp(order_purchase_timestamp) is null),
    count_if(order_delivered_customer_date is not null
             and try_to_timestamp(order_delivered_customer_date) is null),
    count_if(order_estimated_delivery_date is not null
             and try_to_timestamp(order_estimated_delivery_date) is null),
    count_if(order_delivered_customer_date is null),
    min(order_purchase_timestamp),
    max(order_purchase_timestamp)
from orders;
```

| Mesure | Résultat |
|---|---|
| Dates impossibles à convertir | **0** (format homogène `YYYY-MM-DD HH:MI:SS`) |
| Période couverte | du 4 septembre 2016 au 17 octobre 2018 |
| Commandes sans date de livraison client | 2 965 (commandes non livrées) |

### Anomalie

```sql
select count(*) from orders
where order_status = 'delivered' and order_delivered_customer_date is null;
```

**8 commandes au statut « delivered » n'ont pas de date de livraison.**

→ Dans `fct_orders`, le retard de livraison de ces commandes sera `NULL` plutôt qu'une valeur fausse.

### Unicité

`order_id` n'a aucun doublon : c'est une vraie clé primaire.

---

## 2. Paiements (`ORDER_PAYMENTS`)

**103 886 lignes.**

### Moyens de paiement et échéances

```sql
select payment_type, count(*),
       min(try_to_number(payment_installments)),
       max(try_to_number(payment_installments))
from order_payments group by 1;
```

| Type | Paiements | Échéances min | Échéances max |
|---|---:|---:|---:|
| credit_card | 76 795 | **0** | 24 |
| boleto | 19 784 | 1 | 1 |
| voucher | 5 775 | 1 | 1 |
| debit_card | 1 529 | 1 | 1 |
| not_defined | 3 | 1 | 1 |

- **Seule la carte de crédit permet le paiement en plusieurs fois**, jusqu'à 24 échéances.
- Le *boleto* est un bordereau bancaire brésilien, réglé en une seule fois.

### Anomalies

```sql
select
    count_if(try_to_decimal(payment_value, 12, 2) is null),   -- montants invalides
    count_if(try_to_number(payment_installments) = 0),         -- 0 échéance
    count_if(try_to_decimal(payment_value, 12, 2) = 0)         -- montant nul
from order_payments;

select count(*) from orders o
where not exists (select 1 from order_payments p where p.order_id = o.order_id);
```

| Constat | Nombre | Décision |
|---|---:|---|
| Montants impossibles à convertir | 0 | — |
| Paiements par carte avec **0 échéance** | 2 | Valeur brute gardée en staging ; dans le mart, `is_installment = installments_count > 1` |
| Paiements de **0 BRL** | 9 | Gardés : ce sont des bons d'achat (vouchers) |
| Commandes **sans aucun paiement** | 1 | `left join` vers les paiements dans `fct_orders` |

---

## 3. Articles (`ORDER_ITEMS`)

**112 650 lignes.**

```sql
select count(*),
       count(distinct order_id || '-' || order_item_id),
       count_if(try_to_decimal(price, 12, 2) is null)
from order_items;

select count(*) from order_items i
where not exists (select 1 from orders o where o.order_id = i.order_id);
```

| Contrôle | Résultat |
|---|---|
| Couples `(order_id, order_item_id)` distincts | 112 650 sur 112 650 : **clé composite unique** |
| Prix impossibles à convertir | 0 |
| Articles rattachés à une commande inexistante | 0 |

→ La clé composite est testée avec `dbt_utils.unique_combination_of_columns`.

---

## 4. Avis clients (`ORDER_REVIEWS`)

**99 224 lignes.**

### Clé

```sql
select count(*),
       count(distinct review_id),
       count(distinct review_id || order_id),
       count(distinct order_id)
from order_reviews;
```

| Mesure | Valeur |
|---|---:|
| Lignes | 99 224 |
| `review_id` distincts | 98 410 |
| Couples `(review_id, order_id)` distincts | **99 224** |
| `order_id` distincts | 98 673 |

`review_id` n'est pas unique, mais il ne s'agit pas de doublons :

- **un même avis peut couvrir plusieurs commandes** (98 410 identifiants pour 99 224 lignes :
  814 lignes réutilisent un `review_id` déjà présent, chaque fois avec une commande différente) ;
- **une commande peut avoir plusieurs avis** (99 224 lignes pour 98 673 commandes).

→ Le grain réel est le couple `(review_id, order_id)`, qui est unique. Toutes les lignes sont
gardées en staging. Dans `fct_orders`, on retient **un seul avis par commande** (le plus récent)
pour ne pas dupliquer les commandes.

### Notes

```sql
select review_score, count(*) from order_reviews group by 1 order by 1;
```

| Note | Avis | Part |
|---|---:|---:|
| 1 | 11 424 | 12 % |
| 2 | 3 151 | 3 % |
| 3 | 8 179 | 8 % |
| 4 | 19 142 | 19 % |
| 5 | 57 328 | 58 % |

- Toutes les notes sont comprises entre 1 et 5 : elles servent au test `accepted_values`.
- La distribution est très polarisée : majorité de 5, mais une part notable de 1. On pourra la
  croiser avec les retards de livraison.

### Dates et commentaires

- Les dates de création et de réponse se convertissent toutes sans erreur.
- 3 852 commentaires contiennent un retour à la ligne. Ils sont lus correctement grâce à
  `FIELD_OPTIONALLY_ENCLOSED_BY = '"'` dans le format de fichier de l'ingestion.

---

## 5. Clients (`CUSTOMERS`)

**99 441 lignes.**

```sql
select count(*),
       count(distinct customer_id),
       count(distinct customer_unique_id),
       min(length(customer_zip_code_prefix)),
       max(length(customer_zip_code_prefix)),
       count(distinct customer_state)
from customers;
```

| Mesure | Valeur |
|---|---:|
| `customer_id` distincts | 99 441 |
| `customer_unique_id` distincts | **96 096** |
| Longueur des codes postaux | toujours 5 |
| États | 27 (tous les États brésiliens) |

### Le piège du jeu de données

Il y a **exactement autant de `customer_id` que de commandes**. Olist crée un `customer_id` à
chaque commande : ce n'est pas l'identifiant d'une personne. La personne est identifiée par
`customer_unique_id` : 96 096 personnes distinctes, dont environ 3 % ont commandé plusieurs fois.

→ `dim_customers` est construite sur `customer_unique_id`. Avec `customer_id`, on conclurait à
tort qu'aucun client ne revient.

### Codes postaux et villes

- Les codes postaux font tous 5 caractères en `RAW`, chargés en texte. → **Ils restent en texte** :
  une conversion en nombre ferait perdre les zéros en tête (`01310` deviendrait `1310`).
- Aucun problème de casse ou d'espaces dans les villes. Un `lower(trim(...))` est appliqué par précaution.

---

## 6. Vendeurs (`SELLERS`)

**3 095 lignes.**

| Contrôle | Résultat |
|---|---|
| `seller_id` | unique |
| Longueur des codes postaux | toujours 5 |
| États | 23 (contre 27 pour les clients) |

Les vendeurs sont plus concentrés géographiquement que les clients.

---

## 7. Produits (`PRODUCTS`)

**32 951 lignes.**

```sql
select count(*), count(distinct product_id), count_if(product_category_name is null)
from products;

select distinct p.product_category_name
from products p
left join product_category_name_translation t using (product_category_name)
where t.product_category_name is null;
```

| Constat | Décision |
|---|---|
| `product_id` unique | Clé primaire testée |
| **610 produits sans catégorie** | Gardés, catégorie nulle |
| **2 catégories sans traduction anglaise** : `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` | Ajoutées dans `stg_olist__product_category_translations` |
| Colonnes `product_name_lenght` et `product_description_lenght` (faute de frappe dans la source) | Renommées en `length` |

---

## 8. Géolocalisation (`GEOLOCATION`)

**1 000 163 lignes.**

```sql
select count(*),
       count(distinct geolocation_zip_code_prefix),
       min(length(geolocation_zip_code_prefix)),
       count(distinct geolocation_state)
from geolocation;

-- points hors d'un rectangle englobant le Brésil
select count_if(try_to_double(geolocation_lat) not between -34 and 6
             or try_to_double(geolocation_lng) not between -75 and -34)
from geolocation;
```

| Mesure | Valeur |
|---|---:|
| Lignes | 1 000 163 |
| Codes postaux distincts | 19 015 |
| Points par code postal (moyenne) | environ 53 |
| Points GPS **hors du Brésil** | **42** |

| Constat | Risque | Décision |
|---|---|---|
| Plusieurs points par code postal | Une jointure directe multiplierait les lignes des commandes | Agrégation à **une ligne par code postal** (coordonnées moyennes) |
| 42 points hors du Brésil (Europe, océan…) | Moyennes faussées | Filtrés avant l'agrégation |
| Plusieurs orthographes pour une même ville | Libellés incohérents | Ville et État les plus fréquents (`MODE()`) |

Après filtrage, il reste **19 010 codes postaux** : 5 codes n'avaient que des points aberrants.

---

## 9. Contrôles après le staging

Une fois les vues de staging créées, quelques contrôles ont été relancés :

| Contrôle | Résultat |
|---|---|
| Produits catégorisés sans traduction anglaise | 0 |
| Commandes sans date d'achat après conversion | 0 |
| Clients dont le code postal est absent de la géolocalisation | **279** → `left join` obligatoire |
| Tests dbt (unicité, non-nullité, clés composites) | 22 / 22 au vert |

---

## Récapitulatif des décisions

| Constat | Décision | Modèle concerné |
|---|---|---|
| `customer_id` change à chaque commande | Dimension client sur `customer_unique_id` | `dim_customers` |
| `review_id` non unique | Clé `(review_id, order_id)` ; un seul avis par commande dans le mart | `stg_olist__order_reviews`, `fct_orders` |
| 1 million de points GPS pour 19 000 codes postaux | Agrégation par code postal | `stg_olist__geolocation` |
| 42 coordonnées hors du Brésil | Filtrées | `stg_olist__geolocation` |
| 2 traductions de catégorie manquantes | Complétées | `stg_olist__product_category_translations` |
| Faute de frappe `lenght` | Colonnes renommées | `stg_olist__products` |
| Codes postaux avec zéros en tête | Gardés en texte | `stg_olist__customers`, `stg_olist__sellers` |
| 8 commandes livrées sans date de livraison | Retard `NULL` plutôt que faux | `fct_orders` |
| 1 commande sans paiement | `left join` | `fct_orders` |
| 279 clients sans géolocalisation | `left join` | marts |
| 2 paiements par carte avec 0 échéance | `is_installment = installments_count > 1` | `fct_payments` |

[← Retour au README](../README.md)
