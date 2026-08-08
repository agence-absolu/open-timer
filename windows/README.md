# OpenTimer — Windows

Port Windows d'OpenTimer, time tracker pour **OpenProject**. L'app vit dans la zone de
notification : on choisit un work package, on lance le chrono, et à l'arrêt un *time entry*
est créé automatiquement via l'API REST v3.

> Le build ne fonctionne **que sur Windows** : les targeting packs WindowsDesktop (WPF)
> n'existent pas sur macOS ni Linux. Pour construire sans machine Windows, voir la section
> « Sans machine Windows » en bas.

## 1. Prérequis

Une seule chose est indispensable : le **.NET SDK 10**.

```powershell
winget install Microsoft.DotNet.SDK.10
winget install Git.Git
```

Si le nom du paquet a changé : `winget search "dotnet sdk"`. Sinon, téléchargement direct
sur <https://dotnet.microsoft.com/download/dotnet/10.0> — prendre le **SDK**, pas le Runtime.

**Ferme et rouvre PowerShell** après l'installation (le `PATH` n'est pas rafraîchi dans les
terminaux déjà ouverts), puis vérifie :

```powershell
dotnet --list-sdks     # doit lister une version 10.x
```

Un IDE est **optionnel** : Visual Studio 2022+ (charge de travail « Développement .NET
Desktop ») ou Rider ouvrent `OpenTimer.sln` et donnent le designer XAML et le débogueur.
Le SDK seul suffit pour produire l'exe.

## 2. Build

```powershell
git clone https://github.com/agence-absolu/open-timer
cd open-timer\windows

dotnet publish src\OpenTimer.Windows\OpenTimer.Windows.csproj -c Release -o dist
.\dist\OpenTimer.exe
```

C'est exactement ce que fait `build.ps1`, utilisable à la place :

```powershell
.\build.ps1
```

**Mais** PowerShell bloque les scripts par défaut sur Windows client
(`ExecutionPolicy = Restricted`). Deux options :

```powershell
# Une fois pour toutes, pour ton compte :
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

# Ou ponctuellement, sans rien changer :
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

Le `dotnet publish` direct ci-dessus ne passe pas par un script et évite la question.

### Ce que ça produit

| Commande | Sortie | Taille | Runtime .NET requis |
|---|---|---|---|
| `dotnet build` (F5 dans l'IDE) | `bin\Release\…\OpenTimer.exe` + DLL à côté | ~200 Ko + deps | **Oui** |
| `dotnet publish` / `build.ps1` | `dist\OpenTimer.exe` **seul** | ~150 Mo | **Non**, autonome |
| `release.ps1` | `OpenTimer-<version>-win-x64.zip` | ~65 Mo | **Non** |

Le `publish` empaquette le runtime .NET et WPF dans le binaire (`SelfContained` +
`PublishSingleFile`). Au premier lancement, les DLL natives sont extraites dans un cache
sous `%TEMP%` — d'où un démarrage initial un peu lent, puis normal ensuite.

Le premier `publish` télécharge aussi le pack runtime `win-x64` (~100 Mo) : c'est normal
et ça n'arrive qu'une fois.

## 3. En cas d'erreur de compilation

Le code n'a jamais été compilé (il a été écrit sur macOS, où le SDK Windows Desktop est
indisponible). Des erreurs au premier build sont attendues. Pour les isoler :

```powershell
dotnet build src\OpenTimer.Windows\OpenTimer.Windows.csproj -c Release 2>&1 |
  Select-String -Pattern "error"
```

## 4. Configuration de l'app

1. Dans OpenProject : **Mon compte → Jetons d'accès → API** → créer un token.
2. Lancer `OpenTimer.exe` — la fenêtre « Nouveau » s'ouvre, puis l'app reste dans la zone
   de notification (près de l'horloge ; il faut parfois la sortir du chevron « ^ »).
3. **Préférences** → URL de l'instance + token → **Tester** : ton nom doit s'afficher.

Les réglages sont écrits dans `%APPDATA%\OpenTimer\settings.json`. Le token y est
**chiffré via DPAPI**, lié à ton compte Windows.

## 5. Utilisation

1. Clic sur l'icône de la zone de notification (ou menu → **Nouveau**).
2. Choisir un work package, une **activité** (« Développement » présélectionnée si dispo),
   un commentaire optionnel. Cocher **Tous les work packages** pour élargir la recherche à
   ceux assignés à d'autres (recherche serveur : libellé, ou `#id` exact si tu tapes un numéro).
3. **Démarrer** → le chrono s'affiche **dans l'icône** au format `H:MM`, et à la seconde
   près dans l'infobulle au survol. Pause / reprise possibles.
4. **Arrêter et enregistrer** → time entry créé (durée arrondie à la minute, date du jour),
   puis proposition de passer le WP en « Traité » et de le réaffecter à son créateur.

> Contrairement à macOS, la zone de notification Windows n'affiche pas de texte à côté de
> l'icône : le chrono est donc **dessiné dans l'icône**, en `H:MM` (les secondes seraient
> illisibles à 16 px).

## 6. Release

```powershell
# 1. Bumper <Version> dans src\OpenTimer.Windows\OpenTimer.Windows.csproj
# 2. Construire l'artefact + sha256
.\release.ps1
# 3. Reporter version + hash dans ..\bucket\opentimer.json
# 4. Pousser le tag — le workflow release.yml rebuild et publie
git tag windows-vX.Y.Z
git push origin windows-vX.Y.Z
```

Les versions macOS et Windows sont **découplées** : tag `vX.Y.Z` pour macOS,
`windows-vX.Y.Z` pour Windows.

L'exécutable n'étant **pas signé**, SmartScreen avertit au premier lancement :
« Informations complémentaires » → « Exécuter quand même ». Seul un certificat de signature
de code lève cet avertissement (OV ~200-400 $/an, EV ~400-600 $/an) — même arbitrage que la
notarisation côté macOS.

## Sans machine Windows

Le workflow `.github/workflows/ci.yml` builde sur un runner `windows-2022` à chaque push.
Il est déclenchable à la main depuis l'onglet **Actions** de GitHub (`workflow_dispatch`),
et les erreurs de compilation apparaissent dans les logs — plus lent en boucle de
correction, mais ça évite d'installer quoi que ce soit.

## Parité avec macOS — reste à faire

- **Historique** en lecture seule : l'éditeur Début/Fin → Durée recalculée et la suppression
  ne sont pas portés.
- **Thème clair/sombre** : persisté mais pas appliqué (un seul jeu de couleurs).
- **Heures début/fin** : l'API est portée, l'UI ne s'en sert pas encore.

Détails d'architecture et décisions techniques : [`CLAUDE.md`](CLAUDE.md).
