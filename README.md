# GitHub Jira Tracker

Application macOS native de barre de menus pour suivre les PR GitHub ouvertes par l'utilisateur dans `dktunited`, leur CI GitHub Actions, les tickets Jira associés et les tickets dont l'utilisateur est **Code Reviewer**.

## Visuels

### Vue principale

Vue unifiée des tickets Jira et de leurs PR, avec statut CI, conversations et filtre **Reviewer**.

![Vue principale](docs/dashboard.png)

### Barre de menus

Trois styles de pastilles au choix : **Complet** (pastille + logo + chiffre), **Compact** (pastille colorée avec le chiffre) et **Minimal** (point de couleur + chiffre).

Dans l'ordre : sans PR (bleu) › CI verte › CI en cours › CI en échec › commentaires non résolus (violet) › **à reviewer** (indigo, œil).

![Styles des pastilles de la barre de menus](docs/menu-bar-badges.png)

### Réglages

Thème de l'interface et choix du style des pastilles de la barre de menus.

![Réglages — Affichage et style des pastilles](docs/settings.png)

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

## Mode démo

Pour visualiser l'interface sans configurer GitHub ni Jira (données factices, aucun appel réseau) :

```sh
sh Scripts/demo.sh
```

Variables utiles : `JIRA_TRACKER_THEME=white|black|blue` pour forcer le thème et `JIRA_TRACKER_SCREENSHOT=/tmp/pop.png` (ou `JIRA_TRACKER_SETTINGS_SCREENSHOT`, `JIRA_TRACKER_BADGES_SCREENSHOT`) pour exporter des captures. L'application doit être lancée depuis le bundle `dist/GitHub Jira Tracker.app`, pas le binaire seul.

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

Le suivi GitHub et Jira est implémenté : découverte des PR, suivi GitHub Actions par SHA, détail lazy des jobs, conversations de review, pastilles chiffrées, caches locaux, polling adaptatif, Keychain et notifications macOS. La vue principale regroupe les tickets assignés, les tickets dont l'utilisateur est Code Reviewer et leurs PR, et signale les données périmées. Les icônes de statut sont des SVG Lucide (ISC) rendus dans les couleurs de l'application.

### Suivi du reviewer

Les tickets où l'utilisateur est renseigné dans le champ Jira **Code Reviewer** (`customfield_11268`) et positionnés dans un statut de review (ex. `To Review`) sont suivis via une requête Jira dédiée. Pour chacun, l'application interroge l'API dev-status de Jira (intégration GitHub) pour retrouver la PR liée, puis l'API GraphQL de GitHub pour inspecter les conversations de review.

Le ticket est retenu dans la barre de menus (badge œil indigo) uniquement lorsque la branche est prête **et** qu'une action de review reste à faire :

- la PR liée n'est pas un *draft* et ses checks ne sont pas en échec ou en cours ;
- soit l'utilisateur n'a encore rien commenté (review à faire), soit tous ses threads de review sont résolus.

Le ticket est masqué tant que ses threads ne sont pas résolus (l'auteur doit traiter les retours), et sort du suivi dès qu'il quitte le statut `To Review`. Un filtre **Reviewer** dans la barre latérale, ainsi qu'un repère sur chaque ligne, permettent de retrouver ces tickets dans la vue unifiée.

L'entrée `Ordre du suivi…` du menu permet de composer un tri multi-critères. Les statuts Jira sont découverts dynamiquement dans les workflows de chaque projet présent dans le suivi, et les priorités sont chargées depuis Jira. Les états CI GitHub et les états ouverte, draft, fusionnée ou sans PR peuvent être ordonnés séparément. La configuration est appliquée en direct et conservée dans les préférences locales.
