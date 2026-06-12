# Athena : Protection SSH Légère (nftables)

Athena est un daemon de sécurité ultra-léger conçu pour protéger votre serveur contre les attaques par force brute SSH. Il surveille les journaux système en temps réel et bannit automatiquement les IPs suspectes via **nftables**.


## Caractéristiques
- **Ultra-léger** : Consomme moins de **8 Mo de RAM** et quasiment **0% de CPU**.
- **Moderne** : Utilise `nftables` (remplaçant d'iptables) pour des performances optimales.
- **Persistant** : Restaure les bannissements actifs même après un redémarrage du service.

## Structure du Projet
- `athena-server` : Le daemon principal qui surveille les logs et gère le firewall.
- `athena` : L'outil CLI pour lister les bans et débannir manuellement une IP.
- `athena.conf` : Fichier de configuration centralisé.
- `athena.service` : Unité systemd pour la gestion du service.
- `Makefile` : Script d'installation et de désinstallation automatisé.

## Configuration (`/etc/athena/athena.conf`)
Vous pouvez ajuster le comportement d'Athena :
- `THRESHOLD` : Nombre d'échecs autorisés avant le ban (défaut: 2).
- `BAN_TIME` : Durée du bannissement en secondes (défaut: 3600s / 1h).
- `FIND_TIME` : Fenêtre de recherche des échecs dans les logs (défaut: 600s / 10min).
- `CHECK_INTERVAL` : Fréquence de vérification du serveur (défaut: 5s).
- `WHITE_LIST` : Liste d'IPs ou CIDR à ne jamais bannir.
- `PORT_BLOCK` : Ports à bloquer ("all" ou liste séparée par des virgules ex: "22,80,443").

## Installation & Désinstallation

### Installation
Le projet inclut un Makefile pour simplifier le déploiement sur Linux :
```bash
sudo make install
```
*Cette commande installe les binaires dans `/usr/bin`, la conf dans `/etc/athena` et active le service systemd.*

### Désinstallation
Pour supprimer proprement Athena et nettoyer les règles firewall :
```bash
sudo make uninstall
```

## Utilisation du client `athena`
Une fois installé, utilisez la commande `athena` :
- **Lister les bans actifs** : `athena -l`
- **Débannir une IP** : `athena -u 203.0.113.245`


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
```


## Statistiques d'utilisation en mai 2026
```bash
ls -lh --color=no /usr/bin/athena*
```
```text
-rwxr-xr-x 1 root root 2.1K May 27 18:36 /usr/bin/athena
-rwxr-xr-x 1 root root 6.5K May 27 18:36 /usr/bin/athena-server
```
```bash
systemctl status athena.service | grep --color=no -E 'Athena|Active|Memory' 
```
```text
● athena.service - Athena Security Daemon
   Active: active (running) since Wed 2026-05-27 18:36:08 CEST; 5 days ago
   Memory: 7.5M
```
