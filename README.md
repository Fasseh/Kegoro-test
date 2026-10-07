# Épreuve technique Salesforce – Annulation de mission

Solution Apex à l'épreuve technique : quand la mission d'une ou plusieurs entreprises (`Account`) est annulée, les contacts concernés sont désactivés et la synchronisation avec l'API externe est lancée.

## Sommaire

1. [Comportement](#1-comportement)
2. [Limitation connue : `AccountContactRelation`](#2-limitation-connue--accountcontactrelation)
3. [Architecture](#3-architecture)
4. [Choix techniques](#4-choix-techniques)
5. [Métadonnées du projet](#5-métadonnées-du-projet)
6. [Installation et déploiement](#6-installation-et-déploiement)
7. [Lancer les tests](#7-lancer-les-tests)
8. [Suivre les synchronisations](#8-suivre-les-synchronisations)
9. [Ce qui a été vérifié](#9-ce-qui-a-été-vérifié)
10. [Limites et pistes d'amélioration](#10-limites-et-pistes-damélioration)

## 1. Comportement

Quand `Account.MissionStatus__c` passe de `active` (ou vide) à `canceled`, le trigger `AccountTrigger` :

| Étape | Moment | Action |
| --- | --- | --- |
| a | before update | Renseigne `MissionCanceledDate__c` avec la date du jour |
| b | after update | Passe `IsActive__c` à `false` sur les contacts concernés |
| c | asynchrone | Envoie les contacts modifiés à l'API (`PATCH`, corps `[{ "id": "...", "is_active": false }]`) |

Points de détail :

- Seuls les comptes qui **passent** à `canceled` sont traités. Un compte déjà annulé que l'on modifie (par exemple renommé) est ignoré : sa date d'annulation n'est pas réécrite et l'API n'est pas appelée.
- Seuls les contacts **réellement modifiés** sont envoyés à l'API (les contacts déjà inactifs sont ignorés).
- Un compte sans contact pose la date, mais n'appelle pas l'API.
- Le trigger est bulkifié : il fonctionne pour 200 entreprises mises à jour en une fois (testé), et aussi au-delà (201 comptes = 2 lots de trigger).

## 2. Limitation connue : `AccountContactRelation`

> **Cette partie de l'énoncé n'est pas respectée.**

L'énoncé demande de désactiver un contact uniquement si **toutes** les entreprises auxquelles il est rattaché sont annulées, en s'appuyant sur l'objet `AccountContactRelation`.

**Problème rencontré** : l'org de développement utilisée pour ce test ne dispose pas de cet objet. Il n'apparaît ni dans le SOQL (`sObject type 'AccountContactRelation' is not supported`), ni dans `Schema.getGlobalDescribe()`, même après avoir :

- activé « Allow users to relate a contact to multiple accounts » (Setup > Account Settings, et via `Account.settings-meta.xml`) ;
- ajouté les droits sur l'objet via un permission set.

**Contournement appliqué** dans `ContactStatusService` : seul le compte principal du contact (`Contact.AccountId`) est pris en compte. Quand ce compte est annulé, le contact devient inactif.

**Conséquence** : un contact rattaché à plusieurs entreprises serait désactivé dès que son compte principal est annulé, même si ses autres entreprises sont encore en mission. Ce cas n'est pas géré.

**Pour retrouver la règle complète** dans une org qui supporte l'objet, il suffit de modifier `ContactStatusService.deactivateContactsWithoutActiveMission` :

1. Chercher les contacts liés aux comptes annulés : `SELECT ContactId FROM AccountContactRelation WHERE AccountId IN :canceledAccountIds`.
2. Parmi eux, exclure ceux qui ont encore au moins un compte non annulé : `SELECT ContactId FROM AccountContactRelation WHERE ContactId IN :candidateIds AND Account.MissionStatus__c != 'canceled'` (le `!=` inclut les statuts vides, qui comptent comme « non annulé »).
3. Désactiver les contacts restants (le reste de la classe et du projet ne change pas).

Les tests devront aussi retrouver un contact partagé entre deux comptes, avec un `AccountContactRelation` explicite.

## 3. Architecture

```
Account (update)
   |
   v
AccountTrigger ........................ point d'entrée, aucune logique
   |
   v
AccountTriggerHandler
   |-- beforeUpdate : pose MissionCanceledDate__c
   '-- afterUpdate
          |-- ContactStatusService ..... désactive les contacts (un SOQL, un DML)
          '-- ContactSyncQueueable ..... job asynchrone (callout)
                 |-- ContactSyncClient ... appels HTTP par lots (Named Credential)
                 '-- ContactSyncLogger ... trace dans ContactSyncLog__c
```

| Fichier | Rôle |
| --- | --- |
| `triggers/AccountTrigger` | Point d'entrée (before/after update). Délègue tout au handler |
| `classes/AccountTriggerHandler` | Détecte les comptes qui passent à `canceled`, pose la date, lance la désactivation puis la synchronisation |
| `classes/ContactStatusService` | Désactive les contacts. DML partielle : une erreur sur un contact n'empêche pas les autres |
| `classes/ContactSyncQueueable` | Job asynchrone. Envoie par tranches de 90 appels max, se ré-enfile pour le reste, relance en cas d'échec |
| `classes/ContactSyncClient` | Client HTTP : découpe en lots, appelle le Named Credential, lève une erreur si l'API ne répond pas 200 |
| `classes/ContactSyncLogger` | Écrit une ligne dans `ContactSyncLog__c` |
| `classes/MissionConstants` | Valeurs `active` / `canceled`, pour éviter les chaînes écrites en dur |
| `classes/AccountTriggerTest` | Tests de bout en bout (200 comptes, 201 comptes, compte sans contact, compte déjà annulé) |
| `classes/ContactSyncClientTest` | Tests du client HTTP (lots, Named Credential, erreurs, configuration invalide) |
| `classes/ContactSyncQueueableTest` | Tests de la limite de callouts et des traces |
| `classes/ContactSyncMock` | Faux serveur HTTP pour les tests |

## 4. Choix techniques

- **Date en `before update`** : on modifie directement les comptes en mémoire, sans DML supplémentaire.
- **Contacts en `after update`** : les comptes sont enregistrés, on peut modifier les contacts.
- **Appel API asynchrone (Queueable)** : Salesforce interdit un callout après un DML dans la même transaction, et l'enregistrement du compte ne doit pas dépendre de la lenteur de l'API.
- **Bulkification complète** : pas de SOQL ni de DML dans une boucle. Un seul SOQL et un seul DML pour tous les comptes du lot.
- **Limite de 100 callouts par transaction** : un job envoie au plus 90 appels (marge de sécurité), puis ré-enfile un nouveau job avec le reste. Avec des lots de 1000 contacts, un job couvre 90 000 contacts, et le chaînage prend le relais au-delà. Aucun contact n'est perdu.
- **Fiabilité** : si l'API échoue, le job est relancé 2 fois (3 essais au total), avec 1 minute d'attente (`AsyncOptions.MinimumQueueableDelayInMinutes`). Relancer un envoi est sans risque, car l'API fixe un statut au lieu de l'incrémenter.
- **Traçabilité** : chaque issue (succès, nouvelle tentative, échec définitif) est enregistrée dans `ContactSyncLog__c`. Le log d'un échec est écrit par un `Finalizer`, car dans le job l'exception annulerait l'écriture.
- **Named Credential `ContactSyncApi`** : l'URL et le token d'authentification ne sont pas écrits dans le code. Le header `Authorization` est ajouté par Salesforce.
- **Configuration en Custom Metadata (`ApiConfig__mdt`)** : taille des lots et timeout modifiables sans redéploiement. La configuration est validée avant utilisation (une taille de lot de 0 provoquerait une boucle infinie).
- **`without sharing` sur `ContactStatusService`** : règle d'intégrité exécutée par un trigger, elle ne doit pas dépendre des droits de visibilité de l'utilisateur qui modifie le compte.
- **Aucune fonctionnalité no-code pour la logique métier** (pas de Flow, pas de Process Builder). Seuls la configuration (Named Credential, Custom Metadata) et le modèle de données sont déclaratifs.

## 5. Métadonnées du projet

| Objet | Élément | Détail |
| --- | --- | --- |
| `Account` | `MissionStatus__c` | Picklist restreinte : `active`, `canceled` |
| `Account` | `MissionCanceledDate__c` | Date |
| `Contact` | `IsActive__c` | Checkbox |
| `ApiConfig__mdt` | `ChunkSize__c`, `TimeoutMs__c` | Custom Metadata Type. Enregistrement `ContactSync` : 1000 contacts par lot, timeout 20 000 ms |
| `ContactSyncLog__c` | `Status__c`, `ContactCount__c`, `Attempt__c`, `ErrorMessage__c` | Objet de traces (nom en numérotation automatique `LOG-0001`) |
| Named Credential | `ContactSyncApi` | URL de l'API, authentification via l'External Credential `ContactSyncExtCred` |
| Permission Set | `MissionSync_Access` | Droits sur `MissionStatus__c` et sur `ContactSyncLog__c` |

## 6. Installation et déploiement

### Prérequis

- Salesforce CLI (`sf`) et une org de développement authentifiée (`sf org login web --alias <alias>`).
- **External Credential `ContactSyncExtCred`** : il n'est **pas** versionné, car il contient le secret d'authentification. Il doit être créé dans l'org pour que l'appel réel à l'API fonctionne. Les tests utilisent un mock et n'en dépendent pas.

### Étapes

Les champs déployés n'ont aucun droit par défaut, même pour un administrateur. Les tests lancés pendant le premier déploiement échoueraient donc faute d'accès aux champs. L'ordre à suivre :

```
# 1. Déployer sans lancer les tests
sf project deploy start -d force-app/main/default --target-org <alias>

# 2. Donner les droits sur les champs à l'utilisateur
sf org assign permset --name MissionSync_Access --target-org <alias>

# 3. Lancer les tests (voir section 7)
```

Le dossier `force-app/main/default` du dépôt contient uniquement les éléments listés en section 5 et le code.

## 7. Lancer les tests

```
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 10 --target-org <alias>
```

Résultat attendu : 13 tests, tous réussis.

| Classe de test | Ce qui est vérifié |
| --- | --- |
| `AccountTriggerTest` | 200 comptes annulés d'un coup : date posée, contacts désactivés, un seul appel API de 200 contacts, contact du compte non annulé intact. 201 comptes : deux appels API (deux lots de trigger). Compte sans contact : pas d'appel API. Compte déjà annulé : ignoré |
| `ContactSyncClientTest` | 2500 contacts = 3 appels. Appel par le Named Credential, sans header écrit en dur. Liste vide : aucun appel. Code HTTP différent de 200 : erreur. Taille de lot invalide : erreur |
| `ContactSyncQueueableTest` | 120 appels nécessaires, 90 envoyés, 30 rendus pour le job suivant (sans doublon ni oubli). Sous la limite : tout part en une fois. Un job réussi écrit une trace `SUCCESS`. Le logger enregistre les détails d'un échec |

## 8. Suivre les synchronisations

Chaque synchronisation écrit une ligne dans `ContactSyncLog__c` :

| `Status__c` | Signification |
| --- | --- |
| `SUCCESS` | Les contacts ont été envoyés (`ContactCount__c` = nombre envoyé par ce job) |
| `RETRY` | Échec, une nouvelle tentative est planifiée dans 1 minute |
| `FAILED` | Échec définitif après 3 tentatives : une intervention est nécessaire |

Consulter les traces : Setup > Object Manager > Contact Sync Log, ou

```sql
SELECT Name, Status__c, ContactCount__c, Attempt__c, ErrorMessage__c, CreatedDate
FROM ContactSyncLog__c
ORDER BY CreatedDate DESC
```

`ErrorMessage__c` contient le code HTTP renvoyé par l'API : `400` (payload invalide), `401` (token absent ou invalide), `404` (méthode autre que `PATCH`).

## 9. Ce qui a été vérifié

- Les 13 tests passent dans une Developer Edition.
- Un appel réel à l'API via le Named Credential `ContactSyncApi` a renvoyé `200 OK` (vérifié dans la Developer Console : le log d'exécution montre `Named Credential ContactSyncApi, Status Code=200`).
- **Non vérifié** : le chemin d'échec complet (relance automatique puis `FAILED`). Un test Apex ne peut pas enchaîner plusieurs jobs, donc seuls le logger, le découpage et le succès sont testés.
- **Non vérifié** : la règle multi-entreprises avec `AccountContactRelation` (voir section 2).

## 10. Limites et pistes d'amélioration

- Règle `AccountContactRelation` non appliquée (section 2).
- Pas d'alerte automatique en cas de `FAILED` : il faut consulter `ContactSyncLog__c`. On pourrait ajouter une notification ou un rapport planifié.
- Les contacts envoyés dans un job qui échoue sont renvoyés en entier à la nouvelle tentative, y compris les lots déjà acceptés par l'API (sans conséquence, l'opération est idempotente).
- Un contact désactivé puis réactivé manuellement n'est pas resynchronisé : seule l'annulation de mission déclenche l'envoi.
