# Exercices du TP

Quatre exercices progressifs. Les énoncés complets sont dans la **partie 5**
du tutoriel ; ce dossier ne contient que les fichiers des corrigés qui ne
font pas partie du projet de base.

## Exercice 1 — débutant : ajouter un troisième serveur Tomcat

Intégrer une VM `app3` (192.168.56.33) au pool `app_tomcat`, en ne modifiant
**qu'un seul fichier** du projet.

```ini
# inventory/hosts.ini
[app]
app1  ansible_host=192.168.56.31  server_badge_color="#6b46c1"  server_badge_label="APP-1"
app2  ansible_host=192.168.56.32  server_badge_color="#b83280"  server_badge_label="APP-2"
app3  ansible_host=192.168.56.33  server_badge_color="#0f766e"  server_badge_label="APP-3"
```

```bash
ssh-copy-id ansible@192.168.56.33
ansible-playbook site.yml --limit 'app3,lb'
```

`--limit 'app3,lb'` et non `--limit app3` : le fichier `haproxy.cfg` vit sur
`lb1`, il faut rejouer le rôle `haproxy` pour qu'il connaisse `app3`.

## Exercice 2 — intermédiaire : nouvelle page et redéploiement par tag

Ajouter une page `contact.html` au site statique et la déployer **sans
redémarrer aucun service**.

Le corrigé est le fichier [`corrige-2-contact.html.j2`](corrige-2-contact.html.j2).

```bash
cp exercices/corrige-2-contact.html.j2 roles/apache/templates/contact.html.j2
```

Puis ajouter `contact.html` à `apache_pages` dans `group_vars/web.yml`, et le
lien dans le `<nav>` des autres pages :

```bash
ansible-playbook site.yml --tags content --limit web --check --diff
ansible-playbook site.yml --tags content --limit web
```

Aucun handler n'est notifié par les tâches taguées `content` : Apache lit les
fichiers du disque à chaque requête, il n'a rien à recharger.

## Exercice 3 — avancé : persistance de session sur Tomcat

Tout est déjà prévu dans `roles/haproxy/templates/haproxy.cfg.j2`. Une seule
variable à basculer dans `group_vars/lb.yml` :

```yaml
haproxy_app_sticky: true
haproxy_app_cookie_name: "SRVID"
```

```bash
ansible-playbook site.yml --tags haproxy --limit lb --diff

# Le compteur de visites s'incrémente maintenant normalement
rm -f /tmp/cookies.txt
for i in $(seq 1 6); do
  curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt http://192.168.56.11/app/ \
    | sed -n 's@.*<div class="compteur">\([0-9]*\)</div>.*@visites=\1@p'
done
```

Le backend `web_apache` n'est volontairement pas concerné : un site statique
est sans état, l'affinité y serait nuisible.

## Exercice 4 — expert : HTTPS sur HAProxy

Terminaison TLS sur le load balancer, certificat auto-signé généré par
Ansible, redirection automatique HTTP → HTTPS. Le corrigé complet (tâches,
modifications du template, vérifications) est dans la **partie 5** du
tutoriel, section 9.5.

Point d'attention : HAProxy attend **un seul fichier `.pem`** contenant la clé
privée **puis** le certificat concaténés — pas deux fichiers séparés comme
Apache ou Nginx.
