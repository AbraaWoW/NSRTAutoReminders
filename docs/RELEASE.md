# Publier NSRTAutoReminders sur CurseForge

Une release = un clic dans GitHub. Ta VM fait le reste : elle régénère les données, crée le tag, fait le zip et l'envoie sur CurseForge.

## Contenu du kit

| Fichier | Rôle |
|---|---|
| `.github/workflows/release.yml` | Le bouton « Release » dans l'onglet Actions |
| `.pkgmeta` | Ce que le packager met (ou pas) dans le zip |
| `CHANGELOG.md` | Les nouveautés, affichées sur CurseForge |
| `.gitignore` | Empêche `.env`, `.venv` et les zips d'aller sur GitHub |
| `tools/make-zip.sh` | Zip local pour tester en jeu, sans rien publier |

## Mise en place (une seule fois)

### 1. Copier le kit dans le dépôt

```bash
cd /opt/wow/NSRTAutoReminders
unzip -o ~/nsrt-release-kit.zip -d .
chmod +x tools/make-zip.sh
```

Si le `.toc` est dans un sous-dossier (`NSRTAutoReminders/NSRTAutoReminders.toc`), retire les `#` des deux lignes `move-folders` à la fin de `.pkgmeta`.

Si un `.env` ou un `.venv` était déjà suivi par git : `git rm -r --cached .env .venv`.

### 2. Projet et clé CurseForge

1. Crée le projet sur https://authors.curseforge.com (jeu : World of Warcraft). Il doit être validé par CurseForge avant le premier envoi.
2. Note le **Project ID** (encadré « About Project » de la page du projet).
3. Crée une clé : https://legacy.curseforge.com/account/api-tokens.
4. Dans le `.toc`, ajoute sous `## X-Category:` :
   ```
   ## X-Curse-Project-ID: 123456
   ```
5. Sur GitHub : dépôt → Settings → Secrets and variables → Actions → New repository secret
   - Name : `CF_API_KEY`
   - Secret : la clé de l'étape 3

### 3. Runner GitHub sur la VM

Le dépôt doit rester **privé** : un runner sur ta machine exécute le code de quiconque peut lancer un workflow.

```bash
sudo apt install -y git curl jq zip unzip python3-venv
sudo mkdir -p /opt/wow/secrets /opt/wow/releases
sudo chown -R abraa:abraa /opt/wow
```

GitHub : dépôt → Settings → Actions → Runners → **New self-hosted runner** → Linux x64. Lance les commandes affichées, en ajoutant l'étiquette `nsrt` à l'étape `config.sh` :

```bash
mkdir ~/actions-runner && cd ~/actions-runner
# … curl / tar affichés par GitHub …
./config.sh --url https://github.com/AbraaWoW/NSRTAutoReminders --token <JETON> --labels nsrt
sudo ./svc.sh install abraa
sudo ./svc.sh start
```

Le runner apparaît « Idle » dans Settings → Actions → Runners et redémarre avec la VM.

### 4. Clés Warcraft Logs pour le build

```bash
cat > /opt/wow/secrets/build.env <<'EOF'
WCL_CLIENT_ID=...
WCL_CLIENT_SECRET=...
EOF
chmod 600 /opt/wow/secrets/build.env
```

Ce fichier reste sur la VM. Il n'est jamais envoyé sur GitHub.

### 5. Envoyer le kit

```bash
cd /opt/wow/NSRTAutoReminders
git add .github .pkgmeta .gitignore CHANGELOG.md tools docs NSRTAutoReminders.toc
git commit -m "Publication automatique CurseForge"
git push
```

## Publier une version

GitHub → **Actions** → **Release** → **Run workflow**.

- **Régénérer les données** (coché par défaut) : lance le script de build. Il met à jour `Data/` et augmente la version du `.toc`.
- **Nouveautés** : le texte mis dans `CHANGELOG.md` si tu n'as pas déjà écrit la section de cette version.

Pour une version avec du code, écris d'abord la section dans `CHANGELOG.md` :

```markdown
## v13.0.6

- Ce qui a changé.
```

Si tu décoches « Régénérer les données », augmente toi-même `## Version:` dans le `.toc` : la même version ne peut pas être publiée deux fois.

Durée habituelle : le temps du build, puis une minute pour l'envoi. Le fichier apparaît sur CurseForge après leur modération (souvent quelques minutes).

## Tester en jeu sans publier

```bash
tools/make-zip.sh
# -> /opt/wow/releases/NSRTAutoReminders-<version>.zip
```

Le script refuse de faire le zip si un fichier listé dans le `.toc` manque.

## En cas d'échec

| Message | Solution |
|---|---|
| `La version vX est déjà publiée` | Augmente `## Version:` dans le `.toc`, ou coche « Régénérer les données » |
| `build.env absent de la VM` | Refais l'étape 4 |
| Le job reste « Queued » | Le runner est arrêté : `cd ~/actions-runner && sudo ./svc.sh status` |
| `CF_API_KEY` ou ID manquant : envoi ignoré | Vérifie le secret et la ligne `X-Curse-Project-ID` du `.toc` |
| Erreur `401` de CurseForge | Clé expirée ou fausse : recrée-la et remplace le secret |
