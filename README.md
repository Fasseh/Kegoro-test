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
| `classes/ContactSyncQueueable` | Job asynchrone : un callout est impossible après un DML dans le trigger |
| `classes/ContactSyncClient` | Client HTTP, envoi par lots, erreur si l'API ne répond pas 200 |
| `classes/MissionConstants` | Valeurs `active` / `canceled` |
| `objects/ApiConfig__mdt`, `customMetadata/` | Taille des lots (1000) et timeout (20 s), modifiables sans redéploiement |
| `classes/*Test`, `ContactSyncMock` | Tests et mock HTTP |

## Choix techniques

- **Asynchrone (Queueable)** : l'appel API ne bloque pas la sauvegarde du compte.
- **Détection du changement** : on compare ancienne et nouvelle valeur, donc une mise à jour d'un compte déjà annulé est ignorée et la date n'est pas réécrite.
- **Named Credential** `ContactSyncApi` : l'URL et le token ne sont pas écrits dans le code.
- **Lots configurables** : `ApiConfig__mdt` plutôt que des valeurs en dur.

## Configuration requise

- Champs : `Account.MissionStatus__c` (picklist `active` / `canceled`), `Account.MissionCanceledDate__c` (date), `Contact.IsActive__c` (checkbox).
- Le Named Credential `ContactSyncApi` s'appuie sur un External Credential `ContactSyncExtCred`, qui n'est **pas** versionné (le token est un secret). Il doit être créé dans l'org pour que l'appel réel à l'API fonctionne. Les tests utilisent un mock et n'en dépendent pas.

## Lancer les tests

```
sf project deploy start -d force-app/main/default --test-level RunLocalTests --target-org <alias>
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 10 --target-org <alias>
```
