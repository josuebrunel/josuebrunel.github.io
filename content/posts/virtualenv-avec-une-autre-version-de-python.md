---
title: "Virtualenv avec une autre version de python"
date: 2014-11-19 20:12:06
author: "Josue Kouka"
tags: ["virtualenv", "python"]
categories: ["Programming"]
---

Il arrive des moments ou pour des raisons particulieres, l'on voudrait creer un *environment virtual python* 
utilisant une version de python differente de celle par defaut. 
De plus, generalement plus d'une version de *python* sont installés sur nos OS. Alors pour pouvoir créer un environement virtual python avec la version de python que vous voulez, voici la commande à entrer dans votre terminal:

```shell
yosuke@loking$ virtualenv -p /usr/bin/python2.6 <path/to/new/virtualenv/>
```
