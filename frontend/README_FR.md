# 🌍 ECODZ — Application Mobile Écologique Algérienne

> **Version 1.0.0** | Stack: Flutter + Supabase | Date: Avril 2026

## 📋 Table des matières

1. [Vue d'ensemble](#-vue-densemble)
2. [Installation et Configuration](#-installation-et-configuration)
3. [Processus Utilisateur — Flux Complet](#-processus-utilisateur--flux-complet)
4. [Fonctionnalités Principales](#-fonctionnalités-principales)
5. [Système de Gamification](#-système-de-gamification)
6. [Système de Vote](#-système-de-vote)
7. [Intégration Cartographique](#-intégration-cartographique)
8. [Architecture Technique](#-architecture-technique)

---

## 🌱 Vue d'ensemble

**ECODZ** est une application mobile communautaire dédiée aux actions écologiques pour les citoyens algériens. Elle permet aux utilisateurs de:

- **📍 Signaler** les problèmes environnementaux (pollution, dépotoir illégal, espaces verts dégradés, etc.) avec géolocalisation
- **🤝 S'engager** à résoudre ces problèmes physiquement (ramasser des déchets, planter des arbres, nettoyer l'eau)
- **✅ Valider** le travail des autres utilisateurs via un système de vote communautaire décentralisé
- **⭐ Gagner des points XP** et monter de niveau en récompense des actions écologiques réelles

### Philosophie de l'app
```
Signaler → Vote communautaire → Quelqu'un fait le travail → Validation communautaire → XP Récompense
```

**Stack Technologique:**
- **Frontend**: Flutter (Dart) — Application mobile iOS, Android, Web, Windows
- **Backend**: Supabase (PostgreSQL) — Base de données, authentification, stockage
- **Cartographie**: OpenStreetMap (gratuit, sans API key)
- **Géolocalisation**: Nominatim API + GPS de l'appareil

---

## 💻 Installation et Configuration

### Prérequis
- Flutter SDK 3.x installé
- Compte Supabase (accès à la base de données PostgreSQL)
- Credentials Supabase (URL, Clé anonyme)

### Étapes d'installation

1. **Cloner le projet et installer les dépendances**
   ```bash
   cd frontend
   flutter pub get
   ```

2. **Configurer les variables d'environnement Supabase**
   
   Créer un fichier `lib/config/supabase_config.dart`:
   ```dart
   class SupabaseConfig {
     static const String url = 'https://your-project.supabase.co';
     static const String anonKey = 'your-anon-key';
     
     static void validate() {
       if (url.isEmpty || anonKey.isEmpty) {
         throw Exception('Supabase credentials not configured!');
       }
     }
   }
   ```

3. **Lancer l'application**
   ```bash
   flutter run
   ```

---

## 👥 Processus Utilisateur — Flux Complet

### 1️⃣ **Inscription (Sign Up)**

**Fichier:** `lib/pages/signup.dart`

**Étapes:**
1. L'utilisateur remplit le formulaire:
   - Nom complet
   - Email
   - Numéro de téléphone
   - Mot de passe

2. Le formulaire valide les champs (email format, mot de passe min 8 caractères)

3. **Appel API**: `supabase.auth.signUp()` avec métadonnées utilisateur

4. **Trigger automatique**: La base de données crée automatiquement un profil dans la table `profiles`

5. **Email de confirmation**: Un email de vérification est envoyé à l'utilisateur

**Exemple:**
```
Ahmed s'inscrit:
- Nom: Ahmed Boudjemaa
- Email: ahmed.b@example.com
- Téléphone: +213 555 123456
- Mot de passe: SecurePass123

✓ Email de confirmation envoyé
✓ Profil créé: level 1, xp 0, reputation 0
```

---

### 2️⃣ **Connexion (Login)**

**Fichier:** `lib/pages/login.dart`

**Étapes:**
1. Saisir email et mot de passe
2. Case à cocher "Se souvenir de moi" (optionnel)
3. Appel `supabase.auth.signInWithPassword()`
4. Si succès → Navigation vers la page d'accueil
5. Si erreur → Affichage du message (email non confirmé, mauvais identifiants, etc.)

**Exemple:**
```
Ahmed se connecte:
Email: ahmed.b@example.com
Mot de passe: SecurePass123

✓ Authentification réussie
✓ Session active (JWT token stocké)
✓ Redirection vers HomePage
```

---

### 3️⃣ **Page d'Accueil (Home Page)**

**Fichier:** `lib/pages/home.dart`

**Interface:**

| Élément | Description |
|---------|-------------|
| **En-tête** | Avatar utilisateur, nom, badge de niveau XP + barre de progression |
| **Barre de recherche** | Filtrer par titre, localisation, date, XP |
| **Chips de catégories** | Carrousel horizontale des types d'activités |
| **Fil d'activités** | Cartes affichant les activités ouvertes/approuvées |
| **Bouton FAB (+)** | Créer une nouvelle activité |

**Exemple de fil d'activités:**
```
┌────────────────────────────────────────┐
│ 🌳 Plantation d'arbres à Béjaïa      │
│ 📍 Rue Didouche Mourad, Alger        │
│ ⭐ 100 XP | 2 participants           │
│ 📅 15 mai 2026                        │
└────────────────────────────────────────┘

┌────────────────────────────────────────┐
│ 🏖️ Nettoyage plage Sidi Frères       │
│ 📍 Plage Sidi Frères, Béjaïa         │
│ ⭐ 150 XP | En cours...              │
│ 📅 20 mai 2026                        │
└────────────────────────────────────────┘
```

---

### 4️⃣ **Créer une Activité (Create Activity)**

**Fichier:** `lib/widgets/create_activity_modal.dart`

**Processus étape par étape:**

#### Étape 1: Remplir les informations de base
```
Titre: "Nettoyage route Béjaïa-Sidi Aïch"
Description: "Collecte des déchets plastiques et débris le long de la route..."
Catégorie: [Sélectionner] → "Gestion des déchets"
Niveau de difficulté: [Sélectionner] → "Moyen" (100-150 XP)
XP à récompenser: 120
```

#### Étape 2: Sélectionner une localisation
- **Option A**: Appuyer sur "Détecter ma position" → GPS automatique
- **Option B**: Saisir le nom du lieu → Recherche Nominatim → Suggestions
- **Option C**: Toucher la carte → Épingler manuellement

**Exemple:**
```
Utilisateur tape: "Plage Sidi Frères"
↓ Nominatim retourne:
  • Plage Sidi Frères, Béjaïa
  • Avenue Sidi Frères, Alger
  • Rue Sidi Frères, Oran
↓ Utilisateur sélectionne: Plage Sidi Frères, Béjaïa
↓ Coordonnées sauvegardées:
  latitude: 36.7898
  longitude: 5.0652
  localisation: "Plage Sidi Frères, Béjaïa"
```

#### Étape 3: Télécharger une photo "avant"
- Ouvrir la galerie ou caméra
- Sélectionner/prendre une photo
- Télécharger dans le bucket Supabase `activity_image`
- URL de la photo sauvegardée dans la base de données

#### Étape 4: Soumettre
- **Insertion en base de données:**
  ```sql
  INSERT INTO activite 
  (titre, description, localisation, latitude, longitude, 
   xpfinal, status, id_type_act, id_utilisateur, id_niv_act)
  VALUES 
  ('Nettoyage route Béjaïa-Sidi Aïch', ..., 'waiting', ...)
  ```
- **Insertion de la photo:**
  ```sql
  INSERT INTO preuve (url, type, id_act)
  VALUES ('https://...photo_url...', 'avant', 1)
  ```
- **État**: L'activité est en attente de vote d'approbation

**Exemple complet:**
```
Fatima crée une activité:

✓ Titre: "Nettoyage parc Taddart"
✓ Description: "Enlever les déchets et les mauvaises herbes du parc municipal"
✓ Catégorie: Espaces verts
✓ Niveau: Facile (50-75 XP)
✓ XP proposé: 60
✓ Localisation: Parc Taddart, Béjaïa (36.7512, 5.0843)
✓ Photo avant: /uploads/activity_image/uuid-123.jpg

✓✓ ACTIVITÉ CRÉÉE ✓✓
État: En attente d'approbation (waiting)
ID: 42

💬 Système: "Vote en cours! 2 membres communautaires vont voter..."
```

---

### 5️⃣ **Vote d'Approbation (Approval Voting)**

**Fichier:** `lib/pages/activity.dart` → Onglet "Approbation"

**Processus:**

Une activité créée par Fatima (Status: `waiting`) apparaît dans la queue de vote.

**Règles de vote:**
- Besoin de **exactement 2 votes** pour décider
- Le créateur **ne peut pas voter** sur sa propre activité
- Chaque utilisateur vote **une seule fois** (UNIQUE constraint)
- Valeurs: `1` = Approuver, `-1` = Rejeter

**Exemple:**

```
ACTIVITÉ: "Nettoyage parc Taddart" (ID: 42)
Créatrice: Fatima
Status: waiting
────────────────────────────────────

VOTE 1:
Votant: Ahmed ✓
Vote: Approuver (+1)
Raison: "C'est un vrai problème, j'ai vu le parc dégradé"

VOTE 2:
Votant: Leïla ✓
Vote: Approuver (+1)
Raison: "Oui, très utile pour la communauté"

RÉSULTAT:
Approvals: 2 | Rejections: 0
✅ APPROBÉE!
Status change: waiting → priority_pending
────────────────────────────────────

🔔 NOTIFICATION À FATIMA:
"Votre activité a été approuvée! Vous avez 2 minutes pour l'accepter..."
```

**Scénario alternatif (Rejet):**
```
VOTE 1: Ahmed - Rejeter (-1)
VOTE 2: Leïla - Rejeter (-1)

RÉSULTAT:
Approvals: 0 | Rejections: 2
❌ REJETÉE!
Status change: waiting → rejected
────────────────────────────────────

💬 Notification: "Votre activité a été rejetée par la communauté."
```

---

### 6️⃣ **Fenêtre de Priorité (Priority Window)**

**Durée:** 2 minutes après approbation

**Situation:** L'activité de Fatima a été approuvée. Elle a 2 minutes pour l'accepter comme travailleuse.

**Options de Fatima:**
- ✅ **Accepter**: Elle devient travailleuse assignée
- ❌ **Refuser**: L'activité devient ouverte pour tous

**Exemple - Scénario 1 (Accepte):**
```
Fatima clique "Accepter l'activité"

Status: priority_pending → in_progress
Travailleur assigné: Fatima
────────────────────────────────────

ACTIVITÉ ACTIVE:
"Nettoyage parc Taddart"
Travailleur: Fatima
Status: En cours (in_progress)

💬 Notification: "Activité acceptée! Allez faire le travail et soumettez les photos après."
```

**Scénario 2 (Refus ou délai expiré):**
```
Fatima ne répond pas dans les 2 minutes
OU
Fatima clique "Refuser"

Status: priority_pending → open
────────────────────────────────────

ACTIVITÉ OUVERTE:
"Nettoyage parc Taddart"
Status: Disponible (open)
"Rejoindre l'activité" bouton actif

💬 Notification: "L'activité est maintenant ouverte. N'importe qui peut la rejoindre!"
```

---

### 7️⃣ **Rejoindre une Activité Ouverte (Join Open Activity)**

**Situation:** L'activité de Fatima est en statut `open` (elle a refusé ou le délai a expiré).

**Processus:**

Ahmed voit l'activité et clique sur "Rejoindre l'activité"

```
RPC Function: join_open_activity(p_act_id, p_user_id)

↓ Base de données:
- UPDATE activite SET assigned_worker_id = Ahmed.id
- Status: open → in_progress

✓ Ahmed devient travailleur assigné
✓ Notification: "Vous êtes maintenant responsable de cette activité!"
```

**Exemple:**
```
ACTIVITÉ MISE À JOUR:
"Nettoyage parc Taddart"

Avant: open (Fatima a refusé)
Après: in_progress (Ahmed a rejoint)

Travailleur: Ahmed
Status: En cours
────────────────────────────────────

🔔 Ahmed: "Vous avez rejoint l'activité! Faites le travail et soumettez-le."
🔔 Fatima (Créatrice): "Ahmed a accepté votre activité. Il va faire le travail!"
```

---

### 8️⃣ **Soumettre le Travail Effectué (Work Submission)**

**Fichier:** `lib/pages/work_completion_page.dart`

**Processus:**

Ahmed a terminé le nettoyage du parc. Il soumet des photos "après".

**Étapes:**
1. Prendre/sélectionner des photos "après"
2. Télécharger chaque photo dans Supabase Storage
3. Enregistrer les URLs dans la table `preuve` avec type `'apres'`
4. Appel RPC: `submit_work_completion(p_act_id)`
5. Status change: `in_progress` → `pending_validation`

**Exemple:**
```
SOUMISSION PAR AHMED:

Photos téléchargées:
  ✓ photo_apres_1.jpg (parc nettoyé, vue générale)
  ✓ photo_apres_2.jpg (allée nettoyée, détail)
  ✓ photo_apres_3.jpg (avant/après comparaison)

Insérées en base:
  INSERT INTO preuve VALUES 
  (url: 'https://.../uuid-1.jpg', type: 'apres', id_act: 42),
  (url: 'https://.../uuid-2.jpg', type: 'apres', id_act: 42),
  (url: 'https://.../uuid-3.jpg', type: 'apres', id_act: 42);

Status: in_progress → pending_validation
completed_at: 2026-05-20 14:30:00
────────────────────────────────────

💬 Ahmed: "✓ Travail soumis pour validation!"
💬 Communauté: "Nouvelle activité en attente de validation! Allez voter..."
```

---

### 9️⃣ **Vote de Validation (Completion Voting)**

**Fichier:** `lib/pages/activity.dart` → Onglet "Validation"

**Processus:**

L'activité d'Ahmed est en statut `pending_validation`. La communauté vote pour confirmer que le travail a été réellement effectué.

**Règles:**
- Minimum **2 votes**, maximum **5 votes** pour décider
- Le travailleur (Ahmed) **ne peut pas voter** sur sa soumission
- Les votants approuvant proposent un montant XP (optionnel)
- Résultat final: **XP = MOYENNE des propositions XP acceptées**

**Exemple avec 3 votants:**
```
ACTIVITÉ EN VALIDATION: "Nettoyage parc Taddart" (ID: 42)
Travailleur: Ahmed
Créateur XP proposé: 60
Limite: min 2, max 5 votes
────────────────────────────────────

VOTE 1:
Votant: Leïla ✓
Décision: Approuver
XP proposé: 60 XP
Commentaire: "Excellent travail! Le parc est vraiment propre."

VOTE 2:
Votant: Karim ✓
Décision: Approuver
XP proposé: 80 XP
Commentaire: "Les mauvaises herbes aussi enlevées, merci!"

VOTE 3:
Votant: Aïcha ✓
Décision: Approuver
XP proposé: 70 XP
Commentaire: "Très bon, les photos avant/après le montrent clairement."

RÉSULTAT:
Approvals: 3 | Rejections: 0
✅ TRAVAIL APPROUVÉ!

XP Calculé: (60 + 80 + 70) / 3 = 70 XP
────────────────────────────────────

Status: pending_validation → completed
Ahmed.xp += 70
Ahmed.level = calculate_level(Ahmed.xp)

🎉 Ahmed: "Congratulations! Vous avez gagné 70 XP! Nouveau niveau: Sprout 🌱"
🎉 Créateur (Fatima): "Votre activité est complétée!"
```

**Scénario alternatif (Vote rejeté):**
```
VOTE 1: Leïla - Rejeter
VOTE 2: Karim - Rejeter

RÉSULTAT:
Approvals: 0 | Rejections: 2
❌ TRAVAIL REJETÉ!

Status: pending_validation → open (réassignée)
Ahmed reste avec son XP existant (aucun nouveau XP)

💬 Notification: "Votre travail n'a pas été accepté. L'activité est réouverte."
💬 Ahmed peut rejoindre à nouveau OU une autre personne peut rejoindre
```

---

### 🔟 **Onglet Activités (Activity Tab)**

**Fichier:** `lib/pages/activity.dart`

L'onglet Activités affiche 2 sections principales:

#### **Section Communauté** (3 sous-onglets)
| Sous-onglet | Affiche | Action possible |
|---|---|---|
| **Approbation** | Activités en `waiting` | Voter pour approbation |
| **Validation** | Activités en `pending_validation` | Voter pour valider le travail |
| **Historique personnel** | Activités terminées par l'utilisateur | Afficher les résultats |

#### **Section Mon Travail** (4 sous-onglets)
| Sous-onglet | Affiche | Action possible |
|---|---|---|
| **Priorité** | Activités en `priority_pending` pour créateur | Accepter / Refuser (2 min) |
| **Disponible** | Activités en `open` | Rejoindre |
| **En cours** | Activités en `in_progress` assignées à moi | Soumettre travail |
| **Terminée** | Activités en `completed` où j'ai travaillé | Voir résultats |

**Exemple d'écran:**
```
┌──────────────────────────────────────────┐
│ SECTION: MON TRAVAIL                     │
├──────────────────────────────────────────┤
│ 🔵 Priorité (1)     🟡 Disponible (5)   │
│ 🟢 En cours (3)     ✅ Terminée (8)    │
├──────────────────────────────────────────┤
│ Onglet: EN COURS                         │
├──────────────────────────────────────────┤
│ 🌳 Plantation d'arbres - Béjaïa         │
│ Status: En cours | Créateur: Zainab     │
│ 🔘 Soumettre le travail                 │
│                                          │
│ 🏖️ Nettoyage plage Sidi Frères         │
│ Status: En cours | Créateur: Karim      │
│ 🔘 Soumettre le travail                 │
└──────────────────────────────────────────┘
```

---

### 1️⃣1️⃣ **Onglet Recherche / Carte (Search & Map)**

**Fichier:** `lib/pages/search.dart`

**Interface:**
- **Carte interactive** (OpenStreetMap) affichant toutes les activités en tant que marqueurs
- **Chips de filtres** (catégories) en haut
- **Bouton de géolocalisation** (centrer sur ma position)
- **Panneau inférieur** listant les activités à proximité

**Exemple d'utilisation:**
```
Ahmed ouvre l'onglet Carte

✓ Carte centrée sur Béjaïa
✓ Marqueurs verts montrant:
  • 🌳 Plantation d'arbres (5 km)
  • 🏖️ Nettoyage plage (2 km)
  • 💧 Nettoyage source d'eau (8 km)

Ahmed tape "Nettoyage plage Sidi Frères" dans la barre
↓ Nominatim retourne la localisation
↓ Carte vole vers le marqueur
↓ Panneau inférieur: affiche détails de l'activité

Ahmed clique sur le marqueur
↓ Navigation vers ActivityDetailPage (détails complets)
```

---

### 1️⃣2️⃣ **Onglet Profil (Profile Page)**

**Fichier:** `lib/pages/profile.dart`

**Affiche:**
- 👤 Avatar, nom complet
- 📊 Niveau actuel + barre de progression XP
- 📈 Statistiques:
  - Activités complétées
  - Activités en cours
  - Score de réputation
- ⚙️ Paramètres du compte
- 🚪 Bouton Déconnexion

**Exemple:**
```
┌────────────────────────────────────┐
│        PROFIL D'AHMED              │
├────────────────────────────────────┤
│ [Avatar] Seedling Sprout 🌱       │
│         Ahmed Boudjemaa             │
│ ahmed.b@example.com                 │
│                                     │
│ NIVEAU 2: Sprout 🌱                │
│ ████░░░░░░░░░░░░ 45/60 XP          │
│                                     │
│ 📊 STATISTIQUES                     │
│ ✓ Complétées: 3 activités          │
│ ⏳ En cours: 2 activités           │
│ ⭐ Réputation: 42                   │
│                                     │
│ ⚙️ Paramètres                       │
│ 🚪 Déconnexion                      │
└────────────────────────────────────┘
```

---

## 🎮 Fonctionnalités Principales

### 🗺️ Intégration Cartographique

#### Cartographie (OpenStreetMap)
- Basée sur `flutter_map` — **100% gratuite**, aucune API key requise
- Tuiles OSM mises en cache localement
- Marqueurs interactifs pour chaque activité

#### Géolocalisation GPS
- Détecte automatiquement la position de l'utilisateur
- Appuyer sur "Ma position" → Carte se centre sur vous
- Permissions demandées (iOS/Android)

#### Géocodage (Nominatim API)
Nominatim est un service **gratuit et open-source** pour convertir adresses ↔ coordonnées GPS.

**Endpoints utilisés:**
```
1. Forward Geocoding (Recherche par nom):
   GET https://nominatim.openstreetmap.org/search
       ?q=Plage Sidi Frères
       &format=json
       &limit=5
   
   Réponse:
   [{
     "lat": "36.7898",
     "lon": "5.0652",
     "display_name": "Plage Sidi Frères, Béjaïa, Algérie"
   }]

2. Reverse Geocoding (Localisation vers adresse):
   GET https://nominatim.openstreetmap.org/reverse
       ?lat=36.7898
       &lon=5.0652
       &format=json
   
   Réponse:
   {
     "address": {
       "road": "Route Nationale",
       "village": "Sidi Frères",
       "county": "Béjaïa"
     },
     "display_name": "Plage Sidi Frères, Béjaïa"
   }
```

**Implémentation dans l'app:**
- Débounce de 600ms pour éviter la surcharge
- User-Agent: `ecodz-app/1.0` (requis par les ToS de Nominatim)
- Timeout: 8 secondes par requête

**Exemple complet:**
```
Utilisateur crée une activité:

1. Appuie sur "Sélectionner localisation"
   → Carte plein écran s'ouvre

2. Tape "Pont de Toudja" dans la barre de recherche
   → API Nominatim: /search?q=Pont de Toudja
   → Résultats: [
       "Pont de Toudja, Béjaïa",
       "Rue Toudja, Alger",
       "Pont Toudja (Est), Oran"
     ]

3. Sélectionne "Pont de Toudja, Béjaïa"
   → Carte vole à: lat=36.8001, lon=5.0754
   → Épingle rouge placée

4. Reverse geocoding auto:
   → API Nominatim: /reverse?lat=36.8001&lon=5.0754
   → Adresse retournée: "Pont de Toudja, Béjaïa 06000"

5. Valide la localisation
   → Coordonnées sauvegardées:
     {
       "latitude": 36.8001,
       "longitude": 5.0754,
       "localisation": "Pont de Toudja, Béjaïa 06000"
     }
```

---

## ⭐ Système de Gamification

### 💪 Points XP (Experience Points)

**Concept:** Les utilisateurs gagnent des points XP pour chaque activité validée par la communauté.

**Règles:**
- Stockés dans `profiles.xp` (entier, défaut: 0)
- **Jamais décrémentés** — seulement augmentés
- Accordés quand le travail est approuvé par vote

**Exemple:**
```
Ahmed complète 3 activités et reçoit:
- Activité 1: +60 XP (vote d'approbation avec moyenne 60)
- Activité 2: +75 XP (vote avec moyenne 75)
- Activité 3: +50 XP (vote avec moyenne 50)

Total XP d'Ahmed: 60 + 75 + 50 = 185 XP
```

### 📊 Système de Niveaux

**Niveaux & Plages XP:**

| Niveau | Titre | Plage XP | Emoji |
|--------|-------|----------|-------|
| 1 | Seedling (Graine) | 0 – 30 | 🌱 |
| 2 | Sprout (Germe) | 31 – 60 | 🌱 |
| 3 | Sapling (Jeune pousse) | 61 – 120 | 🌿 |
| 4 | Tree (Arbre) | 121 – 210 | 🌳 |
| 5 | Forest Guardian (Gardien de forêt) | 211 – 330 | 🌲 |
| 6 | Eco Warrior (Guerrier Écologique) | 331 – 480 | 💪 |
| 7 | Earth Defender (Défenseur de la Terre) | 481 – 660 | 🌍 |
| 8 | Planet Protector (Protecteur de la Planète) | 661 – 870 | 🌎 |
| 9+ | Legend (Légende) | 871+ | 👑 |

**Formule de progression:** Chaque niveau ajoute ~30 XP de base, puis augmente (niveau 3: 60, niveau 4: 90, etc.)

**Exemple de progression:**
```
Ahmed commence à 0 XP → Niveau 1: Seedling
↓ Gagne 60 XP (activités validées)
Ahmed maintenant 60 XP → Niveau 2: Sprout ✅
↓ Gagne 75 XP
Ahmed maintenant 135 XP → Niveau 4: Tree ✅
↓ Gagne 100 XP
Ahmed maintenant 235 XP → Niveau 5: Forest Guardian ✅

🎉 Ahmed a progressé de 3 niveaux!
```

### 🔄 Synchronisation Automatique Niveau ↔ XP

Une **trigger PostgreSQL** (fonction BEFORE UPDATE) maintient le niveau synchronisé automatiquement:

```sql
TRIGGER trg_sync_level BEFORE UPDATE OF xp ON profiles
  → Exécute: sync_level_from_xp()
  → Recalcule: NEW.level := calculate_level(NEW.xp)
```

**Avantage:** Impossible pour un utilisateur (ou un bug) de définir un niveau incorrect. Le niveau est **toujours dérivé de XP**.

### 🏅 Réputation

- Champ `profiles.reputation` entier
- **Intent:** Mesurer la fiabilité communautaire d'un utilisateur
- **Implémentation future:** Pourrait être décrémentée si l'utilisateur reçoit des votes négatifs répétés

### 🎖️ Badges (Système Futur)

Table `badge`:
- `nom`: Nom du badge (ex: "Nettoyeur de plages")
- `condition_badge`: Condition de déblocage (ex: "5 activités de plage validées")
- `icon`: Icône du badge

**État actuel:** Définis dans la base, mais **pas encore liés** aux profils utilisateurs.

---

## 🗳️ Système de Vote

### ✅ Vote d'Approbation (Approval Voting)

**Quoi:** Décider si une activité nouvellement signalée est légitime.

**Tableau:** `vote_approbation`

**Règles:**
- **Exactement 2 votes** requis
- Créateur **ne peut pas voter** sur sa propre activité
- Chaque utilisateur vote **une seule fois** (UNIQUE: id_act + id_user)
- Valeur: `1` (approuver) ou `-1` (rejeter)

**Résultat:**
```
Si Approbations > Rejections:
  → Status: waiting → priority_pending
  → Créateur reçoit notification (2 min pour accepter)

Si Rejections ≥ Approbations:
  → Status: waiting → rejected
  → Activité fermée
```

**Exemple:**
```
TABLEAU vote_approbation:
┌────────┬────────┬─────────┬──────┐
│ id_act │ id_user│ date    │ value│
├────────┼────────┼─────────┼──────┤
│  42    │ ahmed  │ 14:30   │  1   │ ✓ Approuve
│  42    │ leila  │ 14:32   │  1   │ ✓ Approuve
└────────┴────────┴─────────┴──────┘

2 votes d'approbation, 0 rejets
→ APPROUVÉE!
```

### 🎯 Vote de Validation (Completion Voting)

**Quoi:** Confirmer que le travail a **réellement** été effectué.

**Tableau:** `vote_completion`

**Règles:**
- **Min 2, Max 5 votes** pour décider
- Travailleur assigné **ne peut pas voter** sur sa soumission
- Propositions XP optionnelles par votants approuvant
- **Résultat XP final:** MOYENNE des propositions acceptées

**Exemple détaillé:**
```
ACTIVITÉ: "Nettoyage plage" (ID: 42)
Status: pending_validation
Travailleur: Ahmed

TABLEAU vote_completion:
┌────────┬────────┬─────────┬─────────┬──────────────┐
│ id_act │ id_user│ approve │ date    │ xp_proposal  │
├────────┼────────┼─────────┼─────────┼──────────────┤
│  42    │ leila  │ true    │ 15:00   │ 60           │
│  42    │ karim  │ true    │ 15:02   │ 80           │
│  42    │ aicha  │ true    │ 15:04   │ 70           │
└────────┴────────┴─────────┴─────────┴──────────────┘

Approbations: 3
Rejections: 0
XP Calculé: (60 + 80 + 70) / 3 = 70 XP

→ Status: pending_validation → completed
→ Ahmed.xp += 70
→ Notification: "🎉 70 XP gagnés!"

Scénario rejoint:
┌────────┬────────┬─────────┬─────────┬──────────────┐
│ id_act │ id_user│ approve │ date    │ xp_proposal  │
├────────┼────────┼─────────┼─────────┼──────────────┤
│  42    │ leila  │ false   │ 15:00   │ NULL         │
│  42    │ karim  │ false   │ 15:02   │ NULL         │
└────────┴────────┴─────────┴─────────┴──────────────┘

Approbations: 0
Rejections: 2
→ Status: pending_validation → open (réassignée)
→ Aucun XP accordé
→ Notification: "❌ Travail rejeté, réessayez"
```

---

## 🔐 Architecture Technique

### Architecture générale

```
┌─────────────────────────────┐
│    APPLICATION FLUTTER      │
│  (Frontend iOS/Android)     │
├─────────────────────────────┤
│ Pages, Widgets, Services    │
│  UserService               │
│  LevelSystem (calcul XP)   │
│  LocationPicker            │
└──────────────┬──────────────┘
               │ HTTP(S)
               ▼
┌─────────────────────────────┐
│    SUPABASE CLOUD           │
├─────────────────────────────┤
│ 🗄️ PostgreSQL Database     │
│  Tables: activite, profiles,│
│   vote_approbation, etc.    │
│                             │
│ 🔐 Supabase Auth (JWT)     │
│  Email/Password            │
│  Session Management        │
│                             │
│ 📦 Storage Bucket           │
│  activity_image/           │
│  (Photos avant/après)      │
│                             │
│ ⚙️ RPC Functions           │
│  cast_approval_vote()      │
│  submit_work_completion()  │
│  join_open_activity()      │
└──────────────┬──────────────┘
               │ HTTP
               ▼
┌─────────────────────────────┐
│  NOMINATIM / OSM            │
│  (Géocodage gratuit)        │
└─────────────────────────────┘
```

### Packages Flutter Clés

```dart
supabase_flutter: ^2.12.2    // Client Supabase (DB, Auth, Storage)
flutter_map: ^8.2.2          // Rendu cartes OpenStreetMap
latlong2: ^0.9.1             // Modèle de coordonnées LatLng
geolocator: ^13.0.2          // GPS de l'appareil
geocoding: ^3.0.0            // Géocodage au niveau appareil
http: ^1.2.0                 // Requêtes HTTP (Nominatim)
image_picker: ^1.1.2         // Sélecteur photos
```

### Schéma Base de Données (Résumé)

```sql
-- Utilisateurs
profiles (
  id uuid PRIMARY KEY,
  full_name text,
  email text UNIQUE,
  level integer,      -- Synchronisé via trigger
  xp integer,         -- Points gagnés
  reputation integer
)

-- Activités
activite (
  id_act integer PRIMARY KEY,
  titre text,
  description text,
  localisation text,
  latitude double,
  longitude double,
  status text,        -- waiting, priority_pending, open, in_progress, pending_validation, completed, rejected
  xpfinal integer,    -- XP proposé initialement
  id_utilisateur uuid,-- Créateur
  assigned_worker_id uuid,  -- Travailleur en cours
  id_type_act integer,-- Type/Catégorie
  id_niv_act integer  -- Niveau difficulté
)

-- Photos (Preuves)
preuve (
  id_preuve integer PRIMARY KEY,
  url text,
  type text,          -- 'avant' ou 'apres'
  id_act integer FK
)

-- Votes d'approbation
vote_approbation (
  id integer PRIMARY KEY,
  id_act integer FK,
  id_utilisateur uuid FK,
  valeur integer,     -- 1 ou -1
  UNIQUE(id_act, id_utilisateur)
)

-- Votes de validation
vote_completion (
  id integer PRIMARY KEY,
  id_act integer FK,
  id_utilisateur uuid FK,
  approve boolean,
  xp_proposal integer,
  UNIQUE(id_act, id_utilisateur)
)
```

---

## 🚀 Exemple Complet: Cycle de Vie d'une Activité

**Titre:** Nettoyage Rue Didouche Mourad, Alger

### Jour 1 - Création (10:00)
```
✏️ Fatima crée:
   Titre: "Nettoyage rue Didouche Mourad"
   Description: "Ramasser les déchets et nettoyer les trottoirs"
   Localisation: 36.7525, 5.0843 (Alger)
   Catégorie: Gestion des déchets
   Niveau: Moyen (100-150 XP)
   XP proposé: 120
   Photo avant: ✓ Téléchargée

✅ Activité créée
   Status: waiting
   ID: 123
   
🔔 Système: "Activité créée! En attente de vote..."
```

### Jour 1 - Vote d'Approbation (10:15)
```
👤 Ahmed accède à "Approbation"
   Voit: "Nettoyage rue Didouche Mourad"
   
   Clique: Approuver ✓
   Raison: "C'est vraiment dégradé, excellent signalement!"
   Vote: +1

👤 Leïla accède à "Approbation" (10:20)
   Voit: "Nettoyage rue Didouche Mourad"
   Vote: Approuver ✓

✅ 2 votes approbation, 0 rejet
   Status change: waiting → priority_pending
   
🔔 Fatima: "Activité approuvée! Vous avez 2 minutes pour l'accepter..."
```

### Jour 1 - Fenêtre Priorité (10:20-10:22)
```
⏱️ Fatima a 2 minutes pour réagir

Option 1: Accepter ✓ (à 10:21)
   → Status: priority_pending → in_progress
   → Fatima devient travailleuse
   → Notification: "Activité acceptée! Allez faire le travail..."

[Attendre 2 minutes...]

Option 2 (alternative): Délai expiré (10:22)
   → Status: priority_pending → open
   → Notification: "Temps écoulé, activité ouverte pour tous"
   → Quelqu'un d'autre peut la rejoindre
```

### Jour 1 - Travail en Cours (10:30-17:00)
```
🔨 Fatima travaille sur la rue
   (Nettoyage pendant plusieurs heures)

Status: in_progress
Travailleuse: Fatima
```

### Jour 1 - Soumission du Travail (17:30)
```
📸 Fatima prend des photos "après":
   - Photo 1: Vue générale (rue propre)
   - Photo 2: Détail trottoir avant/après
   - Photo 3: Angle différent (tous les déchets enlevés)

✓ 3 photos téléchargées vers Supabase Storage
✓ URLs ajoutées à la table 'preuve'
✓ RPC submit_work_completion() appelée

Status: in_progress → pending_validation
completed_at: 2026-05-20 17:30:00

🔔 Système: "Travail soumis pour validation communautaire!"
```

### Jour 2 - Vote de Validation (08:00-12:00)
```
👤 Ahmed accède à "Validation"
   Voit: "Nettoyage rue Didouche Mourad" (photos après)
   Clique: Approuver ✓
   XP proposé: 120
   Raison: "Magnifique travail! Rue complètement transformée!"
   Vote: ✅ (enregistré à 08:15)

👤 Leïla accède (10:30)
   Vote: Approuver ✓
   XP proposé: 100
   Raison: "Très bien! Pourrait y avoir quelques détails..."

👤 Aïcha accède (12:00)
   Vote: Approuver ✓
   XP proposé: 130
   Raison: "Excellent travail, au-delà des attentes!"

✅ 3 votes d'approbation, 0 rejet
   Approbations suffisantes (min 2, max 5 atteint 3)

XP FINAL: (120 + 100 + 130) / 3 = 116 XP
```

### Jour 2 - Activité Complétée (12:00)
```
✅ ACTIVITÉ COMPLÉTÉE!

Status change: pending_validation → completed

Fatima (Travailleuse):
  ✓ XP gagnés: +116
  ✓ Nouveau XP total: 116 (supposant elle avait 0 avant)
  ✓ Nouveau niveau: 4 (Tree 🌳) [plage 121-210]
  
🎉 Notification Fatima:
   "Félicitations! Votre travail a été approuvé!
    +116 XP gagnés! 🎉
    Nouveau niveau: Tree (Arbre) 🌳
    Prochaine étape: 210 XP (Forest Guardian)"

Communauté:
   ✓ Activité complétée (visible dans l'historique)
   ✓ Photos avant/après permanentes
   ✓ Votes permanents enregistrés

Base de données:
   activite.status = 'completed'
   activite.completed_at = 2026-05-20 12:00:00
   profiles.xp = 116 (Fatima)
   profiles.level = 4 (auto-synchronisé via trigger)
```

---

## 📞 Support & Contact

Pour toute question sur le fonctionnement de l'application:

- 📧 Email: support@ecodz.com
- 🌐 Site web: www.ecodz.com
- 📱 Téléphone: +213 555 123456

---

**Merci de contribuer à un Algérie plus verte! 🌍🌿**

*Fait avec ❤️ par l'équipe ECODZ*
