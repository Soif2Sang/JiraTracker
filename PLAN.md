# GitHub & Jira System Tray - Plan produit et technique

## 1. Vision

Construire une application macOS native, présente uniquement dans la barre de menus, qui centralise le suivi quotidien des pull requests GitHub et, dans un second temps, des tickets Jira associés.

L'application doit permettre de voir immédiatement :

- les PR ouvertes par l'utilisateur dans l'organisation GitHub `dktunited` ;
- l'état de leurs pipelines GitHub Actions ;
- les workflows, jobs et étapes en échec ;
- les changements importants au moyen de notifications macOS ;
- les tickets Jira assignés à l'utilisateur ;
- les liens entre tickets Jira et PR GitHub ;
- les transitions Jira disponibles, par exemple vers « En cours » ou « Review ».

Le produit cible initialement macOS uniquement. Il sera développé nativement en Swift et SwiftUI.

## 2. Périmètre validé

### GitHub MVP

- Plateforme : macOS uniquement.
- Stack : Swift natif et SwiftUI.
- Interface : popover natif depuis la barre de menus, sans fenêtre principale.
- Source GitHub : `https://github.com/dktunited`.
- PR suivies : toutes les PR ouvertes dont l'utilisateur connecté est l'auteur.
- CI/CD détaillé : GitHub Actions.
- Authentification initiale : Personal Access Token.
- Actualisation : polling adaptatif.
- Notifications : échecs et retours au vert.
- Navigation : liens ouvrant les PR, workflows et jobs dans le navigateur.

### Jira, seconde phase

- Instance : `https://decathlon.atlassian.net/`.
- Type : Jira Cloud.
- Tickets suivis : tickets assignés à l'utilisateur, selon une JQL configurable.
- Association : rapprochement local entre les tickets Jira et les PR GitHub.
- Convention de branche courante : `(fix|feat|chore|...)/TICKET/slug`.
- Exemple : `fix/OPRM-1930/correct-checkout`.
- Actions : affichage et déclenchement des transitions Jira réellement disponibles.

## 3. Expérience utilisateur

### Barre de menus

La barre de menus doit afficher des pastilles chiffrées très visibles plutôt qu'une icône d'état unique.

Exemple conceptuel :

```text
[rouge 2] [orange 1] [vert 4]
```

Signification :

- rouge : nombre de PR ayant au moins une CI en échec ;
- orange : nombre de PR dont la CI est en cours ou en attente ;
- vert : nombre de PR dont la CI est réussie ;
- gris : nombre de PR sans CI ou avec un état inconnu ;
- gris avec `!` : erreur réseau, authentification invalide ou synchronisation impossible.

Règles d'affichage :

- les chiffres doivent rester lisibles dans la hauteur réduite de la barre de menus ;
- la pastille rouge est toujours prioritaire et ne doit jamais être masquée lorsqu'elle est non nulle ;
- les catégories dont le compteur vaut zéro peuvent être masquées pour limiter la largeur ;
- si toutes les PR sont au vert, une seule pastille verte peut être affichée ;
- le rendu doit rester lisible dans les modes clair et sombre ;
- l'état ne doit pas dépendre uniquement de la couleur : le nombre et, si nécessaire, un symbole restent présents.

Une implémentation avec `NSStatusItem` et un dessin personnalisé est préférable à une simple SF Symbol afin de maîtriser les couleurs, les tailles et les chiffres. Le clic ouvre le popover SwiftUI.

### Popover

Le popover est l'unique interface principale. L'application n'affiche pas d'icône dans le Dock.

Exemple :

```text
[rouge 2] [orange 1] [vert 4]       Actualiser

7 PR ouvertes

repo-a #421
OPRM-1930 - Fix checkout
CI failed - 2 jobs
  build-and-test
    lint                 success
    unit-tests           failed
  Ouvrir le job
  Ouvrir la PR

repo-b #98
CI running - 3/5 jobs

Dernière mise à jour : il y a 25 s
Préférences                          Quitter
```

Les compteurs présents dans le popover peuvent servir de filtres : échecs, en cours, réussies et inconnues.

Chaque PR affiche au minimum :

- le repository et le numéro ;
- le titre ;
- l'état draft ou ouvert ;
- l'état CI agrégé ;
- la branche source ;
- le ticket Jira détecté lorsqu'il existe ;
- un lien vers la PR ;
- les workflows, jobs et étapes lorsque la ligne est développée.

## 4. Architecture proposée

### Technologies

