# Registre des trous connus

**Ce qui n'est pas couvert, pas vérifié, ou volontairement reporté.** Une entrée
par trou, chacune rédigée pour être confiée telle quelle à un agent.

Pourquoi ce fichier : l'information existait déjà, mais éparpillée entre
`JOURNAL.md` (chronologique, verbeux — cinq entrées rien que pour le lot 2 de la
synchro), les descriptions de PR (enterrées dès le merge) et `TODO.md` (le
backlog produit, pas les trous de vérification). Rien de tout ça ne répond à
« qu'est-ce qui n'est pas testé, et par quoi je commence ».

**Convention.** Chaque entrée porte un identifiant stable (`GAP-nn`), une
sévérité, ce qui n'est **pas** couvert, **pourquoi** ça a été laissé, et **ce qui
le fermerait**. Une entrée fermée est supprimée d'ici et son histoire reste dans
`JOURNAL.md`. Ne pas laisser d'entrée cochée traîner : un registre à moitié
périmé est pire que pas de registre.

> Les affirmations ci-dessous ont été vérifiées dans le code au 2026-08-14 —
> pas recopiées depuis un rapport d'agent. Avant d'agir sur une entrée, vérifier
> quand même qu'elle est toujours vraie : le code bouge, ce fichier moins vite.

---

## A. Synchro cloud — jamais confrontée au réel

### GAP-01 — La fusion n'a jamais tourné entre deux vrais appareils
**Sévérité : haute.** Toute la logique de fusion du lot 2 (les 4 règles, le rejeu
FSRS, les tombstones, le curseur composite) est couverte par des tests contre un
`FakeSyncServer` en mémoire. **Aucun test à deux appareils réels n'a jamais été
fait**, et c'est précisément le scénario pour lequel le lot existe.

Ce qui le fermerait : deux appareils (ou un device + un simulateur) avec le même
compte anonyme — noter la même carte hors ligne des deux côtés, reconnecter,
vérifier que les deux convergent vers le même état FSRS. Puis : supprimer une
carte sur A pendant que B la modifie, vérifier qu'elle disparaît partout.

Note : l'identité anonyme est **liée à l'appareil** (jeton dans le Trousseau),
donc partager un compte entre deux appareils n'est pas possible aujourd'hui sans
copier le jeton à la main. **Le lot 3 (Sign in with Apple) est ce qui rend ce
test faisable proprement** — c'est un argument de plus pour le faire.

### GAP-02 — Le pull n'a jamais tourné contre le vrai Supabase
**Sévérité : moyenne.** Ce qui a été éprouvé en réel : l'auth anonyme, l'upsert
et son idempotence, l'isolation RLS entre deux utilisateurs, la fonction de
suppression, et la syntaxe du curseur composite (parcours d'un paquet d'ex æquo
avec `limit=1`). Ce qui ne l'a **pas** été : `SyncPullActor` de bout en bout
contre le vrai PostgREST — pagination réelle, volumes réels, latence réelle.

Ce qui le fermerait : un script de fumée qui pousse ~2000 lignes, vide le store
local, relance un pull complet et compare. Attention : ~2000 lignes poussées en
un upsert forment **un seul paquet d'ex æquo** (trigger `now()`), ce qui est
justement le cas que le curseur composite est censé traiter — donc c'est le bon
volume de test, pas un excès.

---

## B. Synchro cloud — résidus assumés dans le code

### GAP-03 — Une ligne dont l'horodatage serveur est illisible retente sans fin
**Sévérité : basse.** `SyncPullActor.swift` (~:150 et ~:207). Si une ligne en
tête de page a un `id` valide mais un `server_updated_at` absent ou non
parsable, elle n'est jamais abandonnée de force : le curseur ne peut pas être
posé sur une position qu'on ne sait pas lire. Choix assumé et commenté
(« mieux vaut caler que fabriquer une position »), **mais aucun test ne le
couvre**.

Pourquoi c'est laissé : le cas suppose une écriture serveur anormale (le trigger
remplit toujours la colonne). Le risque est un blocage de table, pas une perte.

Ce qui le fermerait : décider si on veut un compteur borné là aussi, ou au
minimum écrire le test qui documente le comportement actuel.

