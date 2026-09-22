# GitHub Jira Tracker

Application macOS native de menu bar pour suivre les PR GitHub ouvertes par l'utilisateur dans `dktunited` et leur CI GitHub Actions.

## Prérequis

- macOS 13 ou supérieur ;
- Swift 6 ou Xcode 15+ ;
- un fine-grained GitHub PAT autorisé par `dktunited` avec `Metadata: Read`, `Pull requests: Read` et `Actions: Read`.

## Lancer en développement

```sh
swift run
```

Pour permettre l'import automatique d'un token exporté par le shell :

```sh
export GITHUB_TOKEN="github_pat_..."
swift run
```

L'application vérifie aussi `GH_TOKEN`. Le bouton d'authentification peut également lire une affectation simple `GITHUB_TOKEN=...` ou `export GITHUB_TOKEN=...` dans `~/.zshrc`, sans exécuter le shell. Le token est copié dans le Keychain après validation et n'est jamais écrit dans le cache.

Pour Jira Cloud, définir les deux variables suivantes :

```sh
export JIRA_EMAIL="prenom.nom@decathlon.com"
export JIRA_TOKEN="..."
```

Les noms `JIRA_API_TOKEN`, `JIRA_API_KEY`, `JIRA_PAT`, `ATLASSIAN_API_TOKEN` et `ATLASSIAN_TOKEN` sont également reconnus pour le token. Jira Cloud utilise l'e-mail du compte avec l'API token en Basic Auth.

## Construire une application

```sh
sh Scripts/build-app.sh
open "dist/GitHub Jira Tracker.app"
```

Le script applique une signature ad hoc locale nécessaire aux notifications macOS. La notarisation n'est pas réalisée.

## État actuel

Le suivi GitHub et Jira est implémenté : découverte des PR, suivi GitHub Actions par SHA, détail lazy des jobs, conversations de review, pastilles chiffrées, caches locaux, polling adaptatif, Keychain et notifications macOS. La vue principale regroupe les tickets assignés et leurs PR et signale les données périmées.

L'entrée `Ordre du suivi…` du menu permet de composer un tri multi-critères. Les statuts Jira sont découverts dynamiquement dans les workflows de chaque projet présent dans le suivi, et les priorités sont chargées depuis Jira. Les états CI GitHub et les états ouverte, draft, fusionnée ou sans PR peuvent être ordonnés séparément. La configuration est appliquée en direct et conservée dans les préférences locales.

## Tests

```sh
swift test
```

Les tests utilisent Swift Testing comme dépendance de développement afin de fonctionner avec les Command Line Tools seuls.