- Swift et SwiftUI ;
- `MenuBarExtra` ou combinaison `NSStatusItem` et `NSPopover` ;
- cycle de vie SwiftUI ;
- `URLSession` avec `async/await` ;
- Observation Swift pour l'état de l'interface ;
- Keychain macOS pour les secrets ;
- `UserNotifications` pour les notifications ;
- cache JSON local léger pour le dernier snapshot ;
- `UserDefaults` uniquement pour les préférences non sensibles ;
- `LSUIElement` pour masquer l'application du Dock.

### Organisation logique

```text
App/
Core/
  Networking/
  Security/
  Persistence/
  Notifications/
GitHub/
  GitHubClient
  GitHubModels
  PullRequestRepository
  GitHubPollingService
  CIStatusReducer
Jira/
  JiraClient
  JiraModels
  JiraPollingService
  TicketPRLinker
Features/
  MenuBar/
  PullRequests/
  CIJobs/
  Settings/
```

Les modèles du domaine GitHub ne doivent pas dépendre directement de Jira. Un composant de rapprochement produit une vue agrégée à partir des deux sources.

### Composants principaux

- `GitHubClient` : appels API typés et pagination.
- `PullRequestRepository` : découverte et cache des PR.
- `GitHubPollingService` : planification et backoff.
- `CIStatusReducer` : transformation des runs GitHub en statut lisible.
- `AppStore` : état présenté par le popover.
- `CredentialStore` : lecture et écriture Keychain.
- `NotificationService` : comparaison des snapshots et notifications.
- `JiraClient` : recherche, lecture et transitions Jira.
- `TicketPRLinker` : extraction des clés et associations manuelles.

## 5. Authentification GitHub

Le MVP utilise un fine-grained Personal Access Token lorsque la politique de `dktunited` le permet.

Configuration attendue :

- resource owner : `dktunited` ;
- accès aux repositories nécessaires, idéalement tous les repositories concernés ;
- `Metadata: Read` ;
- `Pull requests: Read` ;
- `Actions: Read`.

Le premier démarrage demande le token dans le popover, puis :

1. l'enregistre dans le Keychain ;
2. appelle `GET /user` pour le valider ;
3. récupère le login GitHub ;
4. vérifie l'accès aux PR privées et aux Actions ;
5. affiche un diagnostic précis si l'organisation ou le SSO bloque l'accès.

Points à vérifier pendant le spike :

- approbation du PAT par l'organisation ;
- éventuelle autorisation SSO/SAML ;
- accès à tous les repositories nécessaires ;
- compatibilité du fine-grained PAT avec la recherche globale souhaitée.

Si la politique de l'organisation ne permet pas ce fonctionnement, les solutions de repli sont plusieurs fine-grained PAT ou un classic PAT avec le scope `repo`. Cette dernière option est plus permissive et ne doit être utilisée qu'en connaissance de cause.

Le token ne doit jamais apparaître dans les logs, le cache ou `UserDefaults`.

## 6. API GitHub

### Découverte des PR

Requête de découverte, environ toutes les cinq minutes :

```text
GET /search/issues
q=is:pr is:open author:<login> org:dktunited
```

La Search API autorise jusqu'à 30 requêtes par minute pour un utilisateur authentifié. Une découverte toutes les cinq minutes laisse une marge importante.

Pour chaque nouvelle PR ou PR modifiée :

```text
GET /repos/{owner}/{repo}/pulls/{number}
```

Données nécessaires :

- repository et numéro ;
- titre, URL et état draft ;
- branche source ;
- SHA du commit de tête ;
- dates de création et de mise à jour ;
- état de review, dans une évolution ultérieure.

### GitHub Actions

Pour chaque SHA actif :

```text
GET /repos/{owner}/{repo}/actions/runs?head_sha={sha}
```

Lorsqu'un workflow est ouvert dans le popover ou que son état change :

```text
GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs
```

Cette API fournit :

- les workflows ;
- les jobs ;
- leurs statuts et conclusions ;
- leurs durées ;
- les étapes de chaque job ;
- les URLs vers GitHub.

Le MVP affiche les workflows, jobs et étapes en échec, avec des liens vers GitHub. Il ne télécharge pas automatiquement les logs complets. Les logs peuvent contenir des données sensibles et leurs URLs de téléchargement expirent rapidement.

Une évolution pourra télécharger à la demande le log d'un job et afficher un extrait local.

## 7. Agrégation des états CI

Une règle centrale, pure et testée transforme les états GitHub en états produit.

