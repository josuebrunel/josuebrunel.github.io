---
title: "Copier une base PostgreSQL de production vers un serveur de developpement"
date: 2013-02-04
author: "Josue Kouka"
description: "pg_dump, scp, psql: la sequence de commandes pour copier une base PostgreSQL de production vers un serveur de developpement, sans outil GUI."
tags: ["postgresql", "linux", "database"]
categories: ["Linux"]
---

Salut !!!!
Cet article a ete ecrit a l'origine pour un projet [_OpenERP_]({{< ref "openerp-module-development-partie-i.md" >}}), mais la technique elle-meme n'a rien de specifique
a OpenERP : c'est simplement la sequence `pg_dump` / `scp` / `psql` pour copier n'importe quelle base PostgreSQL
de production vers un serveur de developpement, sans outil GUI comme _pgAdmin_ ^_^. Les etapes qui suivent
gardent volontairement le contexte OpenERP d'origine (les noms de services a arreter/relancer), mais la partie
PostgreSQL se transpose telle quelle a n'importe quelle stack.

Prérequis :

*  	Connaissances basiques en administration linux/unix
*	Connaissances basiques SQL et administration PostgreSQL

Context :

*	serveur de bdd production : 192.168.1.2  # HOSTNAME = prod
*	serveur de  bdd developpement : 192.168.1.3 # HOSTNAME = preprod
*   Le nom de notre base de données est __pikachu__

### Production

Se connecter au serveur de base de données

```console
ssh root@192.168.1.2

```
Se connecter en tant qu'utilisateur __postgres__

```console
#su postgres

```
Exporter la base de données

```console
postgres@prod:/root/backup$ pg_dump pikachu -U postgres > ./backup/db_backup

```
**db_backup** est le nom du fichier contenant la base de données exportée

	# su postgres

```console
prod:~#ssh root@192.168.1.3

```
Copier la base de données de production sur le serveur de développement

```console
preprod:~# scp root@192.168.1.2:/root/backup/db_backup ./backups/

```
Stopper les services Openerp et Apache(Web, si necéssaire)

```console
preprod:~#/etc/init.d/openerp stop #Arret du serveur openerp de developpement
preprod:~#/etc/init.d/apache2 stop #Arret du serveur web de developpement

```
Connecter vous en tant qu'utilisqteur __postgres__ (on est sur le serveur de developpement cette fois-ci)
	
```console
preprod:~#su postgres

```
Créer une base de données temporaire
	
```console
postgres@preprod:/root$psql
postgres=# create database pikachu_prod with owner=openerp template=template0 encoding='UTF-8' ;
postgres=#\q


```
Charger le fichier de base de données recuperé en production vers la base de données de développement

```console
postgres@preprod:/root/backups$ cat db_backup | psql pikachu_prod

```
Vous pouvez vérifier qu'on a deux bases ( pikachu , pikachu_prod) avec la commande:

```console
postgres=#\l

```
Supprimer la base de développement et renommer la base de production avec le nom de celle de développement

```console
postgres@preprod:/root/backups$ psql
postgres=# drop database pikachu ;
postgres=# alter DATABASE pikachu_prod RENAME TO pikcachu ;
   	

```
Relancez les services Openerp et Apache(Web)

```console
preprod:~#/etc/init.d/openerp start #Demarrage du serveur openerp de développement
preprod:~#/etc/init.d/apache2 start #Demarrage du serveur web de développement


```
Voila !!!
