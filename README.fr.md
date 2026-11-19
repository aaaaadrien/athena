# Athena : Protection SSH Légère (nftables)

Athena est un daemon de sécurité ultra-léger conçu pour protéger votre serveur contre les attaques par force brute SSH. Il lit le journal systemd, compte les échecs d'authentification par adresse source et bannit les fautifs via **nftables**, en IPv4 comme en IPv6.

## Caractéristiques
- **Ultra-léger** : environ **7 Mo de RAM**, et aucun CPU quand rien ne se passe — le journal est suivi en flux, il n'est plus relu à intervalle régulier.
- **Moderne** : utilise `nftables` (remplaçant d'iptables) dans une seule table `inet`, avec un ensemble par famille d'adresses.
- **Persistant** : les bans sont enregistrés avec leur date d'expiration absolue ; un redémarrage du service ou de la machine restaure le temps restant exact.
- **Sûr par défaut** : liste blanche avec support CIDR (IPv4 et IPv6), et un débannissement manuel est respecté pendant toute une fenêtre de détection au lieu d'être annulé au cycle suivant.

## Prérequis
- systemd avec `journalctl` (Athena lit le journal directement ; si journald est configuré en `Storage=volatile`, les bans ne peuvent pas être reconstruits depuis le journal — voir *Mise à jour* ci-dessous).
- `nftables` >= 0.9 (`nft get element`, ensembles `timeout`).
- `bash` >= 4.3, `flock` (util-linux).

## Structure du Projet
- `athena-server` : Le daemon principal qui surveille les logs et gère le firewall.
- `athena` : L'outil CLI pour lister les bans et débannir manuellement une IP.
- `athena.conf` : Fichier de configuration centralisé.
- `athena.service` : Unité systemd pour la gestion du service.
- `VERSION` : source unique du numéro de version, affichée par les deux binaires.
- `Makefile` : installation, désinstallation et cibles de test.
- `tests/` : tests unitaires et tests de bout en bout (exécutés dans un namespace réseau privé).

### Fichiers installés
| Chemin | Contenu |
|---|---|
| `/usr/bin/athena-server`, `/usr/bin/athena` | daemon et client |
| `/usr/share/athena/VERSION` | chaîne de version |
| `/etc/athena/athena.conf` | configuration (conservée lors d'une mise à jour) |
| `/etc/systemd/system/athena.service` | unité systemd |
| `/run/athena/unban_queue` | demandes de débannissement, éphémère |
| `/var/lib/athena/bans` | état des bans : une ligne `<adresse> <expiration epoch>` |

## Configuration (`/etc/athena/athena.conf`)
Vous pouvez ajuster le comportement d'Athena :
- `THRESHOLD` : Nombre d'échecs autorisés avant le ban (défaut: 2).
- `BAN_TIME` : Durée du bannissement en secondes (défaut: 3600s / 1h). Doit rester >= `FIND_TIME`.
- `FIND_TIME` : Fenêtre de recherche des échecs dans les logs (défaut: 600s / 10min).
- `CHECK_INTERVAL` : Fréquence de réveil du serveur pour traiter les demandes de débannissement et purger son état (défaut: 5s).
- `WHITE_LIST` : Adresses ou CIDR (IPv4 et IPv6) à ne jamais bannir.
- `SSH_LOG_TAGS` : identifiants journald portant les messages sshd. `OpenSSH >= 9.8` journalise via `sshd-session`, les versions antérieures via `sshd` ; les deux sont filtrés par défaut.
- `PORT_BLOCK` : Ports à bloquer ("all" ou liste séparée par des virgules ex: "22,80,443", appliqué en TCP et UDP).

Le daemon valide sa configuration au démarrage et refuse de démarrer avec une valeur non numérique ; un `BAN_TIME` inférieur à `FIND_TIME` est signalé par un avertissement dans le journal.

## Installation & Désinstallation

### Installation
Le projet inclut un Makefile pour simplifier le déploiement sur Linux :
```bash
sudo make install
```
*Cette commande installe les binaires dans `/usr/bin`, le fichier de version dans `/usr/share/athena`, la conf dans `/etc/athena`, le répertoire d'état dans `/var/lib/athena`, puis active et démarre le service systemd. Un `athena.conf` existant n'est jamais écrasé.*

Pour un empaquetage, `make install DESTDIR=/chemin/de/staging` dépose les fichiers sans appeler `systemctl`.

### Désinstallation
Pour supprimer proprement Athena et nettoyer les règles firewall :
```bash
sudo make uninstall
```

### Mise à jour depuis 1.0
Rien à faire : au premier démarrage de la 1.1, en l'absence de fichier d'état, les bans actifs sont reconstruits une fois depuis le journal (comme la 1.0 le faisait à chaque démarrage), puis `/var/lib/athena/bans` prend le relais. Les bans déjà présents dans le noyau sont conservés.

## Utilisation du client `athena`
Une fois installé, utilisez la commande `athena` :
- **Lister les bans actifs** : `athena -l`
- **Débannir une IP** : `athena -u 203.0.113.245`

```text
$ athena -l
--- Athena : adresses bannies ---
  198.51.100.7                            1m04s
  203.0.113.5                             59m58s
  2001:db8::66                            1h59m59s
Total : 3 adresse(s) bannie(s).
```

## Surveillance de l'activité
Pour suivre l'activité d'Athena en temps réel (bans, restores, unbans) :
```bash
journalctl -t athena -f
```

```text
-- Logs begin at Fri 2026-05-22 19:58:09 CEST. --
Jun 02 15:39:21 SSH222 athena[1154894]: [BAN] 203.0.113.149 (pour 3600s)
Jun 02 15:59:59 SSH222 athena[1157363]: [BAN] 198.51.100.237 (pour 3600s)
Jun 02 16:00:59 SSH222 athena[1157511]: [BAN] 192.0.2.49 (pour 3600s)
Jun 02 16:33:17 SSH222 athena[1161509]: [BAN] 203.0.113.107 (pour 3600s)
Jun 02 16:33:32 SSH222 athena[1161553]: [BAN] 198.51.100.179 (pour 3600s)
Jun 02 16:33:35 SSH222 athena[1161574]: [UNBAN] 203.0.113.245 (Manuel)
Jun 02 17:01:02 SSH222 athena[1161900]: [RESTORE] 198.51.100.237 (1790s restantes)
Jun 02 17:01:02 SSH222 athena[1161900]: [WARN] journal stream ended, reconnecting
```
Chaque événement et chaque avertissement est écrit dans le journal avec le tag `athena`, donc `journalctl -t athena -f` est le seul endroit à consulter ; les erreurs fatales de démarrage sont en plus écrites sur la sortie d'erreur, où `journalctl -u athena` les récupère.

## Empreinte mesurée
```text
● athena.service - Athena Security Daemon (SSH brute-force blocker)
   Active: active (running) since Sat 2026-11-14 14:19:07 CET; 4 days ago
   Memory: 7.1M (peak: 14.9M)
```
CPU : la version 1.0 relisait le journal à chaque `CHECK_INTERVAL`, soit environ 6 ms par cycle (l'ouverture d'un journal de 212 Mo domine, avec `--since` comme avec `--after-cursor`), et avait accumulé 24 minutes de CPU en 4 jours pour zéro ban. Le daemon suit désormais le journal une seule fois : sur un banc de 20 cycles, on passe de 34 à 4 jiffies, et un cycle inactif ne fait aucun `fork`.

## Tests
```bash
make check        # ShellCheck + tests unitaires (sans root, sans nftables)
make integration  # tests de bout en bout : vrai nftables dans un namespace réseau privé
```
La suite d'intégration pilote le vrai daemon avec un journal simulé : bannissement, seuil, liste blanche (IPv4 et IPv6), débannissement manuel, restauration d'état après redémarrage, purge des entrées expirées et CLI. Elle se relance elle-même dans `unshare --net` et ne touche donc jamais le firewall de l'hôte. La CI exécute les trois commandes à chaque push et pull request.

## Dépannage
- **Rien n'est jamais banni** : vérifiez que le daemon voit bien des échecs :
  `journalctl -t sshd -n 5` et `journalctl -t sshd-session -n 5`. Un OpenSSH antérieur à 9.8 n'utilise que `sshd`, un OpenSSH récent que `sshd-session`. `SSH_LOG_TAGS` liste les deux par défaut.
- **`athena -u` répond que l'adresse n'est pas bannie** : le ban a peut-être expiré de lui-même (`athena -l` affiche le temps restant).
- **Les bans disparaissent après un redémarrage** : vérifiez que l'unité peut écrire dans `/var/lib/athena` (`systemctl status athena`) — c'est le fichier d'état qui les restaure.