Ordre de priorité :

```text
failure > running > cancelled > success > unknown
```

Correspondances :

- `failure`, `timed_out`, `action_required` : échec ;
- `queued`, `in_progress`, `waiting`, `requested`, `pending` : en cours ;
- `cancelled` : annulé ;
- tous les workflows terminés avec `success`, `neutral` ou `skipped` : succès ;
- aucun workflow ou réponse incomplète : inconnu.

Une PR dont le SHA change repart immédiatement en état en cours ou inconnu. Le résultat du commit précédent ne doit pas être présenté comme celui du nouveau commit.

## 8. Polling et limites API

Le polling est adaptatif :

- découverte des nouvelles PR : toutes les 5 minutes ;
- CI en cours : toutes les 30 secondes ;
- CI terminée et PR inchangée : toutes les 2 minutes ;
- jobs détaillés : chargés à l'ouverture puis actualisés si le workflow reste actif ;
- actualisation manuelle : toujours disponible ;
- sortie de veille ou retour du réseau : actualisation immédiate.

Comportement réseau :

- pause des requêtes lorsque le réseau est indisponible ;
- conservation du dernier snapshot valide ;
- backoff exponentiel sur `403`, `429` et `5xx` ;
- respect de `Retry-After` et `X-RateLimit-Reset` ;
- utilisation des `ETag` lorsque les endpoints le permettent ;
- limite initiale de quatre requêtes simultanées ;
- affichage de l'heure de dernière synchronisation ;
- indication claire lorsqu'une donnée affichée est périmée.

GitHub accorde généralement 5 000 requêtes REST par heure à un utilisateur authentifié. L'application doit néanmoins surveiller les en-têtes de quota et réduire sa fréquence avant d'atteindre la limite.

## 9. Notifications macOS

Notifications attendues :

- une PR passe de succès ou en cours vers échec ;
- une PR précédemment en échec revient au vert.

Règles anti-bruit :

- aucune notification au premier chargement ;
- déduplication par PR et SHA ;
- aucune répétition tant que le même échec persiste ;
- clic ouvrant la PR ou le workflow concerné ;
- option pour désactiver les notifications ;
- absence de notification pour un simple rafraîchissement sans transition.

## 10. Intégration Jira Cloud

### Authentification

L'instance cible est `https://decathlon.atlassian.net/`. Pour une application desktop pérenne, OAuth 2.0 3LO est préférable à un API token.

Il faudra vérifier :

- si Decathlon autorise l'enregistrement ou l'approbation d'une intégration Atlassian ;
- les scopes disponibles ;
- les règles de sécurité internes ;
- l'accès aux projets concernés.

Un API token peut servir à un prototype personnel, mais ne constitue pas le choix recommandé pour une distribution plus large.

### Récupération des tickets

JQL initiale, configurable :

```jql
assignee = currentUser()
AND resolution = Unresolved
ORDER BY updated DESC
```

Données affichées :

- clé et résumé ;
- statut ;
- priorité ;
- type ;
- date de dernière modification ;
- URL Jira ;
- PR associées ;
- transitions actuellement disponibles.

Le polling Jira est indépendant de GitHub, toutes les deux à cinq minutes, avec une actualisation immédiate après une transition.

### Association entre PR et tickets

Les PR GitHub et tickets Jira sont récupérés indépendamment, puis rapprochés localement.

Ordre de détection :

1. branche GitHub, par exemple `fix/OPRM-1930/slug` ;
2. titre de la PR ;
3. description de la PR ;
4. association manuelle persistée si aucune correspondance fiable n'est trouvée.

Expression de détection :

```regex
\b[A-Z][A-Z0-9]+-\d+\b
```

La détection est insensible à la casse, puis la clé est normalisée en majuscules. Si plusieurs clés sont présentes, l'application demande laquelle utiliser au lieu de choisir silencieusement.

### Transitions Jira

Les noms « En cours », « Review » ou « Done » ne doivent jamais être codés en dur. Les workflows peuvent varier selon le projet et le type de ticket.

Pour chaque ticket :

1. charger les transitions réellement disponibles ;
2. les afficher dans le popover ;
3. envoyer l'identifiant de la transition sélectionnée ;
4. désactiver temporairement les actions pendant la requête ;
5. recharger immédiatement le ticket après succès ;
6. afficher les erreurs de permission ou les champs obligatoires manquants.

