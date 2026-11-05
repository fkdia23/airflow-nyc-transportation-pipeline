# Taxi ou Citi Bike : lequel est le plus rapide à New York ?

> ### ℹ️ Travail d'apprentissage : code d'accompagnement d'un ouvrage
>
> Ce dépôt reprend le code du **chapitre 14 du livre
> [*Data Pipelines with Apache Airflow*](https://www.manning.com/books/data-pipelines-with-apache-airflow)**
> (Bas Harenslak & Julian de Ruiter, Manning). Le code d'origine appartient à ses auteurs.
>
> Je le conserve, l'annote et l'adapte comme support d'étude sur l'orchestration Airflow d'une
> architecture multi-services conteneurisée. Le README d'origine est conservé en bas de page.
>
> Franklin KANA NGUEDIA

Cette application croise les trajets des **taxis jaunes** et des **vélos partagés Citi Bike** pour
répondre à une question d'aide à la décision : entre deux quartiers, un jour donné et à une heure
donnée, quel mode de transport est le plus rapide ?

Un pipeline Airflow collecte les trajets toutes les 15 minutes, les transforme et les charge dans
une base de résultats. Une page web affiche ensuite la comparaison.

**Stack :** Apache Airflow, Docker Compose, PostgreSQL, MinIO, DuckDB, pandas, GeoPandas, PyArrow,
Flask et nginx.

## Sommaire

- [Architecture fonctionnelle](#architecture-fonctionnelle)
- [La stack à chaque étape](#la-stack-à-chaque-étape)
- [Le pipeline Airflow](#le-pipeline-airflow)
- [Comment la comparaison est calculée](#comment-la-comparaison-est-calculée)
- [Ce que Docker apporte ici](#ce-que-docker-apporte-ici)
- [Lancer le projet en local](#lancer-le-projet-en-local)
- [État du projet](#état-du-projet)
- [Adaptations par rapport au livre](#adaptations-par-rapport-au-livre)
- [Structure du dépôt](#structure-du-dépôt)
- [Sources](#sources)

## Architecture fonctionnelle

![Architecture fonctionnelle en cinq zones. Les données ouvertes taxi et Citi Bike alimentent deux sources simulées. Dans la plateforme de données, Airflow pilote les étapes collecter, transformer et charger, avec un data lake MinIO composé de raw et processed. La base de résultats alimente une page de comparaison utilisée par les décideurs. Docker Compose sert de socle à l'ensemble.](docs/architecture-fonctionnelle.svg)

Le schéma se lit de gauche à droite, et ses numéros correspondent aux étapes ci-dessous.

| N° | Étape | Ce qui se passe | Services ou tâches |
|---|---|---|---|
| 1 | Importer | Un échantillon des trajets de 2019 est chargé au premier démarrage | `taxi_db`, `citibike_db` |
| 2 | Publier | Les sources présentent ces trajets comme s'ils venaient de se terminer | `taxi_fileserver`, `citibike_api` |
| 3 | Collecter | Airflow récupère les nouveaux trajets et les dépose dans MinIO, sous `raw/` | `download_taxi_data`, `download_citi_bike_data` |
| 4 | Transformer | Les durées et les zones sont calculées, puis le Parquet est rangé sous `processed/` | `process_taxi_data`, `process_citi_bike_data` |
| 5 | Charger | Les trajets sont écrits dans une table par mode de transport | `taxi_to_db`, `citi_bike_to_db`, `result_db` |
| 6 | Comparer | La page calcule les temps moyens et met en avant le mode le plus rapide | `nyc_transportation_api` |
| 7 | Décider | L'utilisateur consulte la comparaison pour un trajet, un jour et une tranche horaire | Page de résultats |

D'autres services complètent cet ensemble : `webserver`, `scheduler` et `postgres` font tourner
Airflow, et `minio` héberge le data lake. Au démarrage, `initdb_adduser` prépare la base et le compte
Airflow, et `minio_init` crée le bucket `datalake`.

### Comment le temps réel est simulé

Les données réelles ne sont publiées que par lots. Les deux sources ajoutent donc à chaque date
l'écart entre l'année en cours et 2019. Un trajet du 5 novembre 2019 apparaît ainsi comme un trajet
du 5 novembre de cette année.

- **Source taxi :** un cron exporte toutes les 15 minutes les trajets qui viennent de se terminer
  dans un fichier CSV. Les fichiers sont servis par nginx et supprimés après une heure environ.
- **Source Citi Bike :** une API Flask, protégée par mot de passe, renvoie les trajets récents via
  la route `/recent/<minute|hour|day>/<quantité>`.

## La stack à chaque étape

Ce schéma montre quelles technologies interviennent à chaque étape, et à quoi elles servent.

![Schéma de la stack par étape, dans Docker Compose. 1, initialiser et importer : Airflow CLI, mc, wget, DuckDB, unzip, awk, psql et PostgreSQL. 2, simuler le temps réel : cron, psql, nginx, Flask, Flask-HTTPAuth, psycopg2 et PostgreSQL. Puis, orchestrées par Airflow, 3, collecter : PythonOperator, requests, S3Hook et MinIO. 4, transformer : PandasOperator, pandas, GeoPandas, PyGEOS, PyArrow, client minio et MinIO. 5, charger : MinioPandasToPostgres, pandas, client minio, SQLAlchemy, MinIO et PostgreSQL. 6, restituer : Flask, Jinja, Bootstrap, SQL, psycopg2 et PostgreSQL.](docs/stack-par-etape.svg)

## Le pipeline Airflow

![Schéma du DAG nyc_dag : deux branches, Citi Bike et taxi, composées chacune des étapes collecter, transformer et charger.](docs/dag-nyc.svg)

Le DAG `nyc_dag` démarre seul, toutes les 15 minutes, et ne rattrape pas les exécutions passées. Le
code est dans [dags/nyc_dag.py](dags/nyc_dag.py), et les opérateurs personnalisés sont dans
[src/nyctransport/operators/](src/nyctransport/operators/).

## Comment la comparaison est calculée

Les deux sources ne décrivent pas les lieux de la même façon. Les taxis indiquent une zone, alors
que Citi Bike indique les coordonnées GPS des stations. Le pipeline situe donc chaque station dans
une zone de taxi avec une jointure spatiale.

La page calcule ensuite le temps moyen, en secondes, pour chaque combinaison de ces critères :

- **Trajet :** zone de départ et zone d'arrivée, si elles sont différentes.
- **Jour :** jour de la semaine.
- **Tranche horaire :** 8 h à 11 h, 11 h à 16 h, 16 h à 19 h, 19 h à 22 h, ou 22 h à 8 h.

Seules les combinaisons présentes des deux côtés sont affichées, et le mode le plus rapide ressort
en vert.

![Carte des zones de taxi de New York. 96 zones sur 263 contiennent une station Citi Bike : 58 sur 69 à Manhattan, 29 sur 61 à Brooklyn, 9 sur 69 dans le Queens et aucune dans le Bronx, à Staten Island ou à Newark.](docs/couverture-zones.png)

## Ce que Docker apporte ici

C'est l'intérêt principal de ce chapitre : **douze services** démarrent ensemble à partir d'un
unique [docker-compose.yml](docker-compose.yml), dont dix permanents et deux d'initialisation.

- **Initialisation dédiée :** deux conteneurs préparent Airflow et MinIO, puis s'arrêtent.
- **Configuration commune :** l'ancre YAML `&airflow_environment` regroupe la configuration des
  services Airflow à un seul endroit.
- **Développement sans reconstruction :** le scheduler monte le code et le réinstalle en mode
  éditable avec `pip install -e` à chaque démarrage.

## Lancer le projet en local

**Prérequis :** Docker Desktop avec Docker Compose v2, et une connexion Internet pour le premier
démarrage. Prévoir environ 12 Go d'espace disque. Lors de l'essai, sur un poste de 14 Go de mémoire,
il restait moins de 1 Go de libre : mieux vaut fermer les applications lourdes.

```bash
docker compose up -d --build
docker compose ps -a
docker compose logs -f citibike_db
```

Le premier démarrage a pris une quinzaine de minutes lors de l'essai, dont l'import des données :

- `initdb_adduser` et `minio_init` s'arrêtent avec le code 0, c'est normal.
- La base Citi Bike est prête lorsque son journal indique deux fois
  `database system is ready to accept connections`.
- La page reste vide au début, car il faut qu'un même trajet soit présent côté taxi et côté vélo.

### Accès

| Service | Adresse | Identifiants |
|---|---|---|
| Page de résultats | http://localhost:8083 | aucun |
| Airflow | http://localhost:8080 | `admin` / `admin` |
| Fichiers taxi | http://localhost:8081 | aucun |
| API Citi Bike | http://localhost:8082 | `citibike` / `cycling` |
| MinIO | http://localhost:9000 | `AKIAIOSFODNN7EXAMPLE` / `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| Base Airflow | `localhost:5432`, base `airflow` | `airflow` / `airflow` |
| Base taxi | `localhost:5433`, base `tlctriprecords` | `taxi` / `ridetlc` |
| Base Citi Bike | `localhost:5434`, base `citibike` | `citi` / `cycling` |
| Base de résultats | `localhost:5435`, base `nyctransportation` | `nyc` / `tr4N5p0RT4TI0N` |

> ⚠️ Ces identifiants, comme la clé Fernet du `docker-compose.yml`, sont des valeurs d'exemple
> destinées à un usage local uniquement.

### Arrêter et relancer

```bash
docker compose stop    # arrête tout et garde les données
docker compose start   # relance les conteneurs existants
docker compose down -v # supprime les conteneurs et toutes les données
```

Un simple `docker compose down` supprime aussi les données importées, car elles se trouvent dans
des volumes anonymes : elles seront téléchargées de nouveau au prochain démarrage. Si Docker Desktop
est quitté, seuls `webserver` et `scheduler` repartent seuls. Les autres se relancent avec
`docker compose start`.

## État du projet

Dernier essai réalisé le 5 novembre 2026. Cet essai s'est arrêté avant l'affichage de la première
ligne de comparaison.

| Vérification | Résultat |
|---|---|
| Construction et démarrage des douze services | Réussis |
| Import des trajets taxi | 3 661 649 lignes |
| Import des trajets Citi Bike | 2 568 959 lignes |
| Branche taxi du DAG, de la collecte à la base | Réussie sur une exécution sur quatre |
| Branche Citi Bike du DAG, de la collecte à la base | Réussie sur la dernière exécution, seule à disposer de toutes les corrections |
| Santé d'Airflow et connexion du compte `admin` | Réussies |
| Page de résultats | Répond, mais aucune ligne de comparaison n'a encore été observée |

### Limites connues

- **Collecte et export simultanés :** le DAG et l'export des CSV taxi démarrent à la même minute.
  La collecte peut donc ne trouver aucun nouveau fichier (`No objects to concatenate`). L'erreur
  `No columns to parse from file` indique un fichier vide, probablement copié avant la fin de son
  écriture. Un CSV déjà copié n'est jamais retraité : si l'étape suivante échoue, ses trajets sont
  perdus. Décaler le DAG de quelques minutes, par exemple avec `5-59/15 * * * *`, devrait corriger
  ce point.
- **Mois couverts côté taxi :** seuls janvier, février, mars et novembre 2019 sont importés. Les
  autres mois de l'année, la source taxi ne publie aucun trajet. Il faut ajouter les fichiers
  manquants dans [services/taxi_db/postgres-init.sh](services/taxi_db/postgres-init.sh), puis
  recréer le service `taxi_db`.
- **Couverture géographique :** la comparaison ne concerne que les 96 zones qui contiennent une
  station Citi Bike en 2019.
- **Portée des moyennes :** elles reposent sur un échantillon et sur les seuls trajets collectés
  depuis le démarrage. Elles illustrent la mécanique du pipeline et ne constituent pas une étude de
  mobilité.
- **Versions anciennes :** Airflow 2.0.0 et Python 3.7 et 3.8 sont conservés pour rester fidèle au
  livre. Ce projet n'est pas destiné à la production.

## Adaptations par rapport au livre

Plusieurs ressources utilisées par le code d'origine ont changé ou disparu.

| Élément | Changement constaté | Adaptation |
|---|---|---|
| Données taxi | Les fichiers sont désormais publiés en Parquet | DuckDB convertit les Parquet en CSV, puis PostgreSQL les charge |
| Données Citi Bike | Les fichiers mensuels de New York ont laissé place à une archive annuelle | `citibike_db` importe l'archive de 2019 |
| Fichiers `JC-*` | Ils couvrent Jersey City : aucune de leurs stations n'est dans une zone de taxi | Ils sont remplacés par les données de New York |
| Identifiants de station | Certains mois les écrivent en décimal, par exemple `3507.0` | Ils sont convertis en entiers à l'import |
| Zones de taxi | L'URL a changé et le fichier `.shp` est dans un sous-dossier | Le DAG lit la nouvelle adresse avec `zip+https` |
| Images MinIO | Les dépôts `minio/minio` et `minio/mc` sont introuvables sur Docker Hub | Les images `rancher/minio-minio` et `bitnamilegacy/minio-client` les remplacent |
| Export taxi au démarrage | Une parenthèse en trop figurait dans la requête | Le script est corrigé |

## Structure du dépôt

```text
.
├── dags/nyc_dag.py               # Définition du pipeline
├── docs/                         # Schémas et carte de ce README
├── services/
│   ├── airflow/                  # Image Airflow et dépendances
│   ├── citibike_api/             # Source simulée Citi Bike
│   ├── citibike_db/              # Import des trajets Citi Bike
│   ├── nyc_transportation_api/   # Page de résultats
│   ├── result_db/                # Tables de résultats
│   ├── taxi_db/                  # Import des trajets taxi
│   └── taxi_fileserver/          # Source simulée taxi
├── src/nyctransport/             # Opérateurs Airflow personnalisés
├── docker-compose.yml            # Assemblage des douze services
└── setup.py                      # Paquet nyctransport
```

## Sources

- [Data Pipelines with Apache Airflow](https://www.manning.com/books/data-pipelines-with-apache-airflow), chapitre 14.
- [Taxi vs. Citi Bike in NYC](https://toddwschneider.com/posts/taxi-vs-citi-bike-nyc), l'analyse de Todd Schneider qui a inspiré le cas d'usage.
- [TLC Trip Record Data](https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page), pour les trajets et les zones de taxi.
- [Citi Bike System Data](https://www.citibikenyc.com/system-data), pour les trajets à vélo.

---

<details>
<summary>README d'origine du livre, non mis à jour (en anglais)</summary>

Certaines informations ci-dessous ne correspondent plus au projet : identifiants Airflow, formats
des données et adresses de téléchargement.

# Chapter 14

Code accompanying Chapter 14 of the book [Data Pipelines with Apache Airflow](https://www.manning.com/books/data-pipelines-with-apache-airflow).

Much of this use case was based on the ideas in https://toddwschneider.com/posts/taxi-vs-citi-bike-nyc, where
the fastest method of transportation (Citi Bikes or Yellow Taxis) between two NYC neighborhoods at given times
and days is determines. We will productionize this use case into an Airflow workflow. Two (mocked) real-time
services are created for this purpose:

1. A service providing Citi Bike rides
2. A service providing NYC Yellow Taxi rides

An Airflow DAG will periodically scrape these services, wrangle the data, and send the results into a Postgres
database serving a tiny website, displaying which transportation method is fastest between two NYC
neighborhoods.

The real data is only available in batches of months/years. Therefore we provide two APIs to mimic "live"
systems. The system can be brought online with the `docker-compose.yml` provided with this repository:

```bash
docker-compose up -d
```

If all processing goes well, the final result is visible on http://localhost:8083.

Ports on which services are available:

- http://localhost:5432: Airflow Postgres DB (`airflow`/`airflow`)
- http://localhost:5433: NYC Taxi Postgres DB (`taxi`/`ridetlc`)
- http://localhost:5434: Citi Bike Postgres DB (`citi`/`cycling`)
- http://localhost:5435: NYC Transportation results Postgres DB (`nyc`/`tr4N5p0RT4TI0N`)
- http://localhost:8080: Airflow webserver (`airflow`/`airflow`)
- http://localhost:8081: NYC Taxi static file server
- http://localhost:8082: Citi Bike API (`citibike`/`cycling`)
- http://localhost:8083: NYC Transportation API
- http://localhost:9000: MinIO (`AKIAIOSFODNN7EXAMPLE`/`wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`)

## More information

### Taxi dataset

The taxi dataset refers to the "NYC Taxi and Limousine Commission (TLC) Trip Record Data", available here:
https://www1.nyc.gov/site/tlc/about/tlc-trip-record-data.page.

A snippet of the data:

```csv
VendorID,tpep_pickup_datetime,tpep_dropoff_datetime,passenger_count,trip_distance,RatecodeID,store_and_fwd_flag,PULocationID,DOLocationID,payment_type,fare_amount,extra,mta_tax,tip_amount,tolls_amount,improvement_surcharge,total_amount,congestion_surcharge
1,2019-01-01 00:46:40,2019-01-01 00:53:20,1,1.50,1,N,151,239,1,7,0.5,0.5,1.65,0,0.3,9.95,
1,2019-01-01 00:59:47,2019-01-01 01:18:59,1,2.60,1,N,239,246,1,14,0.5,0.5,1,0,0.3,16.3,
2,2018-12-21 13:48:30,2018-12-21 13:52:40,3,.00,1,N,236,236,1,4.5,0.5,0.5,0,0,0.3,5.8,
2,2018-11-28 15:52:25,2018-11-28 15:55:45,5,.00,1,N,193,193,2,3.5,0.5,0.5,0,0,0.3,7.55,
2,2018-11-28 15:56:57,2018-11-28 15:58:33,5,.00,2,N,193,193,2,52,0,0.5,0,0,0.3,55.55,
2,2018-11-28 16:25:49,2018-11-28 16:28:26,5,.00,1,N,193,193,2,3.5,0.5,0.5,0,5.76,0.3,13.31,
2,2018-11-28 16:29:37,2018-11-28 16:33:43,5,.00,2,N,193,193,2,52,0,0.5,0,0,0.3,55.55,
1,2019-01-01 00:21:28,2019-01-01 00:28:37,1,1.30,1,N,163,229,1,6.5,0.5,0.5,1.25,0,0.3,9.05,
1,2019-01-01 00:32:01,2019-01-01 00:45:39,1,3.70,1,N,229,7,1,13.5,0.5,0.5,3.7,0,0.3,18.5,
```

Data dictionary: https://www1.nyc.gov/assets/tlc/downloads/pdf/data_dictionary_trip_records_yellow.pdf

### Citi Bike dataset

https://www.citibikenyc.com/system-data

A snippet of the data:

```csv
"tripduration","starttime","stoptime","start station id","start station name","start station latitude","start station longitude","end station id","end station name","end station latitude","end station longitude","bikeid","usertype","birth year","gender"
201,"2019-01-01 03:09:09.7110","2019-01-01 03:12:30.8790",3183,"Exchange Place",40.7162469,-74.0334588,3214,"Essex Light Rail",40.7127742,-74.0364857,29612,"Subscriber",1993,1
505,"2019-01-01 05:18:00.1060","2019-01-01 05:26:25.9050",3183,"Exchange Place",40.7162469,-74.0334588,3638,"Washington St",40.7242941,-74.0354826,29213,"Subscriber",1972,2
756,"2019-01-01 10:36:33.3400","2019-01-01 10:49:10.2600",3183,"Exchange Place",40.7162469,-74.0334588,3192,"Liberty Light Rail",40.7112423,-74.0557013,26164,"Subscriber",1985,1
1575,"2019-01-01 12:43:38.6430","2019-01-01 13:09:54.5280",3183,"Exchange Place",40.7162469,-74.0334588,3638,"Washington St",40.7242941,-74.0354826,29672,"Customer",1969,0
1566,"2019-01-01 12:43:39.6010","2019-01-01 13:09:46.5100",3183,"Exchange Place",40.7162469,-74.0334588,3638,"Washington St",40.7242941,-74.0354826,29522,"Customer",1969,0
737,"2019-01-01 12:56:53.2040","2019-01-01 13:09:11.0400",3183,"Exchange Place",40.7162469,-74.0334588,3205,"JC Medical Center",40.71653978099194,-74.0496379137039,29447,"Subscriber",1993,1
917,"2019-01-01 13:03:44.7760","2019-01-01 13:19:02.7690",3183,"Exchange Place",40.7162469,-74.0334588,3277,"Communipaw & Berry Lane",40.71435836870427,-74.06661093235016,29299,"Subscriber",1986,1
3248,"2019-01-01 13:12:03.1280","2019-01-01 14:06:12.0400",3183,"Exchange Place",40.7162469,-74.0334588,3196,"Riverview Park",40.7443187,-74.0439909,29495,"Subscriber",1992,1
3168,"2019-01-01 13:13:12.0450","2019-01-01 14:06:00.4110",3183,"Exchange Place",40.7162469,-74.0334588,3196,"Riverview Park",40.7443187,-74.0439909,26312,"Customer",1969,0
```

</details>
