# TP — HAProxy + Apache + Tomcat avec Ansible

Déploiement automatisé d'une architecture web à **deux backends totalement
indépendants** : un répartiteur de charge HAProxy en point d'entrée unique,
qui distribue le trafic vers un pool Apache httpd (site statique) et un pool
Tomcat (application Java).

> **Le principe du TP :** il n'existe **aucune** liaison entre Apache et
> Tomcat. Pas de `mod_proxy`, pas de `mod_jk`, pas de connecteur `AJP`.
> Apache ne sait pas que Tomcat existe, et réciproquement. C'est **HAProxy
> seul** qui décide, requête par requête, vers quel pool envoyer le trafic.

```
                     Clients  (navigateur / curl)
                                 │  HTTP :80
                                 ▼
                 ┌───────────────────────────────────┐
                 │   lb1 — HAProxy  192.168.56.11    │
                 │   acl path_beg /app  →  Tomcat    │
                 │   tout le reste      →  Apache    │
                 │   statistiques : port 8404        │
                 └──────┬──────────────────┬─────────┘
                        │                  │
                        ▼                  ▼
          ┌───────────────────┐  ┌───────────────────┐
          │ backend web_apache│  │ backend app_tomcat│
          │ web1 .21:80       │  │ app1 .31:8080     │
          │ web2 .22:80       │  │ app2 .32:8080     │
          │ site HTML/CSS     │  │ application JSP   │
          └───────────────────┘  └───────────────────┘

        Aucun lien entre les deux colonnes.
```

## Le lab

| Rôle | Hostname | IP | Groupe Ansible | Ports |
|---|---|---|---|---|
| Nœud de contrôle | ansible | 192.168.56.10 | *(hors inventaire)* | — |
| Load balancer | lb1 | 192.168.56.11 | `lb` | 80, 8404 |
| Serveur web 1 | web1 | 192.168.56.21 | `web` | 80 |
| Serveur web 2 | web2 | 192.168.56.22 | `web` | 80 |
| Serveur app 1 | app1 | 192.168.56.31 | `app` | 8080 |
| Serveur app 2 | app2 | 192.168.56.32 | `app` | 8080 |

OS cible : **Rocky Linux 9** (les rôles gèrent aussi Debian/Ubuntu via
`ansible_os_family`). Les VM tournent sur Proxmox dans le TP d'origine, mais
n'importe quel hyperviseur convient.

**Toutes les adresses IP sont dans `inventory/hosts.ini`** — c'est le seul
fichier à adapter à votre réseau.

## Démarrage rapide

```bash
git clone git@github.com:houcemdevops007/tp-ha-ansible.git
cd tp-ha-ansible

# 1. Adapter les IP à votre lab
vim inventory/hosts.ini

# 2. Installer les collections requises
ansible-galaxy collection install -r requirements.yml

# 3. Vérifier la connectivité SSH (clé + sudo sans mot de passe)
ansible lab -m ping

# 4. Contrôler la syntaxe
ansible-playbook site.yml --syntax-check
ansible-lint

# 5. Déployer
ansible-playbook site.yml

# 6. Prouver l'idempotence : doit afficher changed=0 partout
ansible-playbook site.yml
```

### Prérequis sur chaque VM cible

```bash
useradd -m -s /bin/bash ansible
echo 'ansible ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/99-ansible
chmod 440 /etc/sudoers.d/99-ansible
# puis, depuis le nœud de contrôle : ssh-copy-id ansible@<ip>
```

## Vérifier que ça marche

```bash
# Le site statique alterne entre web1 et web2
for i in $(seq 1 10); do
  curl -sI http://192.168.56.11/ | awk -F': ' '/^[Xx]-[Ss]erved-[Bb]y/ {print $2}'
done

# L'application Java alterne entre app1 et app2
for i in $(seq 1 10); do
  curl -s http://192.168.56.11/app/ \
    | sed -n 's@.*Nom (Ansible)</dt><dd>\([^<]*\)</dd>.*@\1@p'
done

# Quel backend a traité la requête ?
curl -sI http://192.168.56.11/     | grep -i x-backend   # web_apache
curl -sI http://192.168.56.11/app/ | grep -i x-backend   # app_tomcat

# Page de statistiques HAProxy
#   http://192.168.56.11:8404/stats   (admin / voir group_vars/lb.yml)
```

## Arborescence

```
tp-ha-ansible/
├── ansible.cfg                  configuration locale du projet
├── requirements.yml             collections : ansible.posix, community.general
├── site.yml                     playbook principal (un play par groupe)
├── .ansible-lint / .yamllint    qualité du code
│
├── inventory/
│   ├── hosts.ini                LE fichier à adapter
│   └── hosts.yml                même inventaire au format YAML (alternative)
│
├── group_vars/
│   ├── all.yml                  ports, domaine, NTP, paquets communs
│   ├── web.yml                  variables Apache
│   ├── app.yml                  variables Tomcat
│   └── lb.yml                   variables HAProxy
│
├── host_vars/                   couleurs par serveur (optionnel)
│
├── playbooks/
│   ├── test-apache.yml          tester le pool Apache seul
│   └── test-tomcat.yml          tester le pool Tomcat seul
│
├── exercices/                   corrigés des exercices du TP
│
└── roles/
    ├── common/                  paquets, NTP, timezone, firewalld, SELinux, /etc/hosts
    ├── apache/                  httpd + site statique (index, about, health, style.css)
    ├── tomcat/                  JDK 17, Tomcat 9, systemd, application /app
    └── haproxy/                 haproxy.cfg généré depuis l'inventaire
```

