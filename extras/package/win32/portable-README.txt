PowerVLC — portable mode / mode portable
=========================================

[EN] As long as this "portable" folder sits next to powervlc.exe, PowerVLC
keeps its settings, its playlists, its media library and its cached cover art
HERE, instead of writing them to %APPDATA%\powervlc. Copy the whole PowerVLC
folder onto a USB stick and it carries everything with it, on any machine.

Delete this "portable" folder and PowerVLC behaves like a normally installed
copy again: it will go back to %APPDATA%\powervlc.

Nothing else is different. This is the very same build as the installer
version; only where it stores your data changes. Two details worth knowing:
the first launch is slow, because PowerVLC has to scan its plugins once and
build the cache the installer would otherwise have built at install time; and
file associations are not registered, since no installer ran.

[FR] Tant que ce dossier « portable » se trouve à côté de powervlc.exe,
PowerVLC conserve ICI ses réglages, ses listes de lecture, sa médiathèque et
ses pochettes, au lieu de les écrire dans %APPDATA%\powervlc. Copiez tout le
dossier PowerVLC sur une clé USB : il emporte tout avec lui, sur n'importe
quelle machine.

Supprimez ce dossier « portable » et PowerVLC se comporte de nouveau comme
une installation classique : il repassera par %APPDATA%\powervlc.

Rien d'autre ne change. C'est exactement la même version que celle de
l'installeur ; seul l'emplacement de vos données diffère. Deux détails à
connaître : le premier lancement est lent, car PowerVLC doit analyser ses
greffons une fois et construire le cache que l'installeur aurait construit à
l'installation ; et les associations de fichiers ne sont pas enregistrées,
puisqu'aucun installeur n'est passé.

PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.
PowerVLC est un fork non officiel de VLC, sans lien avec VideoLAN.
