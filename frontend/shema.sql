-- WARNING: This schema is for context only and is not meant to be run.
-- Table order and constraints may not be valid for execution.

CREATE TABLE public.activite (
  id_act integer NOT NULL DEFAULT nextval('activite_id_act_seq'::regclass),
  titre text,
  description text,
  localisation text,
  status text,
  xpfinal integer,
  datecreation timestamp without time zone DEFAULT now(),
  id_type_act integer,
  id_utilisateur uuid,
  id_niv_act integer,
  latitude double precision,
  longitude double precision,
  assigned_worker_id uuid,
  priority_deadline timestamp with time zone,
  completed_at timestamp with time zone,
  CONSTRAINT activite_pkey PRIMARY KEY (id_act),
  CONSTRAINT activite_id_type_act_fkey FOREIGN KEY (id_type_act) REFERENCES public.type_activite(id_type_act),
  CONSTRAINT activite_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id),
  CONSTRAINT activite_niveau_fk FOREIGN KEY (id_niv_act) REFERENCES public.niveau_activite(id_niv_act),
  CONSTRAINT activite_assigned_worker_id_fkey FOREIGN KEY (assigned_worker_id) REFERENCES public.profiles(id)
);
CREATE TABLE public.badge (
  id_badge integer NOT NULL DEFAULT nextval('badge_id_badge_seq'::regclass),
  nom text,
  condition_badge text,
  icon text,
  CONSTRAINT badge_pkey PRIMARY KEY (id_badge)
);
CREATE TABLE public.niveau_activite (
  id_niv_act integer NOT NULL DEFAULT nextval('niveau_activite_id_niv_act_seq'::regclass),
  description text,
  xpmin integer,
  xpmax integer,
  CONSTRAINT niveau_activite_pkey PRIMARY KEY (id_niv_act)
);
CREATE TABLE public.notification (
  id_message integer NOT NULL DEFAULT nextval('notification_id_message_seq'::regclass),
  type text,
  id_utilisateur uuid,
  message text,
  created_at timestamp without time zone DEFAULT now(),
  is_read boolean NOT NULL DEFAULT false,
  id_act integer,
  CONSTRAINT notification_pkey PRIMARY KEY (id_message),
  CONSTRAINT notification_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id),
  CONSTRAINT notification_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act)
);
CREATE TABLE public.preuve (
  id_preuve integer NOT NULL DEFAULT nextval('preuve_id_preuve_seq'::regclass),
  url text,
  type text CHECK (type = ANY (ARRAY['avant'::text, 'apres'::text])),
  timestamp timestamp without time zone DEFAULT now(),
  id_act integer,
  CONSTRAINT preuve_pkey PRIMARY KEY (id_preuve),
  CONSTRAINT preuve_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act)
);
CREATE TABLE public.profiles (
  id uuid NOT NULL,
  full_name text NOT NULL,
  email text NOT NULL UNIQUE,
  phone_number text,
  level integer DEFAULT 1,
  created_at timestamp with time zone DEFAULT now(),
  reputation integer DEFAULT 0,
  xp integer NOT NULL DEFAULT 0,
  CONSTRAINT profiles_pkey PRIMARY KEY (id),
  CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id)
);
CREATE TABLE public.reservation (
  id_reserv integer NOT NULL DEFAULT nextval('reservation_id_reserv_seq'::regclass),
  datedebut timestamp without time zone,
  date_exp timestamp without time zone,
  status text,
  id_utilisateur uuid,
  id_act integer,
  CONSTRAINT reservation_pkey PRIMARY KEY (id_reserv),
  CONSTRAINT reservation_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id),
  CONSTRAINT reservation_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act)
);
CREATE TABLE public.type_activite (
  id_type_act integer NOT NULL DEFAULT nextval('type_activite_id_type_act_seq'::regclass),
  nom text UNIQUE,
  icone text,
  CONSTRAINT type_activite_pkey PRIMARY KEY (id_type_act)
);
CREATE TABLE public.validation (
  id_validation integer NOT NULL DEFAULT nextval('validation_id_validation_seq'::regclass),
  phase text CHECK (phase = ANY (ARRAY['XP'::text, 'travail'::text])),
  status text,
  moyenne real,
  date_validation timestamp without time zone DEFAULT now(),
  id_act integer,
  CONSTRAINT validation_pkey PRIMARY KEY (id_validation),
  CONSTRAINT validation_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act)
);
CREATE TABLE public.vote (
  id_vote integer NOT NULL DEFAULT nextval('vote_id_vote_seq'::regclass),
  valeur integer,
  type text CHECK (type = ANY (ARRAY['estimation'::text, 'note'::text])),
  commentaire text,
  id_utilisateur uuid,
  id_act integer,
  CONSTRAINT vote_pkey PRIMARY KEY (id_vote),
  CONSTRAINT vote_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id),
  CONSTRAINT vote_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act)
);
CREATE TABLE public.vote_approbation (
  id integer NOT NULL DEFAULT nextval('vote_approbation_id_seq'::regclass),
  id_act integer NOT NULL,
  id_utilisateur uuid NOT NULL,
  valeur integer NOT NULL CHECK (valeur = ANY (ARRAY[1, '-1'::integer])),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT vote_approbation_pkey PRIMARY KEY (id),
  CONSTRAINT vote_approbation_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act),
  CONSTRAINT vote_approbation_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id)
);
CREATE TABLE public.vote_completion (
  id integer NOT NULL DEFAULT nextval('vote_completion_id_seq'::regclass),
  id_act integer NOT NULL,
  id_utilisateur uuid NOT NULL,
  approve boolean NOT NULL,
  xp_proposal integer CHECK (xp_proposal IS NULL OR xp_proposal >= 0),
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT vote_completion_pkey PRIMARY KEY (id),
  CONSTRAINT vote_completion_id_act_fkey FOREIGN KEY (id_act) REFERENCES public.activite(id_act),
  CONSTRAINT vote_completion_id_utilisateur_fkey FOREIGN KEY (id_utilisateur) REFERENCES public.profiles(id)
);