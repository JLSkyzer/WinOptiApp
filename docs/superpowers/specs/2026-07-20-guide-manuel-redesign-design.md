# Refonte de la page Guide manuel — conception

Date : 2026-07-20
Statut : approuvé par l'utilisateur, en attente de plan d'implémentation

## Contexte

La page Guide manuel actuelle est une checklist par onglets de catégorie, avec des cases
à cocher "fait/pas fait" et une description courte par entrée (`guide-steps.json`, 27
entrées à plat : `{id, category, title, description, action}`).

L'utilisateur a demandé :
1. Une entrée manquante pour activer manuellement Widgets/Copilot (réglage Windows non
   automatisable de façon fiable — voir note ci-dessous).
2. Un remplacement de la checklist par une navigation liste → détail, où chaque entrée
   ouvre une explication complète (quoi, pourquoi, étapes).
3. Une demande initiale de "scraper" des pages web tierces (texte + images) pour les
   inclure dans l'app — refusée pour raison de droit d'auteur (voir Stratégie de contenu).
4. Un ressenti que l'app manque de couverture pour l'optimisation gaming + bureautique
   — traité séparément dans le chantier "extension du catalogue de tweaks" (hors scope
   de ce document, voir Hors scope).

## Périmètre de ce document

Ce document couvre uniquement la refonte de la page Guide manuel (données + UI) et la
stratégie de contenu associée. L'extension du catalogue de tweaks automatisés (recherche
web, inspiration du pack RayOptimizer) fait l'objet d'un brainstorming et d'un spec
séparés.

## Stratégie de contenu (validé)

Aucun contenu ni image tiers n'est copié dans l'app. Chaque entrée de guide est rédigée
en texte original (explication + étapes numérotées). Quand un tutoriel externe illustre
bien le même réglage, un bouton "Voir la source" ouvre ce lien dans le navigateur par
défaut — l'app ne reproduit jamais le contenu de la page source.

Le guide reste une **bibliothèque de référence pure** : pas de suivi "fait/pas fait", pas
de compteur de progression (contrairement à l'ancienne page).

## Modèle de données (`guide-steps.json`)

Remplace le format plat actuel par une structure enrichie, entrée par entrée :

```json
{
  "id": "widgets-copilot-manual",
  "category": "confidentialite",
  "title": "Réactiver Widgets / Copilot dans la barre des tâches",
  "summary": "Phrase courte affichée dans la liste.",
  "relatedTweakId": "widgets-copilot-bing",
  "sourceUrl": "https://support.microsoft.com/...",
  "sourceLabel": "Voir l'article officiel Microsoft",
  "sections": [
    { "heading": "Pourquoi", "body": "Texte explicatif original..." },
    { "heading": "Étapes", "steps": ["Étape 1...", "Étape 2...", "..."] }
  ]
}
```

Règles de champ :
- `category` : **correction post-review** — en inspectant les 27 entrées existantes, leur
  regroupement naturel (NVIDIA Panneau de configuration, BIOS / UEFI, Moniteur /
  Affichage, CS2, Call of Duty, Battlefield, Paramètres Windows) ne correspond pas aux
  7 catégories des tweaks automatisés et perdrait sa structure en y étant forcé. Le
  guide garde donc **sa propre taxonomie de catégories**, indépendante de celle des
  tweaks. Les nouvelles entrées (ex. Widgets/Copilot) créent une nouvelle catégorie de
  guide si besoin (ici : "Confidentialité"). Le pont entre les deux mondes reste
  `relatedTweakId`, pas une catégorie partagée.
- `relatedTweakId` : optionnel. Quand présent, la page détail affiche un lien "Voir le
  tweak automatisé associé →" vers la page de catégorie correspondante.
- `sourceUrl` / `sourceLabel` : optionnels, uniquement quand un vrai tutoriel externe
  vérifié existe. Absents sinon (pas de lien inventé).
- `sections` : liste ouverte de blocs `{heading, body}` (texte libre) ou `{heading,
  steps: [...]}` (liste numérotée). Permet d'ajouter d'autres sections à l'avenir
  (ex. "Comment revenir en arrière") sans changer le schéma.
- Pas de champ `action` (exécution), pas de champ d'état "fait/pas fait".

Les 27 entrées existantes sont migrées vers ce format (réécriture du texte en
sections "Pourquoi"/"Étapes" ; les descriptions courtes actuelles deviennent `summary`).

## UI — vue divisée (liste + détail)

- La page Guide manuel devient une vue à deux colonnes toujours visibles (pas de
  navigation plein écran) :
  - **Colonne gauche** : liste des entrées groupées par catégorie (taxonomie propre au
    guide, voir Modèle de données), sous forme de sections repliables/dépliables. Une
    **barre de recherche** en haut filtre en direct sur `title`/`summary` — nécessaire
    car le nombre d'entrées va augmenter significativement.
  - **Colonne droite** : détail de l'entrée sélectionnée (titre, sections, bouton
    "Voir la source" si `sourceUrl`, lien vers le tweak associé si `relatedTweakId`).
- État par défaut (rien sélectionné) : message "Sélectionne une entrée à gauche".
- Sélectionner une entrée dans la liste ne change pas de page/route — seule la colonne
  de droite se met à jour (cohérent avec le choix "vue divisée" plutôt que "page
  complète" validé par comparaison de maquettes).

## Exemple de contenu validé : entrée Widgets/Copilot

Voir le JSON en section "Modèle de données" ci-dessus — contenu déjà rédigé et validé
avec l'utilisateur, y compris le lien source officiel Microsoft vérifié par recherche
web (support.microsoft.com).

## Hors scope (chantiers séparés)

- Extension du catalogue de tweaks automatisés (`tweaks-catalog.json`) via recherche
  web + inspiration du dossier `D:\Pack d'Opti RayOptimizer` — spec séparé à venir.
- Toute nouvelle entrée de guide au-delà de celle sur Widgets/Copilot suit le même
  gabarit défini ici, mais leur contenu sera rédigé lors du chantier d'extension.