Les automatisations telles que « PR ouverte vers Review » viendront plus tard et resteront configurables. La première version Jira privilégie les actions manuelles explicites.

## 11. Phases d'implémentation

### Phase 0 - Spike technique

- Créer le projet macOS menu bar.
- Valider le rendu de plusieurs pastilles chiffrées dans `NSStatusItem`.
- Vérifier le comportement du popover SwiftUI.
- Tester le PAT sur une PR privée de `dktunited`.
- Valider Search, Pull Request, workflow runs et jobs sur une vraie PR.
- Vérifier les politiques SSO et d'approbation de l'organisation.

Critère de sortie : le prototype récupère une PR privée et affiche ses jobs Actions dans un popover.

### Phase 1 - Fondations

- Application agent sans Dock.
- Popover avec états chargement, vide et erreur.
- Saisie et validation du PAT.
- Stockage Keychain.
- Client HTTP typé.
- Gestion des erreurs et rate limits.
- Cache local.
- Bouton d'actualisation et sortie propre de l'application.

### Phase 2 - Liste des PR

- Recherche des PR ouvertes de l'utilisateur dans `dktunited`.
- Chargement des détails et du SHA.
- Affichage repository, titre, numéro, draft et lien web.
- Pagination.
- Polling de découverte.
- États vides et permissions insuffisantes.

### Phase 3 - GitHub Actions

- Chargement des workflow runs associés au SHA.
- Agrégation du statut CI.
- Détail des workflows, jobs et étapes.
- Liens vers les jobs GitHub.
- Polling adaptatif.
- Pastilles chiffrées dans la barre de menus.
- Filtres par état dans le popover.

### Phase 4 - Fiabilisation du MVP

- Notifications d'échec et de retour au vert.
- Gestion veille, réveil et perte réseau.
- Backoff et suivi du quota API.
- Tests unitaires et tests UI essentiels.
- Signature et notarisation macOS.
- Archive distribuable.
- Documentation de création et d'autorisation du PAT.

Le MVP GitHub est terminé lorsqu'une PR nouvellement créée apparaît automatiquement, que son état CI évolue sans intervention, que les jobs et étapes en échec sont identifiables, que les pastilles affichent les bons compteurs et que les notifications ne sont pas dupliquées.

### Phase 5 - Jira en lecture et association

- Authentification Jira Cloud.
- Polling des tickets assignés.
- Affichage des tickets dans le popover.
- Extraction des clés depuis les PR.
- Rapprochement automatique.
- Association manuelle pour les cas ambigus.
- Liens vers Jira.

### Phase 6 - Actions Jira

- Chargement dynamique des transitions.
- Déclenchement manuel depuis le popover.
- Actualisation immédiate après transition.
- Gestion des permissions et champs obligatoires.
- Préparation d'automatisations configurables ultérieures.

## 12. Tests prioritaires

- Décodage des réponses GitHub.
- Pagination des PR, runs et jobs.
- Réduction des statuts CI.
- Changement de SHA sur une PR.
- Backoff et respect des rate limits.
- Réveil du Mac et retour du réseau.
- Déduplication des notifications.
- Stockage et suppression du token Keychain.
- Calcul des compteurs de pastilles.
- Rendu des pastilles avec un, deux et trois chiffres.
- Modes clair et sombre.
- Extraction de `OPRM-1930` depuis différentes branches.
- Absence de ticket et présence de plusieurs tickets.
- Associations manuelles persistées.
- Transitions Jira variables selon le projet.
- Cache hors ligne et données périmées.

## 13. Sécurité et confidentialité

- Secrets exclusivement dans le Keychain.
- Aucun header d'authentification dans les logs.
- Erreurs réseau nettoyées avant affichage.
- Pas de téléchargement automatique des logs GitHub Actions.
- Cache limité aux métadonnées utiles.
- Possibilité de déconnecter GitHub et Jira et de supprimer les secrets.
- Permissions minimales pour les tokens.
- Liens externes ouverts uniquement vers des URLs GitHub ou Atlassian validées.

## 14. Décisions reportées

- Version minimale exacte de macOS.
- Distribution directe, Homebrew Cask ou Mac App Store.
- OAuth GitHub en remplacement éventuel du PAT.
- Affichage local d'extraits de logs GitHub Actions.
- Suivi des reviews et demandes de changements.
- Actions GitHub depuis le popover, comme relancer un job échoué.
- Automatisation des transitions Jira selon le cycle de vie des PR.
- Support d'autres organisations GitHub ou d'autres fournisseurs CI/CD.
