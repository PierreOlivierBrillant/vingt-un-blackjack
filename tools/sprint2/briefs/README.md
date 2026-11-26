# Consignes des implémenteurs de la phase B (Sprint 2)

Ces fichiers sont les consignes exactes données aux 5 implémenteurs (sous-agents) le 26/11. Ils ont été
interrompus en fin de cours (poste DeepFreeze) : chaque branche `s2-<chantier>` se termine par un commit
« travail en cours (arrêt de fin de cours, NON vérifié) », qui peut ne pas compiler.

Pour relancer un implémenteur : lui donner le contenu de `<chantier>.md` (préambule « Reprise » compris).
Consignes communes : `tools/sprint2/PHASE_B.md`. Périmètres : `tools/sprint2/owners.json`.

| Chantier | Branche | Worktree court | Fichier |
|---|---|---|---|
| Roulette | `s2-roulette` | `C:\Users\<user>\s2\rl` | `roulette.md` |
| Baccarat | `s2-baccarat` | `C:\Users\<user>\s2\bc` | `baccarat.md` |
| Hold'em | `s2-holdem` | `C:\Users\<user>\s2\ho` | `holdem.md` |
| Craps | `s2-craps` | `C:\Users\<user>\s2\cr` | `craps.md` |
| Rendez-vous | `s2-romance` | `C:\Users\<user>\s2\rv` | `romance.md` |

## Préambule commun « Reprise » (à mettre en tête de chaque consigne relancée)

> Tu REPRENDS un chantier interrompu. Ta branche contient déjà du travail : d'abord `git log --oneline
> sprint-2..HEAD`, `git show --stat HEAD`, relis `tools/sprint2/requests/<chantier>.md` s'il existe, et
> fais un état des lieux (typecheck/lint/tests unitaires backend, `app\tool\test.ps1`) avant d'écrire du
> code. Le dernier commit « NON vérifié » peut ne pas compiler : répare d'abord, puis continue la liste
> ci-dessous là où elle s'arrête. Ne refais pas ce qui est fait et vert.
