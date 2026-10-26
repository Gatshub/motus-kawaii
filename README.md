# Motus kawaii ♡

Motus (a.k.a. Lingo) dans le terminal — **Ruby + Charm Ruby** (`bubbletea`, `lipgloss`).

## Règles (comme à la TV)
- Un mot de N lettres à deviner, première lettre donnée.
- 6 essais ; à chaque échec, une lettre de plus est révélée.
- 🟥 carré = lettre bien placée · 🟦 rond = présente mais mal placée.

## Niveaux
`1` 5 lettres · `2` 6 · `3` 7 · `4` 8 · `5` 9 — tous en 6 essais.

## Dictionnaire
`data/mots.txt` : ~95 000 mots français (5–9 lettres, fusion Hunspell + Letterpress).
Les formes fléchées sont acceptées comme propositions ; le *secret* mériterait
un filtrage sur les lemmes (amélioration future).

## Touches
lettres · `←→` bouger · `backspace` effacer · `entrée` valider · `m` menu · `q` quitter
(pendant la saisie, `n`/`m`/`h`/`j`/`k`/`l` sont des lettres, pas des commandes)

## Couleurs
Palette adaptative clair/sombre (Lipgloss AdaptiveColor).
