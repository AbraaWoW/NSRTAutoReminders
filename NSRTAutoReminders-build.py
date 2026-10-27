#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NSRTAutoReminders-build.py — construction des données Lua de l'addon.

UNE SEULE COMMANDE, AUCUN ARGUMENT NÉCESSAIRE :

    python3 NSRTAutoReminders-build.py --addon-dir <dossier de l'addon>

DEUX SOURCES, ET UNE SEULE POUR LES TIMELINES DE BOSS :

  1. WoW Timeline (https://wowtimeline.fr/api) — les top logs Warcraft Logs.
     C'est la SEULE source des timelines de boss : les cooldowns joueurs, les
     bornes de phase (`fight.phases`) et le déroulement des capacités du boss
     (`fight.boss.casts`) viennent tous de là, mesurés sur des pulls réels.
  2. Viserio CD Raid (https://wowutils.com) — les notes publiées, qui couvrent
     tout le raid d'un coup.

Ce que le script va encore chercher chez NSRT, et pourquoi ce n'est PAS une
source de timeline :
  - EncounterAlerts/*.lua : le modèle de phases RUNTIME, c'est-à-dire quelles
    phases NSRT ouvre réellement pendant le combat. Sans lui, des rappels
    partent dans une phase que StartReminders n'ouvre jamais et sont détruits
    silencieusement à l'import (régression 8.1.1). Il ne fournit aucun temps.
  - BossData.lua : les noms de boss et la liste « saison courante ».
  --no-nsrt-fetch coupe ces deux lectures et s'en tient aux tables du script.

Les BossTimelines de NSRT ne sont plus lues du tout : c'était un relevé figé
sur UN pull de référence, que la médiane des top logs remplace avantageusement
(écart mesuré sur Nek'zali Mythique : table figée 197,9 s, logs 102–163 s).

Dépendance : requests  (pip install requests)

Warcraft Logs API v2 (optionnel, fichier .env local) :
    WCL_CLIENT_ID=...
    WCL_CLIENT_SECRET=...
"""

import argparse
import datetime
import email.utils
import html as htmllib
import json
import math
import os
import re
import urllib.parse
import shutil
import stat as stat_module
import statistics
import sys
import time
import unicodedata
from collections import defaultdict

try:
    import requests
except ImportError:
    requests = None

import builtins

SCRIPT_VERSION = "5.9.0"


def console_text(value):
    """Retourne un texte ASCII lisible même avec un terminal mal configuré."""
    text = str(value)
    text = (text.replace("œ", "oe").replace("Œ", "OE")
            .replace("’", "'").replace("«", '"').replace("»", '"')
            .replace("–", "-").replace("—", "-").replace("…", "..."))
    return unicodedata.normalize("NFKD", text).encode(
        "ascii", "ignore").decode("ascii")


def console_print(*values, **kwargs):
    """Affichage immédiat et indépendant de l'encodage du terminal.

    `flush` est impose, mais via setdefault : un appelant qui le passe lui
    aussi ne doit pas faire tomber tout le script sur un « got multiple
    values for keyword argument », a 3000 lignes du vrai probleme.
    """
    kwargs.setdefault("flush", True)
    builtins.print(
        *(console_text(value) for value in values),
        **kwargs,
    )


print = console_print

###############################################################################
#
#   CONFIGURATION SAISON  —  C'EST ICI QU'ON CHANGE DE SAISON
#
#   Au lancement d'une nouvelle saison :
#     1. Passe CURRENT_SEASON au nouveau numéro (ex: 2)
#     2. Si le nouveau raid n'est pas dans SEASONS, ajoute sa ligne
#     3. Relance simplement :  python3 build_data.py
#   Cette valeur s'applique aux DEUX sources (Viserio et WoW Timeline).
#
###############################################################################

# Saison de chaque raid (slug -> numéro). À compléter d'une ligne par
# nouveau raid. CURRENT_SEASON pilote l'ordre d'affichage dans l'addon
# (saison courante en premier) et le filtre --season current.
# >>> À passer à 2 au lancement de la Saison 2 de Midnight. <<<
SEASONS = {
    # Saison 1 (patch 12.0)
    "voidspire": 1,
    "the-voidspire": 1,
    "sporefall": 1,
    "march-on-queldanas": 1,
    "march-on-qualdanas": 1,   # orthographe utilisée par Lorrgs
    "the-dreamrift": 1,
    "dreamrift": 1,
    # Warcraft Logs regroupe parfois ces 3 raids sous un seul nom de zone
    # abrégé ("VS / DR / MQD") — sans cette entrée, ce nom ne matche rien
    # ici et le script le confond avec du contenu jamais vu, proposant de
    # lui assigner une NOUVELLE saison à chaque lancement.
    "vs-dr-mqd": 1,
    # Saison 2 (patch 12.1) : TROIS raids — The Venomous Abyss, The Tidebound
    # Grotto, et The Unbinding of Kith'ix ajoute le 14 octobre. Ula'tek est un
    # boss DANS Venomous Abyss, pas un raid separe.
    "the-venomous-abyss": 2,
    "venomous-abyss": 2,
    # Kith'ix est un RAID a lui seul, et non le 9e boss de Venomous Abyss
    # comme je l'avais suppose avant sa sortie. Viserio emploie deux formes
    # du slug : "the-unbinding-of-kithix" dans les chemins d'image,
    # "unbinding-of-kithix" dans les liens de note.
    "the-unbinding-of-kithix": 2,
    "unbinding-of-kithix": 2,
    # Deuxième raid de la saison 2 (confirmé : Nymrissa Wavecaller y était
    # rattachée sous ce slug côté Viserio, tombait sinon en saison 0/"Autre"
    # faute de correspondance dans cette table).
    "the-tidebound-grotto": 2,
    "tidebound-grotto": 2,
    # Ula'tek : confirmé être un BOSS dans The Venomous Abyss, pas un
    # troisième raid séparé (saison 2 ne compte que deux raids : The
    # Venomous Abyss et The Tidebound Grotto). Slugs gardés ici pour la
    # saison, mais RAID_NAMES pointe maintenant vers Venomous Abyss.
    "curse-of-ulatek": 2,
    "curse-of-ula-tek": 2,
    "ulatek": 2,
}
# Saison d'une RENCONTRE, par ID. Sert de repli quand le nom de zone ne
# correspond a rien dans SEASONS : un contenu annonce avant sa sortie apparait
# chez l'API/Viserio sous un nom de raid qu'on ne connait pas encore, et
# tombait alors en "saison 0 / Autre", donc invisible dans l'addon.
#
# Rattacher par ID plutot que par nom evite d'avoir a deviner le nom a l'avance
# — l'ID de rencontre, lui, est connu des l'annonce (Warcraft Logs l'expose
# avant la sortie). Ce repli ne peut jamais FAIRE AVANCER la saison courante :
# il n'alimente pas la detection, il ne fait que ranger une rencontre deja
# connue dans la bonne saison.
ENCOUNTER_SEASONS = {
    3513: 2,   # Kith'ix — raid "The Unbinding of Kith'ix", sorti le 14 octobre
}

CURRENT_SEASON = 1

# L'API Warcraft Logs v2 sert à confirmer/valider la saison courante — sans
# état persistant : une nouvelle zone/raid doit être ajoutée à la main dans
# SEASONS et RAID_NAMES ci-dessus (voir sync_seasons_from_wcl et le
# cross-check avec Viserio/NSRT plus bas, qui signalent clairement quand
# quelque chose d'inconnu apparaît).
WCL_TOKEN_URL = "https://www.warcraftlogs.com/oauth/token"
WCL_API_URL = "https://www.warcraftlogs.com/api/v2/client"

# Warcraft Logs limite l'API v2 à la fois en fréquence et en points par heure.
# Toutes les requêtes WCL passent par wcl_post() afin qu'un HTTP 429 suspende
# réellement l'ensemble du pipeline au lieu de provoquer une rafale d'échecs.
WCL_MIN_REQUEST_INTERVAL = 1.10
WCL_MAX_RATE_RETRIES = 8
WCL_LAST_REQUEST_AT = 0.0
WCL_BLOCKED_UNTIL = 0.0
WCL_RATE_PAUSE_REASON = None
WCL_LAST_POINTS_SPENT = None
WCL_LAST_POINTS_RESET_IN = None
WCL_MAX_OBSERVED_QUERY_COST = 0.0
WCL_RATE_LIMIT_QUERY_ENABLED = True


class WCLRateLimitExhausted(RuntimeError):
    """Le quota WCL n'est toujours pas revenu après toutes les attentes."""


class SourceBuildAborted(RuntimeError):
    """Une source (Viserio ou WoW Timeline) n'a rien eu à générer.

    Utilisée à la place de sys.exit() À L'INTÉRIEUR de build_viserio() et
    build_toplogs() : un sys.exit() y lève SystemExit, qui remonte direct
    hors de main() et saute prune_stale_toc_entries() en fin de script.
    Résultat observé : si par exemple l'API ne renvoie rien un jour
    donné, tout le script s'arrête AVANT le nettoyage final du .toc, qui
    garde alors des lignes fantômes (fichiers plus jamais régénérés).
    main() attrape cette exception source par source pour que le nettoyage
    du .toc ait toujours lieu, même quand une des deux sources échoue.
    """


def configure_wcl_rate_limit(args):
    """Applique les réglages CLI au régulateur global WCL."""
    global WCL_MIN_REQUEST_INTERVAL, WCL_MAX_RATE_RETRIES
    WCL_MIN_REQUEST_INTERVAL = max(0.0, float(args.wcl_delay))
    WCL_MAX_RATE_RETRIES = max(1, int(args.wcl_max_retries))


def _wcl_wait(seconds, reason):
    """Attend sans produire une ligne par seconde dans le terminal."""
    seconds = max(0.0, float(seconds))
    if seconds <= 0:
        return
    shown = max(1, int(round(seconds)))
    print(f"[PAUSE] {reason} Reprise automatique dans {shown} s.")
    time.sleep(seconds)


def _wcl_retry_after(response, attempt):
    """Lit Retry-After/RateLimit-Reset, puis applique un repli progressif."""
    now = time.time()
    headers = getattr(response, "headers", {}) or {}
    raw = headers.get("Retry-After")
    if raw:
        try:
            return max(1.0, float(raw))
        except (TypeError, ValueError):
            try:
                retry_date = email.utils.parsedate_to_datetime(raw)
                if retry_date.tzinfo is None:
                    retry_date = retry_date.replace(datetime.timezone.utc)
                return max(1.0, retry_date.timestamp() - now)
            except (TypeError, ValueError, OverflowError):
                pass

    for header_name in (
            "X-RateLimit-Reset", "RateLimit-Reset", "X-Rate-Limit-Reset"):
        raw_reset = headers.get(header_name)
        if not raw_reset:
            continue
        try:
            reset = float(raw_reset)
        except (TypeError, ValueError):
            continue
        # Selon le serveur, la valeur peut être un délai ou un timestamp Unix.
        return max(1.0, reset - now if reset > now else reset)

    # Si la dernière réponse GraphQL valide annonçait encore la durée de la
    # fenêtre courante, elle est plus précise qu'un backoff arbitraire. C'est
    # notamment utile lorsque WCL renvoie 429 sans en-tête Retry-After.
    if WCL_LAST_POINTS_RESET_IN is not None:
        try:
            known_reset = float(WCL_LAST_POINTS_RESET_IN)
        except (TypeError, ValueError):
            known_reset = 0.0
        if known_reset > 0:
            return known_reset + 2.0

    # WCL ne fournit pas toujours Retry-After. Une minute évite alors de
    # retenter immédiatement; le plafond empêche une attente exponentielle
    # déraisonnable entre deux messages.
    return min(60.0 * (2 ** attempt), 900.0)


def _wcl_query_with_rate_limit(query):
    """Ajoute rateLimitData à une opération GraphQL sans modifier ses données."""
    if not WCL_RATE_LIMIT_QUERY_ENABLED or "rateLimitData" in query:
        return query
    brace = query.find("{")
    if brace < 0:
        return query
    # Noms exacts exposes par RateLimitData dans l'API Warcraft Logs v2.
    # Les libelles plus courts visibles sur la page de gestion des clients
    # ("Rate Limit" / "Points Spent") ne sont pas les noms du schema GraphQL.
    field = (
        "\n      rateLimitData {"
        " limitPerHour pointsSpentThisHour pointsResetIn }\n"
    )
    return query[:brace + 1] + field + query[brace + 1:]


def _wcl_has_rate_limit_schema_error(payload):
    """Détecte uniquement une incompatibilité de champs RateLimitData."""
    if not isinstance(payload, dict):
        return False
    errors = payload.get("errors")
    if not isinstance(errors, list):
        return False
    messages = " ".join(
        str(error.get("message", error)) if isinstance(error, dict)
        else str(error)
        for error in errors
    ).lower()
    return (
        "ratelimitdata" in messages
        and "cannot query field" in messages
    )


def _wcl_record_rate_limit(payload):
    """Programme une pause avant épuisement du budget de points WCL."""
    global WCL_BLOCKED_UNTIL, WCL_RATE_PAUSE_REASON
    global WCL_LAST_POINTS_SPENT, WCL_LAST_POINTS_RESET_IN
    global WCL_MAX_OBSERVED_QUERY_COST
    data = payload.get("data") if isinstance(payload, dict) else None
    rate = data.get("rateLimitData") if isinstance(data, dict) else None
    if not isinstance(rate, dict):
        return
    try:
        limit = float(rate.get("limitPerHour"))
        spent = float(rate.get("pointsSpentThisHour"))
        reset_in = max(0.0, float(rate.get("pointsResetIn")))
    except (TypeError, ValueError):
        return
    # Mesurer le coût réel entre deux réponses du même créneau. Le compteur
    # pointsSpent repart à zéro à chaque fenêtre; une diminution signale donc
    # un nouveau créneau et ne doit pas être interprétée comme un coût négatif.
    if (
            WCL_LAST_POINTS_SPENT is not None
            and WCL_LAST_POINTS_RESET_IN is not None
            and spent >= WCL_LAST_POINTS_SPENT
            and reset_in <= WCL_LAST_POINTS_RESET_IN + 5.0):
        observed_cost = spent - WCL_LAST_POINTS_SPENT
        if observed_cost > 0:
            WCL_MAX_OBSERVED_QUERY_COST = max(
                WCL_MAX_OBSERVED_QUERY_COST, observed_cost)
    elif WCL_LAST_POINTS_SPENT is not None and spent < WCL_LAST_POINTS_SPENT:
        WCL_MAX_OBSERVED_QUERY_COST = 0.0

    WCL_LAST_POINTS_SPENT = spent
    WCL_LAST_POINTS_RESET_IN = reset_in

    # Une page d'événements peut coûter bien davantage qu'une requête simple.
    # La marge fixe de 2 % utilisée auparavant permettait encore à une grosse
    # page de faire dépasser 3 600 points entre deux contrôles. Garder au moins
    # 200 points ou 5 % du quota, puis adapter cette marge au plus gros coût
    # réellement observé dans le créneau.
    reserve = max(
        200.0,
        limit * 0.05,
        WCL_MAX_OBSERVED_QUERY_COST * 1.50,
    )
    if limit > 0 and spent >= limit - reserve and reset_in > 0:
        WCL_BLOCKED_UNTIL = max(
            WCL_BLOCKED_UNTIL, time.monotonic() + reset_in + 2.0)
        WCL_RATE_PAUSE_REASON = (
            f"Quota Warcraft Logs presque épuisé "
            f"({spent:.2f}/{limit:.0f} points, "
            f"marge {reserve:.0f})."
        )


def wcl_post(url, *, json_body=None, data=None, auth=None, headers=None,
             timeout=45):
    """POST WCL régulé, avec reprise automatique et respect de Retry-After."""
    global WCL_LAST_REQUEST_AT, WCL_BLOCKED_UNTIL, WCL_RATE_PAUSE_REASON
    global WCL_RATE_LIMIT_QUERY_ENABLED

    original_body = json_body

    for attempt in range(WCL_MAX_RATE_RETRIES + 1):
        body = original_body
        if url == WCL_API_URL and isinstance(original_body, dict):
            body = dict(original_body)
            if isinstance(body.get("query"), str):
                body["query"] = _wcl_query_with_rate_limit(body["query"])

        now = time.monotonic()
        if WCL_BLOCKED_UNTIL > now:
            reason = WCL_RATE_PAUSE_REASON or "Quota Warcraft Logs en attente."
            wait_for = WCL_BLOCKED_UNTIL - now
            WCL_BLOCKED_UNTIL = 0.0
            WCL_RATE_PAUSE_REASON = None
            _wcl_wait(wait_for, reason)

        gap = time.monotonic() - WCL_LAST_REQUEST_AT
        if gap < WCL_MIN_REQUEST_INTERVAL:
            time.sleep(WCL_MIN_REQUEST_INTERVAL - gap)

        try:
            response = requests.post(
                url, json=body, data=data, auth=auth, headers=headers,
                timeout=timeout)
        except requests.RequestException:
            WCL_LAST_REQUEST_AT = time.monotonic()
            raise
        WCL_LAST_REQUEST_AT = time.monotonic()

        if response.status_code != 429:
            if response.status_code == 200 and url == WCL_API_URL:
                try:
                    payload = response.json()
                except ValueError:
                    return response
                if (
                        WCL_RATE_LIMIT_QUERY_ENABLED
                        and _wcl_has_rate_limit_schema_error(payload)):
                    # Une évolution future du schéma de quota ne doit jamais
                    # rendre les données métier (zones, classements, casts)
                    # indisponibles. Désactiver seulement la surveillance
                    # proactive et rejouer exactement la même requête.
                    WCL_RATE_LIMIT_QUERY_ENABLED = False
                    print(
                        "[INFO] Champs de quota WCL incompatibles : "
                        "surveillance proactive désactivée pour cette "
                        "exécution; la gestion HTTP 429 reste active."
                    )
                    continue
                _wcl_record_rate_limit(payload)
            return response

        if attempt >= WCL_MAX_RATE_RETRIES:
            raise WCLRateLimitExhausted(
                "Warcraft Logs maintient le blocage HTTP 429 après "
                f"{WCL_MAX_RATE_RETRIES} reprise(s). Les caches déjà créés "
                "sont conservés; relance la même commande plus tard.")

        wait_for = _wcl_retry_after(response, attempt)
        _wcl_wait(
            wait_for,
            f"Limite Warcraft Logs atteinte (HTTP 429, "
            f"tentative {attempt + 1}/{WCL_MAX_RATE_RETRIES}).")

    raise WCLRateLimitExhausted("Limite Warcraft Logs persistante.")


# (classe, spé) slugs du site -> specID Blizzard
SPEC_IDS = {
    ("warrior", "arms"): 71, ("warrior", "fury"): 72, ("warrior", "protection"): 73,
    ("paladin", "holy"): 65, ("paladin", "protection"): 66, ("paladin", "retribution"): 70,
    ("hunter", "beastmastery"): 253, ("hunter", "beast-mastery"): 253,
    ("hunter", "marksmanship"): 254, ("hunter", "survival"): 255,
    ("rogue", "assassination"): 259, ("rogue", "outlaw"): 260, ("rogue", "subtlety"): 261,
    ("priest", "discipline"): 256, ("priest", "holy"): 257, ("priest", "shadow"): 258,
    ("deathknight", "blood"): 250, ("deathknight", "frost"): 251, ("deathknight", "unholy"): 252,
    ("shaman", "elemental"): 262, ("shaman", "enhancement"): 263, ("shaman", "restoration"): 264,
    ("mage", "arcane"): 62, ("mage", "fire"): 63, ("mage", "frost"): 64,
    ("warlock", "affliction"): 265, ("warlock", "demonology"): 266, ("warlock", "destruction"): 267,
    ("monk", "brewmaster"): 268, ("monk", "windwalker"): 269, ("monk", "mistweaver"): 270,
    ("druid", "balance"): 102, ("druid", "feral"): 103,
    ("druid", "guardian"): 104, ("druid", "restoration"): 105,
    ("demonhunter", "havoc"): 577, ("demonhunter", "vengeance"): 581,
    ("demonhunter", "devourer"): 1480,  # nouvelle spé Midnight (ID confirmé via le code Lorrgs)
    ("evoker", "devastation"): 1467, ("evoker", "preservation"): 1468,
    ("evoker", "augmentation"): 1473,
}

# Role de chaque spe (tank/heal/dps) -> metrique a utiliser pour
# /spec_ranking. Confirme via l'onglet Reseau du navigateur : la requete
# reelle pour deathknight-blood (un TANK) utilise bien metric=dps, pas un
# metrique dedie aux tanks — donc tank et dps partagent le meme metrique.
# Seuls les soigneurs utilisent hps. Codee en dur plutot que devinee
# depuis un champ "role"/"type" de l'API /specs, dont le nom exact et le
# format ne sont pas garantis stables d'une version a l'autre.
HEALER_SPECS = {
    ("paladin", "holy"), ("priest", "discipline"), ("priest", "holy"),
    ("shaman", "restoration"), ("monk", "mistweaver"),
    ("druid", "restoration"), ("evoker", "preservation"),
}


# ---------------------------------------------------------------------------
# Phases : numerotation NSRT, instants pris dans les logs
# ---------------------------------------------------------------------------
# L'API et NSRT ne numerotent PAS les phases de la meme facon, et c'est la
# numerotation NSRT qui fait foi : c'est elle qui decide si un rappel se
# declenche (Reminders.lua : StartReminders(phase) -> ProcessedReminder[
# encID][phase]) et c'est elle que l'UI timeline de NSRT reapplique quand on
# edite une note (Timeline.lua : PhaseFromTime + RewriteNoteLine).
#
# Exemple concret, Nek'zali the Soulcoiler (3470) :
#     NSRT      : 1@0s   1.5@134s   1.75@214s   2@277s
#     le report : 1@0s   2@165s     3@276s
# La "phase 3" du report est la phase 2 de NSRT, et NSRT n'a pas de phase 3
# jouable sur ce boss. Ecrire ph:3 rangeait donc les rappels dans un
# compartiment jamais ouvert : ils ne se declenchaient jamais, sans erreur.
#
# Noter les phases FRACTIONNAIRES (1.5, 1.75, 2.5) : NSRT les utilise
# vraiment au runtime (EncounterAlerts .../NekzaliTheSoulcoiler.lua fait
# newPhase = 1.5 puis self:StartReminders(self.Phase)). Tout ce qui touche
# aux phases doit donc accepter des flottants, pas seulement des entiers.
#
# CE QU'ON LIT CHEZ NSRT, ET CE QU'ON N'Y LIT PLUS.
# On n'y lit plus aucun INSTANT : les BossTimelines etaient un relevé fige sur
# un pull de reference ("based on vod" dans leur changelog), qui ne
# correspondait a aucun autre pull. Les bornes viennent maintenant de la
# mediane des top logs servis par l'API (voir write_phase_table).
# On y lit uniquement le MODELE : quelles phases NSRT ouvre vraiment au
# runtime, lu dans EncounterAlerts, qui est le code reellement execute en
# combat. C'est la seule facon de savoir qu'un ph:2 sur Sszorak est injouable.
NSRT_ALERT_DIRS = ["MidnightS1", "MidnightS2"]
NSRT_ALERTS_API = ("https://api.github.com/repos/Reloe/"
                   "NorthernSkyRaidTools/contents/NorthernSkyRaidTools/"
                   "EncounterAlerts")
NSRT_ALERTS_RAW = ("https://raw.githubusercontent.com/Reloe/"
                   "NorthernSkyRaidTools/main/NorthernSkyRaidTools/"
                   "EncounterAlerts")

_RE_ENC_ID = re.compile(r"^\s*local\s+encID\s*=\s*(\d+)", re.M)
# Affectation de phase AU RUNTIME. `self.Phase = ...` et `newphase = ...`
# comptent ; `phase = 1,` (champ de table dans la definition d'une alerte)
# ne compte pas, c'est une etiquette statique.
# Le `=(?!=)` est indispensable : sans lui, la COMPARAISON
# `if self.Phase == 1 then` etait lue comme une affectation de la
# valeur "=", donc classee indirecte, et le modele passait a tort en
# "phases non bornees".
_RE_PHASE_SET = re.compile(
    r"(?:self\.Phase|newphase|newPhase)\s*=(?!=)\s*([^\s,;)]+)")


def detect_nsrt_phase_model(text):
    """Modele de phases d'un boss, lu dans son fichier EncounterAlerts.

    Renvoie (encID, modele) ou (None, None) si le fichier n'est pas lisible.

    Le fichier EncounterAlerts est la SEULE autorite : c'est lui qui fait
    `self.Phase = N` puis `self:StartReminders(self.Phase)`. Un BossTimelines
    peut declarer des phases que personne n'active — Ula'tek en est l'exemple,
    et Kith'ix declare une phase 3 jamais atteinte.

    Deux niveaux de certitude, assumes comme tels :
      - "ce boss change-t-il de phase ?" est binaire et fiable : il y a une
        affectation, ou il n'y en a pas ;
      - "quelles phases exactement ?" ne l'est pas toujours. The Coiled Altar
        fait `self.Phase = newphase`, ou newphase vient d'une table. On releve
        alors les valeurs litterales ET on marque le modele comme non borne
        (`allowed = None`), plutot que de publier une liste incomplete qui
        ferait disparaitre les rappels des phases oubliees.
    """
    m = _RE_ENC_ID.search(text or "")
    if not m:
        return None, None
    enc = int(m.group(1))
    literals, indirect, uncertain = set(), False, False
    for raw in _RE_PHASE_SET.findall(text):
        try:
            literals.add(float(raw))
        except ValueError:
            indirect = True
            # `self.Phase = self.Phase + 1` : NSRT COMPTE les transitions
            # (Entombed Sentinels, The Lost Explorers) — le modele non borne
            # le reproduit exactement. Toute autre valeur calculee
            # (`self.Phase = newphase`, tiree d'une table) laisse inconnue la
            # correspondance entre les phases du log et celles de NSRT :
            # c'est le cas de The Coiled Altar, ou il a fallu la relever a la
            # main (1/2/3/4 dans le log, 1/2/2.5/3 chez NSRT).
            if raw != "self.Phase":
                uncertain = True
    if not literals and not indirect:
        return enc, {"type": "none"}
    if indirect:
        return enc, {"type": "log", "allowed": None, "uncertain": uncertain}
    allowed = sorted({1.0} | literals)
    return enc, {"type": "log",
                 "allowed": [int(v) if float(v).is_integer() else v for v in allowed]}


_PHASE_MODELS = None


def nsrt_phase_models(offline=False):
    """Modeles de phases pour tous les boss, lus chez NSRT puis fusionnes
    avec la table ecrite a la main.

    La table en dur GAGNE systematiquement : elle porte des nuances qu'aucun
    automate ne peut deduire, notamment l'`alias` de Nek'zali, qui corrige la
    numerotation des stages cote Warcraft Logs et non cote NSRT. La detection
    sert donc a deux choses : couvrir les boss absents de la table — c'etait
    le cas de Kith'ix — et signaler une divergence quand NSRT a change.
    """
    global _PHASE_MODELS
    if _PHASE_MODELS is not None:
        return _PHASE_MODELS
    _PHASE_MODELS = dict(NSRT_RUNTIME_PHASES)
    if offline:
        return _PHASE_MODELS

    detected, diverging, discovered = {}, [], []
    for folder in NSRT_ALERT_DIRS:
        try:
            r = request_get(f"{NSRT_ALERTS_API}/{folder}", timeout=20)
            entries = r.json() if r is not None and r.status_code == 200 else None
        except Exception:                                    # noqa: BLE001
            entries = None
        if not isinstance(entries, list):
            continue
        for it in entries:
            name = it.get("name") or ""
            if it.get("type") != "file" or not name.endswith(".lua"):
                continue
            try:
                rf = request_get(f"{NSRT_ALERTS_RAW}/{folder}/{name}", timeout=20)
            except Exception:                                # noqa: BLE001
                rf = None
            if rf is None or rf.status_code != 200:
                continue
            enc, model = detect_nsrt_phase_model(rf.text)
            if enc is None:
                continue
            detected[enc] = model
            known = NSRT_RUNTIME_PHASES.get(enc)
            if known is None:
                _PHASE_MODELS[enc] = model
                discovered.append((enc, name, model))
            elif known.get("type") != model.get("type"):
                diverging.append((enc, name, known.get("type"), model.get("type")))
            elif list(known.get("allowed") or []) != list(model.get("allowed") or []):
                # Ecart sur les phases atteignables, pas sur le type. Il passait
                # inapercu : c'est exactement ce qui a laisse The Coiled Altar
                # avec une liste incomplete pendant que NSRT en ouvrait une de
                # plus. La table ecrite a la main reste prioritaire, mais
                # l'ecart doit se voir.
                diverging.append((
                    enc, name,
                    "allowed=" + str(known.get("allowed")),
                    "allowed=" + str(model.get("allowed"))))

    if discovered:
        print(f"  {len(discovered)} boss absent(s) de la table de phases, "
              f"deduit(s) de EncounterAlerts :")
        for enc, name, model in sorted(discovered):
            detail = ("aucun changement de phase" if model["type"] == "none"
                      else f"phases {model.get('allowed') or 'non bornees'}")
            print(f"       - {enc} ({name}) : {detail}")
    if diverging:
        print(f"  [WARN] {len(diverging)} divergence(s) avec NSRT_RUNTIME_PHASES "
              f"— la table en dur reste prioritaire, mais elle a vieilli :")
        for enc, name, a, b in sorted(diverging):
            print(f"       - {enc} ({name}) : table \"{a}\", NSRT \"{b}\"")
    return _PHASE_MODELS


# Controle des phases, boss par boss : [logs vus, logs refuses, phases du log
# hors modele]. Lu par le rapport de fin de build.
PHASE_CHECK = defaultdict(lambda: [0, 0, set()])


def out_of_model_phases(transitions, model):
    """Numeros de phase du log que le modele NSRT ne sait pas placer."""
    if not model or model.get("type") == "none" or model.get("allowed") is None:
        return set()
    ids = []
    for _ts, pid in transitions:
        try:
            ids.append(float(pid))
        except (TypeError, ValueError):
            continue
    fractional = any(not v.is_integer() for v in ids)
    alias = model.get("alias") or {}
    allowed = {float(a) for a in model["allowed"]}
    bad = set()
    for pid in ids:
        if not fractional and alias:
            pid = float(alias.get(int(pid), pid))
        if pid not in allowed:
            bad.add(pid)
    return bad


def phase_refusal(enc, transitions, model):
    """Raison de refuser ce log, ou None.

    Ne concerne QUE les boss absents de NSRT_RUNTIME_PHASES, dont le modele a
    ete deduit automatiquement (typiquement : le premier build d'une nouvelle
    saison). Pour eux, une phase du log que NSRT ne connait pas, ou un modele
    dont la correspondance est inconnue, ne se devine pas : le log est ecarte
    plutot que de produire des rappels ranges dans une phase que NSRT
    n'ouvrira jamais. Les boss de la table ecrite a la main ne sont jamais
    refuses (Kith'ix ecarte volontairement sa phase 3, par exemple).
    """
    if enc in NSRT_RUNTIME_PHASES or not model:
        return None
    if model.get("uncertain"):
        return "correspondance des phases inconnue (self.Phase calcule par NSRT)"
    bad = out_of_model_phases(transitions, model)
    if bad:
        return "phases du log inconnues de NSRT : " + ", ".join(
            format_lua_phase(b) for b in sorted(bad))
    return None


def phase_model_for(enc):
    """Modele de phases d'une rencontre, table en dur + detection."""
    return nsrt_phase_models().get(enc)


# ---------------------------------------------------------------------------
# Modele de phases RUNTIME de NSRT
# ---------------------------------------------------------------------------
# ATTENTION : il existe DEUX notions de phase dans NSRT, et les confondre est
# exactement l'erreur qui a cause la regression 8.1.1.
#
#   - BossTimelines/*.lua  : releve sur UN pull de reference ("based on vod"
#                            dans le changelog NSRT). Temps FIGES, ne
#                            correspondant a aucun autre pull. CE SCRIPT NE LES
#                            LIT PLUS : les instants viennent des top logs.
#   - EncounterAlerts/*.lua: detection LIVE pendant le combat. C'est elle qui
#                            appelle StartReminders(phase) et decide donc si
#                            un rappel part ou non. C'EST ELLE QUI FAIT FOI,
#                            et c'est la seule chose qu'on lise encore ici.
#
# Releve depuis EncounterAlerts/MidnightS2, recoupe avec les modules BigWigs
# de TheVenomousAbyss (qui confirment le decoupage, sauf Ula'tek — voir plus
# bas) :
#
#   "none" : aucune detection, self.Phase reste a 1 tout le combat. Un rappel
#            avec ph != 1 y est INJOUABLE ; temps absolus.
#   "log"   : on suit les phases du log (phase_id + ts), le modele ne dit plus
#            que lesquelles NSRT peut atteindre ("allowed") et comment traduire
#            la convention Warcraft Logs quand un report l'utilise ("alias").
#
# Piege Ula'tek : BigWigs y declare des stages 1/2/2.5/3, mais NSRT ne change
# JAMAIS de phase sur ce boss. S'aligner sur BigWigs aurait casse un boss qui
# fonctionne : BigWigs sert de recoupement, pas de reference.
NSRT_RUNTIME_PHASES = {
    # "none"  : NSRT ne change JAMAIS de phase sur ce boss — tout part en ph:1,
    #           meme si le log annonce des stages. C'est verifie dans
    #           EncounterAlerts/MidnightS2 et c'est ce qui a casse en 8.1.1 :
    #           Sszorak s'etait vu attribuer 27 rappels en phase 2 alors que
    #           StartReminders(2) n'y est jamais appele.
    # "allowed": phases que NSRT peut reellement atteindre. None = non borne
    #           (le boss incremente autant de fois que l'evenement se repete).
    #           Une phase du log absente de cette liste est ignoree : les casts
    #           qui tombent dedans restent dans la derniere phase valide, ce
    #           qui correspond a ce que fait NSRT.
    # "alias" : certains reports numerotent les stages a la maniere de Warcraft
    #           Logs (2, 3) au lieu de celle de NSRT (1.5, 2). On ne l'applique
    #           qu'aux reports SANS aucune phase fractionnaire, seule facon de
    #           distinguer les deux conventions — cf. detect dans
    #           resolve_log_phases.
    3379: {"type": "none"},                       # Nymrissa Wavecaller
    3420: {"type": "none"},                       # Sszorak
    3421: {"type": "none"},                       # The Twin Fangs
    3455: {"type": "none"},                       # Vashnik the Malignant
    3492: {"type": "none"},                       # Ula'tek
    3445: {"type": "log", "allowed": None},       # Entombed Sentinels
    3497: {"type": "log", "allowed": None},       # The Lost Explorers
    # Nek'zali : l'API renvoie soit [1.5, 1.75, 2] (convention NSRT), soit
    # [2, 3] (convention Warcraft Logs) selon le report. Verifie sur les
    # reports Wyz4a3DTjKYMFAtr (fractionnaire) et cbxdRCFmVLPz8Bqy (entier).
    3470: {"type": "log", "allowed": [1, 1.5, 1.75, 2], "alias": {2: 1.5, 3: 2}},
    # The Coiled Altar : l'API numerote 1, 2, 3, 4 — verifie sur les 21 logs
    # servis par /timeline/3429/{5,4}/Priest/Holy, aucun n'emet de phase
    # fractionnaire. NSRT, lui, enchaine 1 -> 2 -> 2.5 -> 3 et s'arrete la.
    # Les deux decrivent le MEME combat, avec le meme nombre d'etapes dans le
    # meme ordre : la correspondance est donc determinee, 2->2, 3->2.5, 4->3.
    # L'ecart entre les etapes 3 et 4 du log vaut 37,5 a 38,7 s sur les quinze
    # logs mythiques — une etape courte de duree fixe, ce qu'est la 2.5.
    # Sans cet alias, les cooldonws de la derniere etape etaient comptes depuis
    # le debut de l'etape precedente, donc decales d'environ 38 secondes.
    3429: {"type": "log", "allowed": [1, 2, 2.5, 3], "alias": {2: 2, 3: 2.5, 4: 3}},
    # Kith'ix : verifie dans EncounterAlerts/MidnightS2/Kithix.lua, qui fait
    # `self.Phase = 2` puis `self:StartReminders(self.Phase)` sur un
    # ENCOUNTER_TIMELINE_EVENT_STATE_CHANGED annule. Seules les phases 1 et 2
    # sont atteintes au runtime : BossTimelines declare bien une phase 3
    # (360 s en Heroique, 420 s en Mythique) mais aucun code ne l'active, et
    # aucune capacite n'y est rattachee. `allowed` la plafonne donc a 2,
    # sinon les rappels d'apres 360 s partiraient dans un compartiment que
    # StartReminders n'ouvre jamais.
    3513: {"type": "log", "allowed": [1, 2]},
}


def resolve_log_phases(transitions, model):
    """[(ts_ms, phase_id)] -> [(debut_s, phase_NSRT)], phase 1 a 0 incluse.

    On utilise le `phase_id` que l'API donne, et NON la position dans la liste.
    C'etait le defaut de fond des versions precedentes : la position supposait
    que tous les reports annoncent les memes stages dans le meme ordre, ce qui
    est faux. Sur Nek'zali un report peut renvoyer [1.75, 2] sans 1.5 du tout,
    ou [2, 3] dans l'autre convention — dans les deux cas la 1re transition
    devenait "1.5" par position, donc fausse. `phase_id` porte de surcroit les
    sous-phases (1.75, 2.5) avec leur VRAI instant, la ou l'ancien code les
    devinait depuis un pull de reference.
    """
    if not model or model.get("type") == "none":
        return [(0.0, 1)]

    clean = []
    for ts, pid in transitions:
        try:
            pid = float(pid)
        except (TypeError, ValueError):
            continue
        clean.append((ts, pid))

    # Convention du report : une seule phase fractionnaire suffit a affirmer
    # qu'il numerote comme NSRT ; sinon on traduit depuis les stages WCL.
    fractional = any(not float(pid).is_integer() for _, pid in clean)
    alias = model.get("alias") or {}
    allowed = model.get("allowed")

    # MODELE NON BORNE : le `phase_id` du log ne dit PAS le numero de phase
    # NSRT, et s'y fier casse ces boss. Entombed Sentinels (3445) et The Lost
    # Explorers (3497) font, dans EncounterAlerts, `self.Phase = self.Phase + 1`
    # a chaque detection : NSRT COMPTE les transitions, il ne lit aucun
    # identifiant. Warcraft Logs, lui, ALTERNE les siens. Releve sur le pull
    # 7-phases de 七宝宝欺七七 (3445 Mythique) :
    #     log  : 1@0  2@46  1@64  2@155  1@163  2@254  1@263
    #     NSRT : 1@0  2@46  3@64  4@155  5@163  6@254  7@263
    # En reprenant l'identifiant du log, les quatre segments "phase 1" se
    # confondaient en une seule phase : leurs temps, relatifs a quatre origines
    # differentes, etaient tous ecrits en ph:1, et `phaseStarts[1]` ne gardait
    # que la DERNIERE origine (263 s). Degat visible dans l'addon : trois Hymne
    # divin a 0:21, 0:33 et 0:44 — un sort de 3 minutes de recharge lance trois
    # fois en 23 secondes. 391 des 471 variantes de ce boss portaient un
    # `phaseStarts` ou la phase 1 ne demarre pas a zero.
    if allowed is None:
        out, phase = [(0.0, 1)], 1
        for ts, _pid in clean:
            phase += 1
            out.append((ts / 1000.0, phase))
        out.sort()
        return out

    out = [(0.0, 1)]
    for ts, pid in clean:
        if not fractional and alias:
            pid = float(alias.get(int(pid), pid))
        # Hors du modele : on NE CREE PAS la transition. Les casts qui suivent
        # restent donc dans la derniere phase valide, avec un temps compte
        # depuis le debut de celle-ci. Ils se declenchent au bon instant, au
        # lieu d'etre ecrits dans une phase fantome et detruits a l'import.
        #
        # Un modele `allowed = None` n'est PAS borne, et ce n'est pas un oubli :
        # The Lost Explorers (3497) et Entombed Sentinels (3445) font
        # `self.Phase = self.Phase + 1` dans leur DetectPhaseChange, sans
        # plafond. Les versions precedentes coupaient ces boss au nombre de
        # phases declare par BossTimelines (5 pour 3497) : c'etait un plafond
        # emprunte a la timeline d'affichage, qui n'a rien a voir avec ce que
        # StartReminders ouvre reellement. Il est tombe avec BossTimelines.
        if allowed is not None and pid not in allowed:
            continue
        out.append((ts / 1000.0, pid))
    out.sort()
    return out


def nsrt_runtime_phase(seconds, resolved):
    """(phase NSRT, temps relatif au debut de cette phase).

    Le temps est relatif parce que NSRT remet le chrono a zero a chaque phase :
    StartReminders(phase) passe par HideAllReminders(), qui annule chaque timer
    en attente, puis ne replanifie que la phase qui commence.
    """
    phase, start = 1, 0.0
    for st, ph in resolved:
        if seconds >= st:
            phase, start = ph, st
        else:
            break
    return phase, max(seconds - start, 0.0)


def format_lua_phase(phase):
    """1.0 -> "1" mais 1.5 -> "1.5" (NSRT utilise des phases fractionnaires)."""
    return str(int(phase)) if float(phase).is_integer() else ("%g" % phase)


def log_phase_transitions(fight):
    """Normalise le champ `phases` d'un fight en une liste triee de
    transitions (ts_ms, phase_id).

    Format renvoye par l'API (confirme sur wowtimeline.fr) :
        "phases": [ {"ts":165232,"phase_id":2}, {"ts":276147,"phase_id":3} ]
    - `ts` est en MILLISECONDES depuis le debut du combat ;
    - `phase_id` est la phase qui COMMENCE a cet instant ;
    - la phase 1 demarre toujours a ts=0. Une partie des reports la laissent
      implicite, une autre la liste explicitement ({"ts":0,"phase_id":1}) :
      on ne garde JAMAIS ce marqueur, cf. le commentaire dans la boucle.

    Certains reports renvoient des entrees SANS `phase_id` (ex. le report
    XptK2j9Fvb8mGBQV : [{"ts":189281},{"ts":303648}]). On retombe alors sur
    la position dans la liste (1re transition -> phase 2, 2e -> phase 3),
    ce qui correspond au comportement observe sur les reports complets.
    """
    transitions = []
    seen_ts = set()
    for idx, entry in enumerate(fight.get("phases") or []):
        ts = entry.get("ts")
        if ts is None:
            continue
        ts = int(ts)
        phase_id = entry.get("phase_id") or (idx + 2)
        # La phase 1 demarre toujours a 0 et elle est DEJA implicite dans le
        # modele (nsrt_runtime_phase prefixe la liste des debuts de stage par
        # 0.0). Une partie des reports la listent quand meme explicitement,
        # sous la forme {"ts":0,"phase_id":1}. La conserver ajoutait un second
        # 0 dans `starts`, et comme la recherche d'index garde le DERNIER
        # debut <= au cast, tout le combat se retrouvait decale d'une phase :
        # un cast a 37 s dans la phase 1 sortait en `ph:2 time:37`, et aucun
        # rappel n'etait plus jamais ecrit en phase 1. NSRT detruit
        # silencieusement les rappels d'une phase deja passee, donc la note
        # entiere devenait inerte.
        if ts <= 0:
            continue
        # Meme cause, autre forme : une premiere entree phase_id == 1 avec un
        # ts non nul reste un marqueur de debut de phase 1, pas une transition.
        if phase_id == 1 and not transitions:
            continue
        # Deux entrees au meme ts (stage + sous-stage annonces ensemble)
        # produiraient le meme decalage d'un cran.
        if ts in seen_ts:
            continue
        seen_ts.add(ts)
        transitions.append((ts, phase_id))
    transitions.sort()
    return transitions



def metric_for_spec(cls, spec):
    """dps pour DPS et tanks (confirme via DevTools), hps pour les
    soigneurs. Voir HEALER_SPECS ci-dessus."""
    if (cls, spec) in HEALER_SPECS:
        return "hps"
    return "dps"

# slug de boss (dans l'URL de la note) -> (EncounterID, nom affiché)
# Source : UI/BossData.lua de NSRT (Midnight S1 + S2).
BOSSES = {
    "imperator-averzian": (3176, "Imperator Averzian"),
    "vorasius": (3177, "Vorasius"),
    "fallen-king-salhadaar": (3179, "Fallen-King Salhadaar"),
    "vaelgor-and-ezzorak": (3178, "Vaelgor & Ezzorak"),
    "lightblinded-vanguard": (3180, "Lightblinded Vanguard"),
    "crown-of-the-cosmos": (3181, "Crown of the Cosmos"),
    "chimaerus": (3306, "Chimaerus"),
    "chimaerus-the-undreamt-god": (3306, "Chimaerus"),
    "beloren-child-of-alar": (3182, "Belo'ren"),
    "midnight-falls": (3183, "Midnight Falls"),
    "rotmire": (3159, "Rotmire"),
    "nymrissa-wavecaller": (3379, "Nymrissa Wavecaller"),
    "nekzali-the-soulcoiler": (3470, "Nek'zali the Soulcoiler"),
    "entombed-sentinels": (3445, "Entombed Sentinels"),
    "vashnik-the-malignant": (3455, "Vashnik the Malignant"),
    "the-lost-explorers": (3497, "The Lost Explorers"),
    "sszorak": (3420, "Sszorak"),
    "the-twin-fangs": (3421, "The Twin Fangs"),
    "the-coiled-altar": (3429, "The Coiled Altar"),
    "ulatek": (3492, "Ula'tek"),
    # Kith'ix : rencontre 3513, seul boss du raid "The Unbinding of Kith'ix".
    # Avant sa sortie je l'avais range comme 9e boss de The Venomous Abyss et
    # suppose qu'il partageait sa zone — c'etait faux, il a son propre raid.
    # Le slug "kithix" est en revanche confirme sur Viserio, qui nomme ses
    # notes "unbinding-of-kithix-kithix-mythic-...". "kith-ix" reste comme
    # variante defensive : un slug sans correspondance est sans effet.
    "kithix": (3513, "Kith'ix"),
    "kith-ix": (3513, "Kith'ix"),
}

# Ordre de KILL (pas l'EncounterID) pour chaque raid, utilisé pour trier
# les listes deroulantes de l'addon dans l'ordre "boss order" plutot que
# dans l'ordre numerique des EncounterID (qui n'a aucun rapport avec
# l'ordre de progression). Un boss absent de cette table est simplement
# trie par son EncounterID en dernier recours (voir key= plus bas et
# ENCOUNTER_KILL_ORDER dans Core/Core.lua, qui DOIT rester synchronise
# avec cette table).
BOSS_KILL_ORDER = {
    # The Venomous Abyss (saison 2) — cf. image officielle "Boss Order" :
    # Nek'zali -> (Entombed Sentinels / The Lost Explorers, en parallele)
    # -> (Vashnik the Malignant / Sszorak, en parallele) -> The Twin Fangs
    # -> The Coiled Altar -> Ula'tek.
    3470: 1,   # Nek'zali the Soulcoiler
    3445: 2,   # Entombed Sentinels
    3497: 3,   # The Lost Explorers
    3455: 4,   # Vashnik the Malignant
    3420: 5,   # Sszorak
    3421: 6,   # The Twin Fangs
    3429: 7,   # The Coiled Altar
    3492: 8,   # Ula'tek
    # The Unbinding of Kith'ix (saison 2) — un seul boss, donc premier
    # de SON raid. Le tri s'applique a la liste d'un raid a la fois,
    # il n'y a donc pas de conflit avec le 1 de Nek'zali.
    3513: 1,   # Kith'ix
}


def boss_sort_key(enc_id):
    """Cle de tri pour l'ordre d'affichage des boss dans une liste
    deroulante : ordre de kill connu (BOSS_KILL_ORDER) d'abord, puis repli
    sur l'EncounterID pour tout boss pas encore ajoute a la table (ex. un
    nouveau raid dont on n'a pas encore l'ordre officiel) — comportement
    identique a l'ancien tri numerique pour ces cas-la."""
    return (0, BOSS_KILL_ORDER[enc_id]) if enc_id in BOSS_KILL_ORDER else (1, enc_id)


def canonical_boss_name(enc_id, fallback):
    """Nom de boss stable pour un enc_id donné, utilisé pour nommer les
    fichiers Data/Viserio/<Boss>.lua et Data/WowTimeline/<Boss>.lua.

    Viserio et l'API/WCL peuvent renvoyer des libellés différents pour le
    même boss (ex. "Chimaerus, the Undreamt God" vs le nom court
    "Chimaerus" utilisé par Viserio/NSRT) : sans ça, le même enc_id produit
    deux noms de fichier différents selon la source, ce qui casse le lien
    visuel entre les deux dossiers pour un même boss. BOSSES (complété par
    sync_bosses_from_nsrt) reste la référence commune aux deux sources ;
    on n'utilise le nom propre à la source que si l'enc_id n'y figure pas.
    """
    for enc, name in BOSSES.values():
        if enc == enc_id:
            return name
    return fallback


RAID_NAMES = {
    "voidspire": "The Voidspire",
    "the-voidspire": "The Voidspire",
    "sporefall": "Sporefall",
    "march-on-queldanas": "March on Quel'Danas",
    "march-on-qualdanas": "March on Quel'Danas",
    "the-dreamrift": "The Dreamrift",
    "dreamrift": "The Dreamrift",
    "the-venomous-abyss": "The Venomous Abyss",
    "venomous-abyss": "The Venomous Abyss",
    # Slug interne utilisé par Viserio pour ce même deuxième raid de
    # saison 2 — unifié sous le même nom d'affichage que ci-dessus plutôt
    # que de laisser apparaître le slug brut "the-tidebound-grotto".
    "the-tidebound-grotto": "The Tidebound Grotto",
    "tidebound-grotto": "The Tidebound Grotto",
    # Troisieme raid de la saison 2. Les deux slugs renvoient au meme nom
    # d'affichage, comme pour les raids ci-dessus.
    "the-unbinding-of-kithix": "The Unbinding of Kith'ix",
    "unbinding-of-kithix": "The Unbinding of Kith'ix",
    # Ula'tek est un BOSS dans The Venomous Abyss, pas un raid séparé.
    # "Vaults of Atal'Utek" (nom précédemment supposé ici) n'a jamais été
    # confirmé et est retiré.
    "curse-of-ulatek": "The Venomous Abyss",
    "curse-of-ula-tek": "The Venomous Abyss",
    "ulatek": "The Venomous Abyss",
}


# --- Source unique des top logs : WoW Timeline -------------------------------
# WoW Timeline lit Warcraft Logs et sert /zones, /specs, /spells et
# /spec_ranking. Lorrgs a ete entierement retire : il publiait avec plusieurs
# jours de retard (pas de Kith'ix deux jours apres la sortie du raid) et sa
# journalisation des capacites de boss repetait une meme incantation une fois
# par cible, ce qui noyait le deroulement affiche dans l'addon.
#
# Adresse : WOWTIMELINE_DEFAULT ci-dessous, remplacable par --wowtimeline-api
# ou par WOWTIMELINE_API dans le .env.
#
# Certificat : le serveur est en HTTPS avec un certificat cree par Caddy
# (« tls internal »), que Python ne connait pas. Le script utilise la racine de
# Caddy UNIQUEMENT pour les requetes vers WoW Timeline (Warcraft Logs garde la
# verification normale). Elle est cherchee dans cet ordre : --wowtimeline-ca,
# WOWTIMELINE_CA dans le .env, puis caddy-root.crt a cote du script.
#
# Au demarrage, /health est teste. S'il ne repond pas, l'etape des top logs
# est abandonnee proprement : il n'y a plus de source de secours, et mieux
# vaut conserver les donnees du run precedent que d'en ecrire des fausses.
WOWTIMELINE_DEFAULT = "https://wowtimeline.fr/api"
WOWTIMELINE_API = None          # renseigne dans main() si le service repond
WOWTIMELINE_BASE = None         # adresse configuree (meme si injoignable)
WOWTIMELINE_CA = None           # certificat racine de Caddy, ou None
SOURCE_LABELS = {"wowtimeline": "Warcraft Logs via WoW Timeline"}
SOURCE_COUNTS = defaultdict(int)  # timelines retenues par source


def tls_verify_for(url):
    """Verification TLS d'une URL : racine de Caddy pour WoW Timeline seulement."""
    if WOWTIMELINE_CA and WOWTIMELINE_BASE:
        root = WOWTIMELINE_BASE[:-4] if WOWTIMELINE_BASE.endswith("/api") else WOWTIMELINE_BASE
        if url.startswith(root):
            return WOWTIMELINE_CA
    return True


def wowtimeline_alive(base):
    """(True, "") si WoW Timeline repond sur /health, sinon (False, raison)."""
    root = base[:-4] if base.endswith("/api") else base
    try:
        r = requests.get(root + "/health", timeout=5, headers=UA,
                         verify=tls_verify_for(root + "/health"))
        if r.status_code == 200:
            return True, ""
        return False, f"HTTP {r.status_code}"
    except requests.exceptions.SSLError:
        if WOWTIMELINE_CA:
            return False, (f"certificat refuse, meme avec {WOWTIMELINE_CA} "
                           f"(est-ce bien la racine de CE serveur Caddy ?)")
        return False, ("certificat HTTPS non reconnu. Recupere la racine de Caddy sur "
                       "le serveur (docker compose cp caddy:/data/caddy/pki/authorities/"
                       "local/root.crt ./caddy-root.crt) et pose caddy-root.crt a cote "
                       "de ce script")
    except requests.RequestException as exc:
        return False, f"injoignable ({exc.__class__.__name__})"


# Apres ce nombre d'echecs CONSECUTIFS de WoW Timeline, on cesse de
# l'interroger pour le reste du run : sur ~800 requetes, continuer a attendre
# son delai a chaque appel couterait des dizaines de minutes.
def source_get(path, cache_hours):
    """GET d'une route WoW Timeline. Renvoie (donnees, "wowtimeline").

    Source unique : plus aucun repli. Une reponse vide est une reponse, et
    une panne est une panne — l'appelant decide quoi en faire.
    """
    if not WOWTIMELINE_API:
        return None, "wowtimeline"
    return api_fetch(WOWTIMELINE_API + path, cache_hours)[0], "wowtimeline"


# ---------------------------------------------------------------------------
# Export complet : un boss et une difficulte en UNE requete
# ---------------------------------------------------------------------------
# /api/v1/export/<encounterID>/<difficulte> renvoie TOUTES les spes d'un boss
# d'un coup. La route est reservee aux IP de RATE_LIMIT_ALLOW cote serveur
# (app/protect.py : export_allowed) ; une autre IP recoit un 403 et le script
# retombe alors sur /spec_ranking, une requete par spe, comme avant.
#
# Ce que ca change en nombre d'appels : 1 requete par boss et par difficulte,
# au lieu d'une par (boss, spe, difficulte). Avec les 40 spes servies par
# /specs, un boss passe de 80 requetes a 2.
#
# Les deux routes ne servent PAS le meme schema, et c'est tout l'objet de la
# conversion ci-dessous. L'export suit le format de la page d'analyse :
#   {"encounter": {"id", "name"}, "difficulty": 5, "all_spells": false,
#    "specs": {"<Classe>-<Spe>": {..., "logs": [...]}}, "spells": {...}}
#   un log : {"rank", "player", "amount", "report", "fight", "duration",
#             "phases": [{"t", "id"}], "casts": [[t_ms, spell_id]],
#             "boss": [[t_ms, spell_id]]}
# alors que tout le reste du script consomme le schema de /spec_ranking
# (reports -> fights -> players, phases en {"ts", "phase_id"}). On convertit
# donc vers CE schema : la suite du pipeline ne voit aucune difference.
WOWTIMELINE_EXPORT = False        # True si /api/v1/export repond a cette IP
WOWTIMELINE_EXPORT_INDEX = set()  # (encounterID, difficulte) exportables
EXPORT_CONSENSUS = True           # ajouter la variante « Plan consensus »
EXPORT_CONSENSUS_SHARE = 0.4      # cf. consensus_min_share dans config.yaml
EXPORT_DIFFICULTY_IDS = {"normal": 3, "heroic": 4, "mythic": 5}
_EXPORT_CACHE = {}                # (enc, diffID) -> {slug de spe: format Lorrgs}

# Plan consensus : repris de app/analysis.py du service. L'export ne le fournit
# pas (c'est une route a part, /api/v1/consensus, une requete PAR SPE — ce qui
# annulerait tout le benefice de l'export), mais il se calcule entierement a
# partir des logs deja recus. Le calcul est donc refait ici A L'IDENTIQUE.
# >>> Si analysis.consensus() change cote service, mettre a jour ces trois
#     fonctions, sinon la variante consensus divergera de celle du site. <<<
CONSENSUS_GAP_MS = 15_000   # deux casts a plus de 15 s d'ecart = deux moments
CONSENSUS_MIN_LOGS = 3      # en dessous, pas de consensus

# Combats anormalement courts. Releve sur Nek'zali Heroique : 14 timelines, dont
# plusieurs Top #1, duraient 14 s pour une duree mediane de 213 s — de vrais
# logs, tres hauts au classement justement parce que le combat a ete bref,
# mais sans valeur comme plan (un seul « Wake of Ashes a 6 s »). Un combat
# plus court que SHORT_FIGHT_SHARE fois la duree MEDIANE des logs de la meme
# spe, du meme boss et de la meme difficulte est ecarte, et le log suivant du
# classement prend sa place. Le seuil vient des logs eux-memes ; sous
# SHORT_FIGHT_MIN_LOGS logs, pas de mediane fiable, donc pas de filtre.
# >>> Meme regle dans app/analysis.py du service (consensus). <<<
SHORT_FIGHT_SHARE = 0.4
SHORT_FIGHT_MIN_LOGS = 5
SHORT_FIGHTS = []           # (encID, difficulte, spe, joueur, duree_s, mediane_s)


def short_fight_limit(durations_ms):
    """Duree minimale (ms) d'un combat exploitable, ou None sans mediane fiable."""
    durs = [float(d) for d in durations_ms if d and float(d) > 0]
    if len(durs) < SHORT_FIGHT_MIN_LOGS:
        return None
    return SHORT_FIGHT_SHARE * statistics.median(durs)


def drop_short_fights(logs):
    """logs au format consensus ({"duration": ms, ...}) sans les combats trop courts."""
    limit = short_fight_limit(lg.get("duration") for lg in logs)
    if limit is None:
        return logs
    return [lg for lg in logs if (lg.get("duration") or 0) >= limit]


def _consensus_phase_of(t_ms, transitions):
    """(phase, debut de la phase en ms) pour un instant du combat."""
    phase, start = 1, 0
    for ts, pid in transitions:
        if t_ms >= ts:
            phase, start = pid, ts
    return phase, start


def consensus_plan(logs, min_share=EXPORT_CONSENSUS_SHARE):
    """logs : [{"duration": ms, "phases": [(ts_ms, id)], "casts": [(t_ms, sid)]}].

    Renvoie {"duration", "phases", "casts", "logs"} ou None. Les temps sont
    reconstruits comme debut median de la phase + temps median depuis le debut
    de cette phase : un plan ancre sur les phases reste juste meme quand les
    kills n'ont pas tous la meme duree.
    """
    logs = [lg for lg in drop_short_fights(logs) if lg.get("casts")]
    n = len(logs)
    if n < CONSENSUS_MIN_LOGS:
        return None
    need = max(CONSENSUS_MIN_LOGS, math.ceil(min_share * n))

    starts = {}
    for lg in logs:
        for ts, pid in lg.get("phases") or []:
            starts.setdefault(pid, []).append(ts)
    phase_start = {1: 0}
    phase_start.update({pid: int(statistics.median(v)) for pid, v in starts.items()
                        if len(v) * 2 >= n and pid != 1})

    buckets = {}
    for i, lg in enumerate(logs):
        tr = sorted(lg.get("phases") or [])
        for t, sid in lg["casts"]:
            ph, st = _consensus_phase_of(t, tr)
            buckets.setdefault((sid, ph), []).append((t - st, i))

    plan = []
    for (sid, ph), items in buckets.items():
        if ph not in phase_start:
            continue
        items.sort()
        groups, cur = [], [items[0]]
        for it in items[1:]:
            if it[0] - cur[-1][0] <= CONSENSUS_GAP_MS:
                cur.append(it)
            else:
                groups.append(cur)
                cur = [it]
        groups.append(cur)
        for g in groups:
            if len({i for _, i in g}) >= need:
                plan.append((phase_start[ph] + int(statistics.median(r for r, _ in g)), sid))

    if not plan:
        return None
    plan.sort()
    return {
        "duration": int(statistics.median(lg["duration"] for lg in logs)),
        "phases": sorted((ts, pid) for pid, ts in phase_start.items() if pid != 1),
        "casts": plan,
        "logs": n,
    }


def _export_spec_to_reports(spec_data):
    """Une spe de l'export -> le schema de /spec_ranking, consensus compris."""
    logs = (spec_data or {}).get("logs") or []
    reports = []
    for lg in logs:
        phases = [{"ts": p.get("t"), "phase_id": p.get("id")}
                  for p in (lg.get("phases") or [])
                  if p.get("t") is not None and p.get("id") is not None]
        reports.append({
            "report_id": lg.get("report"),
            "fights": [{
                "fight_id": lg.get("fight"),
                "duration": lg.get("duration"),
                "phases": phases,
                # Frise du boss DE CE PULL, deja dedoublonnee par le service
                # (analysis.collapse_boss_casts) exactement comme pour
                # /spec_ranking : rien a refaire ici.
                "boss": {"casts": [{"ts": t, "id": sid}
                                   for t, sid in (lg.get("boss") or [])]},
                "players": [{
                    "name": lg.get("player"),
                    "total": lg.get("amount"),
                    "casts": [{"ts": t, "id": sid}
                              for t, sid in (lg.get("casts") or [])],
                }],
            }],
        })
    out = {"reports": reports}
    if not (EXPORT_CONSENSUS and reports):
        return out
    plan = consensus_plan(
        [{"duration": lg.get("duration") or 0,
          "phases": [(p.get("t"), p.get("id")) for p in (lg.get("phases") or [])],
          "casts": [(t, sid) for t, sid in (lg.get("casts") or [])]}
         for lg in logs],
        EXPORT_CONSENSUS_SHARE)
    if plan:
        # Meme forme que extra_reports de /spec_ranking : la frise du boss est
        # celle du rang 1, et le nom porte le nombre de logs concordants.
        out["extra_reports"] = [{
            "report_id": "consensus",
            "fights": [{
                "fight_id": 0,
                "duration": plan["duration"],
                "phases": [{"ts": ts, "phase_id": pid} for ts, pid in plan["phases"]],
                "boss": reports[0]["fights"][0]["boss"],
                "players": [{
                    "name": f"Plan consensus (top {plan['logs']})",
                    "total": None,
                    "casts": [{"ts": t, "id": sid} for t, sid in plan["casts"]],
                }],
            }],
        }]
    return out


def wowtimeline_export_ready(base):
    """(True, raison) si /api/v1/export repond a cette IP. Remplit l'index."""
    url = base + "/v1/export"
    try:
        r = requests.get(url, timeout=20, headers=UA, verify=tls_verify_for(url))
    except requests.RequestException as exc:
        return False, f"injoignable ({exc.__class__.__name__})"
    if r.status_code == 403:
        return False, ("IP non autorisee — ajoute-la a RATE_LIMIT_ALLOW dans le "
                       ".env du service, ou lance ce script depuis le serveur")
    if r.status_code != 200:
        return False, f"HTTP {r.status_code}"
    try:
        rows = r.json()
    except ValueError:
        return False, "reponse non-JSON"
    if not isinstance(rows, list):
        return False, "schema inattendu (liste attendue)"
    for row in rows:
        try:
            WOWTIMELINE_EXPORT_INDEX.add(
                (int(row["encounter_id"]), int(row["difficulty"])))
        except (KeyError, TypeError, ValueError):
            continue
    return True, f"{len(WOWTIMELINE_EXPORT_INDEX)} couple(s) boss/difficulte"


def fetch_boss_export(enc, difficulty, cache_hours):
    """Toutes les spes d'un boss pour une difficulte, en une requete.

    Renvoie {slug de spe: donnees au format /spec_ranking}, {} si ce boss n'a
    rien a exporter, ou None quand l'export n'est pas utilisable — et c'est
    alors, et seulement alors, que l'appelant repart sur /spec_ranking.
    """
    diff_id = EXPORT_DIFFICULTY_IDS.get(str(difficulty).lower())
    if not (WOWTIMELINE_EXPORT and WOWTIMELINE_API) or diff_id is None:
        return None
    key = (enc, diff_id)
    if key in _EXPORT_CACHE:
        return _EXPORT_CACHE[key]
    # L'index dit deja quels couples existent : inutile d'aller chercher un
    # 404 pour chaque boss sans log dans cette difficulte.
    if WOWTIMELINE_EXPORT_INDEX and key not in WOWTIMELINE_EXPORT_INDEX:
        _EXPORT_CACHE[key] = {}
        return {}
    data, ok = api_fetch(f"{WOWTIMELINE_API}/v1/export/{enc}/{diff_id}", cache_hours)
    if not ok:
        return None
    specs = (data or {}).get("specs")
    if data and not isinstance(specs, dict):
        print(f"[WARN] Export {enc}/{diff_id} : pas de cle 'specs' "
              f"(cles recues : {sorted(data)}) — retour au mode spe par spe.")
        return None
    out = {str(name).lower(): _export_spec_to_reports(spec)
           for name, spec in (specs or {}).items()}
    _EXPORT_CACHE[key] = out
    return out


def fetch_spec_ranking(sslug, bslug, enc, difficulty, metric, cache_hours):
    """Top logs d'une spe sur un boss. Renvoie (donnees, source).

    Passe par l'export du boss quand il est autorise (une requete pour toutes
    les spes), sinon par /spec_ranking (une requete par spe).
    """
    if not WOWTIMELINE_API:
        return {}, "wowtimeline"
    exported = fetch_boss_export(enc, difficulty, cache_hours)
    if exported is not None:
        return exported.get(sslug) or {}, "wowtimeline"
    query = f"?difficulty={difficulty}&metric={metric}"
    data, _ok = api_fetch(
        f"{WOWTIMELINE_API}/spec_ranking/{sslug}/{bslug}{query}", cache_hours)
    return data or {}, "wowtimeline"


NSRT_BOSSDATA_URL = ("https://raw.githubusercontent.com/Reloe/"
                     "NorthernSkyRaidTools/main/NorthernSkyRaidTools/BossData.lua")


def slugify(name):
    s = name.lower()
    s = s.replace("&", "and").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s


def normalize_name(name):
    return re.sub(r"[^a-z0-9]", "", (name or "").lower())


def load_dotenv(path=".env"):
    """Charge un .env minimal sans dépendance supplémentaire.

    Les variables déjà présentes dans l'environnement restent prioritaires.
    """
    if not os.path.isfile(path):
        return
    try:
        with open(path, encoding="utf-8") as env_file:
            for raw_line in env_file:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                key, value = line.split("=", 1)
                key = key.strip()
                value = value.strip()
                if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                    value = value[1:-1]
                if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
                    os.environ.setdefault(key, value)
    except OSError as exc:
        print(f"[WARN] Impossible de lire {path} : {exc}")


def known_season_for_raid(raid_name):
    raid_norm = normalize_name(raid_name)
    matches = []
    for raid_slug, season in SEASONS.items():
        known_name = RAID_NAMES.get(raid_slug, raid_slug)
        known_norm = normalize_name(known_name)
        slug_norm = normalize_name(raid_slug)
        if raid_norm in {known_norm, slug_norm}:
            matches.append(season)
    return max(matches) if matches else None


def wcl_access_token(client_id, client_secret):
    try:
        response = wcl_post(
            WCL_TOKEN_URL,
            auth=(client_id, client_secret),
            data={"grant_type": "client_credentials"},
            headers=UA,
            timeout=30,
        )
    except requests.RequestException as exc:
        raise RuntimeError(f"Connexion OAuth Warcraft Logs impossible : {exc}") from exc
    if response.status_code != 200:
        raise RuntimeError(
            f"OAuth Warcraft Logs refusé (HTTP {response.status_code}). "
            "Vérifie WCL_CLIENT_ID et WCL_CLIENT_SECRET.")
    try:
        token = response.json().get("access_token")
    except ValueError as exc:
        raise RuntimeError("Réponse OAuth Warcraft Logs invalide.") from exc
    if not token:
        raise RuntimeError("Warcraft Logs n'a retourné aucun access_token.")
    return token


def wcl_zones(client_id, client_secret):
    query = """
    query NSRTAutoRemindersZones {
      worldData {
        zones {
          id
          name
          frozen
          expansion {
            id
            name
          }
          difficulties {
            id
            name
          }
          encounters {
            id
            name
          }
        }
      }
    }
    """
    token = wcl_access_token(client_id, client_secret)
    try:
        response = wcl_post(
            WCL_API_URL,
            json_body={"query": query},
            headers={
                **UA,
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            timeout=45,
        )
    except requests.RequestException as exc:
        raise RuntimeError(f"Requête Warcraft Logs impossible : {exc}") from exc
    if response.status_code != 200:
        raise RuntimeError(
            f"API Warcraft Logs en erreur (HTTP {response.status_code}).")
    try:
        payload = response.json()
    except ValueError as exc:
        raise RuntimeError("Réponse GraphQL Warcraft Logs invalide.") from exc
    if payload.get("errors"):
        messages = "; ".join(
            str(error.get("message", error)) for error in payload["errors"])
        raise RuntimeError(f"Warcraft Logs GraphQL : {messages}")
    zones = (((payload.get("data") or {}).get("worldData") or {}).get("zones"))
    if not isinstance(zones, list):
        raise RuntimeError("Warcraft Logs n'a retourné aucune liste de zones.")
    return zones


# Rencontres telles que Warcraft Logs les publie, remplies a l'execution par
# sync_seasons_from_wcl. Source d'identite du script : id, nom, zone.
WCL_ENCOUNTERS = {}

# Raid d'une rencontre, d'apres le raidSlug des notes Viserio (voir
# sync_raids_from_viserio). Warcraft Logs ne publie pas ce decoupage : sa
# "zone" est un conteneur de classements, et la 53 contient les trois raids
# de la saison 2. Viserio, lui, suit les vrais raids.
RAID_BY_ENCOUNTER = {}


def sync_seasons_from_wcl(args):
    """Détecte les raids WCL pertinents et renvoie la saison courante.

    Sans état persistant (plus de wcl_seasons.json) : chaque zone est
    résolue via SEASONS/RAID_NAMES uniquement, à chaque lancement. Une zone
    non reconnue n'est plus devinée/confirmée interactivement — elle est
    juste signalée, à ajouter à la main dans les tables (cohérent avec le
    reste de la vérification croisée : on préfère un script déterministe
    et prévisible plutôt qu'un état caché qui peut se perdre ou désynchro-
    niser d'un poste de travail à l'autre).
    """
    fallback = CURRENT_SEASON
    if args.no_wcl:
        return args.current_season or fallback

    load_dotenv(args.env_file)
    client_id = os.environ.get("WCL_CLIENT_ID", "").strip()
    client_secret = os.environ.get("WCL_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        print("[INFO] Warcraft Logs non configuré : détection automatique ignorée.")
        print(f"       Ajoute WCL_CLIENT_ID et WCL_CLIENT_SECRET dans {args.env_file}.")
        return args.current_season or fallback

    print("\n=== Détection des raids et saisons (Warcraft Logs API v2) ===")
    try:
        zones = wcl_zones(client_id, client_secret)
    except RuntimeError as exc:
        print(f"[WARN] {exc}")
        print("       Les saisons locales restent utilisables.")
        return args.current_season or fallback

    # IDENTIFICATION : Warcraft Logs fait foi pour ce qui EXISTE.
    #
    # Avant, on intersectait ses rencontres avec la table BOSSES ecrite a la
    # main (`encounter_ids & known_encounters`) : un boss que Warcraft Logs
    # connaissait et que la table ignorait etait silencieusement ecarte.
    # C'est ce verrou qui a rendu Kith'ix invisible jusqu'a ce que la table
    # soit editee. On prend desormais TOUTES ses rencontres, et le slug se
    # deduit du nom par slugify() — verifie sur les dix boss de la saison 2,
    # ou les dix slugs obtenus correspondent a ceux de Viserio.
    # BORNE : extension courante, et raids seulement.
    #
    # Sans borne, /zones remonte tout l'historique de Warcraft Logs : 310
    # rencontres et 41 zones inconnues — Throne of Thunder, Torghast, les
    # saisons Mythique+, les Gouffres... Du contenu qu'on ne generera jamais,
    # qui noyait les vraies nouveautes dans le rapport et polluait BOSSES.
    #
    # Deux criteres, tous deux lus dans la reponse, aucun nom devine :
    #   - `expansion.id` le plus eleve : l'extension en cours ;
    #   - `difficulties` contenant "Mythic" ou "Heroic" a l'identique. Un raid
    #     les propose ; une zone Mythique+ annonce "Mythic+", qui n'est PAS
    #     "Mythic" — d'ou la comparaison exacte et non par inclusion.
    # Une zone sans `difficulties` exploitable est conservee : mieux vaut une
    # ligne de trop qu'un raid disparu sans bruit.
    expansions = [(z.get("expansion") or {}).get("id") for z in zones]
    current_expansion = max((e for e in expansions if isinstance(e, int)),
                            default=None)
    RAID_DIFFICULTIES = {"Mythic", "Heroic"}

    def is_current_raid(zone):
        exp = (zone.get("expansion") or {}).get("id")
        if current_expansion is not None and exp != current_expansion:
            return False
        diffs = zone.get("difficulties")
        if not isinstance(diffs, list) or not diffs:
            return True
        names = {(d.get("name") or "").strip() for d in diffs if isinstance(d, dict)}
        return bool(names & RAID_DIFFICULTIES)

    relevant = []
    discovered = 0
    skipped_zones = 0
    for zone in zones:
        encounters = [e for e in (zone.get("encounters") or [])
                      if isinstance(e.get("id"), int)]
        if not encounters:
            continue
        if not is_current_raid(zone):
            skipped_zones += 1
            continue
        zname = zone.get("name") or f"Zone {zone.get('id')}"
        for e in encounters:
            enc_id, ename = e["id"], (e.get("name") or "").strip()
            if not ename:
                continue
            WCL_ENCOUNTERS[enc_id] = {
                "name": ename, "slug": slugify(ename),
                "zone": zname, "zone_id": zone.get("id"),
            }
            slug = slugify(ename)
            if slug and slug not in BOSSES:
                BOSSES[slug] = (enc_id, ename)
                discovered += 1
        relevant.append((zone, sorted(e["id"] for e in encounters)))
    relevant.sort(key=lambda item: int(item[0].get("id") or 0))
    if skipped_zones:
        exp_name = next(((z.get("expansion") or {}).get("name") for z in zones
                         if (z.get("expansion") or {}).get("id") == current_expansion
                         and (z.get("expansion") or {}).get("name")), None)
        print(f"  {skipped_zones} zone(s) ignoree(s) : hors de l'extension "
              f"courante{f' ({exp_name})' if exp_name else ''}, ou sans "
              f"difficulte Mythique/Heroique (Mythique+, Gouffres...).")
    if discovered:
        print(f"  {discovered} rencontre(s) decouverte(s) chez Warcraft Logs "
              f"et absente(s) de la table locale — ajoutees automatiquement.")

    detected_seasons = []
    unresolved = []
    for zone, overlap in relevant:
        zone_name = zone.get("name") or f"Zone {zone.get('id')}"
        season = known_season_for_raid(zone_name)
        if season is None:
            unresolved.append((zone_name, len(overlap)))
            continue
        print(f"  [OK  ] {zone_name} : saison {season}, {len(overlap)} rencontre(s)")
        detected_seasons.append(season)

    if unresolved:
        print(f"  [WARN] {len(unresolved)} zone(s) Warcraft Logs non "
              f"reconnue(s) (nom absent de SEASONS/RAID_NAMES) :")
        for zone_name, n in unresolved:
            print(f"       - \"{zone_name}\" ({n} rencontre(s))")
        print("       -> si c'est du contenu légitime, ajoute son nom "
              "dans SEASONS et RAID_NAMES avec la bonne saison, puis relance.")

    if not relevant:
        print("[WARN] Aucune zone Warcraft Logs ne correspond aux boss NSRT connus.")

    current = args.current_season or max(detected_seasons, default=fallback)
    print(f"  Saison courante utilisée : {current}")
    print("  (Ces zones viennent de Warcraft Logs, utilisées ici uniquement "
          "pour confirmer la saison — le découpage réel en raids séparés "
          "vient de Viserio lui-même, voir plus bas. Les deux peuvent "
          "grouper les rencontres différemment : normal, pas une erreur.)")
    return current


NSRT_CURRENT_ENCOUNTER_IDS = set()  # rempli par sync_bosses_from_nsrt()


def sync_bosses_from_nsrt(offline=False):
    """Complète BOSSES avec les boss connus de NSRT (nouveaux raids inclus).

    Reloe maintient NorthernSkyRaidTools/BossData.lua à chaque nouveau tier ;
    on en hérite. Les entrées manuelles de BOSSES restent prioritaires (elles
    couvrent les slugs du site qui diffèrent du nom du boss, ex.
    beloren-child-of-alar).

    Ce sont des NOMS de boss, pas des timelines : aucun instant n'en sort.
    --no-nsrt-fetch (offline=True) s'en tient à la table du script.
    """
    if offline:
        print("  --no-nsrt-fetch : liste des boss du script uniquement "
              f"({len({e for e, _ in BOSSES.values()})} boss).")
        return
    print("  téléchargement de la liste des boss depuis GitHub (NSRT)…")
    try:
        r = request_get(NSRT_BOSSDATA_URL, timeout=10)
        if r is None:
            return
        if r.status_code != 200:
            print(f"[WARN] BossData NSRT injoignable (HTTP {r.status_code}) — table locale seulement.")
            return
    except requests.RequestException as e:
        print(f"[WARN] BossData NSRT injoignable ({e}) — table locale seulement.")
        return
    added = 0
    known_ids = {enc for enc, _ in BOSSES.values()}
    for enc_id, name in re.findall(r'\[(\d+)\]\s*=\s*"([^"]+)"', r.text):
        enc_id = int(enc_id)
        slug = slugify(name)
        if enc_id not in known_ids and slug not in BOSSES:
            BOSSES[slug] = (enc_id, name)
            known_ids.add(enc_id)
            added += 1
    if added:
        print(f"  [SYNC] {added} boss ajoutés depuis le BossData de NSRT.")
    print(f"  {len({e for e, _ in BOSSES.values()})} boss connus au total.")

    # NSRT maintient à la main sa propre liste "saison courante" (voir
    # currentEncounterIDs dans BossData.lua) — un troisième signal
    # indépendant de WCL et Viserio, tenu à jour par le mainteneur de NSRT
    # lui-même à chaque nouveau tier.
    m = re.search(r"currentEncounterIDs\s*=\s*\{(.*?)\}", r.text, re.S)
    if m:
        NSRT_CURRENT_ENCOUNTER_IDS.clear()
        NSRT_CURRENT_ENCOUNTER_IDS.update(int(n) for n in re.findall(r"\d+", m.group(1)))
        print(f"  {len(NSRT_CURRENT_ENCOUNTER_IDS)} rencontre(s) "
              f"marquée(s) \"saison courante\" par NSRT.")




# ---------------------------------------------------------------------------
# Découverte de la Library
# ---------------------------------------------------------------------------

BASE = "https://wowutils.com"
LIBRARY = BASE + "/viserio-cooldowns/library"
UA = {"User-Agent": "NSRTAutoReminders-pipeline/0.1 (addon companion; contact via CurseForge)"}
SLEEP = 1.0
DEFAULT_CACHE_HOURS = 0

RE_NOTE_PATH = re.compile(r"/viserio-cooldowns/library/([a-z0-9-]+)")


def request_get(url, timeout=30, attempts=3):
    """GET avec nouvelles tentatives pour erreurs réseau et HTTP temporaires."""
    last_error = None
    for attempt in range(1, attempts + 1):
        try:
            response = requests.get(url, timeout=timeout, headers=UA,
                                    verify=tls_verify_for(url))
            if response.status_code < 500 and response.status_code != 429:
                return response
            last_error = f"HTTP {response.status_code}"
        except requests.RequestException as exc:
            last_error = str(exc)
        if attempt < attempts:
            time.sleep(min(2 ** (attempt - 1), 4))
    print(f"[erreur réseau] {url} — {last_error or 'échec inconnu'}")
    return None


def get(url, as_text=True):
    time.sleep(SLEEP)
    r = request_get(url)
    if r is not None and r.status_code == 200:
        return r.text if as_text else r.content
    if r is not None:
        print(f"[http {r.status_code}] {url}")
    return None


def cache_is_fresh(path, max_age_hours):
    if max_age_hours <= 0 or not os.path.exists(path):
        return False
    age = time.time() - os.path.getmtime(path)
    return age <= max_age_hours * 3600


# ---------------------------------------------------------------------------
# Stratégie 1 : sitemaps
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Stratégie 2 : données Next.js
# ---------------------------------------------------------------------------

def from_next_data():
    urls = set()
    html = get(LIBRARY)
    if not html:
        return urls

    # Les liens directement présents dans la page (notes récentes)
    for m in RE_NOTE_PATH.finditer(html):
        urls.add(BASE + "/viserio-cooldowns/library/" + m.group(1))

    # __NEXT_DATA__ embarque parfois la liste initiale + le buildId
    m = re.search(r'__NEXT_DATA__"?\s*(?:type="application/json"[^>]*>|=\s*)({.*?})</script>',
                  html, re.DOTALL)
    build_id = None
    if m:
        try:
            data = json.loads(m.group(1))
            build_id = data.get("buildId")
            blob = json.dumps(data)
            for p in RE_NOTE_PATH.finditer(blob):
                urls.add(BASE + "/viserio-cooldowns/library/" + p.group(1))
        except json.JSONDecodeError:
            pass
    else:
        b = re.search(r'"buildId"\s*:\s*"([^"]+)"', html)
        build_id = b.group(1) if b else None

    # Route de données JSON de la page Library
    if build_id:
        data_url = f"{BASE}/_next/data/{build_id}/viserio-cooldowns/library.json"
        blob = get(data_url)
        if blob:
            print(f"[next-data] {data_url}")
            for p in RE_NOTE_PATH.finditer(blob):
                urls.add(BASE + "/viserio-cooldowns/library/" + p.group(1))
    return urls





API_LIBRARY = BASE + "/viserio-cooldowns/api/library?sort=recent"


# La Library etait paginee DEUX fois par run : une fois pour la verification
# croisee avec Warcraft Logs, une fois pour la generation. Soit 40 requetes
# HTTP et 40 attentes la ou 20 suffisent — la liste ne change pas entre les
# deux appels, qui tombent a quelques secondes d'intervalle.
_LIBRARY_CACHE = None


def discover_api():
    """Pagine l'API de la Library et retourne toutes les notes (métadonnées).

    Le resultat est garde en memoire pour la duree du run : le deuxieme
    appel le reutilise au lieu de tout retelecharger.

    L'avancement s'ecrit sur UNE ligne reecrite en place quand la sortie est
    un terminal ; rediriger vers un fichier donne juste la ligne de bilan,
    au lieu d'une page de "page 7 : +24 notes".
    """
    global _LIBRARY_CACHE
    if _LIBRARY_CACHE is not None:
        print(f"  Library deja en memoire : {len(_LIBRARY_CACHE)} notes "
              f"(pas de nouvelle requete)")
        return _LIBRARY_CACHE

    items, seen, cursor, page = [], set(), None, 0
    live = sys.stdout.isatty()
    print("  interrogation de l'API de la Library…")
    while True:
        url = API_LIBRARY + (("&cursor=" + cursor) if cursor else "")
        time.sleep(SLEEP)
        try:
            r = request_get(url)
        except Exception as e:
            print(f"[erreur] {e} — pagination interrompue")
            break
        if r is None:
            break
        if r.status_code != 200:
            print(f"[http {r.status_code}] pagination interrompue")
            break
        try:
            data = r.json()
        except ValueError:
            print("[WARN] réponse non-JSON — pagination interrompue")
            break
        batch = [it for it in data.get("items", []) if it.get("slug") not in seen]
        for it in batch:
            seen.add(it["slug"])
        items += batch
        page += 1
        if live:
            print(f"\r  page {page}, {len(items)} notes…", end="")
        cursor = data.get("nextCursor")
        if not cursor or not batch:
            break
    if live:
        print("\r" + " " * 40, end="\r")
    print(f"  {len(items)} notes trouvees en {page} page(s)")
    _LIBRARY_CACHE = items
    return items


# ---------------------------------------------------------------------------
# Parsing d'une page de note
# ---------------------------------------------------------------------------

# Icône de spé = début d'une section d'acteur (ou de la compo)
RE_SPEC_ICON = re.compile(r"spec-icons%2F([a-z-]+)%2F([a-z-]+)\.png|spec-icons/([a-z-]+)/([a-z-]+)\.png")
# Icône de sort de joueur : images/<classe>/<spellID>.jpg (les sorts du boss
# sont sous boss-abilities/ et sont exclus par la classe)
RE_CAST = re.compile(r"images%2F([a-z]+)%2F(\d+)\.jpg|images/([a-z]+)/(\d+)\.jpg")
RE_TIME = re.compile(r"(\d+):(\d{2})")
PLAYER_CLASSES = {c for c, _ in SPEC_IDS} | {"demonhunter"}



def raid_display_name(raid_slug, fallback=""):
    """Nom affichable d'un raid a partir de son slug Viserio.

    RAID_NAMES ne sert plus de filtre, seulement d'orthographe : elle porte
    les apostrophes et la casse exacte, qu'un slug ne peut pas restituer
    ("the-unbinding-of-kithix" ne redonne pas "Kith'ix"). Un slug absent de
    la table produit donc un titre approchant plutot que rien du tout — le
    raid reste visible, c'est son libelle qui est imparfait.
    """
    if not raid_slug:
        return fallback
    known = RAID_NAMES.get(raid_slug)
    if known:
        return known
    small = {"of", "the", "and", "on", "in"}
    words = [w for w in raid_slug.split("-") if w]
    return " ".join(w if i and w in small else w.capitalize()
                    for i, w in enumerate(words)) or fallback


def sync_raids_from_viserio():
    """Remplit RAID_BY_ENCOUNTER depuis les raidSlug publies par Viserio.

    C'est la seule source vivante du decoupage en raids. Warcraft Logs
    regroupe par zone de classement (la 53 porte les dix rencontres de la
    saison 2, soit trois raids), Viserio publie le vrai raid de chaque note.
    Un boss dont personne n'a encore publie de note garde le nom de sa zone
    Warcraft Logs : visible, au pire mal range.
    """
    try:
        items = discover_api()
    except Exception as exc:                      # noqa: BLE001
        print(f"[WARN] Decoupage en raids indisponible ({exc.__class__.__name__}) : "
              f"les noms de zone Warcraft Logs serviront de raids.")
        return RAID_BY_ENCOUNTER
    seen = {}
    for it in items or []:
        raid_slug = (it.get("raidSlug") or "").strip()
        resolved = resolve_boss(it.get("bossSlug"))
        if raid_slug and resolved:
            seen.setdefault(resolved[0], raid_slug)
    for enc_id, raid_slug in seen.items():
        RAID_BY_ENCOUNTER[enc_id] = raid_display_name(raid_slug)
    if RAID_BY_ENCOUNTER:
        groupes = {}
        for enc_id, raid in RAID_BY_ENCOUNTER.items():
            groupes.setdefault(raid, []).append(enc_id)
        print(f"  Decoupage Viserio : {len(groupes)} raid(s) pour "
              f"{len(RAID_BY_ENCOUNTER)} rencontre(s)")
        for raid in sorted(groupes):
            print(f"    - {raid} : {len(groupes[raid])} boss")
    return RAID_BY_ENCOUNTER


def resolve_boss(boss_slug):
    """Résout un bossSlug de l'API vers (encID, nom), avec tolérance.

    Les slugs Viserio utilisent parfois le nom complet du boss
    (ex. chimaerus-the-undreamt-god) là où NSRT utilise le nom court
    (chimaerus). On matche donc par inclusion, au plus long d'abord.
    """
    if not boss_slug:
        return None
    hit = BOSSES.get(boss_slug)
    if hit:
        return hit
    best = None
    for slug, pair in BOSSES.items():
        if (slug in boss_slug or boss_slug in slug) and \
                (best is None or len(slug) > len(best[0])):
            best = (slug, pair)
    return best[1] if best else None


def parse_note_url(url):
    m = re.search(r"/library/([a-z0-9-]+)-(mythic|heroic)-([a-z0-9-]+)$", url)
    if not m:
        return None, None, None, None
    prefix, difficulty = m.group(1), m.group(2)
    best = None
    for slug, (enc_id, name) in BOSSES.items():
        if slug in prefix and (best is None or len(slug) > len(best[0])):
            best = (slug, enc_id, name)
    if best:
        slug, enc_id, name = best
        raid_slug = prefix.split(slug)[0].rstrip("-")
        raid = RAID_NAMES.get(raid_slug, raid_slug or "?")
        return enc_id, name, difficulty.capitalize(), raid
    return None, None, difficulty.capitalize(), None


def parse_page(html):
    """Retourne { (class_slug, spec_slug): [(seconds, spellid), ...] }.

    La page liste, après la timeline du boss, une section par acteur :
    icône de spé, puis la suite de casts (icône du sort + horodatage m:ss).
    On avance linéairement : chaque icône de spé ouvre une section, chaque
    icône de sort de classe joueur suivie d'un horodatage ajoute un cast.
    Les icônes de la section Composition n'ont pas de casts entre elles :
    elles produisent des sections vides qu'on ignore au final.
    """
    events = []  # (position, type, payload)
    for m in RE_SPEC_ICON.finditer(html):
        cls = m.group(1) or m.group(3)
        spec = m.group(2) or m.group(4)
        events.append((m.start(), "spec", (cls, spec)))
    for m in RE_CAST.finditer(html):
        cls = m.group(1) or m.group(3)
        spell = int(m.group(2) or m.group(4))
        if cls in PLAYER_CLASSES:
            # horodatage : premier m:ss dans les ~300 caractères qui suivent
            window = html[m.end(): m.end() + 300]
            t = RE_TIME.search(window)
            if t:
                seconds = int(t.group(1)) * 60 + int(t.group(2))
                events.append((m.start(), "cast", (cls, spell, seconds)))

    events.sort(key=lambda e: e[0])
    # Une section par ACTEUR, jamais fusionnees par spe : une note Viserio
    # peut contenir deux joueurs de la meme specialisation (comps avec
    # "Beast Mastery x2", deux Holy, etc.). Les fusionner melangeait leurs
    # deux plans de cooldowns dans une seule timeline — le joueur recevait
    # aussi les assignations de l'autre, d'ou des cooldowns de plusieurs
    # minutes reclames a une seconde d'intervalle.
    actors = []            # [(spec_key, [casts...]), ...] dans l'ordre de la page
    current = None
    for _, kind, payload in events:
        if kind == "spec":
            current = (payload, [])
            actors.append(current)
        elif kind == "cast" and current is not None:
            cls, spell, seconds = payload
            current[1].append((seconds, spell))
    # sections vides (compo) eliminees ; tri temporel ; dedoublonnage exact
    grouped = defaultdict(list)
    for spec_key, casts in actors:
        if casts:
            grouped[spec_key].append(sorted(set(casts)))
    return dict(grouped)

# ---------------------------------------------------------------------------
# Génération du Lua
# ---------------------------------------------------------------------------

def lua_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def validate_plans(plans, encounter_names, source_label, allow_dense=False):
    """Contrôle les anomalies qui produiraient des timelines Lua inutilisables."""
    errors, warnings = [], []
    timeline_count = reminder_count = 0
    for (enc_id, difficulty, spec_id), variants in sorted(plans.items()):
        if enc_id not in encounter_names:
            errors.append(f"EncounterID {enc_id} sans nom")
        if difficulty not in {"Mythic", "Heroic"}:
            errors.append(f"{enc_id}/{spec_id} : difficulté invalide {difficulty!r}")
        if not isinstance(spec_id, int) or spec_id <= 0:
            errors.append(f"{enc_id} : specID invalide {spec_id!r}")
        if not variants:
            errors.append(f"{enc_id}/{difficulty}/{spec_id} : aucune timeline")
            continue
        for variant in variants:
            timeline_count += 1
            casts = variant.get("casts") or []
            if not casts:
                errors.append(
                    f"{enc_id}/{difficulty}/{spec_id}/{variant.get('name', '?')} : vide")
                continue
            if len(casts) > 300 and not allow_dense:
                warnings.append(
                    f"{enc_id}/{spec_id}/{variant.get('name', '?')} : "
                    f"{len(casts)} rappels (anormalement long)")
            seen = set()
            for cast in casts:
                # Les top logs produisent des casts (secondes, spellID, phase) depuis
                # l'ajout du support des phases ; Viserio reste sur
                # (secondes, spellID). On accepte les deux plutot que de
                # supposer une forme unique — un unpack fige a 2 elements
                # plantait ici alors que TOUTES les donnees etaient deja
                # generees et ecrites correctement.
                if len(cast) >= 3:
                    seconds, spell_id, phase = cast[0], cast[1], cast[2]
                else:
                    seconds, spell_id, phase = cast[0], cast[1], 1
                reminder_count += 1
                if (
                    not isinstance(seconds, (int, float))
                    or isinstance(seconds, bool)
                    or seconds < -60
                    or seconds > 7200
                ):
                    warnings.append(
                        f"{enc_id}/{spec_id} : temps inhabituel {seconds!r}")
                if not isinstance(spell_id, int) or spell_id <= 0:
                    errors.append(
                        f"{enc_id}/{spec_id} : spellID invalide {spell_id!r}")
                # Les phases NSRT peuvent etre FRACTIONNAIRES (1.5, 1.75,
                # 2.5) : refuser les non-entiers rejetterait des donnees
                # parfaitement valides.
                if (not isinstance(phase, (int, float)) or isinstance(phase, bool)
                        or phase < 1):
                    errors.append(
                        f"{enc_id}/{spec_id} : phase invalide {phase!r}")
                # Le doublon se juge PAR PHASE : les temps repartent de zero
                # a chaque phase, donc (25s, phase 1) et (25s, phase 2) sont
                # deux rappels distincts, pas un duplicata.
                if (seconds, spell_id, phase) in seen:
                    warnings.append(
                        f"{enc_id}/{spec_id} : rappel dupliqué "
                        f"{seconds}/{spell_id} (phase {phase})")
                seen.add((seconds, spell_id, phase))

    print(f"\n=== Validation {source_label} ===")
    print(f"  {timeline_count} timelines, {reminder_count} rappels")
    for message in warnings[:25]:
        print(f"[WARN] {message}")
    if len(warnings) > 25:
        print(f"[WARN] … {len(warnings) - 25} avertissements supplémentaires")
    for message in errors:
        print(f"[ERR ] {message}")
    if errors:
        raise RuntimeError(
            f"Validation échouée : {len(errors)} erreur(s), aucun fichier produit.")
    print(f"  Validation réussie ({len(warnings)} avertissement(s)).")


def validate_full_notes(full_notes, encounter_names, source_label):
    """Contrôle les notes Viserio complètes (toutes spés dans une note)
    avant écriture — pendant équivalent de validate_plans pour ce schéma."""
    errors, warnings = [], []
    note_count = spec_section_count = reminder_count = 0
    for enc_id, notes in sorted(full_notes.items()):
        if enc_id not in encounter_names:
            errors.append(f"EncounterID {enc_id} sans nom")
        if not notes:
            errors.append(f"{enc_id} : aucune note")
            continue
        for note in notes:
            note_count += 1
            name = note.get("name", "?")
            if note.get("difficulty") not in {"Mythic", "Heroic"}:
                errors.append(
                    f"{enc_id}/{name} : difficulté invalide {note.get('difficulty')!r}")
            specs = note.get("specs") or {}
            if not specs:
                errors.append(f"{enc_id}/{name} : aucune spécialisation")
                continue
            for spec_id, spec_actors in specs.items():
                if not isinstance(spec_id, int) or spec_id <= 0:
                    errors.append(f"{enc_id}/{name} : specID invalide {spec_id!r}")
                if not spec_actors:
                    errors.append(f"{enc_id}/{spec_id}/{name} : vide")
                    continue
                # spec_actors = une liste de rappels PAR JOUEUR de cette spe.
                for actor_idx, casts in enumerate(spec_actors, start=1):
                    spec_section_count += 1
                    if not casts:
                        errors.append(
                            f"{enc_id}/{spec_id}/{name} : joueur {actor_idx} vide")
                        continue
                    seen = set()
                    for seconds, spell_id in casts:
                        reminder_count += 1
                        if (
                            not isinstance(seconds, (int, float))
                            or isinstance(seconds, bool)
                            or seconds < -60
                            or seconds > 7200
                        ):
                            warnings.append(
                                f"{enc_id}/{spec_id} : temps inhabituel {seconds!r}")
                        if not isinstance(spell_id, int) or spell_id <= 0:
                            errors.append(
                                f"{enc_id}/{spec_id} : spellID invalide {spell_id!r}")
                        if (seconds, spell_id) in seen:
                            warnings.append(
                                f"{enc_id}/{spec_id} : rappel dupliqué "
                                f"{seconds}/{spell_id}")
                        seen.add((seconds, spell_id))

    print(f"\n=== Validation {source_label} ===")
    print(f"  {note_count} notes complètes, {spec_section_count} sections de spé, "
          f"{reminder_count} rappels")
    for message in warnings[:25]:
        print(f"[WARN] {message}")
    if len(warnings) > 25:
        print(f"[WARN] … {len(warnings) - 25} avertissements supplémentaires")
    for message in errors:
        print(f"[ERR ] {message}")
    if errors:
        raise RuntimeError(
            f"Validation échouée : {len(errors)} erreur(s), aucun fichier produit.")
    print(f"  Validation réussie ({len(warnings)} avertissement(s)).")


def addon_root(args, out_file=None):
    """Dossier de l'addon : --addon-dir, sinon le dossier du fichier de sortie."""
    if args.addon_dir:
        return os.path.abspath(args.addon_dir)
    return os.path.dirname(os.path.abspath(out_file or args.out))


def ensure_toc_entry(hint_dir, entry):
    """Ajoute `entry` au .toc, juste avant Core\\Core.lua, si elle n'y est pas.

    Pour les fichiers qui ne dependent d'aucune source (Phases.lua,
    BossTimelines.lua, Spells.lua) : ils vivent HORS des blocs
    « # BEGIN <SOURCE> DATA », pour ne pas etre emportes par
    prune_stale_toc_entries quand une source ne genere rien."""
    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if not os.path.isfile(toc_path):
        return
    with open(toc_path, encoding="utf-8") as f:
        toc = f.read()
    if entry in toc:
        return
    anchor = "Core\\Core.lua"
    toc = (toc.replace(anchor, entry + "\n" + anchor, 1) if anchor in toc
           else toc.rstrip("\n") + "\n" + entry + "\n")
    write_file_atomic(toc_path, toc)
    print(f"[OK  ] .toc : {entry} ajouté.")


def file_identity(path):
    """(uid, gid, mode) d'un fichier existant, ou None s'il n'existe pas."""
    if os.name != "posix":
        return None
    try:
        st = os.stat(path)
    except OSError:
        return None
    return st.st_uid, st.st_gid, stat_module.S_IMODE(st.st_mode)


def apply_identity(path, identity):
    """Repose proprietaire, groupe et droits sur un fichier qu'on vient de
    reecrire.

    L'ecriture est atomique (fichier temporaire puis os.replace), donc le
    fichier final est un NOUVEL inode : il porte l'utilisateur courant, son
    groupe principal et le umask, et perd ce qu'avait l'ancien. Concretement,
    un fichier `nino:root` en rw-rw-r-- revenait en `nino:nino` apres chaque
    generation, et en `root:root` si le script tournait en sudo — plus
    editable sans repasser en sudo.

    `identity` vient de file_identity() AVANT l'ecriture. A defaut (fichier
    cree pour la premiere fois), on herite du dossier parent, qui est le bon
    reperage dans tous les cas rencontres.

    Silencieux par conception : changer de groupe demande d'appartenir au
    groupe vise, et un echec ne doit jamais interrompre une generation.
    """
    if os.name != "posix":
        return
    uid = gid = mode = None
    if identity:
        uid, gid, mode = identity
    else:
        try:
            st = os.stat(os.path.dirname(os.path.abspath(path)) or ".")
            uid, gid = st.st_uid, st.st_gid
            # Droits alignes sur le dossier, bits d'execution retires : un
            # fichier neuf suit ainsi la convention du dossier (775 -> 664) au
            # lieu de dependre du umask de celui qui lance le script.
            parent_mode = stat_module.S_IMODE(st.st_mode)
            # Un dossier reprend les droits du parent tels quels ; un fichier
            # les reprend sans les bits d'execution (775 -> 664).
            mode = parent_mode if os.path.isdir(path) else parent_mode & 0o666
        except OSError:
            return
    # Lance en sudo : viser l'utilisateur reel plutot que root.
    try:
        if os.geteuid() == 0 and not identity:
            uid = int(os.environ.get("SUDO_UID", uid))
            gid = int(os.environ.get("SUDO_GID", gid))
    except (AttributeError, TypeError, ValueError):
        pass
    try:
        os.chown(path, uid, gid)
    except OSError:
        # Groupe inaccessible : au moins garder le proprietaire.
        try:
            os.chown(path, uid, -1)
        except OSError:
            pass
    if mode is not None:
        try:
            os.chmod(path, mode)
        except OSError:
            pass


def write_file_atomic(path, content):
    """Écriture atomique (fichier temporaire puis remplacement) : l'ancien
    fichier reste intact si l'écriture échoue. Sert à tous les fichiers
    générés (Data/*.lua, Index.lua, Register.lua, .toc)."""
    directory = os.path.dirname(os.path.abspath(path))
    # Tous les dossiers manquants, du plus profond au plus proche de la racine.
    # Les creer puis ne traiter que le dernier ne suffit pas : il heriterait
    # d'un parent cree a la meme seconde, donc deja mauvais. On les reprend
    # dans l'ordre inverse, chacun heritant d'un parent deja corrige.
    missing = []
    probe = directory
    while probe and not os.path.isdir(probe):
        missing.append(probe)
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    os.makedirs(directory, exist_ok=True)
    for created in reversed(missing):
        apply_identity(created, None)
    # Releve AVANT l'ecriture : apres os.replace l'ancien inode a disparu.
    identity = file_identity(path)
    temp_path = path + ".tmp"
    with open(temp_path, "w", encoding="utf-8", newline="\n") as output:
        output.write(content)
    # Pose l'identite sur le TEMPORAIRE : le remplacement reste atomique et le
    # fichier final n'existe jamais avec de mauvais droits, meme une fraction
    # de seconde.
    apply_identity(temp_path, identity)
    os.replace(temp_path, path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def fetch_note(url, cache_hours):
    # cache_hours == 0 (defaut) : pas de cache DU TOUT — ni lecture, ni
    # ecriture, ni meme creation du dossier .cache_viserio/. Avant : le
    # dossier etait toujours cree et rempli, meme quand cache_hours=0
    # servait juste a "ne jamais relire" — le disque se remplissait quand
    # meme pour rien. Voir --cache-hours.
    if cache_hours <= 0:
        print(f"  … téléchargement : {url.rsplit('/', 1)[-1]}")
        time.sleep(1.0)
        r = request_get(url)
        if r is None:
            return None
        if r.status_code != 200:
            print(f"[ERR ] HTTP {r.status_code} pour {url}")
            return None
        return r.text

    cache_dir = ".cache_viserio"
    os.makedirs(cache_dir, exist_ok=True)
    cache_file = os.path.join(cache_dir, url.rsplit("/", 1)[-1] + ".html")
    if cache_is_fresh(cache_file, cache_hours):
        with open(cache_file, encoding="utf-8") as cf:
            return cf.read()
    print(f"  … téléchargement : {url.rsplit('/', 1)[-1]}")
    time.sleep(1.0)
    r = request_get(url)
    if r is None:
        return None
    if r.status_code != 200:
        print(f"[ERR ] HTTP {r.status_code} pour {url}")
        return None
    with open(cache_file, "w", encoding="utf-8") as cf:
        cf.write(r.text)
    return r.text



# ---------------------------------------------------------------------------
# Source WoW Timeline : top parses Warcraft Logs par spé et par boss
# ---------------------------------------------------------------------------

# Nombre d'observations en dessous duquel on ne tire aucune conclusion
# statistique d'une distribution (sert au reperage des phases volatiles).
PHASE_MIN_SAMPLES = 20

# Au-dela de cet ecart entre le pull le plus rapide et le plus lent, une
# transition de phase n'est pas pilotee par un minuteur et aucune valeur unique
# ne peut la representer. 20 s : Entombed Sentinels derive de 8 a 21 s et reste
# exploitable, Nek'zali s'etale sur 102 s et ne l'est pas.
PHASE_SPREAD_WARN = 20.0

_SPELL_META = None


def spell_meta_table(cache_hours):
    """{spell_id: {"cooldown": s, "name": str, "spell_type": str}} depuis
    /api/spells, l'endpoint dont le site se sert pour dessiner ses barres de
    cooldown. Une seule requete par execution.

    En cas d'echec on renvoie {} : le filtrage est alors simplement desactive,
    jamais bloquant.
    """
    global _SPELL_META
    if _SPELL_META is not None:
        return _SPELL_META
    _SPELL_META = {}
    data, _ = source_get("/spells", cache_hours)
    if not isinstance(data, dict):
        print("[WARN] /api/spells illisible : pas de contrôle de cooldown.")
        return _SPELL_META
    for key, entry in data.items():
        if not isinstance(entry, dict):
            continue
        try:
            sid = int(entry.get("spell_id") or key)
        except (TypeError, ValueError):
            continue
        try:
            cd = float(entry.get("cooldown") or 0)
        except (TypeError, ValueError):
            cd = 0.0
        # Duree de l'effet, servie par le meme endpoint. Elle ne sert pas au
        # filtrage, mais l'addon en a besoin pour dessiner la barre "effet
        # actif" a cote de la barre "en recharge", comme le fait le site.
        try:
            dur = float(entry.get("duration") or 0)
        except (TypeError, ValueError):
            dur = 0.0
        _SPELL_META[sid] = {
            "cooldown": cd,
            "duration": dur,
            "name": entry.get("name") or "",
            "spell_type": entry.get("spell_type") or "",
        }
    print(f"  {len(_SPELL_META)} sorts connus de WoW Timeline (cooldowns)")
    return _SPELL_META


def is_foreign_cast(spell_id, meta):
    """True si ce sort n'est pas lance PAR le joueur classe.

    L'API fait figurer sur la timeline d'un joueur les externals qu'il a
    RECUS : verifie sur Innervate (29166), donne comme
    spell_type "other-externals" et present 14 fois chez des chamans
    restauration, qui ne peuvent pas le lancer. Un rappel demandant a un
    chaman d'appuyer sur Innervate n'a aucun sens.

    On ne filtre QUE sur cette valeur, seule categorie verifiee. Les types
    inconnus, vides ou non reconnus sont conserves : mieux vaut un rappel en
    trop qu'un bijou supprime parce que sa categorie ne nous disait rien.
    """
    stype = (meta.get(spell_id) or {}).get("spell_type") or ""
    return stype.startswith("other-external")


def api_fetch(url, cache_hours):
    """GET sur UNE racine d'API. Renvoie (donnees, ok).

    `ok` separe deux cas que l'ancien code confondait en renvoyant None :
      - ok=False : l'API n'a pas repondu correctement (reseau, code HTTP,
        corps non-JSON). C'est le seul cas qui justifie un repli.
      - ok=True avec donnees vides : l'API a repondu, et sa reponse est
        "rien". Un 404 ou des reports vides sont des REPONSES legitimes
        (une spe sans parse sur ce boss), pas des pannes. Replier dessus
        doublerait le nombre d'appels pour toutes les spes sans donnee.
    """
    # cache_hours <= 0 (defaut) : pas de cache DU TOUT — voir le meme
    # commentaire dans fetch_note().
    cache_dir = ".cache_wowtimeline"
    cache_file = None
    if cache_hours > 0:
        os.makedirs(cache_dir, exist_ok=True)
        host = urllib.parse.urlparse(url).netloc
        key = re.sub(r"[^a-z0-9]+", "_", (host + "_" + url.split("/api/")[-1]).lower())
        cache_file = os.path.join(cache_dir, key + ".json")
        if cache_is_fresh(cache_file, cache_hours):
            try:
                with open(cache_file, encoding="utf-8") as f:
                    return json.load(f), True
            except (OSError, ValueError):
                print(f"[WARN] Cache invalide, nouveau téléchargement : {cache_file}")
    time.sleep(1.0)
    try:
        r = request_get(url)
    except Exception as e:
        print(f"[erreur] {url} — {e}")
        return None, False
    if r is None:
        return None, False
    if r.status_code == 404:
        data = {}
    elif r.status_code != 200:
        print(f"[http {r.status_code}] {url}")
        return None, False
    else:
        try:
            data = r.json()
        except ValueError:
            # Avant : échec avalé en silence (return None sans rien
            # afficher), ce qui donnait "0 spés" partout sans aucun indice
            # sur la cause réelle (ex. page de blocage anti-bot renvoyée
            # avec un code 200 mais un corps HTML au lieu de JSON).
            ctype = r.headers.get("Content-Type", "?")
            snippet = r.text[:200].replace("\n", " ") if r.text else "(vide)"
            print(f"[JSON invalide] {url}")
            print(f"    Content-Type: {ctype}")
            print(f"    Début de la réponse : {snippet!r}")
            return None, False
    if isinstance(data, dict) and "reports" not in data and "/spec_ranking/" in url:
        # Schéma inattendu pour cet endpoint précis : ni "reports" ni objet
        # vide franc. Peut signaler un changement de schéma côté API plutôt
        # qu'un vrai résultat vide — on le signale une fois plutôt que de
        # traiter ça silencieusement comme "aucun parse pour cette spé".
        print(f"[WARN] Pas de clé 'reports' dans la réponse de {url} "
              f"— clés reçues : {sorted(data.keys())}")
    # On ne met en cache que les résultats non vides, et seulement si le
    # cache est actif (cache_file non None). Un résultat vide (404, ou
    # JSON {}/[]) est souvent légitime (ex. un boss sans ranking pour
    # telle spé) mais peut aussi être une erreur transitoire (service
    # indisponible, rate-limit, endpoint temporairement cassé) — surtout sur les
    # endpoints critiques /zones et /specs. Ne pas le cacher évite qu'un
    # faux "vide" reste figé jusqu'à --cache-hours et bloque tout le build
    # derrière un message "aucune donnée" trompeur.
    if data and cache_file:
        with open(cache_file, "w", encoding="utf-8") as f:
            json.dump(data, f)
    return data, True


def _write_toplogs_boss_file(data_root, enc_id, plans, encounter_names):
    """Écrit le fichier Data/WowTimeline/<Boss>.lua d'UN SEUL boss (extrait de
    write_toplogs_boss_files pour pouvoir être appelé boss par boss, au fil
    de l'eau, plutôt qu'une seule fois à la toute fin — voir build_toplogs.
    Retourne le nom de fichier écrit."""
    base = slugify(canonical_boss_name(enc_id, encounter_names.get(enc_id, ""))) or f"encounter-{enc_id}"
    filename = f"{base}.lua"
    lines = [
        "-- Généré par NSRTAutoReminders-build.py — ne pas éditer.",
        "local ADDON_NAME, EP = ...",
        "EP.WowTimelinePlans = EP.WowTimelinePlans or {}",
        f"EP.WowTimelinePlans[{enc_id}] = {{ -- {encounter_names.get(enc_id, '')}",
    ]
    # Mythic avant Heroic dans les données générées (et donc dans l'ordre
    # d'affichage du menu déroulant de l'addon) — un tri alphabétique brut
    # mettrait "Heroic" avant "Mythic".
    diffs = sorted(
        {d for (e, d, _) in plans if e == enc_id},
        key=lambda d: (0 if d == "Mythic" else 1, d))
    for diff in diffs:
        lines.append(f'    ["{diff}"] = {{')
        spec_ids = sorted({s for (e, d, s) in plans if e == enc_id and d == diff})
        for spec_id in spec_ids:
            lines.append(f"        [{spec_id}] = {{")
            for variant in plans[(enc_id, diff, spec_id)]:
                lines.append("            {")
                lines.append(f'                name = "{lua_escape(variant["name"])}",')
                lines.append(f'                author = "{lua_escape(variant["author"])}",')
                # Duree REELLE du combat, calculee sur les temps absolus et
                # transportee depuis build_toplogs. Depuis le passage aux
                # phases, c[0] est un temps RELATIF au debut de sa phase :
                # en prendre le max donnait la duree de la plus longue
                # phase, pas celle du combat. Sur un boss en 7 phases comme
                # The Lost Explorers, un log de 6 minutes s'affichait en
                # "1:14" et la timeline paraissait tronquee de moitie.
                duration = variant.get("duration") or max(
                    (c[0] for c in variant["casts"]), default=0)
                lines.append(f"                duration = {duration},")
                # Debut absolu de chaque phase dans ce log : permet a l'addon
                # d'afficher une piste chronologique correcte a partir de
                # temps qui sont, eux, relatifs a leur phase.
                starts = variant.get("phase_starts") or {}
                if starts:
                    pairs = ", ".join(
                        f"[{format_lua_phase(p)}] = {int(v)}"
                        for p, v in sorted(starts.items()))
                    lines.append(f"                phaseStarts = {{ {pairs} }},")
                lines.append("                reminders = {")
                for cast in variant["casts"]:
                    seconds, spell, phase = cast[0], cast[1], cast[2]
                    # spellID 0 : aucun sort reel (NSRT n'afficherait rien).
                    if not spell or int(spell) <= 0:
                        continue
                    lines.append(
                        f"                    {{ time = {seconds}, "
                        f"ph = {format_lua_phase(phase)}, "
                        f"spellid = {spell} }},")
                lines.append("                },")
                lines.append("            },")
            lines.append("        },")
        lines.append("    },")
    lines.extend(("}", ""))
    write_file_atomic(os.path.join(data_root, filename), "\n".join(lines))
    return filename


def write_toplogs_boss_files(output_hint, plans, raids_order, current_season,
                             plans_raid_map, encounter_names, raid_metadata,
                             addon_dir=None):
    """Écrit les données des top logs : un fichier Lua par boss
    (Data/WowTimeline/<Boss>.lua), regroupant toutes les spés et difficultés de
    ce boss. Régénère systématiquement tous les fichiers de boss présents dans
    plans et supprime les fichiers orphelins (boss retiré). Le bloc
    « # BEGIN TOPLOGS DATA » du .toc est reconstruit à partir de
    Data/WowTimeline/*.lua. (Les restes de l'ancienne source Lorrgs sont
    retirés au début du run par migrate_lorrgs_layout.)

    Les fichiers par boss ont déjà été écrits au fil de l'eau par
    build_toplogs (voir _write_toplogs_boss_file) : les réécrire ici est sans
    effet (mêmes données) mais garantit un état cohérent même si l'écriture
    incrémentale a été sautée pour une raison quelconque. Cette fonction
    reste seule responsable d'Index.lua, du nettoyage des orphelins, de
    Register.lua et du .toc, qui n'ont de sens qu'une fois TOUS les boss
    connus (pas boss par boss)."""
    hint_dir = os.path.abspath(addon_dir) if addon_dir else os.path.dirname(os.path.abspath(output_hint))
    data_root = os.path.join(hint_dir, "Data", "WowTimeline")
    os.makedirs(data_root, exist_ok=True)

    index = [
        "-- Généré par NSRTAutoReminders-build.py — ne pas éditer.",
        "-- Source : WoW Timeline (Top Logs)",
        "local ADDON_NAME, EP = ...",
        "EP.WowTimelineRaid = {",
    ]
    ordered = (
        [r for r in raids_order
         if raid_metadata.get(r, {}).get("season") == current_season]
        + [r for r in raids_order
           if raid_metadata.get(r, {}).get("season") != current_season]
    )
    for raid in ordered:
        encs = sorted(
            (e for e in encounter_names if plans_raid_map.get(e) == raid),
            key=boss_sort_key)
        meta = raid_metadata.get(raid, {})
        index.append(
            f'    {{ name = "{lua_escape(raid)}", '
            f'season = {meta.get("season") or 0}, '
            f'current = {"true" if meta.get("season") == current_season else "false"}, '
            f'encounters = {{ {", ".join(map(str, encs))} }} }},')
    index.extend(("}", "EP.WowTimelineEncounterNames = {"))
    for enc_id in sorted(encounter_names):
        index.append(f'    [{enc_id}] = "{lua_escape(encounter_names[enc_id])}",')
    index.extend(("}", ""))
    write_file_atomic(os.path.join(data_root, "Index.lua"), "\n".join(index))

    kept_filenames = set()
    encs_with_fresh_data = {e for (e, _, _) in plans}
    all_known_encs = sorted(encounter_names.keys())
    for enc_id in all_known_encs:
        base = slugify(canonical_boss_name(enc_id, encounter_names.get(enc_id, ""))) or f"encounter-{enc_id}"
        filename = f"{base}.lua"
        kept_filenames.add(filename)
        if enc_id in encs_with_fresh_data:
            _write_toplogs_boss_file(data_root, enc_id, plans, encounter_names)
        # Sinon (boss amorcé depuis un Index.lua précédent mais pas encore
        # retraité par CETTE exécution) : le fichier existant est déjà
        # correct — on le laisse tel quel plutôt que de l'écraser avec un
        # bloc EP.WowTimelinePlans[enc_id] vide, ce qui perdrait ses données.

    for existing in os.listdir(data_root):
        if existing in ("Index.lua", "Register.lua"):
            continue
        if existing.endswith(".lua") and existing not in kept_filenames:
            os.remove(os.path.join(data_root, existing))

    register = f"""local ADDON_NAME, EP = ...
EP.RegisterSource({{
    id = "wowtimeline",
    label = "WoW Timeline (Top Logs)",
    GeneratedAt = "{datetime.date.today().isoformat()}",
    CurrentSeason = {current_season},
    Raid = EP.WowTimelineRaid,
    EncounterNames = EP.WowTimelineEncounterNames,
    Plans = EP.WowTimelinePlans,
}})
"""
    write_file_atomic(os.path.join(data_root, "Register.lua"), register)

    toc_entries = [r"Data\WowTimeline\Index.lua"]
    for filename in sorted(kept_filenames):
        toc_entries.append(os.path.join("Data", "WowTimeline", filename).replace(os.sep, "\\"))
    toc_entries.append(r"Data\WowTimeline\Register.lua")

    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if os.path.isfile(toc_path):
        with open(toc_path, encoding="utf-8") as f:
            toc = f.read()
        begin, end = "# BEGIN TOPLOGS DATA", "# END TOPLOGS DATA"
        block = begin + "\n" + "\n".join(toc_entries) + "\n" + end
        if begin in toc and end in toc:
            toc = re.sub(
                re.escape(begin) + r".*?" + re.escape(end), lambda _: block, toc, flags=re.S)
        else:
            anchor = "Sources.lua"
            toc = toc.replace(anchor, anchor + "\n" + block, 1) if anchor in toc else (
                toc.rstrip("\n") + "\n" + block + "\n")
        write_file_atomic(toc_path, toc)
    else:
        write_file_atomic(
            os.path.join(data_root, "TOC_entries.txt"),
            "\n".join(toc_entries) + "\n")
        print(
            f"  [ATTENTION] Aucun NSRTAutoReminders.toc trouvé dans "
            f"{hint_dir} — le .toc N'A PAS été mis à jour automatiquement. "
            f"La liste des fichiers a été écrite dans "
            f"{os.path.join(data_root, 'TOC_entries.txt')} à défaut. "
            f"Relance avec --addon-dir pointant vers le dossier de l'addon "
            f"en jeu pour que ce soit fait automatiquement la prochaine fois."
        )

    return data_root, len(toc_entries) - 2


# Debuts de phase REELLEMENT observes dans les top logs, par (encID,
# difficulte, phase) -> [secondes]. Rempli pendant build_toplogs, consomme par
# write_phase_table : la mediane des vrais pulls est la seule reference
# pour les notes Viserio, la ou BossTimelines n'etait qu'UN pull
# enregistre a la main. Ecart mesure sur Nek'zali Mythique : la table figee
# annonce l'intermission a 197,9 s, les logs la placent entre 102 et 163 s.
OBSERVED_PHASE_STARTS = defaultdict(list)


def build_toplogs(args):
    out_file = args.out if args.out != "Data_Viserio.lua" else "Data_WowTimeline.lua"
    current = args.current_season

    # Calculé ici (même logique que dans write_toplogs_boss_files) pour
    # pouvoir écrire chaque boss — ET tenir Index.lua/Register.lua/.toc à
    # jour — au fil de l'eau, dès que ses spés sont toutes traitées, plutôt
    # que d'attendre la toute fin de l'étape 3/3. Avant : une interruption
    # (Ctrl+C, erreur réseau fatale) pendant l'étape 3/3 perdait TOUT le
    # travail déjà fait, même si 8 boss sur 9 avaient déjà répondu — rien
    # n'était écrit avant la fin de la boucle complète, y compris le .toc
    # qui ne référençait donc jamais les boss fraîchement traités tant que
    # le run entier n'avait pas fini.
    hint_dir = addon_root(args, out_file)
    data_root = os.path.join(hint_dir, "Data", "WowTimeline")

    # Les phases d'une timeline viennent du log lui-meme (phase_id + ts).
    # Les bornes servies aux notes Viserio (Data/Phases.lua) en sont la
    # mediane, relevee ici dans OBSERVED_PHASE_STARTS — voir
    # write_phase_table. Aucune table de reference n'intervient.

    print("\n=== Étape 1/3 : boss et raids (WoW Timeline) ===")
    zones, _ = source_get("/zones", args.cache_hours)
    zones = zones or []
    zone_list = zones.get("zones", []) if isinstance(zones, dict) else zones
    boss_info = {}    # slug -> (encID, nom, raid, saison)
    for z in zone_list:
        zname = z.get("name") or "?"
        # normalisation agressive (sans tirets ni apostrophes) pour matcher
        # "March on Quel'Danas" avec notre slug "march-on-queldanas"
        z_norm = re.sub(r"[^a-z0-9]", "", zname.lower())
        season, raid_name = 0, zname
        for known_slug, known_season in SEASONS.items():
            if known_slug.replace("-", "") in z_norm:
                season = known_season
                raid_name = RAID_NAMES.get(known_slug, zname)
        for b in z.get("bosses", []):
            slug = b.get("full_name_slug")
            enc = b.get("id")
            name = b.get("full_name") or b.get("name")
            if slug and enc:
                # Nom de zone inconnu : on rattache par ID de rencontre
                # plutot que de laisser la saison a 0 (voir ENCOUNTER_SEASONS).
                boss_season = season or ENCOUNTER_SEASONS.get(enc, 0)
                if boss_season and not season:
                    print(f"  [INFO] {name} rattaché à la saison "
                          f"{boss_season} par son ID ({enc}) — zone "
                          f"\"{zname}\" absente de SEASONS.")
                # Le raid vient de Viserio (RAID_BY_ENCOUNTER) ; le nom de
                # zone de l'API des top logs n'est qu'un repli, car il suit
                # le decoupage de Warcraft Logs et peut couvrir plusieurs
                # raids a la fois.
                boss_raid = RAID_BY_ENCOUNTER.get(enc) or raid_name
                boss_info[slug] = (enc, name, boss_raid, boss_season)
    if not boss_info:
        raise SourceBuildAborted(
            "WoW Timeline : aucune donnée de zones. Copie ce message à Claude.")
    print(f"  {len(boss_info)} boss connus, {len(zone_list)} raids")

    dropped = sum(1 for v in boss_info.values() if v[3] == 0)
    boss_info = {s: v for s, v in boss_info.items() if v[3] != 0}
    if dropped:
        print(f"  {dropped} boss d'anciennes extensions ignorés (hors Midnight)")
    if (args.season or "current") != "all":
        boss_info = {s: v for s, v in boss_info.items() if v[3] == current}
        print(f"  filtre saison courante ({current}) : {len(boss_info)} boss retenus")
    if args.raid:
        boss_info = {s: v for s, v in boss_info.items() if args.raid in v[2].lower()}

    print("\n=== Étape 2/3 : spécialisations ===")
    specs, _ = source_get("/specs", args.cache_hours)
    specs = specs or []
    spec_list = specs.get("specs", []) if isinstance(specs, dict) else specs
    spec_slugs = {}   # slug -> (specID, metric)
    for s in spec_list:
        slug = s.get("full_name_slug", "")
        cls, _, spec = slug.partition("-")
        spec_id = SPEC_IDS.get((cls, spec)) or SPEC_IDS.get((cls, spec.replace("-", "")))
        if spec_id:
            spec_slugs[slug] = (spec_id, metric_for_spec(cls, spec))
        elif cls == "other":
            pass  # pseudo-catégories (externals/potions/trinkets), pas des spés
        else:
            print(f"[WARN] Spé inconnue : {slug} (à ajouter dans SPEC_IDS)")
    print(f"  {len(spec_slugs)} spécialisations")

    print(f"\n=== Étape 3/3 : top parses ({len(boss_info)} boss x {len(spec_slugs)} spés) ===")
    plans = defaultdict(list)
    plans_raid, enc_names, raids_meta = {}, {}, {}
    raids_order = []
    warned_no_phases = set()
    warned_refused = set()
    # Phases reellement emises par boss, pour le controle de coherence en fin
    # de boss : les boss dont "allowed" vaut None ne sont pas bornes, donc un
    # log qui annonce plus de phases que NSRT n'en gere (The Lost Explorers
    # monte a phase_id 7 alors que NSRT n'en connait que 5) produit des rappels
    # dans une phase que StartReminders n'ouvre peut-etre jamais.
    phases_emitted = defaultdict(set)
    # Casts ecartes parce que le sort etait encore en recharge, et un exemple
    # par sort pour que le resume de fin soit verifiable.
    foreign_dropped = 0
    foreign_examples = {}
    spell_meta = spell_meta_table(args.cache_hours)

    # Amorcage : les boss pas encore retraites par la boucle ci-dessous
    # doivent figurer dans Index.lua/.toc, sinon chaque ecriture
    # incrementale les ferait disparaitre (et le nettoyage des orphelins
    # supprimerait leurs fichiers) jusqu'a ce que leur tour vienne.
    #
    # L'amorcage vient de `boss_info`, c'est-a-dire la REPONSE DU JOUR de
    # /zones — et NON de l'Index.lua du run precedent.
    #
    # C'est la correction d'un vrai defaut : le rattachement boss -> raid
    # n'etait reecrit que si le boss avait rendu au moins une spe ce run
    # (`if not added_any: continue`). Un boss liste par l'API mais sans
    # parse exploitable gardait donc, indefiniment, le raid du run
    # precedent, et une erreur de classement devenait permanente : seul un
    # effacement manuel d'Index.lua en sortait.
    for enc, bname, raid_name, season in sorted(boss_info.values()):
        enc_names[enc] = bname
        plans_raid[enc] = raid_name
        raids_meta[raid_name] = {"season": season}
        if raid_name not in raids_order:
            raids_order.append(raid_name)

    # Repli Mythic -> Heroic : un raid tout juste sorti (contenu "current")
    # peut n'avoir aucun log Mythic pendant plusieurs semaines,
    # le temps que les guildes progressent, alors que l'Héroïque est déjà
    # bien fourni. Avant : difficulté "mythic" figée en dur, donc un raid
    # en cours de progression Mythic ne remontait STRICTEMENT rien (0 spés
    # partout) même quand des données Héroïque existaient bel et bien.
    # --difficulty force une difficulté unique (comportement explicite,
    # pas de repli) ; sans l'option, on tente mythic puis heroic par
    # boss/spé et on garde ce qui répond.
    if args.difficulty:
        difficulties_to_try = [args.difficulty]
    else:
        difficulties_to_try = ["mythic", "heroic"]

    for bslug, (enc, bname, raid, season) in sorted(boss_info.items()):
        for sslug, (spec_id, metric) in sorted(spec_slugs.items()):
            added_any = False
            # On garde les DEUX difficultés séparément (au lieu de choisir
            # Mythic OU Heroic) : --top logs de chaque, l'une n'excluant
            # plus l'autre. Utile tant qu'une progression Mythic est encore
            # naissante — les logs Heroic (souvent plus stables/nombreux à
            # ce stade) restent visibles à côté des Mythic dans l'addon
            # plutôt que d'être totalement écartés dès qu'un seul parse
            # Mythic existe.
            for difficulty in difficulties_to_try:
                # &metric=... est requis par l'API depuis Midnight S2 —
                # confirme via l'onglet Reseau du navigateur (la requete
                # reelle envoyee par lorrgs.io est bien
                # ".../entombed-sentinels?difficulty=heroic&metric=dps").
                # Sans ce parametre l'API repond 200 avec un JSON valide
                # mais "reports": [] — pas d'erreur, juste un resultat vide
                # qui donnait "0 spes" partout sans aucun indice. dps pour
                # les DPS/tanks, hps pour les soigneurs (voir metric plus
                # haut), sinon l'API semble ignorer les logs de heal.
                data, source = fetch_spec_ranking(
                    sslug, bslug, enc, difficulty, metric, args.cache_hours)
                reports = (data or {}).get("reports") or []
                if not reports:
                    continue
                SOURCE_COUNTS[source] += 1
                used_difficulty = difficulty.capitalize()
                # Rang REEL de chaque log dans le classement, conserve meme
                # quand un log mieux classe est ecarte (combat trop court) :
                # « Top #2 » reste le 2e du classement, pas le 1er retenu.
                ranked = list(enumerate(reports, start=1))
                durations = []
                for _, rep_ in ranked:
                    try:
                        durations.append(rep_["fights"][0].get("duration") or 0)
                    except (KeyError, IndexError, AttributeError):
                        durations.append(0)
                limit = short_fight_limit(durations)
                if limit is not None:
                    kept = []
                    for (rank_, rep_), dur in zip(ranked, durations):
                        if dur and dur < limit:
                            try:
                                who = rep_["fights"][0]["players"][0].get("name")
                            except (KeyError, IndexError, AttributeError):
                                who = "?"
                            SHORT_FIGHTS.append((enc, used_difficulty, spec_id, who,
                                                 round(dur / 1000),
                                                 round(limit / SHORT_FIGHT_SHARE / 1000)))
                            continue
                        kept.append((rank_, rep_))
                    ranked = kept
                top_n = args.top if args.top and args.top > 0 else len(ranked)
                selected = ranked[:top_n]
                # WoW Timeline ajoute un « Plan consensus » : les moments communs
                # a la majorite du top, plus fiables que le plan d'un seul joueur.
                # Il vient en plus des --top logs, sans en prendre la place.
                if source == "wowtimeline" and not args.no_consensus:
                    selected += [(None, r) for r in (data or {}).get("extra_reports") or []]
                for rank, report in selected:
                    try:
                        fight = report["fights"][0]
                        player = fight["players"][0]
                        casts = player.get("casts") or []
                    except (KeyError, IndexError):
                        continue
                    # Modele de phases RUNTIME : il ne sert plus qu'a savoir
                    # QUELLES phases NSRT peut atteindre et a traduire la
                    # convention du report ; les instants viennent du log
                    # lui-meme (phase_id + ts). Un boss absent de la table est
                    # traite comme "aucune phase" (tout en ph:1, temps
                    # absolus) : comportement d'avant les phases, sans risque
                    # de produire des rappels injouables.
                    model = phase_model_for(enc)
                    if model is None and enc not in warned_no_phases:
                        warned_no_phases.add(enc)
                        print(f"[WARN] {bname} : aucune donnee de phase chez NSRT — "
                              f"tout en phase 1 (temps absolus).")
                    # Controle avant usage : un log dont les phases ne se
                    # rangent pas dans le modele NSRT est ecarte (voir
                    # phase_refusal) au lieu d'etre devine.
                    transitions = log_phase_transitions(fight)
                    check = PHASE_CHECK[enc]
                    check[0] += 1
                    check[2].update(out_of_model_phases(transitions, model))
                    refusal = phase_refusal(enc, transitions, model)
                    if refusal:
                        check[1] += 1
                        if enc not in warned_refused:
                            warned_refused.add(enc)
                            print(f"[REFUS] {bname} : {refusal}. Logs ecartes ; "
                                  f"ajouter ce boss a NSRT_RUNTIME_PHASES.")
                        continue
                    # Phases REELLES de ce log : instants ET numeros donnes
                    # par l'API, traduits dans la convention NSRT.
                    resolved = resolve_log_phases(transitions, model)
                    for start_s, ph in resolved:
                        if start_s > 0:
                            OBSERVED_PHASE_STARTS[
                                (enc, used_difficulty, ph)].append(start_s)
                    # Capacites du boss DANS CE LOG : instants reels, pas une
                    # table de reference. Ne sert qu'a construire le
                    # deroulement affiche a cote des rappels (BossTimelines) :
                    # aucun rappel n'est rattache a une capacite, faute de
                    # donnee etablissant ce lien.
                    #
                    # DEDOUBLONNAGE EXACT sur le couple (ts, id). Une capacite
                    # qui touche tout le raid est journalisee une fois PAR
                    # CIBLE, au meme horodatage a la milliseconde pres : sur
                    # Nek'zali Heroique, le sort 1297624 apparait 31 fois a
                    # ts=3037 puis 12 fois a ts=4049. Numerotees par
                    # occurrence, ces 43 lignes devenaient "Brulure rituelle
                    # (1)" a "(43)" en deux secondes dans l'addon.
                    #
                    # Ce n'est pas une tolerance : les horodatages sont
                    # IDENTIQUES, donc c'est la meme incantation, pas deux.
                    # On garde un `set` plutot qu'une fenetre, pour ne jamais
                    # fusionner deux incantations reellement distinctes.
                    #
                    # (Le Mythique de ce meme boss n'a pas le defaut — 12
                    # incantations en tout. Avoir mesure sur le Mythique seul
                    # m'avait fait conclure a tort qu'il n'y avait rien a
                    # dedoublonner.)
                    boss_casts = sorted({
                        (c.get("ts"), c.get("id"))
                        for c in ((fight.get("boss") or {}).get("casts") or [])
                        if c.get("ts") is not None and c.get("id") is not None})
                    # Deroulement du boss, pour l'afficher a cote des rappels.
                    # Numerote par occurrence : "Ravage (3)" n'est pas au meme
                    # instant que "Ravage (1)".
                    if boss_casts:
                        occ = defaultdict(int)
                        for bts, bspell in boss_casts:
                            occ[bspell] += 1
                            OBSERVED_BOSS_CASTS[
                                (enc, used_difficulty, bspell, occ[bspell])
                            ].append(bts / 1000.0)
                    seen, reminders = set(), []
                    # Duree du combat en temps ABSOLU. Indispensable depuis
                    # le passage aux phases : les temps stockes dans
                    # `reminders` repartent de zero a chaque phase et ne
                    # permettent donc plus de deduire la longueur du log.
                    # `duration` de l'API est en millisecondes ; on retombe
                    # sur le dernier cast absolu si le champ manque.
                    fight_duration = (fight.get("duration") or 0) // 1000
                    last_cast_abs = 0
                    phase_starts = {}
                    for c in casts:
                        spell, ts = c.get("id"), c.get("ts")
                        if spell is None or ts is None:
                            continue
                        # Sort recu d'un autre joueur : pas une action de
                        # celui a qui la note est destinee.
                        if is_foreign_cast(spell, spell_meta):
                            foreign_dropped += 1
                            foreign_examples.setdefault(spell, bname)
                            continue
                        phase, rel_s = nsrt_runtime_phase(ts / 1000.0, resolved)
                        # Debut ABSOLU de cette phase dans CE log. Emis avec
                        # la variante pour que l'addon puisse replacer chaque
                        # rappel sur une piste chronologique : `time` etant
                        # relatif a sa phase, l'apercu superposait sinon
                        # toutes les phases au debut de la piste (marques qui
                        # reculent, duree de piste fausse).
                        phase_starts[phase] = int(ts / 1000.0 - rel_s)
                        # Temps RELATIF au debut de la phase : verifie dans
                        # le code source de NSRT (Reminders.lua). NSRT
                        # appelle StartReminders(phase) a chaque changement
                        # de phase ; cette fonction remet a zero
                        # self.ReminderTimer puis planifie les rappels de
                        # la phase via C_Timer.NewTimer(info.time-info.dur).
                        # Le timer part donc du DEBUT DE LA PHASE, et tous
                        # les timers de la phase precedente sont annules.
                        # C'est la cause du bug remonte : un rappel ecrit
                        # {time:126, ph:1} lancait un timer de 126 s au
                        # pull, detruit au passage en phase 2 (~60-90 s sur
                        # Entombed Sentinels) avant d'avoir tire — rappel
                        # jamais affiche, sans aucune erreur.
                        seconds = int(rel_s)
                        # Dedup par (sort, phase, seconde) : deux casts du
                        # meme sort peuvent tomber a la meme seconde
                        # RELATIVE dans deux phases differentes sans etre
                        # des doublons.
                        if (spell, phase, seconds) in seen:
                            continue
                        seen.add((spell, phase, seconds))
                        last_cast_abs = max(last_cast_abs, ts // 1000)
                        phases_emitted[enc].add(phase)
                        reminders.append((seconds, spell, phase))
                    if not reminders:
                        continue
                    # Tri par (phase, temps) : les phases doivent rester
                    # groupees et dans l'ordre, sinon les temps relatifs
                    # s'entremelent d'une phase a l'autre.
                    reminders.sort(key=lambda r: (r[2], r[0]))
                    pname = player.get("name") or "?"
                    plans[(enc, used_difficulty, spec_id)].append({
                        "name": f"Top #{rank} : {pname}" if rank else pname,
                        "author": SOURCE_LABELS[source],
                        "casts": reminders,
                        "duration": max(fight_duration, last_cast_abs),
                        "phase_starts": dict(phase_starts),
                    })
                    added_any = True
            if not added_any:
                continue
            enc_names[enc] = bname
            plans_raid[enc] = raid
            raids_meta[raid] = {"season": season}
            if raid not in raids_order:
                raids_order.append(raid)
        print(f"[OK  ] {bname} : "
              f"{sum(1 for k in plans if k[0] == enc)} spés")

        # Contrôle de cohérence : aucun rappel ne doit sortir en dehors de la
        # phase 1, et aucune phase émise ne doit manquer au modèle runtime.
        # Les deux cas produisent des rappels que StartReminders ne déclenchera
        # jamais, sans la moindre erreur visible en jeu.
        #
        # Le plafond ne vient plus de BossTimelines : un modèle borné filtre
        # déjà en amont (resolve_log_phases), donc seule la phase 1 reste à
        # vérifier. Pour un modèle non borné, il n'y a rien à plafonner —
        # NSRT incrémente sans limite sur ces boss.
        emitted = phases_emitted.get(enc) or set()
        if emitted:
            if 1 not in emitted:
                print(f"[WARN] {bname} : aucun rappel en phase 1 "
                      f"(phases émises : {sorted(emitted)}) — décalage de "
                      f"phase probable, vérifier fight['phases'].")
            model = phase_model_for(enc) or {}
            allowed = model.get("allowed")
            unexpected = sorted(p for p in emitted if allowed and p not in allowed)
            if unexpected:
                print(f"[WARN] {bname} : phases {unexpected} émises alors que "
                      f"le modèle NSRT ne connaît que {allowed} — ces rappels "
                      f"risquent de ne jamais se déclencher.")

        # Écriture incrémentale COMPLETE : dès que ce boss est entièrement
        # traité (toutes ses spés interrogées), son fichier
        # Data/WowTimeline/<boss>.lua ET Index.lua/Register.lua/.toc sont mis à
        # jour tout de suite plutôt que d'attendre les 8 autres boss. Si le
        # script est interrompu juste après, ce boss garde ses nouvelles
        # données ET reste bien référencé dans le .toc — il est donc
        # immédiatement utilisable en jeu, pas seulement présent sur le
        # disque. Sûr grâce à l'amorçage plus haut : les boss pas encore
        # atteints restent référencés avec leurs anciennes données, et ne
        # sont ni effacés ni supprimés par le nettoyage des orphelins.
        write_toplogs_boss_files(
            out_file, plans, raids_order, current, plans_raid, enc_names,
            raids_meta, addon_dir=args.addon_dir)
        print(f"       -> Data/WowTimeline/ et NSRTAutoReminders.toc mis à jour "
              f"({bname})")

    if not plans:
        raise SourceBuildAborted("Rien à générer (API vide ?).")

    top_label = (f"WoW Timeline top {args.top}" if args.top and args.top > 0
                 else "WoW Timeline top logs")
    validate_plans(plans, enc_names, top_label)
    data_root, file_count = write_toplogs_boss_files(
        out_file, plans, raids_order, current, plans_raid, enc_names, raids_meta,
        addon_dir=args.addon_dir)
    bosses = {e for (e, _, _) in plans}
    specs_n = {s for (_, _, s) in plans}
    print(f"\n=== Terminé : {data_root} ===")
    print(f"  {len(raids_order)} raid(s), {len(bosses)} boss, {len(specs_n)} spés, "
          f"{sum(len(v) for v in plans.values())} timelines")
    print(f"  {file_count} fichier(s) de boss dans {data_root}, "
          "un seul par boss (toutes spés et difficultés confondues).")
    print("  Le fichier NSRTAutoReminders.toc a été mis à jour automatiquement "
          "lorsqu'il est trouvé (--addon-dir ou dossier de --out).")

    if foreign_dropped:
        names = ", ".join(
            ((spell_meta.get(sid) or {}).get("name") or str(sid))
            for sid in list(foreign_examples)[:5])
        print(f"\n  {foreign_dropped} cast(s) écarté(s) : sorts reçus d'un "
              f"autre joueur, pas lancés par le destinataire ({names}).")

    if SHORT_FIGHTS:
        by_boss = defaultdict(list)
        for enc_, diff_, spec_, who, dur, med in SHORT_FIGHTS:
            by_boss[(enc_, diff_, dur, med)].append(f"{spec_}:{who}")
        print(f"\n  {len(SHORT_FIGHTS)} combat(s) anormalement court(s) écarté(s) "
              f"(moins de {int(SHORT_FIGHT_SHARE * 100)} % de la durée médiane, "
              f"remplacés par le log suivant du classement) :")
        for (enc_, diff_, dur, med), who in sorted(by_boss.items()):
            print(f"    {enc_} {diff_} : {dur} s pour une médiane de {med} s — "
                  f"{len(who)} log(s) ({', '.join(who[:4])}"
                  + (", ..." if len(who) > 4 else "") + ")")



def migrate_lorrgs_layout(hint_dir):
    """Retire les traces de l'ancienne source Lorrgs dans une installation.

    Lorrgs a ete remplace par WoW Timeline : les donnees s'ecrivent desormais
    sous Data/WowTimeline/. Sans ce nettoyage, l'ancien dossier resterait sur
    le disque ET resterait declare dans le .toc, donc CHARGE par le jeu — on
    aurait deux sources enregistrees, l'ancienne figee a la date de son
    dernier run. Les fichiers concernes sont entierement generes : les
    supprimer ne perd rien qu'un run ne reecrive.

    L'addon migre de son cote le reglage « source active » (voir
    MigrateSourceIds dans Core/Core.lua), pour que la bascule soit invisible.
    """
    removed_files, removed_block = 0, False
    old_dir = os.path.join(hint_dir, "Data", "Lorrgs")
    if os.path.isdir(old_dir):
        for root, _dirs, files in os.walk(old_dir, topdown=False):
            for name in files:
                os.remove(os.path.join(root, name))
                removed_files += 1
            os.rmdir(root)

    old_monolith = os.path.join(hint_dir, "Data_Lorrgs.lua")
    if os.path.isfile(old_monolith):
        os.remove(old_monolith)
        removed_files += 1

    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if os.path.isfile(toc_path):
        with open(toc_path, encoding="utf-8") as f:
            toc = f.read()
        before = toc
        toc = re.sub(r"# BEGIN LORRGS DATA.*?# END LORRGS DATA\n?", "", toc, flags=re.S)
        # Lignes isolees laissees par une version anterieure aux marqueurs.
        toc = "\n".join(l for l in toc.splitlines()
                         if "Data\\Lorrgs\\" not in l and l.strip() != "Data_Lorrgs.lua")
        if not toc.endswith("\n"):
            toc += "\n"
        if toc != before:
            removed_block = True
            write_file_atomic(toc_path, toc)

    if removed_files or removed_block:
        print(f"  [MIGRATION] Ancienne source Lorrgs retiree : "
              f"{removed_files} fichier(s) supprime(s)"
              f"{', bloc .toc retire' if removed_block else ''}.")
    return removed_files, removed_block


def archive_previous_season_if_needed(args):
    """Si la saison qu'on s'apprête à générer est plus récente que celle
    actuellement enregistrée dans Register.lua, archive tout le contenu
    existant de Data/Viserio et Data/WowTimeline (au lieu de le laisser se faire
    silencieusement écraser/supprimer par le nettoyage normal des fichiers
    orphelins) dans Data/Archive/Season<ancienne>/, puis vide les dossiers
    Data/Viserio et Data/WowTimeline pour que la génération reparte sur une base
    propre, saison courante uniquement.
    """
    hint_dir = addon_root(args)

    old_season = None
    register_path = os.path.join(hint_dir, "Data", "Viserio", "Register.lua")
    if os.path.isfile(register_path):
        with open(register_path, encoding="utf-8") as f:
            m = re.search(r"CurrentSeason\s*=\s*(\d+)", f.read())
        if m:
            old_season = int(m.group(1))

    new_season = args.current_season
    if old_season is None or new_season is None or new_season <= old_season:
        return

    print(f"\n=== Nouvelle saison détectée ({old_season} -> {new_season}) : "
          f"archivage de la saison {old_season} ===")
    archive_root = os.path.join(hint_dir, "Data", "Archive", f"Season{old_season}")
    for sub in ("Viserio", "WowTimeline", "Lorrgs"):
        src = os.path.join(hint_dir, "Data", sub)
        if not os.path.isdir(src):
            continue
        dst = os.path.join(archive_root, sub)
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)
        os.makedirs(src, exist_ok=True)
        print(f"  [ARCHIVE] {sub} -> {os.path.relpath(dst, hint_dir)}")
    print(f"  Saison {old_season} conservée intacte dans Data/Archive/, "
          f"mais plus référencée par l'addon (Index.lua régénéré pour la "
          f"saison {new_season} uniquement).")


def cross_check_wcl_viserio(args):
    """Compare tôt, avant toute génération, ce que Warcraft Logs et Viserio
    disent chacun de leur côté sur la saison de chaque rencontre connue —
    plutôt que de laisser une divergence (comme "the-tidebound-grotto" au
    départ) passer inaperçue jusqu'à l'inspection du fichier généré.
    N'utilise que l'API de découverte Viserio (légère, liste seulement —
    pas de téléchargement du contenu de chaque note), donc reste rapide.
    """
    print("\n=== Vérification croisée Warcraft Logs <-> Viserio ===")
    if args.no_wcl:
        print("  --no-wcl actif : vérification ignorée.")
        return

    load_dotenv(args.env_file)
    client_id = os.environ.get("WCL_CLIENT_ID", "").strip()
    client_secret = os.environ.get("WCL_CLIENT_SECRET", "").strip()
    if not client_id or not client_secret:
        print("  Warcraft Logs non configuré : vérification ignorée.")
        return

    try:
        zones = wcl_zones(client_id, client_secret)
    except RuntimeError as exc:
        print(f"  [WARN] {exc} — vérification ignorée.")
        return

    known_encounters = {enc_id for enc_id, _ in BOSSES.values()}
    wcl_season_of = {}
    for zone in zones:
        zone_name = zone.get("name") or ""
        season = known_season_for_raid(zone_name)
        if season is None:
            continue
        for encounter in zone.get("encounters") or []:
            enc_id = encounter.get("id")
            if isinstance(enc_id, int) and enc_id in known_encounters:
                wcl_season_of[enc_id] = (season, zone_name)

    items = discover_api()
    if not items:
        print("  Library Viserio indisponible : vérification ignorée.")
        return

    mismatches = []
    checked = 0
    for it in items:
        resolved = resolve_boss(it.get("bossSlug"))
        if not resolved:
            continue
        enc_id, boss_name = resolved
        raw_slug = it.get("raidSlug") or ""
        viserio_season = SEASONS.get(raw_slug)
        wcl_entry = wcl_season_of.get(enc_id)
        if wcl_entry is None:
            continue
        checked += 1
        wcl_season, wcl_zone_name = wcl_entry
        if viserio_season != wcl_season:
            mismatches.append((boss_name, raw_slug, viserio_season, wcl_zone_name, wcl_season))

    print(f"  {checked} rencontre(s) comparée(s) entre les deux sources.")
    if not mismatches:
        print("  [OK] Aucune divergence — Warcraft Logs et Viserio sont d'accord.")
    else:
        print(f"  [WARN] {len(mismatches)} divergence(s) détectée(s) :")
        seen_slugs = set()
        for boss_name, raw_slug, viserio_season, wcl_zone_name, wcl_season in mismatches:
            print(f"       - {boss_name} : Viserio dit saison {viserio_season} "
                  f"(slug \"{raw_slug}\") mais Warcraft Logs dit saison "
                  f"{wcl_season} (zone \"{wcl_zone_name}\")")
            seen_slugs.add(raw_slug)
        print("       -> vérifie/ajoute ces slugs dans SEASONS et RAID_NAMES "
              "si le nom ou la saison affichée ne te semble pas correcte : "
              + ", ".join(sorted(f'"{s}"' for s in seen_slugs)))

    # Troisième signal, indépendant des deux autres : la liste "saison
    # courante" tenue à la main par NSRT lui-même (voir sync_bosses_from_nsrt).
    if NSRT_CURRENT_ENCOUNTER_IDS:
        current_season_ids = {
            enc_id for enc_id, (season, _) in wcl_season_of.items()
            if season == args.current_season
        }
        missing_in_nsrt = sorted(current_season_ids - NSRT_CURRENT_ENCOUNTER_IDS)
        missing_in_wcl = sorted(NSRT_CURRENT_ENCOUNTER_IDS - current_season_ids)
        if not missing_in_nsrt and not missing_in_wcl:
            print("  [OK] NSRT est d'accord avec Warcraft Logs sur la "
                  "composition de la saison courante.")
        else:
            if missing_in_nsrt:
                print(f"  [WARN] Warcraft Logs classe ces rencontres en "
                      f"saison {args.current_season}, mais NSRT ne les a "
                      f"pas (encore) dans sa liste \"saison courante\" : "
                      f"{missing_in_nsrt}")
            if missing_in_wcl:
                print(f"  [WARN] NSRT classe ces rencontres comme \"saison "
                      f"courante\", mais Warcraft Logs ne les met pas en "
                      f"saison {args.current_season} : {missing_in_wcl}")


# Version d'addon minimale capable de lire ce que ce script produit. A monter
# quand le FORMAT des donnees change (pas a chaque correction du script).
MIN_ADDON_VERSION = (8, 4, 0)


def bump_addon_version(hint_dir):
    """Incremente le dernier nombre de `## Version:` dans NSRTAutoReminders.toc.

    Sert de repere : WoW affiche cette version dans sa liste d'addons, donc un
    numero qui change dit « les donnees de ce dossier ont ete regenerees ».
    Sans ca, rien ne distingue un dossier a jour d'un dossier oublie.

    9.5.0 devient 9.5.1. Une version a deux nombres est d'abord completee
    (9.5 -> 9.5.1) plutot que de sauter une version mineure entiere.

    Le travail se fait sur les OCTETS, pas sur du texte decode : le .toc peut
    porter un BOM et des fins de ligne Windows, et seul le numero doit bouger.
    L'ecriture est atomique et repose proprietaire, groupe et droits — un .toc
    revenu en root:root ne serait plus editable (voir apply_identity).

    Renvoie (ancienne, nouvelle) ou None si rien n'a pu etre fait.
    """
    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if not os.path.isfile(toc_path):
        return None

    with open(toc_path, "rb") as f:
        raw = f.read()

    m = re.search(rb"(?mi)^(##[ \t]*Version[ \t]*:[ \t]*)([0-9]+(?:\.[0-9]+)*)",
                  raw)
    if not m:
        print("[WARN] Pas de ligne '## Version:' dans le .toc : version non "
              "incrementee.")
        return None

    old = m.group(2).decode("ascii")
    parts = [int(x) for x in old.split(".")]
    while len(parts) < 3:
        parts.append(0)
    parts[-1] += 1
    new = ".".join(str(x) for x in parts)

    updated = raw[:m.start(2)] + new.encode("ascii") + raw[m.end(2):]

    identity = file_identity(toc_path)
    tmp = toc_path + ".tmp"
    with open(tmp, "wb") as f:
        f.write(updated)
    apply_identity(tmp, identity)
    os.replace(tmp, toc_path)
    return old, new


def check_addon_version(hint_dir):
    """Avertit quand le script ecrit dans un dossier d'addon plus ancien que
    les donnees qu'il genere.

    Cas reel rencontre : le script est lance sur le dossier installe, il
    rafraichit Data/ et les entrees du .toc, mais l'utilisateur n'a jamais
    remplace les fichiers de l'addon. Resultat, une fenetre qui annonce
    "v8.0.2 - Donnees du 2026-09-29" : des donnees neuves lues par du code qui
    ne sait pas les interpreter, sans le moindre message d'erreur.
    """
    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if not os.path.isfile(toc_path):
        return
    version = None
    with open(toc_path, encoding="utf-8-sig") as f:
        for line in f:
            m = re.match(r"##\s*Version\s*:\s*([0-9.]+)", line)
            if m:
                version = m.group(1)
                break
    if not version:
        return
    try:
        parts = tuple(int(x) for x in version.split("."))
    except ValueError:
        return
    parts = parts + (0,) * (3 - len(parts))
    if parts[:3] < MIN_ADDON_VERSION:
        want = ".".join(str(x) for x in MIN_ADDON_VERSION)
        print(
            f"\n[WARN] L'addon installé dans ce dossier est en v{version}, "
            f"or ces données demandent au moins la v{want}.\n"
            f"       Les fichiers de l'addon n'ont probablement pas été "
            f"remplacés : seul Data/ vient d'être régénéré.\n"
            f"       Dézippe la nouvelle version par-dessus "
            f"{os.path.basename(hint_dir)}, puis relance WoW (un /reload ne "
            f"relit pas le .toc).\n"
        )


# Capacites du boss observees, par (encID, difficulte, spellID, occurrence) ->
# [secondes]. Rempli pendant build_lorrgs, consomme par write_boss_timelines.
OBSERVED_BOSS_CASTS = defaultdict(list)

# Une occurrence n'est retenue que si elle apparait dans au moins cette part des
# logs du boss : les derniers casts n'existent que dans les pulls les plus longs
# et ne font pas partie du deroulement normal.
BOSS_CAST_MIN_SHARE = 0.5


def write_boss_timelines(hint_dir):
    """Ecrit Data/BossTimelines.lua : le deroulement des capacites de chaque
    boss, en secondes absolues depuis le pull.

    Mesure sur Ula'tek Mythique, deux pulls differents : les memes capacites
    tombent a 44 ms a 700 ms pres. Le script d'un boss est deterministe, donc
    une mediane sur les top logs donne un deroulement fidele, pas une
    approximation — contrairement aux bornes de phase, qui elles dependent du
    rythme du groupe.

    Sert a afficher dans l'addon la timeline du boss a cote des rappels, pour
    voir a quelle capacite chacun repond et pouvoir en placer un soi-meme.
    """
    # Les capacites du boss ne viennent QUE de l'API : elles sont lues dans
    # `fight.boss.casts`. Un run Viserio seul, ou un run ou l'API n'a rien
    # renvoye, laisse donc cette table vide.
    #
    # Avant, on sortait ici sans rien dire : la timeline du boss disparaissait
    # de l'addon sans le moindre message, et plus rien n'expliquait pourquoi
    # un cooldown etait place a tel instant. On prefere le dire, et preciser
    # si un fichier existant a ete conserve.
    if not OBSERVED_BOSS_CASTS:
        path = os.path.join(hint_dir, "Data", "BossTimelines.lua")
        if os.path.isfile(path):
            print("\n[WARN] Aucune capacite de boss relevee ce run : "
                  "Data/BossTimelines.lua est CONSERVE tel quel.")
        else:
            print("\n[WARN] Aucune capacite de boss relevee, et "
                  "Data/BossTimelines.lua n'existe pas.")
            print("       L'addon n'affichera donc aucune ligne de capacite "
                  "de boss dans la timeline.")
        print("       Ces donnees ne viennent que de WoW Timeline : relancer "
              "sans --source viserio.")
        return

    logs_seen = defaultdict(int)
    for (enc, diff, _, occ), times in OBSERVED_BOSS_CASTS.items():
        if occ == 1:
            logs_seen[(enc, diff)] = max(logs_seen[(enc, diff)], len(times))

    by_boss = defaultdict(lambda: defaultdict(list))
    kept = 0
    for (enc, diff, spell, occ), times in OBSERVED_BOSS_CASTS.items():
        total = logs_seen.get((enc, diff)) or len(times)
        if total and len(times) / total < BOSS_CAST_MIN_SHARE:
            continue
        by_boss[enc][diff].append(
            (round(statistics.median(times), 1), spell, occ))
        kept += 1
    if not by_boss:
        return

    # RENUMEROTATION PAR LE TEMPS.
    #
    # `occ` est le rang de l'incantation DANS UN LOG. La mediane etant prise
    # log par log, et deux logs n'ayant pas forcement le meme nombre
    # d'incantations, le rang 15 d'un log peut tomber plus tard que le rang
    # 30 d'un autre : l'addon affichait "Lancer de camelote (15)" a 3:55
    # apres "(30)" a 3:31. On renumerote donc chaque sort dans l'ordre
    # chronologique de la piste finale, ce qui rend l'ordre croissant par
    # construction. Deux entrees du meme sort tombant a la meme seconde sont
    # la meme incantation vue par deux logs : on n'en garde qu'une.
    for enc in by_boss:
        for diff in list(by_boss[enc]):
            seen_tp, ordered = set(), []
            for t, spell, _occ in sorted(by_boss[enc][diff]):
                if (t, spell) in seen_tp:
                    continue
                seen_tp.add((t, spell))
                ordered.append((t, spell))
            seq = defaultdict(int)
            renumbered = []
            for t, spell in ordered:
                seq[spell] += 1
                renumbered.append((t, spell, seq[spell]))
            by_boss[enc][diff] = renumbered
    kept = sum(len(v) for d in by_boss.values() for v in d.values())

    lines = [
        "-- Généré automatiquement par NSRTAutoReminders-build.py — NE PAS ÉDITER.",
        "-- Déroulement des capacités de chaque boss, en secondes depuis le pull.",
        "-- Médiane des top logs : le script d'un boss étant déterministe, l'écart",
        "-- entre deux pulls se compte en dixièmes de seconde.",
        "local _, EP = ...",
        "EP.BossTimeline = {",
    ]
    for enc in sorted(by_boss, key=boss_sort_key):
        lines.append(f"    [{enc}] = {{")
        for diff in sorted(by_boss[enc]):
            lines.append(f'        ["{diff}"] = {{')
            for t, spell, occ in sorted(by_boss[enc][diff]):
                lines.append(
                    f"            {{ t = {t:g}, id = {spell}, n = {occ} }},")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")

    data_dir = os.path.join(hint_dir, "Data")
    os.makedirs(data_dir, exist_ok=True)
    write_file_atomic(os.path.join(data_dir, "BossTimelines.lua"),
                             "\n".join(lines) + "\n")

    ensure_toc_entry(hint_dir, r"Data\BossTimelines.lua")
    print(f"[OK  ] Data/BossTimelines.lua : {len(by_boss)} boss, {kept} capacités.")


PHASE_BOUND_MIN_LOGS = 3


def write_phase_table(hint_dir):
    """Ecrit Data/Phases.lua : les bornes de phase de chaque boss, en secondes
    ABSOLUES depuis le debut du combat, par difficulte.

    Pourquoi l'addon en a besoin. Depuis 8.3.0 l'utilisateur ne voit et
    n'edite qu'UNE timeline continue en temps absolu ; c'est l'addon qui
    redecoupe en (phase, temps relatif) au moment de l'import, parce que NSRT
    remet le chrono a zero a chaque phase et detruit les rappels d'une phase
    deja passee (Reminders.lua : StartReminders -> HideAllReminders ->
    v:Cancel() sur chaque timer, puis ReminderTimer = {}).

    Pour les timelines issues des top logs, les bornes exactes du pull sont
    deja embarquees dans chaque variante (`phaseStarts`) et ont la priorite.
    Cette table sert aux notes VISERIO, qui ne viennent d'aucun log et
    n'avaient donc aucune phase du tout : tout etait ecrit en ph:1, donc perdu
    des le premier changement de phase.

    D'OU VIENNENT LES BORNES. Uniquement de l'API : pour chaque (boss,
    difficulte, phase), la MEDIANE des instants releves dans les top logs
    (OBSERVED_PHASE_STARTS, rempli par build_toplogs). Mediane et non moyenne :
    un seul pull avec un enrage tres tardif ne doit pas deplacer la borne.

    Les BossTimelines de NSRT servaient de base avant, et ne servent plus :
    c'est un relevé fige sur un pull de reference, mesure a 197,9 s pour
    l'intermission de Nek'zali Mythique la ou les vrais pulls la placent entre
    102 et 163 s. Un boss sans assez de logs n'a donc plus de bornes du tout —
    c'est volontaire : mieux vaut pas de borne qu'une borne fausse, l'addon
    retombant alors sur ph:1, exactement comme pour un boss sans phases.
    """
    def allowed_phases(enc):
        """Phases que NSRT peut REELLEMENT atteindre sur ce boss.

        Le log annonce des stages que le detecteur live (EncounterAlerts)
        n'ouvre jamais. Sszorak en est l'exemple : les reports y passent en
        stage 2 alors que NSRT ne quitte jamais la phase 1 — emettre ph:2
        la-bas etait exactement la regression de 8.1.1 (27 rappels ranges dans
        une phase qui ne s'ouvre pas). On n'expose donc a l'addon que les
        phases du modele runtime, et rien du tout (phase 1 seule) pour un boss
        inconnu du modele.
        """
        model = phase_model_for(enc)
        if not model or model.get("type") == "none":
            return {1}
        allowed = model.get("allowed")
        if allowed is None:
            return None          # non borne : on garde tout
        return set(allowed) | {1}

    phases, measured, thin = {}, 0, []
    for enc in sorted({e for e, _, _ in OBSERVED_PHASE_STARTS}):
        ok = allowed_phases(enc)
        out = defaultdict(dict)
        for (e, diff, ph), starts in OBSERVED_PHASE_STARTS.items():
            if e != enc:
                continue
            if ok is not None and ph not in ok:
                continue
            if len(starts) < PHASE_BOUND_MIN_LOGS:
                # Une borne tiree d'un ou deux pulls n'est pas une mediane,
                # c'est un exemple. On la laisse de cote plutot que de la
                # publier comme une reference.
                thin.append((enc, diff, ph, len(starts)))
                continue
            out[diff][ph] = round(statistics.median(starts), 2)
            measured += 1
        for diff in list(out):
            out[diff].setdefault(1, 0)
        if out:
            phases[enc] = dict(out)

    if not phases:
        print("[WARN] Aucune borne de phase mesurée dans les top logs : "
              "Data/Phases.lua non écrit (les notes Viserio resteront en ph:1).")
        return
    print(f"[OK  ] {measured} bornes de phase mesurées sur la médiane des "
          f"top logs ({len(phases)} boss"
          + (f", {len(thin)} ignorée(s) faute de {PHASE_BOUND_MIN_LOGS} logs"
             if thin else "") + ").")

    # Dispersion des transitions : une borne tres variable signale une phase
    # declenchee par un SEUIL DE VIE et non par un minuteur. Mesure sur
    # Nek'zali Mythique : la sortie de phase 1 s'etale de 97,6 s a 199,3 s
    # selon les logs. Aucune source ne peut dire quand CE raid l'atteindra, et
    # une mediane y est donc une approximation irreductible — autant le dire,
    # plutot que de laisser croire a une valeur exacte. Les timelines des top
    # logs ne sont pas concernees : chacune porte les bornes de son propre pull.
    volatile = []
    for (enc, diff, ph), starts in OBSERVED_PHASE_STARTS.items():
        if len(starts) < PHASE_MIN_SAMPLES:
            continue
        spread = max(starts) - min(starts)
        if spread > PHASE_SPREAD_WARN:
            volatile.append((spread, enc, diff, ph, min(starts), max(starts)))
    if volatile:
        # Une seule ligne : c'est une information de jeu, pas un defaut du
        # build. Detail par boss et difficulte, phases entre parentheses.
        by_boss = defaultdict(list)
        for _spread, enc, diff, ph, _lo, _hi in sorted(volatile, key=lambda v: (v[1], v[2], v[3])):
            by_boss[(enc, diff)].append("P" + format_lua_phase(ph))
        short = {"Mythic": "MM", "Heroic": "HM"}
        detail = ", ".join(f"{enc} {short.get(diff, diff)} ({' '.join(phs)})"
                           for (enc, diff), phs in sorted(by_boss.items()))
        print(f"[INFO] Phases à durée variable selon les dégâts : {detail} — "
              f"notes Viserio : vérifier en raid les rappels proches d'une transition.")

    lines = [
        "-- Généré automatiquement par NSRTAutoReminders-build.py — NE PAS ÉDITER.",
        "-- Source : médiane des top logs (wowtimeline.fr), filtrée par le",
        "-- modèle de phases runtime de NSRT (EncounterAlerts).",
        "-- Bornes de phase NSRT, en secondes absolues depuis le début du combat.",
        "local _, EP = ...",
        "EP.PhaseTable = {",
    ]
    for enc in sorted(phases, key=boss_sort_key):
        lines.append(f"    [{enc}] = {{")
        for diff in sorted(phases[enc]):
            pairs = ", ".join(
                f"[{format_lua_phase(ph)}] = {start:g}"
                for ph, start in sorted(phases[enc][diff].items()))
            lines.append(f'        ["{diff}"] = {{ {pairs} }},')
        lines.append("    },")
    lines.append("}")

    data_dir = os.path.join(hint_dir, "Data")
    os.makedirs(data_dir, exist_ok=True)
    write_file_atomic(os.path.join(data_dir, "Phases.lua"),
                             "\n".join(lines) + "\n")

    ensure_toc_entry(hint_dir, r"Data\Phases.lua")
    print(f"[OK  ] Data/Phases.lua : {len(phases)} boss (top logs).")


def write_spell_table(hint_dir, meta):
    """Ecrit Data/Spells.lua : recharge et duree d'effet de chaque sort suivi.

    Source unique : /api/spells de WoW Timeline, le meme catalogue que le site
    utilise pour dessiner ses barres. Rien n'est deduit ici — un sort dont le
    catalogue ne donne ni recharge ni duree n'est pas ecrit, et l'addon se
    contente alors de la marque, sans barre.

    Permet a l'addon de montrer, pour chaque cooldown, la duree pendant
    laquelle il agit puis le temps qu'il met a revenir : c'est ce qui rend
    visible un trou de trois minutes dans un plan.
    """
    rows = []
    for spell_id in sorted(meta):
        entry = meta[spell_id] or {}
        try:
            if int(spell_id) <= 0:
                continue                    # pas un sort reel
        except (TypeError, ValueError):
            continue
        cd = float(entry.get("cooldown") or 0)
        dur = float(entry.get("duration") or 0)
        if cd <= 0 and dur <= 0:
            continue
        rows.append((spell_id, cd, dur, entry.get("name") or ""))
    if not rows:
        print("[WARN] Aucune recharge connue : Data/Spells.lua non ecrit.")
        return

    lines = [
        "-- Généré automatiquement par NSRTAutoReminders-build.py — NE PAS ÉDITER.",
        "-- Recharge (cd) et durée d'effet (dur) en secondes, depuis",
        "-- /api/spells de WoW Timeline. Sert aux barres de la timeline.",
        "local _, EP = ...",
        "EP.SpellTable = {",
    ]
    for spell_id, cd, dur, name in rows:
        parts = []
        if cd > 0:
            parts.append(f"cd = {cd:g}")
        if dur > 0:
            parts.append(f"dur = {dur:g}")
        comment = f"  -- {name}" if name else ""
        lines.append(f"    [{spell_id}] = {{ {', '.join(parts)} }},{comment}")
    lines.append("}")

    data_dir = os.path.join(hint_dir, "Data")
    os.makedirs(data_dir, exist_ok=True)
    write_file_atomic(os.path.join(data_dir, "Spells.lua"),
                             "\n".join(lines) + "\n")

    ensure_toc_entry(hint_dir, r"Data\Spells.lua")
    print(f"[OK  ] Data/Spells.lua : {len(rows)} sorts (recharge et durée).")


def prune_stale_toc_entries(hint_dir):
    """Passe finale, indépendante de --source : vérifie chaque ligne de
    fichier à l'intérieur de chaque bloc "# BEGIN ... DATA / # END ... DATA"
    du .toc contre ce qui existe réellement sur le disque, et retire ce qui
    n'existe plus — plutôt que de laisser un bloc entier figé (jamais
    retouché) dès qu'un lancement ne couvre qu'une seule source. C'est
    exactement le genre de résidu ("Data\\WowTimeline\\vaelgor-and-ezzorak.lua"
    provoquant une LUA_WARNING en jeu) que cette fonction élimine.
    """
    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    if not os.path.isfile(toc_path):
        return
    with open(toc_path, encoding="utf-8") as f:
        toc = f.read()

    removed_lines, removed_blocks = 0, 0
    for label in ("VISERIO", "TOPLOGS", "LORRGS"):
        begin, end = f"# BEGIN {label} DATA", f"# END {label} DATA"
        m = re.search(re.escape(begin) + r"(.*?)" + re.escape(end), toc, flags=re.S)
        if not m:
            continue
        block_body = m.group(1)
        lines = [l for l in block_body.splitlines() if l.strip()]
        kept_lines = []
        for line in lines:
            rel_path = line.strip().replace("\\", os.sep)
            if os.path.isfile(os.path.join(hint_dir, rel_path)):
                kept_lines.append(line.strip())
            else:
                removed_lines += 1
        if not kept_lines:
            # Plus un seul fichier valide pour cette source : le dossier
            # Data correspondant n'existe sans doute plus du tout, on
            # retire le bloc entier plutôt que de laisser des marqueurs
            # vides trainer dans le .toc.
            toc = toc.replace(begin + block_body + end + "\n", "")
            toc = toc.replace(begin + block_body + end, "")
            removed_blocks += 1
        elif len(kept_lines) != len(lines):
            new_block = begin + "\n" + "\n".join(kept_lines) + "\n" + end
            toc = toc[:m.start()] + new_block + toc[m.end():]

    if removed_lines or removed_blocks:
        write_file_atomic(toc_path, toc)
        print("\n=== Nettoyage final du .toc ===")
        if removed_lines:
            print(f"  {removed_lines} ligne(s) fantôme(s) retirée(s) "
                  f"(fichier référencé mais absent du disque).")
        if removed_blocks:
            print(f"  {removed_blocks} bloc(s) de données entièrement "
                  f"retiré(s) (plus aucun fichier valide dedans).")


def print_phase_check():
    """Resume du controle des phases (voir phase_refusal)."""
    rows = [(enc, c) for enc, c in sorted(PHASE_CHECK.items()) if c[1] or c[2]]
    if not rows:
        return
    print("\nControle des phases (logs WoW Timeline) :")
    for enc, (seen, refused, bad) in rows:
        phases = ", ".join(format_lua_phase(b) for b in sorted(bad)) or "-"
        if refused:
            print(f"  [REFUS] {enc} : {refused}/{seen} logs ecartes "
                  f"(phases hors modele : {phases}).")
        else:
            print(f"  [INFO] {enc} : phases {phases} du log ignorees, comme prevu "
                  f"par NSRT_RUNTIME_PHASES ({seen} logs).")


def main():
    # Declarees ici, avant tout usage : argparse lit certains de ces
    # reglages comme valeur par defaut d'option plus bas.
    global WOWTIMELINE_API, WOWTIMELINE_BASE, WOWTIMELINE_CA
    global WOWTIMELINE_EXPORT, EXPORT_CONSENSUS, EXPORT_CONSENSUS_SHARE
    # argparse(action="version") quitte déjà normalement. Ce chemin explicite
    # garantit aussi qu'un lanceur Python inhabituel ne poursuive jamais la
    # génération après une simple demande de version.
    if sys.argv[1:] == ["--version"]:
        print(f"NSRTAutoReminders-build.py {SCRIPT_VERSION}")
        return

    ap = argparse.ArgumentParser(
        prog="NSRTAutoReminders-build.py",
        description=(
            "Construit les fichiers de donnees Lua de NSRT AutoReminders "
            "depuis Viserio et WoW Timeline. Le script detecte aussi les nouveaux "
            "raids et les associe a leur saison via Warcraft Logs API v2."
        ),
        epilog="""EXEMPLES
  Afficher cette aide :
    python3 NSRTAutoReminders-build.py --help

  Verifier uniquement les raids et saisons Warcraft Logs :
    python3 NSRTAutoReminders-build.py --wcl-only

  Generer les deux sources avec les reglages recommandes :
    python3 NSRTAutoReminders-build.py

  Generer uniquement Viserio pour le raid The Voidspire :
    python3 NSRTAutoReminders-build.py --source viserio --raid the-voidspire

  Generer uniquement les trois meilleurs logs :
    python3 NSRTAutoReminders-build.py --source wowtimeline --top 3

  Ignorer Warcraft Logs et utiliser les saisons locales :
    python3 NSRTAutoReminders-build.py --no-wcl

LIMITES WARCRAFT LOGS (HTTP 429)
  Toutes les requetes WCL sont espacees de 1.10 seconde en mode standard.
  Le script surveille aussi les points GraphQL et conserve une marge d'au
  moins 200 points, ajustee au cout reel des grosses pages d'evenements. Si le
  quota approche de cette marge ou si WCL repond HTTP 429, il affiche une
  seule ligne [PAUSE], attend la remise a zero, puis reprend automatiquement
  la meme requete.
  --wcl-delay permet de ralentir davantage; --wcl-max-retries controle le
  nombre de reprises. Il ne faut pas relancer le script pendant une [PAUSE].

GESTION DES TIMELINES INVALIDES (VISERIO ET WOW TIMELINE)
  Par defaut, Viserio propose jusqu'a 10 notes par boss (--viserio-top) et
  WoW Timeline jusqu'a 5 logs par boss/spe/difficulte (--top). Une note vide,
  illisible ou sans specialisation
  reconnue est ignoree sans consommer le quota. Le script continue alors
  avec la candidate suivante classee par popularite. Un bilan n'est affiche
  que si toutes les candidates sont epuisees avant d'obtenir le quota
  demande.

FICHIERS LOCAUX
  .env                 contient WCL_CLIENT_ID et WCL_CLIENT_SECRET
  .cache_viserio/      cree seulement si --cache-hours > 0 (voir plus haut)
  .cache_wowtimeline/  cree seulement si --cache-hours > 0 (voir plus haut)

SECURITE
  Ne publie jamais le fichier .env et ne place jamais le Client Secret
  Warcraft Logs dans le script ou dans le ZIP de l'addon.
""",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        add_help=False,
    )
    ap._optionals.title = "Options generales"
    ap.add_argument(
        "-h", "--help", action="help",
        help="Afficher cette aide detaillee puis quitter.",
    )
    ap.add_argument(
        "--version", action="version",
        version=f"%(prog)s {SCRIPT_VERSION}",
        help="Afficher la version du script puis quitter.",
    )

    generation = ap.add_argument_group("Generation des donnees")
    generation.add_argument(
        "--source", choices=["viserio", "wowtimeline", "lorrgs", "both"],
        default="both",
        help=(
            "Source a generer : 'viserio', 'wowtimeline' ou 'both'. "
            "Viserio pour les plans publies, WoW Timeline pour les "
            "timelines issues des meilleurs logs. Defaut : both. "
            "'lorrgs' reste accepte comme ancien nom de 'wowtimeline'."
        ),
    )
    generation.add_argument(
        "--out", default="Data_Viserio.lua", metavar="FICHIER",
        help=(
            "Chemin indicatif (utilise seulement pour retrouver le dossier "
            "de l'addon si --addon-dir n'est pas fourni). Les donnees sont "
            "ecrites sous Data/Viserio/<Boss>.lua et Data/WowTimeline/<Boss>.lua "
            "(un fichier par boss pour chaque source) et le .toc est mis a "
            "jour automatiquement. Defaut : Data_Viserio.lua."
        ),
    )
    generation.add_argument(
        "--addon-dir", default=None, metavar="DOSSIER",
        help=(
            "Dossier de l'addon en jeu (celui qui contient "
            "NSRTAutoReminders.toc), si ce n'est pas celui du script ou "
            "de --out. Permet de generer les donnees depuis n'importe quel "
            "dossier de travail tout en mettant a jour le vrai .toc "
            "installe en jeu (WoW/_retail_/Interface/AddOns/NSRTAutoReminders "
            "par exemple). Sans cette option, le dossier de --out est "
            "utilise."
        ),
    )
    generation.add_argument(
        "--raid", metavar="SLUG",
        help=(
            "Limiter la generation a un raid. Utile pour tester rapidement "
            "un nouveau raid. Exemple : the-voidspire."
        ),
    )
    generation.add_argument(
        "--difficulty", choices=["mythic", "heroic"],
        help=(
            "Limiter les notes Viserio a une difficulte. Les top logs sont "
            "collectes en Mythique et en Heroique."
        ),
    )
    generation.add_argument(
        "--season", choices=["current", "all"], default=None,
        help=(
            "Choisir la saison courante seulement ou toutes les saisons. "
            "Sans cette option : Viserio garde toutes les saisons Midnight "
            "et WoW Timeline garde la saison courante."
        ),
    )
    generation.add_argument(
        "--no-nsrt-fetch", action="store_true",
        help=(
            "Ne rien lire chez NSRT sur GitHub : ni le modele de phases "
            "(EncounterAlerts), ni la liste des boss (BossData). Le script "
            "s'en tient alors a ses tables internes. Les BORNES de phase ne "
            "sont pas concernees : elles viennent des top logs de l'API, "
            "jamais de NSRT."
        ),
    )
    generation.add_argument(
        "--no-version-bump", action="store_true",
        help=(
            "Ne pas incrementer '## Version:' dans NSRTAutoReminders.toc a la "
            "fin du run. Par defaut le dernier nombre augmente de 1 "
            "(9.5.0 -> 9.5.1), pour que la liste d'addons de WoW montre que "
            "les donnees ont ete regenerees."
        ),
    )
    generation.add_argument(
        "--wowtimeline-api", default=None, metavar="URL",
        help=(
            "Adresse de WoW Timeline, interroge en priorite pour les top "
            "logs (ex. http://serveur:8000/api). Peut aussi venir de "
            "WOWTIMELINE_API dans le .env. Si le service ne repond pas, "
            "l'etape des top logs est abandonnee et les donnees existantes "
            "sont conservees. "
            f"Defaut : {WOWTIMELINE_DEFAULT}."
        ),
    )
    generation.add_argument(
        "--wowtimeline-ca", default=None, metavar="FICHIER",
        help=(
            "Certificat racine de Caddy pour le HTTPS de WoW Timeline. Defaut : "
            "WOWTIMELINE_CA dans le .env, sinon caddy-root.crt a cote du script."
        ),
    )
    generation.add_argument(
        "--no-export", action="store_true",
        help=(
            "Ne pas utiliser /api/v1/export : interroger /spec_ranking une "
            "spe a la fois, comme avant. Par defaut l'export est tente au "
            "demarrage et utilise s'il repond (une requete par boss et "
            "difficulte au lieu d'une par spe). Il est reserve aux IP de "
            "RATE_LIMIT_ALLOW cote service ; un refus fait repartir le script "
            "sur l'ancien mode, sans rien perdre."
        ),
    )
    generation.add_argument(
        "--consensus-share", type=float, default=EXPORT_CONSENSUS_SHARE,
        metavar="PART",
        help=(
            "Part des top logs qui doivent concorder pour qu'un moment entre "
            "dans le « Plan consensus » calcule depuis l'export. A garder "
            "egal a consensus_min_share du config.yaml du service, sinon la "
            "variante differera de celle du site. "
            f"Defaut : {EXPORT_CONSENSUS_SHARE}."
        ),
    )
    generation.add_argument(
        "--no-consensus", action="store_true",
        help=(
            "Ne pas ajouter la variante « Plan consensus » fournie par NSRT "
            "Timeline (moments communs a la majorite des top logs)."
        ),
    )
    generation.add_argument(
        "--top", type=int, default=5, metavar="N",
        help=(
            "Quota de donnees valides pour les top logs : N logs par boss, "
            "specialisation ET difficulte (Mythic et Heroic sont gardes "
            "separement, l'un n'exclut plus l'autre). Utilise 0 pour tout "
            "conserver. Defaut : 5. Pour Viserio, voir --viserio-top."
        ),
    )
    generation.add_argument(
        "--viserio-top", type=int, default=10, metavar="N",
        help=(
            "Quota de notes completes Viserio par boss, toutes difficultes "
            "confondues (une note Viserio couvre deja tout le raid, pas "
            "une seule specialisation). Classement par popularite ; une "
            "candidate invalide est remplacee automatiquement par la "
            "suivante. Utilise 0 pour tout conserver. Defaut : 10."
        ),
    )
    generation.add_argument(
        "--limit", type=int, metavar="N",
        help=(
            "Limiter le nombre total de notes Viserio. Utile pour un test "
            "rapide; ne pas utiliser pour une generation finale."
        ),
    )

    wcl = ap.add_argument_group("Warcraft Logs et saisons")
    wcl.add_argument(
        "--wcl-only", action="store_true",
        help=(
            "Synchroniser les boss NSRT, detecter les raids/saisons via "
            "Warcraft Logs, puis quitter sans "
            "generer de fichier Lua."
        ),
    )
    wcl.add_argument(
        "--no-wcl", action="store_true",
        help=(
            "Ne pas contacter Warcraft Logs. Utile hors ligne ou si aucun "
            "client API v2 n'est configure."
        ),
    )
    wcl.add_argument(
        "--current-season", type=int, default=None, metavar="N",
        help=(
            "Forcer la saison courante. A utiliser pour corriger ou imposer "
            "un choix; sinon le script utilise ses tables internes et la "
            "detection Warcraft Logs."
        ),
    )
    wcl.add_argument(
        "--env-file", default=".env", metavar="FICHIER",
        help=(
            "Fichier contenant WCL_CLIENT_ID et WCL_CLIENT_SECRET. "
            "Defaut : .env."
        ),
    )
    wcl.add_argument(
        "--wcl-delay", type=float, default=1.10, metavar="SECONDES",
        help=(
            "Delai minimal entre deux requetes Warcraft Logs. Le mode "
            "standard utilise 1.10 s et respecte aussi Retry-After ainsi que "
            "le budget de points GraphQL. Augmente cette valeur si ton client "
            "API dispose d'un quota reduit. Defaut : 1.10."
        ),
    )
    wcl.add_argument(
        "--wcl-max-retries", type=int, default=8, metavar="N",
        help=(
            "Nombre maximal de reprises automatiques apres HTTP 429. "
            "L'attente est progressive et les caches deja telecharges sont "
            "conserves. Defaut : 8."
        ),
    )

    execution = ap.add_argument_group("Cache et execution")
    execution.add_argument(
        "--cache-hours", type=float, default=DEFAULT_CACHE_HOURS,
        metavar="HEURES",
        help=(
            "Duree de validite des caches Viserio/WoW Timeline. Par defaut (0), "
            "le cache est entierement desactive : rien n'est lu ni ecrit, "
            "les dossiers .cache_viserio/.cache_wowtimeline ne sont meme "
            "crees, chaque execution retelecharge tout. Mets une valeur "
            "positive (ex. 24) pour reactiver le cache et eviter de "
            "retelecharger a chaque run."
        ),
    )
    args = ap.parse_args()

    # Source des top logs : WoW Timeline si configure et joignable, sinon Lorrgs.
    load_dotenv(args.env_file)
    wt_api = (args.wowtimeline_api or os.environ.get("WOWTIMELINE_API", "")
              or WOWTIMELINE_DEFAULT).strip().rstrip("/")
    ca = args.wowtimeline_ca or os.environ.get("WOWTIMELINE_CA", "").strip()
    if not ca:
        beside = os.path.join(os.path.dirname(os.path.abspath(__file__)), "caddy-root.crt")
        ca = beside if os.path.isfile(beside) else ""
    if ca and not os.path.isfile(ca):
        print(f"[WARN] Certificat WoW Timeline introuvable : {ca} (ignore).")
        ca = ""
    WOWTIMELINE_CA = ca or None
    EXPORT_CONSENSUS = not args.no_consensus
    EXPORT_CONSENSUS_SHARE = args.consensus_share
    if wt_api and args.source in ("wowtimeline", "both"):
        WOWTIMELINE_BASE = wt_api
        ok, why = wowtimeline_alive(wt_api)
        if ok:
            WOWTIMELINE_API = wt_api
            print(f"[OK  ] WoW Timeline joignable ({wt_api}) : source des top logs.")
            # Export complet : une requete par boss et difficulte au lieu
            # d'une par spe. Teste une seule fois ; un refus (403 : IP hors
            # liste blanche) n'est pas une panne, juste l'ancien mode.
            if not args.no_export:
                ready, why_export = wowtimeline_export_ready(wt_api)
                WOWTIMELINE_EXPORT = ready
                if ready:
                    print(f"[OK  ] Export complet autorise ({why_export}) : "
                          f"1 requete par boss et difficulte, toutes spes "
                          f"comprises.")
                else:
                    print(f"[INFO] Export complet indisponible : {why_export}.")
                    print("       Lecture spe par spe (/spec_ranking), "
                          "comportement inchange.")
        else:
            # Plus aucune source de secours depuis le retrait de Lorrgs.
            # L'etape des top logs est donc abandonnee, et les donnees du run
            # precedent sont conservees telles quelles : mieux vaut une
            # timeline datee qu'une timeline fausse ou absente.
            print(f"[ERR ] WoW Timeline indisponible ({wt_api}) : {why}.")
            print("       L'etape des top logs est abandonnee ; les fichiers "
                  "existants sont conserves.")
            if args.source == "wowtimeline":
                print("       Rien d'autre a generer (--source wowtimeline).")
            else:
                print("       Seul Viserio sera genere ce run.")

    if requests is None:
        ap.error(
            "le module 'requests' est requis. Installe-le avec : "
            "python3 -m pip install requests"
        )
    if args.wcl_only and args.no_wcl:
        ap.error("--wcl-only et --no-wcl ne peuvent pas etre utilises ensemble")
    # "lorrgs" reste accepte comme ancien nom de la source des top logs, pour
    # ne pas casser les scripts et les habitudes. Un seul nom circule ensuite.
    if args.source == "lorrgs":
        args.source = "wowtimeline"
        print("[INFO] --source lorrgs : Lorrgs a ete retire, "
              "la source des top logs est WoW Timeline.")
    if args.current_season is not None and args.current_season <= 0:
        ap.error("--current-season doit etre superieur a zero")
    if args.wcl_delay < 0:
        ap.error("--wcl-delay doit etre egal ou superieur a zero")
    if args.wcl_max_retries <= 0:
        ap.error("--wcl-max-retries doit etre superieur a zero")
    if args.top < 0:
        ap.error("--top doit etre egal ou superieur a zero")
    if args.viserio_top < 0:
        ap.error("--viserio-top doit etre egal ou superieur a zero")
    if args.limit is not None and args.limit <= 0:
        ap.error("--limit doit etre superieur a zero")
    if args.cache_hours < 0:
        ap.error("--cache-hours doit etre egal ou superieur a zero")

    configure_wcl_rate_limit(args)

    print("=== Préparation : boss connus (synchro NSRT) ===")
    migrate_lorrgs_layout(addon_root(args))
    sync_bosses_from_nsrt(offline=args.no_nsrt_fetch)
    # Modele de phases charge ici, une fois pour tout le run : phase_model_for()
    # lit ensuite le cache memorise, et --no-nsrt-fetch est donc respecte par
    # tous ses appels sans avoir a le propager partout.
    nsrt_phase_models(offline=args.no_nsrt_fetch)
    args.current_season = sync_seasons_from_wcl(args)
    # Decoupage en raids : apres Warcraft Logs, qui a fourni l'identite des
    # rencontres (resolve_boss en depend), et avant les deux generateurs, qui
    # consomment tous deux RAID_BY_ENCOUNTER. La Library est memorisee, donc
    # build_viserio ne la retelecharge pas.
    print("\n=== Decoupage en raids (Viserio) ===")
    sync_raids_from_viserio()
    cross_check_wcl_viserio(args)
    if args.wcl_only:
        print("\nDétection Warcraft Logs terminée.")
        return
    archive_previous_season_if_needed(args)
    aborted_sources = []
    if args.source in ("viserio", "both"):
        print("################ SOURCE 1/2 : VISERIO CD RAID ################\n"
              if args.source == "both" else "", end="")
        try:
            build_viserio(args)
        except SourceBuildAborted as exc:
            aborted_sources.append("Viserio")
            print(f"[ABANDON] Viserio : {exc}")
    if args.source in ("wowtimeline", "both"):
        print("\n########### SOURCE 2/2 : WOW TIMELINE (TOP LOGS) ###########\n"
              if args.source == "both" else "", end="")
        if not WOWTIMELINE_API:
            # Service injoignable : signale comme un abandon, pour que
            # l'incrementation de version en tienne compte et que le
            # nettoyage du .toc ne retire pas les fichiers existants.
            aborted_sources.append("WoW Timeline")
            print("[ABANDON] WoW Timeline : service injoignable, "
                  "donnees existantes conservees.")
        else:
            try:
                build_toplogs(args)
            except SourceBuildAborted as exc:
                aborted_sources.append("WoW Timeline")
                print(f"[ABANDON] WoW Timeline : {exc}")

    # Le nettoyage doit tourner meme si une (ou les deux) source(s) ci-dessus
    # n'a rien eu a generer : sinon le .toc garde des lignes fantomes vers
    # des fichiers qui ne seront jamais regeneres (voir SourceBuildAborted).
    hint_dir = addon_root(args)
    # Independant des sources : l'addon en a besoin pour redecouper une
    # timeline absolue en phases NSRT, y compris pour les notes Viserio.
    write_phase_table(hint_dir)
    write_boss_timelines(hint_dir)
    write_spell_table(hint_dir, spell_meta_table(args.cache_hours))
    prune_stale_toc_entries(hint_dir)

    print_phase_check()

    # Incrementation de version : seulement si la generation a produit quelque
    # chose. Un run ou toutes les sources ont echoue ne doit pas faire croire,
    # par un numero neuf, que les donnees ont ete rafraichies.
    all_failed = bool(aborted_sources) and len(aborted_sources) == len(
        ["viserio", "wowtimeline"] if args.source == "both" else [args.source])
    if not (all_failed or args.no_version_bump):
        bumped = bump_addon_version(hint_dir)
        if bumped:
            print(f"\nVersion de l'addon : {bumped[0]} -> {bumped[1]}")

    # En dernier, pour que l'avertissement soit la derniere chose lue.
    check_addon_version(hint_dir)

    if all_failed:
        sys.exit(
            f"\nAucune source n'a produit de donnees ({', '.join(aborted_sources)}). "
            f"Le .toc a quand meme ete nettoye des fichiers absents."
        )


def write_viserio_boss_files(output_hint, full_notes, raids_order, current_season,
                              plans_raid_map, encounter_names, raid_metadata,
                              addon_dir=None):
    """Écrit les notes Viserio complètes : un fichier Lua par boss
    (Data/Viserio/<Boss>.lua), chacun contenant jusqu'à --viserio-top notes
    complètes (toutes spécialisations confondues, comme publiées sur
    Viserio — pas de découpage par spé). Régénère systématiquement tous les
    fichiers de boss présents dans full_notes et supprime les fichiers de
    boss orphelins (boss retiré de la Library). Le .toc est reconstruit
    automatiquement en scannant Data/Viserio/*.lua, et l'ancien fichier
    monolithique Data_Viserio.lua est retiré du .toc et supprimé du disque
    s'il traîne encore d'une version précédente."""
    hint_dir = os.path.abspath(addon_dir) if addon_dir else os.path.dirname(os.path.abspath(output_hint))
    data_root = os.path.join(hint_dir, "Data", "Viserio")
    os.makedirs(data_root, exist_ok=True)

    index = [
        "-- Généré par NSRTAutoReminders-build.py — ne pas éditer.",
        "-- Source : Viserio CD Raid",
        "local ADDON_NAME, EP = ...",
        "EP.ViserioRaid = {",
    ]
    ordered = (
        [r for r in raids_order
         if raid_metadata.get(r, {}).get("season") == current_season]
        + [r for r in raids_order
           if raid_metadata.get(r, {}).get("season") != current_season]
    )
    for raid in ordered:
        encs = sorted(
            (e for e in encounter_names if plans_raid_map.get(e) == raid),
            key=boss_sort_key)
        meta = raid_metadata.get(raid, {})
        index.append(
            f'    {{ name = "{lua_escape(raid)}", '
            f'season = {meta.get("season") or 0}, '
            f'current = {"true" if meta.get("season") == current_season else "false"}, '
            f'encounters = {{ {", ".join(map(str, encs))} }} }},')
    index.extend(("}", "EP.ViserioEncounterNames = {"))
    for enc_id in sorted(encounter_names):
        index.append(f'    [{enc_id}] = "{lua_escape(encounter_names[enc_id])}",')
    index.extend(("}", ""))
    write_file_atomic(os.path.join(data_root, "Index.lua"), "\n".join(index))

    kept_filenames = set()
    for enc_id, notes in full_notes.items():
        base = slugify(canonical_boss_name(enc_id, encounter_names.get(enc_id, ""))) or f"encounter-{enc_id}"
        filename = f"{base}.lua"
        kept_filenames.add(filename)
        lines = [
            "-- Généré par NSRTAutoReminders-build.py — ne pas éditer.",
            "local ADDON_NAME, EP = ...",
            "EP.ViserioFullNotes = EP.ViserioFullNotes or {}",
            f"EP.ViserioFullNotes[{enc_id}] = {{",
        ]
        for note in notes:
            duration = max(
                (t for spec_actors in note["specs"].values()
                 for casts in spec_actors for t, _ in casts), default=0)
            lines.append("    {")
            lines.append(f'        name = "{lua_escape(note["name"])}",')
            lines.append(f'        author = "{lua_escape(note["author"])}",')
            lines.append(f'        difficulty = "{note["difficulty"]}",')
            lines.append(f"        duration = {duration},")
            # Details de la note, lus dans l'API Viserio (absents si la note a
            # ete lue par le HTML de secours).
            d = note.get("details") or {}
            starts = d.get("phase_starts") or {}
            if starts:
                pairs = ", ".join(f"[{format_lua_phase(p)}] = {v:g}"
                                  for p, v in sorted(starts.items()))
                # Debut de chaque phase DANS LE PLAN DE L'AUTEUR : l'addon
                # redecoupe la note avec, au lieu de la table moyenne.
                lines.append(f"        phaseStarts = {{ [1] = 0, {pairs} }},")
            # Seule la composition est reprise des details de la note : c'est
            # la seule information que l'addon affiche (decision du projet).
            if d.get("composition"):
                lines.append("        composition = { "
                             + ", ".join(str(x) for x in d["composition"]) + " },")
            lines.append("        specs = {")
            for spec_id in sorted(note["specs"]):
                # Un sous-bloc par ACTEUR. L'addon lit indifferemment
                # l'ancien format (liste de rappels) et celui-ci (liste de
                # listes) — voir SpecActors() dans Core.lua.
                lines.append(f"            [{spec_id}] = {{")
                for casts in note["specs"][spec_id]:
                    lines.append("                {")
                    for seconds, spell in casts:
                        if not spell or int(spell) <= 0:
                            continue
                        lines.append(
                            f"                    {{ time = {seconds}, ph = 1, "
                            f"spellid = {spell} }},")
                    lines.append("                },")
                lines.append("            },")
            lines.append("        },")
            lines.append("    },")
        lines.extend(("}", ""))
        write_file_atomic(os.path.join(data_root, filename), "\n".join(lines))

    # Fichiers de boss orphelins (boss retiré de la Library depuis la
    # dernière génération) : supprimés pour ne pas garder de données mortes.
    for existing in os.listdir(data_root):
        if existing in ("Index.lua", "Register.lua", "BossTimeline.lua"):
            continue
        if existing.endswith(".lua") and existing not in kept_filenames:
            os.remove(os.path.join(data_root, existing))

    register = f"""local ADDON_NAME, EP = ...
EP.RegisterSource({{
    id = "viserio",
    label = "Viserio CD Raid",
    GeneratedAt = "{datetime.date.today().isoformat()}",
    CurrentSeason = {current_season},
    Raid = EP.ViserioRaid,
    EncounterNames = EP.ViserioEncounterNames,
    Plans = {{}},
    FullNotes = EP.ViserioFullNotes,
    fullRaid = true,
}})
"""
    write_file_atomic(os.path.join(data_root, "Register.lua"), register)

    toc_entries = [r"Data\Viserio\Index.lua"]
    for filename in sorted(kept_filenames):
        toc_entries.append(os.path.join("Data", "Viserio", filename).replace(os.sep, "\\"))
    if os.path.isfile(os.path.join(data_root, "BossTimeline.lua")):
        toc_entries.append(r"Data\Viserio\BossTimeline.lua")
    toc_entries.append(r"Data\Viserio\Register.lua")

    toc_path = os.path.join(hint_dir, "NSRTAutoReminders.toc")
    old_monolith = os.path.join(hint_dir, "Data_Viserio.lua")
    if os.path.isfile(toc_path):
        with open(toc_path, encoding="utf-8") as f:
            toc = f.read()
        begin, end = "# BEGIN VISERIO DATA", "# END VISERIO DATA"
        block = begin + "\n" + "\n".join(toc_entries) + "\n" + end
        if begin in toc and end in toc:
            toc = re.sub(
                re.escape(begin) + r".*?" + re.escape(end), lambda _: block, toc, flags=re.S)
        elif "Data_Viserio.lua" in toc:
            # Migration : remplace l'ancienne ligne unique par le nouveau bloc.
            toc = toc.replace("Data_Viserio.lua", block, 1)
        else:
            anchor = "Sources.lua"
            toc = toc.replace(anchor, anchor + "\n" + block, 1) if anchor in toc else (
                toc.rstrip("\n") + "\n" + block + "\n")
        write_file_atomic(toc_path, toc)
        if os.path.isfile(old_monolith):
            os.remove(old_monolith)
            print(f"  [MIGRATION] Ancien {old_monolith} supprimé (remplacé par {data_root}).")
    else:
        write_file_atomic(
            os.path.join(data_root, "TOC_entries.txt"),
            "\n".join(toc_entries) + "\n")
        print(
            f"  [ATTENTION] Aucun NSRTAutoReminders.toc trouvé dans "
            f"{hint_dir} — le .toc N'A PAS été mis à jour automatiquement. "
            f"La liste des fichiers a été écrite dans "
            f"{os.path.join(data_root, 'TOC_entries.txt')} à défaut. "
            f"Relance avec --addon-dir pointant vers le dossier de l'addon "
            f"en jeu pour que ce soit fait automatiquement la prochaine fois."
        )

    return data_root, len(toc_entries) - 2


# ---------------------------------------------------------------------------
# Viserio : lecture par l'API d'une note (source Viserio UNIQUEMENT)
# ---------------------------------------------------------------------------
# /viserio-cooldowns/api/library/<slug> renvoie la note en JSON. On y prend :
#   - listing.mrtString : la note telle que l'auteur l'a ecrite, au format
#     NSRT (time;ph;tag;spellid), phases comprises ;
#   - listing.snapshot.userSpells : les memes sorts, en temps ABSOLU ;
#   - les details : publisherName, stats, updatedAt, classComposition.
#
# `mrtString` donne des temps RELATIFS a la phase, l'addon travaille en temps
# absolu. Pour un meme joueur, les sorts de `userSpells` et ceux de
# `mrtString` sont les memes, dans le meme ordre : la difference entre le
# temps absolu et le temps relatif donne donc, pour chaque phase, l'instant
# ou elle commence dans le plan de l'auteur. C'est une MESURE : si les ecarts
# d'une meme phase ne concordent pas a la seconde pres, la note est rejetee
# pour cette voie et on retombe sur l'ancienne lecture HTML.
VISERIO_API_NOTE = BASE + "/viserio-cooldowns/api/library/"
_RE_MRT = {k: re.compile(v) for k, v in {
    "time": r"time:(-?\d+(?:\.\d+)?)", "ph": r"ph:(\d*\.?\d+)",
    "tag": r"tag:([^;]+)", "spell": r"spellid:(\d+)"}.items()}


def _norm_actor(name):
    """« Holy priest #1 » et « holy priest #1- » -> « holy priest #1 »."""
    return (name or "").strip().rstrip("-").strip().lower()


def _spec_id_from_name(name):
    """« Holy Priest », « Beast Mastery Hunter » -> specID, par SPEC_IDS."""
    key = re.sub(r"[^a-z]", "", (name or "").lower())
    for (cls, spec), spec_id in SPEC_IDS.items():
        if key == re.sub(r"[^a-z]", "", spec + cls):
            return spec_id
    return None


def fetch_note_api(slug, cache_hours):
    """Le `listing` JSON d'une note, ou None si l'API ne repond pas."""
    data, ok = api_fetch(VISERIO_API_NOTE + slug, cache_hours)
    if not ok or not isinstance(data, dict):
        return None
    listing = data.get("listing")
    return listing if isinstance(listing, dict) else None


def parse_note_api(listing):
    """(specs, details) depuis l'API, ou (None, raison) si inexploitable.

    specs : {specID: [[(secondes_absolues, spellID), ...] par joueur]}, la
    meme forme que parse_page() — le reste du pipeline ne change pas.
    """
    snap = listing.get("snapshot") or {}
    mrt = listing.get("mrtString") or ""

    # Joueurs : nom de la note -> specID.
    actor_spec = {}
    for actor in snap.get("actors") or []:
        spec_name = ((actor.get("playerSpec") or {}).get("name") or "")
        spec_id = _spec_id_from_name(spec_name)
        if spec_id:
            actor_spec[_norm_actor(actor.get("name"))] = spec_id
    if not actor_spec:
        return None, "aucun joueur reconnu"

    # Lignes de sort de mrtString, par joueur. Les lignes texte (tag:everyone,
    # text:...) ne portent pas de spellid et sont laissees de cote ici.
    rel = defaultdict(list)
    for line in mrt.splitlines():
        sp, tg, tm = (_RE_MRT[k].search(line) for k in ("spell", "tag", "time"))
        if not (sp and tg and tm):
            continue
        ph = _RE_MRT["ph"].search(line)
        rel[_norm_actor(tg.group(1))].append(
            (float(ph.group(1)) if ph else 1.0, float(tm.group(1)), int(sp.group(1))))
    if not rel:
        return None, "mrtString sans ligne de sort"

    absolute = defaultdict(list)
    for us in snap.get("userSpells") or []:
        if us.get("startTime") is not None:
            absolute[_norm_actor(us.get("actorId"))].append(float(us["startTime"]))

    # Debut de chaque phase, mesure joueur par joueur.
    offsets = defaultdict(list)
    for actor, lines in rel.items():
        lines.sort(key=lambda r: (r[0], r[1]))
        abs_times = sorted(absolute.get(actor) or [])
        if len(abs_times) != len(lines):
            continue
        for (ph, t, _), a in zip(lines, abs_times):
            offsets[ph].append(a - t)
    phase_starts = {}
    for ph, values in offsets.items():
        values.sort()
        mid = values[len(values) // 2]
        if max(values) - min(values) > 1.0:
            return None, f"phase {format_lua_phase(ph)} : debut incoherent ({min(values):g}-{max(values):g} s)"
        phase_starts[ph] = round(mid, 2)
    used = {ph for lines in rel.values() for ph, _, _ in lines}
    missing = sorted(p for p in used if p not in phase_starts)
    if missing:
        return None, f"debut de phase non mesurable : {[format_lua_phase(p) for p in missing]}"
    if phase_starts.get(1.0, 0) != 0:
        return None, f"phase 1 qui ne demarre pas a 0 ({phase_starts[1.0]:g} s)"

    specs = defaultdict(list)
    for actor in sorted(rel, key=lambda a: (a.split("#")[0], a)):
        spec_id = actor_spec.get(actor)
        if not spec_id:
            continue
        casts = sorted({(int(round(phase_starts[ph] + t)), sid)
                        for ph, t, sid in rel[actor]})
        if casts:
            specs[spec_id].append(casts)
    if not specs:
        return None, "aucun sort rattache a une specialisation"

    # Composition = les joueurs qui ont AU MOINS UN sort dans la note, comme le
    # bloc « Details » de la page. Pas `classComposition`, qui liste tout le
    # roster : verifie sur la note rz8p1d7 de Nek'zali, 29 joueurs dans
    # classComposition (tanks compris) mais 13 affiches, soit exactement les 13
    # joueurs distincts de userSpells.
    composition = [spec_id for spec_id in sorted(specs)
                   for _ in specs[spec_id]]
    details = {
        "phase_starts": {p: s for p, s in phase_starts.items() if p != 1.0},
        "composition": composition,
    }
    return dict(specs), details


# ---------------------------------------------------------------------------
# Viserio : frise du boss (source Viserio UNIQUEMENT)
# ---------------------------------------------------------------------------
# La frise « Boss timeline » d'une note Viserio n'est pas dans l'API de la note :
# Viserio la dessine depuis les BossTimelines de NSRT. Verifie, pas suppose :
# sur The Coiled Altar, les 12 premieres capacites de la frise Viserio et de
# BossTimelines/MidnightS2/TheCoiledAltar.lua sont identiques, dans le meme
# ordre, memes spellID, jusqu'aux paires Sever + Venom Rupture a la meme
# seconde. On lit donc ce fichier, et uniquement pour la source Viserio : la
# frise des timelines WoW Timeline reste celle mesuree sur les top logs.
NSRT_BOSSTIMELINES_API = ("https://api.github.com/repos/Reloe/"
                          "NorthernSkyRaidTools/contents/NorthernSkyRaidTools/"
                          "BossTimelines")
NSRT_BOSSTIMELINES_RAW = ("https://raw.githubusercontent.com/Reloe/"
                          "NorthernSkyRaidTools/main/NorthernSkyRaidTools/"
                          "BossTimelines")
# Noms des fichiers BossTimelines de NSRT, utilises seulement si l'API GitHub
# ne repond pas. Tous verifies (HTTP 200) sur raw.githubusercontent.com.
NSRT_BOSSTIMELINE_FILES = {
    "MidnightS1": ["Beloren", "Chimaerus", "CrownOfTheCosmos",
                   "FallenKingSalhadaar", "ImperatorAverzian",
                   "LightblindedVanguard", "MidnightFalls", "Rotmire",
                   "VaelgorEzzorak", "Vorasius"],
    "MidnightS2": ["EntombedSentinels", "Kithix", "NekzaliTheSoulcoiler",
                   "NymrissaWavecaller", "Sszorak", "TheCoiledAltar",
                   "TheLostExplorers", "TheTwinFangs", "Ulatek",
                   "VashnikTheMalignant"],
}
_RE_ABILITY = re.compile(
    r'name\s*=\s*"((?:[^"\\]|\\.)*)"\s*,\s*spellID\s*=\s*(\d+).*?'
    r'phase\s*=\s*([\d.]+)\s*,\s*times\s*=\s*\{([^}]*)\}'
    r'(?:\s*,\s*duration\s*=\s*([\d.]+))?')


def parse_viserio_frise(src):
    """{encID: {difficulte: [(t_absolu, spellID, duree, nom), ...]}}.

    Temps ABSOLU = debut de la phase (bloc `phases`) + temps dans la phase.
    """
    m = re.search(r"NSI\.BossTimelines\[(\d+)\]\s*=\s*\{(.*?)\}", src, re.S)
    if not m:
        return {}
    enc, out = int(m.group(1)), {}
    for diff, var in re.findall(r"(\w+)\s*=\s*(\w+)", m.group(2)):
        blk = re.search(r"local\s+" + var + r"\s*=\s*\{(.*?)\n\}", src, re.S)
        if not blk:
            continue
        body = blk.group(1)
        phases = {float(k): float(v) for k, v in re.findall(
            r"\[([\d.]+)\]\s*=\s*\{\s*start\s*=\s*([\d.]+)\s*\}", body)}
        events = []
        for name, sid, ph, times, dur in _RE_ABILITY.findall(body):
            base = phases.get(float(ph))
            if base is None:
                continue
            for t in times.split(","):
                t = t.strip()
                if t:
                    events.append((round(base + float(t), 2), int(sid),
                                   float(dur or 0), name))
        if events:
            out[diff] = sorted(events)
    return {enc: out} if out else {}


def write_viserio_frise(hint_dir, encounters):
    """Ecrit Data/Viserio/BossTimeline.lua pour les boss qui ont des notes.

    Un boss absent des BossTimelines de NSRT n'a simplement pas de frise :
    rien n'est complete ni invente.
    """
    found = {}
    for folder in NSRT_ALERT_DIRS:
        names, origine = None, "API GitHub"
        try:
            r = request_get(f"{NSRT_BOSSTIMELINES_API}/{folder}", timeout=20)
            entries = r.json() if r is not None and r.status_code == 200 else None
        except Exception:                                    # noqa: BLE001
            entries = None
        if isinstance(entries, list):
            names = [it.get("name") or "" for it in entries
                     if it.get("type") == "file"
                     and (it.get("name") or "").endswith(".lua")]
        else:
            # L'API GitHub non authentifiee est limitee a 60 requetes par
            # heure : quand elle refuse, on lit directement les fichiers dont
            # le nom est connu (verifies un par un sur raw.githubusercontent).
            names = [f"{n}.lua" for n in NSRT_BOSSTIMELINE_FILES.get(folder, [])]
            origine = "noms connus (API GitHub indisponible)"
        lus = 0
        for name in names:
            rf = request_get(f"{NSRT_BOSSTIMELINES_RAW}/{folder}/{name}", timeout=20)
            if rf is None or rf.status_code != 200:
                print(f"[WARN] Frise Viserio : {folder}/{name} illisible.")
                continue
            lus += 1
            for enc, per_diff in parse_viserio_frise(rf.text).items():
                if enc in encounters:
                    found[enc] = per_diff
        print(f"[INFO] Frise Viserio : {folder} — {lus}/{len(names)} fichier(s) "
              f"lu(s) via {origine}.")
    manquants = sorted(set(encounters) - set(found))
    if manquants:
        print("[INFO] Frise Viserio : pas de frise NSRT pour "
              + ", ".join(str(e) for e in manquants) + ".")

    path = os.path.join(hint_dir, "Data", "Viserio", "BossTimeline.lua")
    if not found:
        print("[WARN] Frise Viserio : aucune frise recuperee — "
              + ("fichier existant conserve." if os.path.isfile(path)
                 else "pas de fichier ecrit."))
        return
    lines = [
        "-- Généré par NSRTAutoReminders-build.py — ne pas éditer.",
        "-- Frise du boss des notes Viserio : Viserio la dessine depuis les",
        "-- BossTimelines de NSRT, reprises telles quelles (temps absolus).",
        "local ADDON_NAME, EP = ...",
        "EP.ViserioBossTimeline = {",
    ]
    for enc in sorted(found, key=boss_sort_key):
        lines.append(f"    [{enc}] = {{")
        for diff in sorted(found[enc]):
            lines.append(f'        ["{diff}"] = {{')
            for t, sid, dur, name in found[enc][diff]:
                lines.append(f"            {{ t = {t:g}, id = {sid}, dur = {dur:g} }},"
                             f"  -- {name}")
            lines.append("        },")
        lines.append("    },")
    lines.append("}")
    write_file_atomic(path, "\n".join(lines) + "\n")
    print(f"[OK  ] Data/Viserio/BossTimeline.lua : {len(found)} boss.")


def build_viserio(args):
    print("=== Étape 1/2 : découverte de la Library (API paginée) ===")
    items = discover_api()
    if not items:
        print("  API indisponible, repli sur la page Library…")
        for u in sorted(from_next_data()):
            slug = u.rsplit("/", 1)[-1]
            items.append({"slug": slug})
    if not items:
        raise SourceBuildAborted(
            "Aucune note découverte. Envoie-moi ce message, on ajustera.")

    if args.season == "current":
        items = [it for it in items
                 if SEASONS.get(it.get("raidSlug") or "") == args.current_season]
    if args.raid:
        items = [it for it in items if args.raid in (it.get("raidSlug") or "")]
    if args.difficulty:
        items = [it for it in items if (it.get("difficulty") or "") == args.difficulty]
    if args.viserio_top:
        # Une note Viserio couvre déjà tout le raid (toutes les spés d'un
        # coup) : le quota se compte donc par BOSS, toutes difficultés
        # confondues — pas par (boss, difficulté) comme pour Lorrgs. On ne
        # tronque pas avant analyse : une note peut être publiée mais vide
        # ou illisible, donc on garde toutes les candidates, classées
        # d'abord par difficulté (Mythic AVANT Heroic — exigence du
        # projet, cf. difficulties_to_try dans build_lorrgs pour la même
        # règle côté Lorrgs) puis par popularité au sein d'une même
        # difficulté. Avant : tri par popularité seule, toutes difficultés
        # mélangées — une note Heroic très copiée pouvait consommer le
        # quota avant même qu'une note Mythic moins populaire soit
        # essayée, avec le risque d'exclure complètement le Mythic pour ce
        # boss. Le quota n'est consommé qu'après conversion réussie dans
        # la boucle ci-dessous.
        DIFFICULTY_PRIORITY = {"mythic": 0, "heroic": 1}
        by_boss = defaultdict(list)
        for it in items:
            by_boss[it.get("bossSlug")].append(it)
        items = []
        for group in by_boss.values():
            group.sort(
                key=lambda it: (
                    DIFFICULTY_PRIORITY.get((it.get("difficulty") or "").lower(), 99),
                    -((it.get("stats") or {}).get("copies", 0)),
                ))
            items += group
    if args.limit:
        items = items[: args.limit]
    print(f"  {len(items)} notes retenues")

    print("\n=== Étape 2/2 : téléchargement et conversion ===")
    full_notes = defaultdict(list)
    plans_raid, enc_names, raids_meta = {}, {}, {}
    raids_order = []
    # Slugs de raid renvoyés par Viserio mais absents de RAID_NAMES/SEASONS
    # (voir avertissement en fin de fonction) : sert à repérer un cas comme
    # "the-tidebound-grotto" avant qu'il ne finisse silencieusement en
    # saison 0/"Autre" dans l'addon généré.
    unknown_raid_slugs = {}
    valid_notes_by_boss = defaultdict(int)
    rejected_notes_by_boss = defaultdict(int)

    for it in items:
        boss_slug = it.get("bossSlug")
        if args.viserio_top and valid_notes_by_boss[boss_slug] >= args.viserio_top:
            continue

        slug = it["slug"]
        url = BASE + "/viserio-cooldowns/library/" + slug
        resolved = resolve_boss(boss_slug)
        if resolved:
            enc_id, boss_name = resolved
            difficulty = (it.get("difficulty") or "mythic").capitalize()
            raw_slug = it.get("raidSlug") or ""
            raid = RAID_NAMES.get(raw_slug, raw_slug or "?")
            if raw_slug and (raw_slug not in RAID_NAMES or raw_slug not in SEASONS):
                unknown_raid_slugs.setdefault(raw_slug, set()).add(boss_name)
        else:
            enc_id, boss_name, difficulty, raid = parse_note_url(url)
        if not enc_id:
            print(f"[SKIP] Boss non reconnu ({boss_slug or '?'}) : {url}")
            print("       -> ajoute son slug dans la table BOSSES du script.")
            continue

        note_name = htmllib.unescape(it.get("title") or boss_name)
        publisher = it.get("publisherName")
        note_author = htmllib.unescape(publisher) if publisher else "Viserio CD Raid"

        # L'API d'abord : la note telle que l'auteur l'a ecrite, avec ses
        # phases. La lecture du HTML ne sert plus que de secours.
        details = {}
        listing = fetch_note_api(slug, args.cache_hours)
        parsed, why = parse_note_api(listing) if listing else (None, "API muette")
        if parsed:
            specs = parsed
            details = why
        else:
            print(f"[INFO] {note_name} : lecture HTML ({why}).")
            html = fetch_note(url, args.cache_hours)
            if not html:
                continue
            sections = parse_page(html)
            specs = None
        if specs is None and not sections:
            print(f"[SKIP] Timeline vide ou illisible : {note_name} — {url}")
            rejected_notes_by_boss[boss_slug] += 1
            if args.viserio_top:
                print("       -> quota inchangé, recherche d'une remplaçante valide.")
            continue

        if specs is None:
            specs = {}
            for (cls, spec), spec_actors in sections.items():
                spec_id = SPEC_IDS.get((cls, spec))
                if not spec_id:
                    continue
                # Liste d'acteurs (un par joueur de cette spe dans la note).
                specs[spec_id] = spec_actors
        if not specs:
            print(f"[SKIP] Timeline sans spécialisation reconnue : {note_name} — {url}")
            rejected_notes_by_boss[boss_slug] += 1
            if args.viserio_top:
                print("       -> quota inchangé, recherche d'une remplaçante valide.")
            continue

        enc_names[enc_id] = boss_name
        plans_raid[enc_id] = raid
        if raid not in raids_order:
            raids_order.append(raid)
        raids_meta[raid] = {"season": SEASONS.get(raw_slug, 0)}
        full_notes[enc_id].append({
            "name": note_name, "author": note_author,
            "difficulty": difficulty, "specs": specs,
            "details": details,
        })
        valid_notes_by_boss[boss_slug] += 1
        copies = (it.get("stats") or {}).get("copies")
        pop = f", {copies} copies" if copies is not None else ""
        quota = (
            f", valide {valid_notes_by_boss[boss_slug]}/{args.viserio_top}"
            if args.viserio_top else ""
        )
        print(
            f"[OK  ] {boss_name} [{raid}] ({difficulty}) — {note_name} : "
            f"{len(specs)} spés{pop}{quota}"
        )

    if unknown_raid_slugs:
        print(f"\n[WARN] {len(unknown_raid_slugs)} slug(s) de raid Viserio "
              f"non reconnu(s) par SEASONS/RAID_NAMES — comme pour "
              f"\"the-tidebound-grotto\" plus tôt, ça finit sinon en saison "
              f"0/\"Autre\" avec le slug brut affiché tel quel :")
        for slug, bosses in sorted(unknown_raid_slugs.items()):
            print(f"       - \"{slug}\" (boss concerné(s) : {', '.join(sorted(bosses))})")
        print("       -> ajoute ce slug dans les tables SEASONS et "
              "RAID_NAMES du script avec le bon nom d'affichage et la "
              "bonne saison, puis relance.")

    if args.viserio_top:
        for boss_slug, rejected in sorted(rejected_notes_by_boss.items()):
            if not rejected:
                continue
            valid = valid_notes_by_boss[boss_slug]
            if valid < args.viserio_top:
                print(
                    f"[INCOMPLET] {boss_slug or '?'} : "
                    f"{valid}/{args.viserio_top} notes valides après épuisement "
                    f"des candidates ({rejected} rejetée(s)).")

    if not full_notes:
        raise SourceBuildAborted("Rien à générer.")

    validate_full_notes(full_notes, enc_names, "Viserio CD Raid")
    if not args.no_nsrt_fetch:
        hint = addon_root(args)
        os.makedirs(os.path.join(hint, "Data", "Viserio"), exist_ok=True)
        write_viserio_frise(hint, set(full_notes))
    data_root, file_count = write_viserio_boss_files(
        args.out, full_notes, raids_order, args.current_season,
        plans_raid, enc_names, raids_meta, addon_dir=args.addon_dir)

    bosses = set(full_notes)
    specs_seen = {s for notes in full_notes.values() for n in notes for s in n["specs"]}
    note_count = sum(len(v) for v in full_notes.values())
    print(f"\n=== Terminé : {data_root} ===")
    print(f"  {len(raids_order)} raid(s), {len(bosses)} boss, "
          f"{note_count} notes complètes, {len(specs_seen)} spécialisations couvertes")
    print(f"  {file_count} fichier(s) de boss dans {data_root}, "
          "un seul par boss (toutes spés et difficultés confondues).")
    print("  Le fichier NSRTAutoReminders.toc a été mis à jour automatiquement "
          "lorsqu'il est trouvé (--addon-dir ou dossier de --out).")


if __name__ == "__main__":
    main()