### GAP-04 — Adoption d'id `RPGState` : une ligne serveur orpheline permanente
**Sévérité : basse.** `SyncPullActor.swift:705`. Après un pull échoué suivi d'un
push réussi, un appareil réinstallé peut pousser un `RPGState` neuf alors que le
serveur en détient déjà un pour le même profil. Le pull suivant les délivre tous
les deux : l'un fusionne, l'autre déclenche la branche d'adoption d'id. Le
système **se stabilise** (vérifié : pas de boucle) au prix d'une ligne serveur
orpheline par profil touché, et d'un changement d'identifiant sur un `@Model`
déjà persisté. Aucun compteur n'est perdu (fusion par `max()`).

Ce qui le fermerait : soit accepter et documenter, soit un nettoyage serveur des
`rpg_states` orphelins.

### GAP-05 — `ISO8601DateFormatter` tronque à la milliseconde
**Sévérité : informative.** Le serveur renvoie 6 chiffres de microsecondes ;
`…22.968936+00:00` et `…22.968999+00:00` donnent le **même** `Date`. Analysé :
conséquence possible = redélivrance de la queue d'une même milliseconde, jamais
de perte, parce que le curseur est toujours posé sur une ligne réellement
présente dans la page donc strictement en avant. La branche `eq` du filtre
utilise la **chaîne verbatim**, jamais un `Date` re-sérialisé — c'est ce qui
protège.

À ne pas « corriger » sans refaire l'analyse : c'est le genre de détail qu'on
casse en croyant l'améliorer.

---

## C. Périmètre volontairement reporté

### GAP-06 — Pas d'opt-in séparé pour l'historique Sakura
**Sévérité : bloquant si le chat part un jour au serveur.** La spec place cet
opt-in au lot 4 ; il a été reporté parce que **rien ne pousse
`companion_chat_messages` aujourd'hui**. Le chat reste local, `privacy.html` le
dit explicitement, et la fonction de suppression couvre quand même la table côté
serveur.

Règle à ne pas casser : **le jour où on pousse du contenu de conversation, cet
opt-in doit exister d'abord.** C'est un consentement distinct de la sauvegarde.

### GAP-07 — La fonction Edge n'est pas redéployée automatiquement
**Sévérité : moyenne (piège silencieux).** `supabase/config.toml` fige la config
et `CLAUDE.md` documente la commande, mais il n'y a **pas de step CI** (il
faudrait un secret `SUPABASE_ACCESS_TOKEN`). Si le projet Supabase est
réinitialisé, la suppression casse en 404 pendant que `privacy.html` continue de
la promettre.

Ce qui le fermerait : un job GitHub Actions sur `master` avec le secret, calqué
sur l'exemple officiel `supabase/setup-cli`.

---

## D. Hors synchro

### GAP-08 — La Watch ne produit aucun historique FSRS
**Sévérité : moyenne.** Vérifié : aucun `ReviewLog(` dans `IkeruWatch/`. Les
nano-sessions de la montre font travailler l'apprenant sans que ça alimente la
mémorisation à long terme — l'effort est réel, la trace n'existe pas.

Ce qui le fermerait : produire des `ReviewLog` côté montre et les remonter via
`WatchConnectivity` (`transferUserInfo`, file d'attente garantie), puis les
appliquer côté iPhone.

### GAP-09 — Aucune cible de tests UI
**Sévérité : moyenne.** L'infrastructure de fixtures par argument de lancement
existe, mais rien ne l'exerce. Aucun parcours utilisateur n'est testé de bout en
bout.

### GAP-10 — La CI ne lance qu'un sous-ensemble filtré des tests Core
**Sévérité : moyenne, contrainte externe.** Le filtre couvre ~40 motifs de suites
sur 1015 cas `@Test`. Ce n'est **pas** du code non testé : c'est l'image
`macos-15` dont la bibliothèque Swift Testing (1501) SIGSEGV sur une suite
legacy, alors que la toolchain locale (1902) passe tout. Débloqué par un bump de
l'image, pas par du travail sur nos tests.

---

## E. Dû par l'utilisateur (ne peut pas être fait par un agent)

### GAP-11 — Suppression de profil sur device
Supprimer un profil **actif**, puis un profil **non actif**. Guetter un nom vide
pendant l'animation de disparition. C'est le seul risque de crash que la
vérification statique ne peut pas trancher.

### GAP-12 — Parcours de sauvegarde cloud sur device
Activer l'interrupteur, vérifier que le statut passe à « À jour », puis
« Supprimer mes données du serveur » et vérifier le message de confirmation. La
fonction Edge est déployée et testée en HTTP, mais **le chemin app → fonction
n'a jamais été exercé depuis un vrai appareil**.
