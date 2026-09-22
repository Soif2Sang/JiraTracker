# GitHub Jira Tracker

Application macOS native de barre de menus pour suivre les PR GitHub ouvertes par l'utilisateur dans `dktunited`, leur CI GitHub Actions et les tickets Jira associés.

## Visuels

### Réglages

Thème de l'interface et choix du style des pastilles de la barre de menus.

![Réglages — Affichage et style des pastilles](docs/settings.png)

### Barre de menus

Trois styles de pastilles au choix : **Complet** (pastille + logo + chiffre), **Compact** (pastille colorée avec le chiffre) et **Minimal** (point de couleur + chiffre).

![Styles des pastilles de la barre de menus](docs/menu-bar-badges.png)

### Tableau de bord

Vue unifiée des tickets Jira et de leurs PR, avec statut CI et conversations.

![Tableau de bord](docs/dashboard.png)

## Prérequis

- macOS 13 ou supérieur ;
- Swift 6 ou Xcode 15+ ;
- Git ;
- un fine-grained GitHub PAT autorisé par `dktunited` avec `Metadata: Read`, `Pull requests: Read` et `Actions: Read`.

Vérifier l'installation de Swift :

```sh
swift --version
```

## Installation locale

Cloner le dépôt puis se placer à sa racine :

```sh
git clone <URL_DU_DEPOT>
cd github-jira-system-tray
```

Les dépendances Swift sont récupérées automatiquement par Swift Package Manager lors de la première compilation.

## Lancer en développement

Pour compiler et lancer directement depuis le terminal :

```sh
swift run
```

L'application s'exécute dans la barre de menus et n'affiche pas de fenêtre dans le Dock. Arrêter le processus avec `Ctrl+C`.

Pour lancer avec les variables d'environnement GitHub et Jira :

```sh
export GITHUB_TOKEN="github_pat_..."
export JIRA_EMAIL="prenom.nom@decathlon.com"
export JIRA_TOKEN="..."
swift run
```

L'application vérifie aussi `GH_TOKEN`. Pour Jira, les noms `JIRA_API_TOKEN`, `JIRA_API_KEY`, `JIRA_PAT`, `ATLASSIAN_API_TOKEN` et `ATLASSIAN_TOKEN` sont également reconnus pour le token. Les tokens validés sont copiés dans le Keychain macOS et ne sont pas écrits dans le cache.

Le bouton d'authentification peut aussi lire une affectation simple `GITHUB_TOKEN=...` ou `export GITHUB_TOKEN=...` dans `~/.zshrc`, sans exécuter le shell.

## Compiler

Compiler en mode debug sans lancer l'application :

```sh
swift build
```

Compiler en mode release :

```sh
swift build -c release
```

Le binaire est alors disponible dans `.build/release/GitHubJiraSystemTray`.

## Construire et lancer l'application macOS

Le script suivant compile en release, crée `dist/GitHub Jira Tracker.app` et lui applique une signature ad hoc locale :

```sh
sh Scripts/build-app.sh
open "dist/GitHub Jira Tracker.app"
```

La signature locale est nécessaire pour certaines notifications macOS. L'application n'est ni notarisée ni distribuable telle quelle à d'autres utilisateurs.

## Tests

```sh
swift test
```

Les tests utilisent Swift Testing comme dépendance de développement afin de fonctionner avec les Command Line Tools seuls.

## Dépannage

- Si `swift` est introuvable, installer Xcode ou les Command Line Tools, puis relancer `xcode-select --install`.
- Si l'application semble ne pas démarrer avec `swift run`, vérifier la barre de menus : elle est configurée comme application sans icône Dock.
- Si Jira ou GitHub ne répond pas, vérifier les variables d'environnement, les permissions du token et l'accès réseau.
- Pour repartir d'une compilation propre, supprimer `.build/` puis relancer `swift build`.

## État actuel

Le suivi GitHub et Jira est implémenté : découverte des PR, suivi GitHub Actions par SHA, détail lazy des jobs, conversations de review, pastilles chiffrées, caches locaux, polling adaptatif, Keychain et notifications macOS. La vue principale regroupe les tickets assignés et leurs PR et signale les données périmées.

L'entrée `Ordre du suivi…` du menu permet de composer un tri multi-critères. Les statuts Jira sont découverts dynamiquement dans les workflows de chaque projet présent dans le suivi, et les priorités sont chargées depuis Jira. Les états CI GitHub et les états ouverte, draft, fusionnée ou sans PR peuvent être ordonnés séparément. La configuration est appliquée en direct et conservée dans les préférences locales.
