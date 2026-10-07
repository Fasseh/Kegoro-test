# Épreuve technique Salesforce – Annulation de mission

Quand `Account.MissionStatus__c` passe à `canceled`, le trigger :

1. renseigne `MissionCanceledDate__c` avec la date du jour ;
2. passe à inactifs (`IsActive__c = false`) les contacts concernés ;
3. synchronise ces contacts avec l'API externe (`PATCH`, payload `[{ id, is_active }]`).

Le traitement est bulkifié : il fonctionne pour 200 entreprises mises à jour en une fois (testé).

## Limitation connue : `AccountContactRelation`

L'énoncé demande de désactiver un contact uniquement si **toutes** ses entreprises sont annulées, via `AccountContactRelation`.

Mon org de développement ne dispose pas de cet objet : il n'apparaît ni dans le SOQL, ni dans `Schema.getGlobalDescribe()`, même après avoir activé « Contacts to Multiple Accounts » (Account Settings) et ajouté un permission set.

La règle a donc été contournée dans `ContactStatusService` : seul le compte principal (`Contact.AccountId`) est pris en compte. Un contact rattaché à plusieurs entreprises n'est pas géré. Le code, les tests et l'appel API fonctionnent sur cette base.

Pour retrouver la règle complète dans une org qui supporte l'objet, il suffit de remplacer la requête sur `Contact` de `ContactStatusService` par deux requêtes sur `AccountContactRelation` : les contacts liés aux comptes annulés, puis ceux qui ont encore au moins un compte non annulé.

## Structure

| Fichier | Rôle |
| --- | --- |
| `triggers/AccountTrigger` | Point d'entrée (before/after update), sans logique |
| `classes/AccountTriggerHandler` | Détecte les comptes qui **passent** à `canceled`, pose la date, lance le reste |
| `classes/ContactStatusService` | Désactive les contacts (DML partielle : une erreur n'en bloque pas d'autres) |
| `classes/ContactSyncQueueable` | Job asynchrone (callout impossible après un DML), 90 appels max par job puis chaînage, 3 tentatives |
| `classes/ContactSyncLogger`, `objects/ContactSyncLog__c` | Trace chaque synchronisation (SUCCESS / RETRY / FAILED) |
| `permissionsets/MissionSync_Access` | Droits sur `MissionStatus__c` et `ContactSyncLog__c` (à assigner avant de lancer les tests) |
| `classes/ContactSyncClient` | Client HTTP, envoi par lots, erreur si l'API ne répond pas 200 |
| `classes/MissionConstants` | Valeurs `active` / `canceled` |
| `objects/ApiConfig__mdt`, `customMetadata/` | Taille des lots (1000) et timeout (20 s), modifiables sans redéploiement |
| `classes/*Test`, `ContactSyncMock` | Tests et mock HTTP |

## Choix techniques

- **Asynchrone (Queueable)** : l'appel API ne bloque pas la sauvegarde du compte.
- **Détection du changement** : on compare ancienne et nouvelle valeur, donc une mise à jour d'un compte déjà annulé est ignorée et la date n'est pas réécrite.
- **Limite de 100 callouts par transaction** : un job envoie au plus 90 appels (lots de 1000 contacts par défaut), puis se ré-enfile pour le reste. Aucun contact n'est perdu, quel que soit leur nombre.
- **Fiabilité et traçabilité** : si l'API échoue, le job est relancé 2 fois (1 minute d'attente), puis marqué `FAILED`. Chaque issue est enregistrée dans `ContactSyncLog__c` (statut, nombre de contacts, tentative, message d'erreur). Relancer un envoi est sans risque : l'API fixe un statut, elle ne l'incrémente pas. Pour consulter : Setup > Object Manager > Contact Sync Log, ou une requête `SELECT Status__c, ContactCount__c, Attempt__c, ErrorMessage__c FROM ContactSyncLog__c`.
- **Named Credential** `ContactSyncApi` : l'URL et le token ne sont pas écrits dans le code.
- **Lots configurables** : `ApiConfig__mdt` plutôt que des valeurs en dur.

## Configuration requise

- Champs : `Account.MissionStatus__c` (picklist `active` / `canceled`), `Account.MissionCanceledDate__c` (date), `Contact.IsActive__c` (checkbox).
- Le Named Credential `ContactSyncApi` s'appuie sur un External Credential `ContactSyncExtCred`, qui n'est **pas** versionné (le token est un secret). Il doit être créé dans l'org pour que l'appel réel à l'API fonctionne. Les tests utilisent un mock et n'en dépendent pas.

## Lancer les tests

Les champs déployés n'ont aucun droit par défaut : assigner d'abord le permission set `MissionSync_Access` à l'utilisateur qui lance les tests (`sf org assign permset --name MissionSync_Access`).

```
sf project deploy start -d force-app/main/default --test-level RunLocalTests --target-org <alias>
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 10 --target-org <alias>
```
