---
title: "Introduction a bottle"
date: 2013-08-07 08:00:29
author: "Josue Kouka"
description: "A hello-world introduction to the Bottle Python web framework: install, routes, and reading GET/POST data."
tags: ["python", "bottle"]
categories: ["Programming"]
---

Hello guys !!!
Oui oui, ça fait des années.  Depuis le temps que j'ai envie d'écrire cette introduction à bottle . Je me suis levé comme d'habitude,
la flemme d'écrire un article. 
Enfin bref comme dirait [Franklin](http://www.youtube.com/watch?v=tYVNZrDh5y0).

## INSTALLATION

```console
yosuke@loking:~$ mkvirtualenv bottle
New python executable in bottle/bin/python
Installing distribute............................................................................................................................................................................................................................done.
Installing pip................done.
(bottle)yosuke@loking:~$ pip install bottle 
Requirement already satisfied (use --upgrade to upgrade): bottle in ./.virtualenvs/bottle/lib/python2.7/site-packages
Cleaning up...
(bottle)yosuke@loking:~$ 

```
On a créé un environement virtuel (virtualenvwrapper) puis fait l'installation de **bottle** dans cette envrinement.

## HELLO WORLD

```python
from bottle import route, run, template

@route('/hello')
def hello():
    '''Returns a simple hello world
    '''
    return "Hello World"

@route('/hello/<name>')
def hello_name(name):
    '''Returns hello + name
    '''
    return "Hello %s" %(name,)

@route('/hello/age/<age:int>') # <var:int>, 'int' est un filtre
def tell_age(age):
    '''Returns Age
    '''
    return "You're %s" %(age,)

run(host='localhost', port='8888', reloader=True, debug=True)

```
#### Explications

On a declare trois routes. La derniere, `/hello/age/<age:int>`, utilise un **filtre** (`:int`) qui valide et
convertit automatiquement le segment d'URL en entier avant de l'injecter dans la fonction - si on passe
autre chose qu'un nombre, Bottle renvoie directement une erreur 404 sans qu'on ait a le verifier soi-meme.

## REQUETTES

Bottle vous donne acces a `request`, qui contient les donnees de la requete HTTP courante (query string,
formulaire, headers, etc.).

### Get

Les parametres passes dans l'URL (`?nom=valeur`) sont accessibles via `request.query` :

```python
from bottle import route, run, request

@route('/greet')
def greet():
    name = request.query.name or 'inconnu'
    return "Salut %s" % (name,)

# GET /greet?name=josue -> "Salut josue"
```

### Post

Les donnees d'un formulaire soumis en POST sont accessibles via `request.forms` :

```python
from bottle import route, run, request

@route('/greet', method='POST')
def greet_post():
    name = request.forms.get('name', 'inconnu')
    return "Salut %s" % (name,)

# POST /greet avec name=josue dans le corps -> "Salut josue"
```

Notez le `method='POST'` dans le decorateur `@route` : par defaut Bottle ne route que les requetes **GET**,
il faut explicitement autoriser les autres methodes.
