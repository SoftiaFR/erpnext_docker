@echo off
prompt $G
setlocal enabledelayedexpansion

REM Charger les variables d'environnement depuis .env
echo Chargement du fichier .env...
if not exist .env (
    echo ERREUR: Fichier .env introuvable !
    exit /b 1
)

REM Charger le fichier .env en ignorant les commentaires
for /f "usebackq tokens=1,* delims==" %%a in (.env) do (
    set "line=%%a"
    if not "!line:~0,1!"=="#" (
        if not "%%a"=="" (
            set "%%a=%%b"
        )
    )
)

REM Étape 1 : Arrêter les services
echo Arrêt des services ...
docker compose down --volumes --remove-orphans

REM Étape 2 : Lancer les services
echo Lancement des services ...
docker compose up -d
if errorlevel 1 (
    echo ERREUR: Échec de lancement des services.
    exit /b 1
)

REM Étape 3 : Installer Frappe
echo Installation de Frappe ...
set /a elapsed=0
set /a timeout_val=%TIMEOUT_BEFORE_EXIT%
set /a interval_val=%SLEEP_INTERVAL%

:frappe_loop
docker compose logs create-site > temp_output.txt 2>&1
type temp_output.txt

findstr /c:"Current Site set to frontend" temp_output.txt >nul
if !errorlevel! equ 0 (
    echo Installation Frappe terminée.
    del temp_output.txt
    goto frappe_done
)

if !elapsed! geq !timeout_val! (
    echo ERREUR: Échec de l'installation de Frappe. Abandon.
    del temp_output.txt
    exit /b 1
)

timeout /t !interval_val! /nobreak >nul
set /a elapsed+=!interval_val!
goto frappe_loop

:frappe_done
del temp_output.txt

REM Étape 4 : Activer le mode développeur
echo Activation mode développeur ...
docker compose exec backend bash -c "jq '. + {developer_mode: 1}' sites/frontend/site_config.json > sites/frontend/site_config.json.tmp && mv sites/frontend/site_config.json.tmp sites/frontend/site_config.json"
if errorlevel 1 (
    echo ERREUR: Échec activation mode développeur. Abandon.
    exit /b 1
)

REM Étape 5 : Installer l'app Erpnext_Softia_Fr
echo Récupération de Erpnext_Softia_Fr ...
docker compose exec backend bench get-app %APP_NAME% %GIT_URL%
if errorlevel 1 (
    echo ERREUR: Échec installation app. Abandon.
    exit /b 1
)

echo Installation de Erpnext_Softia_Fr ...
docker compose exec backend bench --site frontend install-app %APP_NAME%
if errorlevel 1 (
    echo ERREUR: Échec installation app. Abandon.
    exit /b 1
)

echo Migration ...
docker compose exec backend bench --site frontend migrate
if errorlevel 1 (
    echo ERREUR: Échec migration. Abandon.
    exit /b 1
)

REM Étape 6 : Redémarrer les services
echo Redémarrage des services ...
docker compose restart

REM Étape 7 : Enregistrer l'app
echo Enregistrement de %APP_NAME% ...
docker compose exec backend bash -c "echo '%APP_NAME%' >> sites/apps.txt"

REM Étape 8 : Copier les traductions
echo Copie des traductions ...
docker compose exec backend bash -c "cp -f apps/erpnext_softia_fr/locale/frappe_fr.po apps/frappe/frappe/locale/fr.po; bench build --app frappe;"
docker compose exec backend bash -c "mkdir -p apps/erpnext/erpnext/locale; cp -f apps/erpnext_softia_fr/locale/erpnext_fr.po apps/erpnext/erpnext/locale/fr.po; bench build --app erpnext;"

REM Étape 9 : Clear cache
echo Clear-cache ...
docker compose exec backend bench --site frontend clear-cache

echo Clear-website-cache ...
docker compose exec backend bench --site frontend clear-website-cache

echo Déploiement terminé.
pause