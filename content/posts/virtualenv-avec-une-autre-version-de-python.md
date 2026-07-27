---
title: "Virtualenv avec une autre version de python"
date: 2014-11-19 20:12:06
author: "Josue Kouka"
description: "A one-line tip for creating a virtual environment pinned to a specific Python interpreter version."
tags: ["virtualenv", "python"]
categories: ["Programming"]
---

Il arrive des moments ou pour des raisons particulieres, l'on voudrait creer un *environment virtual python* 
utilisant une version de python differente de celle par defaut. 
De plus, generalement plus d'une version de *python* sont installés sur nos OS. Alors pour pouvoir créer un environement virtual python avec la version de python que vous voulez, voici la commande à entrer dans votre terminal:

```shell
yosuke@loking$ virtualenv -p /usr/bin/python2.6 <path/to/new/virtualenv/>
```

**Mise a jour (2026)** : `virtualenv -p` fonctionne toujours, mais avec Python 3 le module `venv` integre a la
stdlib suffit dans la plupart des cas, plus besoin d'installer `virtualenv` separement :

```shell
yosuke@loking$ python3.12 -m venv <path/to/new/virtualenv/>
```

Si vous gerez plusieurs versions de Python cote a cote, [uv](https://github.com/astral-sh/uv) simplifie encore
la commande : `uv venv --python 3.12 <path/to/new/virtualenv/>`.