## Les deux idées à retenir

**1. L'inventaire est la source de vérité.** `roles/haproxy/templates/haproxy.cfg.j2`
boucle sur `groups['web']` et `groups['app']` :

```jinja
{% for hote in groups['web'] | sort %}
    server {{ hote }} {{ hostvars[hote]['ansible_host'] }}:{{ apache_http_port }} check inter 2000 rise 2 fall 3
{% endfor %}
```

Ajouter un serveur, c'est ajouter **une ligne dans `inventory/hosts.ini`**,
puis `ansible-playbook site.yml --limit 'web3,lb'`. Aucun fichier de
configuration n'est édité à la main.

Le template lit `hostvars[hote]['ansible_host']` (issu de l'inventaire) et non
`ansible_default_ipv4.address` (un *fact*) : c'est ce qui permet de rejouer le
rôle `haproxy` seul, sans collecter les faits des serveurs backend.

**2. La configuration est validée avant d'être installée.**

```yaml
- name: "haproxy | Générer haproxy.cfg depuis l'inventaire"
  ansible.builtin.template:
    src: haproxy.cfg.j2
    dest: /etc/haproxy/haproxy.cfg
    validate: "haproxy -c -f %s"      # <-- le garde-fou
```

Ansible écrit d'abord un fichier temporaire, lance `haproxy -c -f` dessus et
n'installe le fichier définitif **que si la commande retourne 0**. Une erreur
de syntaxe fait échouer la tâche sans jamais toucher au load balancer en
production.

## Exécution ciblée

```bash
ansible-playbook site.yml --list-tags                  # tags disponibles
ansible-playbook site.yml --tags content --limit web   # redéployer le site seul
ansible-playbook site.yml --tags haproxy --limit lb    # régénérer haproxy.cfg
ansible-playbook site.yml --check --diff               # simulation
ansible-playbook site.yml --skip-tags install          # sans les paquets
```

Tags disponibles : `common`, `apache`, `tomcat`, `haproxy`, `install`,
`config`, `content`, `deploy`, `service`, `firewall`, `selinux`, `time`,
`logs`, `verify`, `war`, `security`.

## Variantes fournies

| Variante | Comment l'activer |
|---|---|
| Routage par nom d'hôte au lieu du chemin | `haproxy_routing_mode: host` dans `group_vars/lb.yml` |
| Persistance de session sur Tomcat (cookie) | `haproxy_app_sticky: true` |
| Application packagée en `.war` | `tomcat_package_as_war: true` |
| Inventaire au format YAML | `inventory = inventory/hosts.yml` dans `ansible.cfg` |

## Sécuriser le mot de passe des statistiques

Le dépôt livre `haproxy_stats_password: "ChangeMe-Lab2026"` **en clair** dans
`group_vars/lb.yml`, pour que le TP fonctionne dès le clonage. En conditions
réelles, passez par `ansible-vault` :

```bash
mkdir group_vars/lb
git mv group_vars/lb.yml group_vars/lb/vars.yml

openssl rand -base64 32 > .vault_pass && chmod 600 .vault_pass
ansible-vault create group_vars/lb/vault.yml
#   vault_haproxy_stats_password: "votre-vrai-mot-de-passe"

# puis dans group_vars/lb/vars.yml :
#   haproxy_stats_password: "{{ vault_haproxy_stats_password }}"

# et décommenter dans ansible.cfg :
#   vault_password_file = .vault_pass
```

> Un fichier `group_vars/vault.yml` **ne serait jamais chargé** : dans
> `group_vars/`, le nom du fichier désigne un groupe. D'où le passage par un
> dossier `group_vars/lb/`. `.vault_pass` est déjà dans le `.gitignore`.

## Dépannage express

| Symptôme | Cause la plus probable |
|---|---|
| Tous les backends `DOWN` en `L4CON` | Booléen SELinux : `setsebool -P haproxy_connect_any 1` |
| HAProxy ne démarre pas sur 8404 | `semanage port -a -t http_port_t -p tcp 8404` |
| `503 No server is available` | Tous les serveurs d'un backend sont DOWN — voir la page de stats |
| Apache : `Address already in use` | Directive `Listen 80` en double |
| Tomcat : 404 sur `/app` | `src: "app/"` (avec le `/` final) ou permissions `tomcat:tomcat` |
| Lignes `server` collées dans `haproxy.cfg` | Une balise Jinja `{% %}` a mangé le saut de ligne |

La colonne `LastChk` de la page de statistiques donne presque toujours la
réponse : `L4CON` (connexion refusée), `L7STS/404` (URL de health check
absente), `L7OK/200` (tout va bien).

## Qualité du code

```bash
ansible-lint     # Passed: 0 failure(s) — profil « production »
yamllint .
```

Trois règles sont désactivées dans `.ansible-lint`, chacune avec sa
justification écrite dans le fichier — notamment `var-naming[no-role-prefix]`,
parce que plusieurs variables sont **volontairement** partagées entre rôles
(`haproxy.cfg.j2` lit `apache_http_port` et `tomcat_http_port`).

## Licence

Support de formation — réutilisation libre en contexte pédagogique.
