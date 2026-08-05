/*****************************************************************************
 * dvddriver_backend.c : décodage MPEG-2 accéléré matériel via l'ABI DVDDriver*
 *****************************************************************************
 * Voir dvddriver_backend.h et doc/appleva-mpeg2-hwaccel-spec.md §6.
 *
 * Séquence (validée sur iBook G3, harnais ati_open.c/ati_decode.c) :
 *   surface CGS -> IOServiceGetMatchingService("ATIRadeon")
 *   -> DVDInitializeLibrary(serviceTable, mask, flushThunk, bindThunk=CGSBindSurface)
 *   -> DVDDriverOpenDevice(&ctx, &dims, displayID, cid, wid, sid, &caps, ...)
 *   -> par picture : DVDDriverDecode(ctx, pic_desc, rect{i16 top,left,bottom,right})
 *   -> DVDDriverShowMPBuffer(ctx, 0, ...)
 * Le driver construit en interne les paquets Radeon type-3 depuis pic_desc :
 *   pic_desc[0x02]=picture_structure ; [0x0c]=mb_desc[] (28 o) ; [0x10]=coeffs
 *     {u8 run,u8 pad,i16 level} ; [0x14/0x18/0x1c]=buffers de travail.
 *   mb_desc[0x14]=mb_type ; [0x16..0x1b]=nb_coeffs par bloc (Y0..V). Pas de CBP.
 *****************************************************************************/
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <ApplicationServices/ApplicationServices.h>
#include <IOKit/IOKitLib.h>

#include "dvddriver_backend.h"

/* U4 — INSTANCE UNIQUE par process. Le device DVDDriver/ATI n'admet qu'un
 * décodeur HW à la fois ; un 2e dvddriver_open() (2e flux MPEG-2 simultané)
 * renvoie NULL → l'appelant retombe sur libmpeg2 CPU. */
static int s_dd_instances = 0;

/* ==== FAMILLES GPU SUPPORTÉES ============================================
 * Une famille = une classe de service IOKit + le bundle DVDDriver que le kext
 * correspondant déclare en `IODVDBundleName`. N'ENTRE ICI QUE CE QUI A ÉTÉ
 * VÉRIFIÉ SUR LE MATÉRIEL — voir le garde-fou plus bas.
 *
 * ATIRage128 (ajouté le 2026-08-04) : Rage Mobility M3 de l'iBook G3
 * PowerBook4,1. Le bundle ATIRage128DVDDriver expose LA MÊME table de symboles
 * que celui du RV200, avec le même partage vraies-fonctions/stubs, et un
 * DVDDriverDecode de 4120 o contre 4164 (même code source). Validé en trois
 * temps par harnais autonomes sur la machine : OpenDevice rc=0 (caps=240,
 * dims={768,576}, ctx[0x1FC]=0 = même mode blit) ; DVDDriverDecode rc=0 en
 * ~4 ms sur une intra 720×576 au format pic_desc/mb_desc/coeffs du RV200,
 * 10 images d'affilée sans échec ni gel ; et l'image décodée S'AFFICHE
 * (dégradé horizontal reconnu à l'œil) par la recette Carbon compositing.
 * La transformation des coefficients est donc la même que sur le RV200. */
struct dd_family {
    const char *service;    /* classe IOKit du GPU */
    const char *bundle;     /* exécutable du bundle DVDDriver */
    /* Le plan SUBPICTURE matériel adresse le contexte PRIVÉ du driver par des
     * offsets relevés au désassemblage (ctx[0x1C4], [0x2D4+4i], [0x2F4+4i],
     * [0x414]…). Ces offsets ne valent QUE pour le layout où ils ont été
     * relevés. Faux ⇒ décodage matériel seul, sous-titres par le chemin CPU. */
    bool        sp_layout_ok;
    /* Taille du contexte alloué par OpenDevice (lue dans son désassemblage :
     * le `li r3,<n>` qui précède le memset). Documentaire, mais c'est elle qui
     * dit pourquoi `sp_layout_ok` est faux ci-dessous. */
    unsigned    ctx_size;
    /* La surface doit-elle vivre dans NOTRE fenêtre Carbon plutôt que dans la
     * fenêtre (Cocoa) de VLC ?
     * ⚠ Le Rage 128 a d'abord semblé l'exiger (écran noir en s'y liant), mais
     * c'était le MÊME défaut que l'écran vert : le plan vidéo n'était pas armé
     * (SetMPRects/EnableMP jamais appelés). Une fois armé, la surface s'affiche
     * parfaitement dans la fenêtre de VLC — et c'est CE chemin qu'il faut, il
     * laisse les contrôles accessibles et permet au vout d'incruster les
     * sous-titres. Le champ reste pour une famille qui l'exigerait vraiment. */
    bool        needs_own_window;
    /* Suivre STRICTEMENT le protocole d'affichage du lecteur d'Apple, relevé au
     * spy interposé : ni CGSSetWindowLevel sur la fenêtre vidéo, ni
     * CGSFlushSurface (jamais un seul en lecture). Sur le Rage 128 c'est la
     * condition de l'affichage ; le RV200 garde le protocole qui y est éprouvé,
     * n'ayant pas été retesté avec celui-ci. */
    bool        apple_display_seq;

    /* ==== Offsets du plan SUBPICTURE dans le contexte privé ================
     * `GetSPBuffer` rend DEUX séries de tampons :
     *     série « a » (Rage 128 : ctx[0x188+4i]) = LE PLAN DE PIXELS, progressif,
     *                 192 o/ligne × 576 lignes (0x1B000), 2 bits/pixel ;
     *     série « b » (ctx[0x168+4i])            = les commandes DCSQ.
     * ⚠ Il existe une TROISIÈME série (ctx[0x1A8+4i]) qui n'est PAS un second
     * champ, contrairement à ce que j'ai cru : `ClearSP` l'initialise à 0xFF sur
     * 0x9000 octets seulement (192 × 192) et le blit lui soumet un descripteur
     * distinct. Y recopier le plan la déborde de 72 Ko et écrase les tampons
     * voisins, qui sont contigus. On n'y touche pas — voir la note détaillée
     * dans `dvddriver_sp_submit`.
     * `sp_flag_off` = le DRAPEAU D'AFFICHAGE, armé par le moteur d'ApplySPDCSQ
     * et sans lequel le plan reste invisible quoi qu'on y écrive
     * (Rage 128 : 0x15C ; RV200 : 0x1C4). 0 = inconnu pour cette famille. */
    unsigned    sp_flag_off;
    /* Faut-il RÉ-ÉTALER le subpicture après chaque image vidéo ?
     * Sur le RV200, `ShowMPBuffer` le fait lui-même à chaque image (gate
     * ctx[0x1C4]) : rien à faire. Sur le Rage 128 cette branche N'EXISTE PAS
     * (son ShowMPBuffer fait 128 o et ne contient aucune logique SP), si bien
     * que l'image vidéo suivante ÉCRASE le subpicture aussitôt blitté — d'où
     * « 10 incrustés, 0 en échec » et pourtant rien à l'écran.
     * ⚠⚠ Ne l'activer QUE pour ces familles : appeler ShowSPBuffer en boucle
     * sur le chemin de present a FIGÉ un GPU le 2026-07-22 (extinction complète
     * requise). Les gardes du site d'appel sont là pour ça. */
    bool        sp_needs_reshow;
    /* Surface à la TAILLE NATIVE au lieu du letterbox mis à l'échelle.
     * ⚠ Piste ouverte pour rendre le subpicture visible dans VLC : le harnais ne
     * l'affiche QUE dans cette configuration. Mais poser le rect ici ne suffit
     * pas — `dvddriver_present_index` le réécrit à chaque image avec la
     * géométrie du vout. Pour vraiment tester, il faut AUSSI neutraliser ce
     * SetBounds-là. Laissé à false : rien de concluant à ce jour. */
    bool        sp_needs_native_scale;
    /* Le moteur 2D lit le plan SP en mots de 32 bits PETIT-BOUTISTES, alors que
     * nous l'écrivons en gros-boutiste : il faut échanger les octets dans chaque
     * mot, sinon les pixels sortent retournés par fenêtres de 16 (4 octets), ce
     * qui rend le texte illisible « en miroir par morceaux » tout en laissant
     * les aplats intacts.
     * ⚠ Établi à l'écran sur le Rage 128 (2026-08-04) après avoir ÉLIMINÉ le
     * miroir de ligne : une mire de repères asymétriques (gate /tmp/hw_sp_band)
     * tombe exactement à sa place, donc l'adressage global est bon. Attention,
     * cette mire ne discrimine PAS à elle seule — des blocs de 16 px ou plus
     * sont invariants par ce retournement, comme un aplat l'est par n'importe
     * quel adressage. Seul du VRAI texte tranche. */
    bool        sp_swap_words;
    /* Drainer la file des soumissions en RÉ-AFFICHANT la surface déjà à l'écran
     * au lieu de la surface périmée. Corrige les « retours en arrière » (image
     * future poussée à l'écran) sans aucune contre-pression — cf. la note dans
     * `dvddriver_present_index`. Vrai pour les familles `apple_display_seq`, qui
     * n'appellent pas `CGSFlushSurface` et dont la composition asynchrone peut
     * donc échantillonner un Show intermédiaire. Laissé FAUX sur le RV200, où
     * l'artefact avait déjà été réglé sur les trois OS et où ce changement n'a
     * pas été éprouvé ; `/tmp/hw_drain_last` permet de l'y essayer. */
    bool        drain_shows_current;
    /* ★ 10.2 UNIQUEMENT — offset du mot couleurs/contrastes que le chemin
     * `lay_sp_stub` écrit À LA MAIN (le SetSPBuffer de 10.2 est un quasi-stub).
     * ⚠⚠ 0 = PAS D'ÉQUIVALENT CONNU, et il FAUT alors s'abstenir : le contexte
     * du Rage 128 sous 10.2 ne fait que 348 o (0x15C), l'offset 0x1DC du RV200
     * y écrirait 128 octets APRÈS la fin du bloc — corruption du tas. */
    unsigned    sp_cc_off_102;
    /* ★ Taille du contexte SOUS 10.2, quand le pilote y est un autre binaire.
     * 0 = même taille que `ctx_size`. Le Rage 128 tombe de 760 à 348 o : sans
     * cette valeur, tous nos offsets relevés sur 10.4 débordent silencieusement
     * (cf. `ctx_bytes` dans le contexte). */
    unsigned    ctx_size_102;
};

/* ── Accès BORNÉS au contexte privé du pilote ────────────────────────────────
 * Tout accès à `dev_ctx` à un offset codé en dur DOIT passer par ici. Les
 * offsets sont relevés au désassemblage d'UNE version du bundle ; une autre
 * version, ou un autre système, alloue un contexte plus petit et l'accès sort
 * du bloc. En lecture cela ramène du tas voisin (diagnostic mensonger) ; en
 * écriture c'est une corruption ; et pour ctx[0x204], suivi comme un pointeur,
 * c'est un déréférencement d'adresse arbitraire. */
static bool     dd_ctx_has(const dvddriver_ctx *ctx, unsigned off, unsigned len);
static uint32_t dd_ctx_u32(const dvddriver_ctx *ctx, unsigned off);

static const struct dd_family s_dd_families[] = {
    { "ATIRadeon",
      "/System/Library/Extensions/ATIRadeonDVDDriver.bundle/Contents/MacOS/"
      "ATIRadeonDVDDriver",
      true, 1132, false, false,
      /* sp_flag_off, sp_needs_reshow, sp_needs_native_scale,
         sp_swap_words, drain_shows_current, sp_cc_off_102, ctx_size_102 */
      0x1C4, false, false, false, false, 0x1DC, 0 },
    /* Rage 128 : contexte de 760 o (0x2F8) contre 1132 sur le RV200, avec ses
     * huit derniers octets en chaînage (OpenDevice fait `stw ctx,0(ctx+752)`).
     * Sa carte d'offsets SP a été relevée POUR ELLE-MÊME et validée à l'écran
     * (2026-08-04) : les champs sont plus bas que ceux du RV200, avec deux écarts
     * distincts (0x16C pour les tableaux, 0xB4/0x70 pour l'état) — ce n'est PAS
     * une simple translation. `Get/SetFeatureParam` y sont des stubs, mais ils ne
     * servent pas : le drapeau d'affichage est armé par le moteur d'ApplySPDCSQ.
     * ⚠ Ces offsets valent pour les bundles 10.4 ET 10.3 (même code, décalé de
     * 4 octets — vérifié : GetSPBuffer y lit les mêmes 0x188/0x168).
     * ⚠⚠ Le bundle 10.2 est un TOUT AUTRE pilote (42748 o) : son GetSPBuffer
     * ignore le contexte et déréférence un GLOBAL, lisant ses séries à +0x44 et
     * +0x24 — même structure que le 10.2 du RV200. Sur le RV200, le SP matériel
     * FONCTIONNE pourtant sur Jaguar, via le chemin `lay_sp_stub` (paquet SPU
     * brut dans la série b + mot couleurs/contrastes posé à la main). Mais ce
     * chemin écrit `ctx[0x1DC]`, un offset RV200 : il n'a PAS été relevé pour le
     * Rage 128, et son champ 1 vit dans le global, pas dans le contexte.
     * ⇒ Sur Rage 128, le SP est donc actif en 10.3/10.4 et désactivé en 10.2
     * FAUTE DE RELEVÉ — pas par impossibilité. Le refaire demande de dériver le
     * layout du bundle 10.2 de cette puce (le harnais `r128_sp5.c` s'y prête). */
    { "ATIRage128",
      "/System/Library/Extensions/ATIRage128DVDDriver.bundle/Contents/MacOS/"
      "ATIRage128DVDDriver",
      true, 760, false, true,
      /* sp_flag_off, sp_needs_reshow, sp_needs_native_scale,
         sp_swap_words, drain_shows_current, sp_cc_off_102, ctx_size_102 */
      0x15C, false, false, true, true, 0, 348 },
      /* ⚠ `sp_layout_ok` réactivé POUR LE TEST /tmp/hw_sp_solid (2026-08-04) :
       * le protocole SP est entièrement reversé et PROUVÉ au harnais
       * (r128_sp5.c affiche le plan à l'écran), mais dans VLC il n'affichait
       * RIEN tout en coûtant des à-coups et du scintillement.
       * Éliminés par la mesure : l'écrasement par l'image vidéo (le SP survit au
       * décodage continu), la géométrie/mise à l'échelle (rect figé en natif :
       * image centrée, toujours aucun sous-titre) et le type de fenêtre
       * (Carbon dédiée : idem). Seule piste restante : le CONTENU (bitmap RLE
       * décodé + colors/contrasts réels) — le gate /tmp/hw_sp_solid force le
       * motif uniforme du harnais pour trancher. Si ce test échoue aussi,
       * remettre FALSE (sous-titres logiciels). */
      /* ré-étalement du SP : inutile (testé — le SP survit au décodage continu) ;
       * surface en taille native : expérience NON CONCLUANTE, cf. la note
       * `sp_needs_native_scale` — le rect posé à l'ouverture est de toute façon
       * ÉCRASÉ à chaque image par le present (CGSSetSurfaceBounds avec la
       * géométrie publiée par le vout), donc le test n'a jamais porté. */
};

/* ★★★ DÉCOUVERTE DYNAMIQUE DU GREFFON DE LA CARTE — `IODVDBundleName`.
 *
 * C'est ainsi qu'Apple s'y prend, relevé au désassemblage de `DVD.framework`
 * (`DVDVideoOpenDevice`) : il localise l'accélérateur de l'écran, lit la
 * propriété IOKit **`IODVDBundleName`** sur son nœud, et en déduit
 * `/System/Library/Extensions/<nom>.bundle/Contents/MacOS/<nom>`.
 * Le catalogue d'un 10.2 en liste déjà quatre — `ATIRadeonDVDDriver`,
 * `ATIRadeon8500DVDDriver`, `ATIRadeon9700DVDDriver`, `ATIRage128DVDDriver` —
 * plus un repli LOGICIEL `AppleAltiVecDVDDriver`.
 *
 * ⇒ Intérêt : **plus aucun chemin de greffon ni nom de classe IOKit en dur**.
 * Une carte que nous ne possédons pas est prise en charge sans une ligne de
 * code, là où la table ne connaissait que les deux puces des bancs de test.
 *
 * ⚠ On n'utilise PAS `DVD.framework` lui-même : ce n'est qu'un aiguilleur
 * (`DVDVideoDecode` = `bctr` vers `vtable[0x24]`, arguments inchangés), il
 * n'apporterait rien de plus, et PowerVLC doit rester indépendant de tout autre
 * logiciel. On refait donc ses deux appels utiles nous-mêmes.
 * ⚠ On n'utilise PAS non plus `IOAccelFindAccelerator` (non documenté) : un
 * parcours du registre IOKit avec des API publiques disponibles **depuis 10.0**
 * fait le même travail et reste valable de 10.2 à aujourd'hui.
 *
 * ⇒ EXTENSION PRÉVUE (Intel, GMA950…) : ces machines n'exposent pas
 * `IODVDBundleName` mais passent par **AppleVA** (`AppleVADriver.bundle`, clé
 * `AppleVABundlePath` du cadriciel d'Apple, arbitrée par `UseGPUDVDDriver`).
 * C'est une AUTRE API que `DVDDriver*` — d'où la séparation ci-dessous entre
 * « quel greffon » et « quelle API » : la découverte rend un nom, le reste du
 * backend décide quoi en faire. Cf. [[powervlc-gma950-mpeg2-hw-decode]]. */
static bool dd_bundle_name_from_ioreg(char *out, size_t outsz,
                                      io_service_t *out_svc)
{
    io_iterator_t it = 0;
    if (IORegistryCreateIterator(kIOMasterPortDefault, kIOServicePlane,
                                 kIORegistryIterateRecursively, &it) != KERN_SUCCESS)
        return false;

    bool found = false;
    io_object_t obj;
    while (!found && (obj = IOIteratorNext(it)) != 0)
    {
        CFTypeRef v = IORegistryEntryCreateCFProperty(obj,
                          CFSTR("IODVDBundleName"), kCFAllocatorDefault, 0);
        if (v != NULL) {
            if (CFGetTypeID(v) == CFStringGetTypeID()
                && CFStringGetCString((CFStringRef) v, out, (CFIndex) outsz,
                                      kCFStringEncodingUTF8)
                && out[0] != '\0') {
                found = true;
                if (out_svc != NULL) {
                    *out_svc = obj;       /* transmis à l'appelant, non relâché */
                    obj = 0;
                }
            }
            CFRelease(v);
        }
        if (obj != 0)
            IOObjectRelease(obj);
    }
    IOObjectRelease(it);
    return found;
}

/* Famille « découverte » : remplie à la volée quand `IODVDBundleName` désigne un
 * greffon que la table ne connaît pas. On n'y active QUE le décodage : aucun
 * offset de contexte n'ayant été relevé pour cette puce, tout accès à des
 * offsets codés en dur reste interdit (`sp_layout_ok` faux, `sp_flag_off` et
 * `sp_cc_off_102` nuls, `ctx_size` nul ⇒ `lay_mp_pitch` forcé à 0 à l'ouverture).
 * Sous-titres par le chemin logiciel : lent mais correct, et surtout SÛR. */
static struct dd_family s_dd_discovered;
static char s_dd_disc_bundle[512];
static char s_dd_disc_name[128];

/* Cherche la première famille dont le service IOKit est présent ET dont le
 * bundle expose l'API. Renvoie NULL si aucune : l'appelant fait le fallback CPU.
 * `out_svc`, s'il est fourni, reçoit le service (à libérer par l'appelant) ;
 * sinon le service est relâché ici. */
/* ★★ MÉMOÏSATION — indispensable, pas une optimisation.
 * Cette fonction fait un parcours du registre IOKit ET un `dlopen`/`dlclose` du
 * greffon du pilote. Elle est appelée à CHAQUE ouverture de décodeur — et avec
 * dvdnav, un DVD en recrée un à chaque transition menu/titre. Charger puis
 * DÉCHARGER en boucle le greffon d'une carte pendant qu'un contexte est ouvert
 * est tout sauf anodin : c'est ce qui a fait planter le RV200 (erreur de bus,
 * 0 image, là où le greffon d'origine en décodait 778) dès que j'ai ajouté un
 * appel de journalisation qui refaisait ce travail.
 * ⇒ La FAMILLE est constante pour la durée du processus : on la calcule une
 * fois. Seul le SERVICE IOKit est réobtenu à la demande, car l'appelant le
 * possède et doit le libérer. */
static const struct dd_family *s_dd_cached      = NULL;
static bool                    s_dd_cached_done = false;

static const struct dd_family *dd_find_family_uncached(io_service_t *out_svc);

static const struct dd_family *dd_find_family(io_service_t *out_svc)
{
    if (s_dd_cached_done && out_svc == NULL)
        return s_dd_cached;              /* aucun travail : ni IOKit, ni dlopen */

    const struct dd_family *f = dd_find_family_uncached(out_svc);
    if (!s_dd_cached_done) {
        s_dd_cached      = f;
        s_dd_cached_done = true;
    }
    return f;
}

static const struct dd_family *dd_find_family_uncached(io_service_t *out_svc)
{
    if (out_svc != NULL)
        *out_svc = 0;

    /* 1) Voie DYNAMIQUE, celle d'Apple : la carte annonce son greffon. */
    io_service_t dsvc = 0;
    if (dd_bundle_name_from_ioreg(s_dd_disc_name, sizeof s_dd_disc_name, &dsvc))
    {
        snprintf(s_dd_disc_bundle, sizeof s_dd_disc_bundle,
                 "/System/Library/Extensions/%s.bundle/Contents/MacOS/%s",
                 s_dd_disc_name, s_dd_disc_name);

        void *dl = dlopen(s_dd_disc_bundle, RTLD_NOW | RTLD_LOCAL);
        const bool api_ok = dl != NULL
                         && dlsym(dl, "DVDDriverOpenDevice") != NULL
                         && dlsym(dl, "DVDDriverDecode")     != NULL;
        if (dl != NULL)
            dlclose(dl);

        if (api_ok) {
            /* Cette puce est-elle DÉJÀ tabulée ? On compare le nom annoncé au
             * chemin connu : si oui, on garde les réglages relevés pour elle
             * (offsets SP, taille de contexte, inversion de mots…), qui valent
             * mieux que des valeurs par défaut. */
            for (size_t i = 0; i < sizeof(s_dd_families) / sizeof(s_dd_families[0]); i++) {
                const struct dd_family *f = &s_dd_families[i];
                if (strstr(f->bundle, s_dd_disc_name) != NULL) {
                    if (out_svc != NULL) *out_svc = dsvc; else IOObjectRelease(dsvc);
                    return f;
                }
            }
            /* Inconnue : décodage seulement, tout accès mémoire spéculatif
             * interdit (cf. la note sur `s_dd_discovered`). */
            memset(&s_dd_discovered, 0, sizeof s_dd_discovered);
            s_dd_discovered.service = s_dd_disc_name;   /* documentaire */
            s_dd_discovered.bundle  = s_dd_disc_bundle;
            if (out_svc != NULL) *out_svc = dsvc; else IOObjectRelease(dsvc);
            return &s_dd_discovered;
        }
        IOObjectRelease(dsvc);
    }

    /* 2) Repli AUTOMATIQUE : l'ancienne table, si la carte n'annonce pas la
     * propriété (ou si son greffon n'expose pas l'API). C'est ce repli — et non
     * un interrupteur — qui couvre le cas d'une découverte infructueuse. */

    for (size_t i = 0; i < sizeof(s_dd_families) / sizeof(s_dd_families[0]); i++)
    {
        const struct dd_family *f = &s_dd_families[i];

        io_service_t svc = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                   IOServiceMatching(f->service));
        if (svc == 0)
            continue;

        /* Le service existe : le bundle doit exister aussi et porter l'API. */
        void *dl = dlopen(f->bundle, RTLD_NOW | RTLD_LOCAL);
        if (dl == NULL) {
            IOObjectRelease(svc);
            continue;
        }
        bool ok = dlsym(dl, "DVDDriverOpenDevice") != NULL
               && dlsym(dl, "DVDDriverDecode")     != NULL;
        dlclose(dl);
        if (!ok) {
            IOObjectRelease(svc);
            continue;
        }

        if (out_svc != NULL)
            *out_svc = svc;
        else
            IOObjectRelease(svc);
        return f;
    }
    return NULL;
}

/* Banc d'essai : charger le pilote d'un AUTRE système que celui qui a démarré.
 * Les trois volumes de la machine de test en portent trois versions distinctes
 * (md5 différents) et DVDDriverDecode n'y coûte pas le même prix. Sans effet
 * si la variable n'est pas posée. */
static const char *ati_bundle_path(const struct dd_family *f)
{
    const char *p = getenv("POWERVLC_ATI_BUNDLE");

    if (p != NULL && *p != '\0')
        return p;
    return (f != NULL) ? f->bundle : s_dd_families[0].bundle;
}
#define CARBON_FW \
    "/System/Library/Frameworks/Carbon.framework/Carbon"

/* ⚠️ NE PAS AJOUTER DE FAMILLE À `s_dd_families` SANS L'AVOIR VÉRIFIÉE SUR LE
 * MATÉRIEL. Le Mac mini G4 expose sa Radeon 9200 (RV280) sous la classe
 * "ATIRadeon8500" ; l'y avoir fait correspondre a bien allumé le chemin matériel
 * — et a FIGÉ LE GPU de la machine (2026-07-23, extinction complète requise).
 * "ATIRadeon8500" reste donc EXCLUE, de même que "ATIRadeon9700" et "ATIRagePro".
 *
 * Le protocole de vérification, celui qui a servi à admettre ATIRage128 le
 * 2026-08-04, est en trois temps et par HARNAIS AUTONOME (jamais VLC en
 * premier — un gel coûte une extinction complète) :
 *   1. le bundle du kext (`IODVDBundleName`) expose-t-il DVDDriverOpenDevice et
 *      un VRAI DVDDriverDecode (et non le stub `li r3,-5`) ? — au désassemblage ;
 *   2. OpenDevice/CloseDevice rc=0 sans fuite de contexte IOKit ;
 *   3. Decode rc=0 sur une intra synthétique, puis affichage vérifié À L'ŒIL
 *      (screencapture ne voit pas la surface du décodeur).
 * Voir doc/pb-offload/, powervlc-g4-deinterlace-selector et
 * powervlc-ibook-rage128-testbed. */

#define MB_DESC_SIZE 0x1c        /* 28 o */

/* ==== Fenêtre Carbon compositing (recette d'affichage HW crackée) =========
 * L'affichage de la surface décodée à l'écran exige une VRAIE fenêtre
 * applicative CARBON : ni une NSWindow Cocoa, ni une fenêtre CGS nue ne
 * compositent la surface liée au décodeur (mur reversé sur G3 ET Intel ;
 * harnais ati_carbon.c). On résout les fonctions Carbon par dlsym pour ne pas
 * tirer <Carbon/Carbon.h> dans un module codec (cross-compile GCC13/SDK Tiger).
 * La séquence : CreateNewWindow(compositing) → wid → CGSAddSurface →
 * CGSSetSurfaceBounds → CGSOrderSurface(order=1) → OpenDevice ; puis par frame
 * Decode → ShowMPBuffer → CGSSetSurfaceBounds → CGSFlushSurface(cid,wid,sid,région). */
typedef struct { int16_t top, left, bottom, right; } dd_Rect;
#define DD_kDocumentWindowClass         6u
#define DD_kPlainWindowClass            3u            /* borderless, pas de barre de titre */
#define DD_kWindowCompositingAttribute  0x00080000u   /* 1<<19 */
#define DD_kWindowStandardHandlerAttr   0x02000000u   /* 1<<25 */
#define DD_kWindowNoActivatesAttribute  0x00020000u   /* 1<<17 : ne devient jamais fenêtre clé */

/* Prototypes de l'ABI DVDDriver* (résolus par dlsym). */
typedef void (*dvd_init_fn)(void *serviceTable, uint32_t mask, void *flush, void *bind);
typedef int  (*dvd_open_fn)(void **outCtx, void *outDims, uint32_t displayID,
                            uint32_t cid, uint32_t wid, uint32_t sid,
                            uint32_t *outCaps, uint32_t unused,
                            uint16_t *outFive, uint16_t *outEight);
typedef int  (*dvd_decode_fn)(void *ctx, void *pic_desc, void *rect);
typedef void (*dvd_show_fn)(void *ctx, uint32_t index, void *field, void *buf);
typedef void (*dvd_close_fn)(void *ctx);
typedef void (*dvd_term_fn)(void);
/* RE perf : SetMVLevel(ctx_struct, level) — envoie io_connect sel=146. DVD Player
 * l'appelle ~1×/picture (level=0) ; nous jamais. Test d'un chemin MC plus rapide. */
typedef int  (*dvd_setmvlevel_fn)(void *ctx, int level);

/* ── Chantier SP : sous-titres composés par le DÉCODEUR MATÉRIEL ────────────
 * Le bundle expose tout un plan « subpicture » (c'est ainsi que le lecteur DVD
 * d'Apple affiche des sous-titres sur de la vidéo accélérée, sans faire
 * intervenir le WindowServer — dont le chemin translucide au-dessus d'une
 * surface matérielle coûte 15 à 50 ms par mise à jour, cf.
 * doc/pb-offload/subs-osd-findings.md).
 * Signatures déduites du désassemblage (ATIRadeonDVDDriver-full-disasm.txt) :
 *   GetSPBuffer(ctx, a[8], b[8]) : recopie ctx[0x2F4+4i] → a[i] et
 *       ctx[0x2D4+4i] → b[i] pour i<8 — HUIT tampons SP, deux champs chacun ;
 *   SetSPBuffer(ctx, idx, rect)  : mémorise idx en ctx+0x1B0 et le rectangle
 *       (4× i16) en ctx+0x1E4… ;
 *   ShowSPBuffer(ctx, idx, rect) : pendant de ShowMPBuffer ;
 *   SetSPPalette(ctx, pal)       : recopie 64 octets = 16 entrées × 4 (la
 *       palette SPU du DVD), puis conversion YUV→RGB en interne ;
 *   ApplySPDCSQ(ctx, idx, base, off) : applique la séquence de commandes
 *       d'affichage SPU BRUTE située en base+off — le driver sait donc
 *       interpréter le paquet SPU natif du disque ;
 *   EnableSP(ctx, on), ClearSP(ctx, ?) ;
 *   GetKeyColor(ctx, &color) : le plan SP est composé par COULEUR-CLÉ.
 * SetSPColorControl / SetSPDefaultColorControl sont des stubs (return 0). */
typedef int  (*dvd_getspbuf_fn)(void *ctx, uint32_t a[8], uint32_t b[8]);
typedef int  (*dvd_setspbuf_fn)(void *ctx, uint32_t idx, const void *rect);
typedef int  (*dvd_showspbuf_fn)(void *ctx, uint32_t idx, const void *rect);
typedef int  (*dvd_setsppal_fn)(void *ctx, const void *palette64);
typedef int  (*dvd_applydcsq_fn)(void *ctx, uint32_t idx, const void *base,
                                 uint32_t dcsq_offset);
typedef int  (*dvd_enablesp_fn)(void *ctx, int enable);
typedef int  (*dvd_clearsp_fn)(void *ctx, int arg);
/* ── API BOUTON : c'est ELLE qui déclenche le blit sur le pilote de 10.2 ─────
 * Désassemblage (bundle 10.2, mode surface ctx[0x1FC]==0) :
 *   PrepareButton(ctx, rect, _) : range le rect du bouton (4 × int16, ordre Mac
 *       { haut, gauche, bas, droite }) en ctx[0x1F4] et ctx[0x1F8], puis le
 *       DÉCOUPE contre le rect du plan rangé par ShowSPBuffer (ctx[0x1E4]…) ;
 *       le 3e argument n'est lu que dans l'autre mode.
 *   EnableButton(ctx, on) : pose ctx[0x1D8] = !!on — la condition SANS LAQUELLE
 *       ShowSPBuffer n'appelle le blit qu'avec son argument « 0 », c'est-à-dire
 *       pour rien — puis, si le drapeau d'affichage ctx[0x1C4] est armé,
 *       APPELLE LUI-MÊME LE VRAI BLIT sur le tampon ctx[0x1B0] (0x2690/0x26a0,
 *       le second appel avec l'argument 1).
 * Sur 10.4 rien de tout cela n'est nécessaire : son SetSPBuffer blitte
 * directement. Sur 10.2 SetSPBuffer est un stub, et cette API est la SEULE
 * route vers le blit. */
typedef int  (*dvd_preparebutton_fn)(void *ctx, const void *rect, void *unused);
typedef int  (*dvd_enablebutton_fn)(void *ctx, int enable);
typedef int  (*dvd_getkeycolor_fn)(void *ctx, uint32_t *color);
/* Plan VIDÉO (MP). Le driver expanse le bitmap SPU vers la destination définie
 * par ces appels : sans eux, sa boucle d'expansion écrit à une adresse invalide
 * (crash mesuré sur `stwx` dans DVDDriverSetFeatureParam+996). Arités relevées
 * au désassemblage : SetMPRects(ctx, rect4, 0, 0) — cf. l'appel interne à
 * 0x40f4 qui construit un rect de 4 × int16 sur la pile. */
typedef int  (*dvd_setmprects_fn)(void *ctx, const void *rect, int a, int b);
typedef int  (*dvd_enablemp_fn)(void *ctx, int enable);

/* CGSBindSurface : pointeur résolu une fois, utilisé par le thunk myBind.
 * OpenDevice appelle allocator(cid,wid,sid,36,displayID) ; le thunk d'Apple fait
 * CGSBindSurface(cid,wid,sid,2,36,displayID). On réplique exactement. */
static int (*s_CGSBindSurface)(int, int, int, int, int, uint32_t);
static int dd_bind_thunk(int cid, int wid, int sid, int a6, uint32_t disp)
{
    return s_CGSBindSurface ? s_CGSBindSurface(cid, wid, sid, 2, a6, disp) : -1;
}
static int dd_flush_thunk(int a, int b, int c, int d)
{
    (void)a; (void)b; (void)c; (void)d;
    return 0;
}

/* Lit un gate /tmp (chantier perf/RE). Absent → -1 ; présent sans contenu → 1 ;
 * sinon la valeur entière écrite dedans. Lu UNE fois par appelant (cache). */
static int dd_gate_read(const char *path)
{
    FILE *f = fopen(path, "r");
    if (f == NULL)
        return -1;
    int v = 1;
    if (fscanf(f, "%d", &v) != 1)
        v = 1;
    fclose(f);
    return v;
}

struct dvddriver_ctx
{
    void *dl_bundle;                 /* dlopen(ATIRadeonDVDDriver) */
    void *dl_as;                     /* dlopen(ApplicationServices) */
    void *dev_ctx;                   /* contexte DVDDriverOpenDevice (1132 o) */
    dvd_decode_fn Decode;
    dvd_show_fn   Show;
    /* plan subpicture matériel (chantier SP) */
    dvd_getspbuf_fn    GetSPBuffer;
    dvd_setspbuf_fn    SetSPBuffer;
    dvd_showspbuf_fn   ShowSPBuffer;
    dvd_setsppal_fn    SetSPPalette;
    dvd_applydcsq_fn   ApplySPDCSQ;
    dvd_enablesp_fn    EnableSP;
    dvd_clearsp_fn     ClearSP;
    dvd_preparebutton_fn PrepareButton;
    dvd_enablebutton_fn  EnableButton;
    dvd_getkeycolor_fn GetKeyColor;
    dvd_setmprects_fn  SetMPRects;
    dvd_enablemp_fn    EnableMP;
    /* sonde : valeurs lues par GetSPBuffer à l'ouverture (16 mots) + couleur-clé */
    int16_t  sp_rect[4];   /* rectangle du dernier montage SP (diagnostic) */
    uint32_t sp_probe[16];
    uint32_t sp_first_word[8];   /* premier mot lu dans chaque tampon SP */
    /* SP5c — contenu de la destination du blit, avant/après les premiers Show */
    uint32_t sp_dest_before[3][4], sp_dest_after[3][4];
    int      sp_dest_probes;
    uint32_t sp_stage[6];          /* SP7b — empreintes par étape de la séquence */
    int      sp_stage_valid;
    uint32_t sp_keycolor;
    /* SP4 — état du plan SP en exploitation réelle (paquets SPU du disque). */
    int      sp_next_buf;          /* rotation des 8 tampons SP               */
    bool     sp_test_band;         /* gate /tmp/hw_sp_band (A/B contenu)      */
    bool     sp_force_mprects;     /* gate /tmp/hw_sp_mprects (mise au point) */
    bool     sp_armed;             /* EnableSP(1) + palette déjà posés          */
    bool     sp_visible;           /* une incrustation est actuellement montée  */
    int64_t  sp_hide_at_us;        /* échéance d'effacement, 0 = pas d'échéance */
    int64_t  sp_last_apply_us;     /* dernier montage — sert au plafond de cadence */
    uint32_t sp_shown, sp_hidden, sp_dropped;   /* compteurs (diagnostic)       */
    /* Régularité de la présentation : histogramme des intervalles entre deux
     * presents. Sépare un défaut de CADENCE de notre côté (intervalles
     * irréguliers) d'une saccade structurelle 25 fps sur écran 60 Hz
     * (intervalles réguliers à 40 ms, mais 2 ou 3 rafraîchissements par image).
     * Coût : deux entiers par image, aucune lecture mémoire GPU. */
    unsigned long pres_last_us;
    uint32_t pres_hist[8];   /* <25, <33, <37, <43, <50, <60, <100, >=100 ms */
    uint32_t dec_hist[8];    /* durée d'un Decode : <4, <8, <12, <16, <24, <40, <80, >=80 ms */
    unsigned long us_last_decode;  /* durée du dernier Decode (corrélation type↔durée) */
    uint32_t pres_n;
    uint32_t sp_mode_flag, sp_ctx_word0, sp_cur_buf, sp_enable_st, sp_caps;
    /* ── Layout du contexte PRIVÉ, par version du bundle ────────────────────
     * Relevé par désassemblage des trois versions (cf. dvddriver_open). Tous
     * les champs que nous touchons sont en LECTURE SEULE et se trouvent aux
     * MÊMES offsets sur 10.2, 10.3 et 10.4 — à une exception près :
     *   `lay_mp_pitch` : le pas de ligne de la destination du blit, que le
     *   SetMPRects de 10.3/10.4 MÉMORISE en ctx[0x414] (avec le rect en
     *   0x410/0x418/0x41c/0x420). Celui de 10.2 ne mémorise RIEN — il n'écrit
     *   que ctx[0x18] — donc l'offset n'y existe pas et vaut 0 ici : on ne peut
     *   pas demander au pilote si la géométrie est déjà posée, et on n'y touche
     *   donc PAS du tout sur 10.2 (cf. dvddriver_sp_submit : l'y forcer déplace
     *   l'image et éteint le plan subpicture).
     * `lay_deref_ok` : peut-on suivre ctx[0x204] comme un POINTEUR pour les
     * empreintes de diagnostic ? Seulement là où le layout est connu — sinon
     * ce serait déréférencer ce qui traîne à cet offset. */
    unsigned lay_mp_pitch;
    bool     lay_deref_ok;
    /* `lay_sp_stub` : sur 10.2, `DVDDriverSetSPBuffer` est un QUASI-STUB — il
     * mémorise l'index et arme le drapeau ctx[0x1D0], puis rend la main sans
     * jamais lire le descripteur ni appeler le blit (13 instructions, contre 40
     * sur 10.4). Il faut donc poser à sa place le mot couleurs/contrastes que
     * la version 10.4 extrait du descripteur. */
    bool     lay_sp_stub;
    /* valeurs de SORTIE d'OpenDevice, jusqu'ici ignorées */
    uint32_t open_caps, open_dims[4];
    uint16_t open_five, open_eight;
    bool     sp_available;
    /* Recopié de la famille GPU : suivre le protocole d'affichage d'Apple
     * (pas de CGSFlushSurface). Cf. `apple_display_seq`. */
    bool     no_flush;
    /* Offsets SP recopiés de la famille (0 = inconnu). Cf. `sp_flag_off`. */
    unsigned sp_flag_off;
    /* commandes SPU du sous-titre courant (0x03 SET_COLOR / 0x04 SET_CONTR),
     * mémorisées au submit pour que dd_sp_set_display les rejoue telles quelles */
    uint16_t sp_cmd_colors, sp_cmd_contrasts;
    bool     sp_needs_reshow;      /* recopié de la famille */
    bool     sp_native_scale;      /* recopié de la famille */
    bool     sp_swap_words;        /* recopié de la famille */
    bool     drain_shows_current;  /* recopié de la famille */
    unsigned sp_cc_off_102;        /* recopié de la famille */
    /* ★★★ TAILLE RÉELLE du contexte privé, en octets — la seule borne qui
     * protège TOUS les accès ci-dessus. Elle dépend de la famille ET DU SYSTÈME :
     * le Rage 128 alloue 760 o sous 10.3/10.4 mais seulement 348 (0x15C) sous
     * 10.2, où le pilote est un tout autre binaire. Or nos offsets de diagnostic
     * (0x1B0, 0x1C8, 0x1FC, 0x204, 0x410…) ont TOUS été relevés sur 10.4 : sous
     * 10.2 ils tombent 160 à 700 octets APRÈS la fin du bloc. La lecture y ramène
     * du tas voisin ; pire, ctx[0x204] est ensuite SUIVI COMME UN POINTEUR, donc
     * un déréférencement d'adresse arbitraire. 0 = borne inconnue (aucune
     * restriction, comportement d'avant). Passer par dd_ctx_u32/dd_ctx_has. */
    unsigned ctx_bytes;
    int      sp_show_idx;          /* index du dernier ShowSPBuffer réussi */
    dvd_close_fn  Close;
    dvd_term_fn   Term;
    dvd_setmvlevel_fn SetMVLevel;    /* RE perf test (dlsym DVDDriverSetMVLevel) */

    unsigned width, height;
    /* surface WindowServer (CGS) liée à la sortie du décodeur */
    int cid, wid, sid;

    /* affichage HW on-screen (recette Carbon crackée). Si on_screen est faux
     * (fenêtre Carbon indisponible), le décodage marche mais rien n'est affiché
     * (fenêtre CGS offscreen) — l'appelant garde son vout logiciel. */
    bool  on_screen;
    void *win;                       /* WindowRef Carbon (à disposer à la fermeture) */
    void *region;                    /* CGSRegionRef réutilisée par CGSFlushSurface */
    int (*SetBounds)(int, int, int, CGRect);
    int (*FlushSurf)(int, int, int, void *);   /* CGSFlushSurface 4 args (cid,wid,sid,région) */
    /* La région de flush doit SUIVRE les bounds : elle délimite la zone que le
     * WindowServer recompose. Créée à l'ouverture pour le rect d'alors, elle
     * tronquait l'image dès que le rectangle vidéo devenait plus grand — sur un
     * DVD anamorphosé (source 720×576 affichée en 1001×563) seule une bande de
     * 720 px de large était composée, le reste gardant le contenu périmé du
     * framebuffer GL (bandes bleues constatées sur « Le Voyage de Chihiro »). */
    int (*NewRegion)(const CGRect *, void **);
    void (*ReleaseRegion)(void *);
    void (*DisposeWin)(void *);

    /* M4 — mode AFFICHAGE (display_mode) : la fenêtre HW couvre l'écran et la
     * surface décodée (native width×height) est mise à l'échelle par le compositeur
     * WindowServer via CGSSetSurfaceBounds → la fenêtre HW DEVIENT l'affichage
     * vidéo (le vout logiciel, vide en remplacement, est recouvert). dst_rect =
     * rectangle destination letterboxé (ratio natif préservé) dans l'écran.
     * Sinon (additif) : petite fenêtre native, surface 1:1 — pratique pour l'A/B. */
    bool   display_mode;
    CGRect dst_rect;

    /* accumulateur de picture (pic_desc). `descriptors`/`coeffs` sont des ALIAS
     * du jeu de tampons actif (voir *_store ci-dessous) : les hooks écrivent
     * toujours à travers eux, begin() les fait pointer sur le bon jeu. */
    uint8_t *descriptors;            /* nb_mbs * 28 o (mb_desc) */
    uint8_t *coeffs;                 /* flux run-level 4 o/coeff */
    unsigned nb_mbs, mb_index;
    unsigned coeffs_len, coeffs_cap;
    int coding_type, pic_structure;

    /* ── Soumission ASYNCHRONE (recouvrement VLD/Decode) ─────────────────
     * Mesuré sur l'iBook G3 (Panther) : DVDDriverDecode est du temps BLOQUÉ
     * dans le kext (le CPU du processus plafonne à ~80 %), 8-34 ms par
     * picture, pendant lesquelles la VLD de la picture suivante pourrait
     * déjà tourner. Un worker unique fait le Decode ; profondeur 1 (l'enqueue
     * suivant attend la fin du précédent) → deux jeux de tampons suffisent,
     * et il n'y a JAMAIS deux Decode en vol (scratch1/2/reftab restent
     * uniques). Le verrou est relâché PENDANT l'appel Decode ; les autres
     * appels driver (Show, SP) attendent async_busy via
     * dd_wait_gpu_idle_locked() — même sérialisation qu'avant, sans bloquer
     * pick/hold/release qui ne touchent pas le driver. */
    bool           async_on;
    bool           async_started;
    pthread_t      async_th;
    pthread_cond_t async_in_cv;      /* réveil du worker */
    pthread_cond_t async_done_cv;    /* fin d'un Decode / place libre */
    bool           async_quit;
    bool           async_job;        /* un job en file (profondeur 1) */
    bool           async_busy;       /* Decode en cours dans le worker */
    uint8_t        async_pic[0x40];
    int16_t        async_rect[4];
    int            async_out_idx;
    int            async_coding;
    int            async_last_rc;
    unsigned long  us_submit_wait;   /* attente de la fin du job précédent */
    unsigned long  us_last_submit_wait;
    int            async_fail_type;  /* coding_type d'un échec non consommé */
    uint8_t       *desc_store[2];
    unsigned       desc_cap_mbs[2];
    uint8_t       *coeff_store[2];
    unsigned       coeff_store_cap[2];
    int            wset;             /* jeu actif en écriture (0/1) */
    /* Pool de 5 surfaces GPU (offload P/B). ref_idx[0]=dernière I/P décodée,
     * ref_idx[1]=avant-dernière (-1=aucune) ; out_idx=surface de sortie de la
     * picture courante ; fwd_ref/bwd_ref=indices de réf pour pic_desc (0xff=none). */
    int ref_idx[2];
    int out_idx;
    int fwd_ref, bwd_ref;
    /* Phase 2 (field prediction) : field_seen=1 si la picture contient au moins
     * un MB field-predicted (mb_type 5/6/7). field_enable=1 pour autoriser la
     * SOUMISSION de telles pictures au GPU. Tant que le format field n'est pas
     * calibré (le driver HANG sur descripteur field mal formé), field_enable=0 →
     * ces pictures retombent proprement sur le CPU (submit rc=-3). field_exp = mode
     * d'expérience de déblocage (lu depuis /tmp/field_exp) : 0=off/safe, 1/2/3+ cf.
     * mb_begin. field_exp>=1 autorise la soumission field. */
    int field_seen, field_exp;
    /* état du macrobloc courant (walker de blocs) */
    uint8_t  cur_cbp;
    unsigned cur_block;

    /* buffers de travail pour pic_desc[0x14]/[0x18]/[0x1c] */
    uint8_t  scratch1[0x20000], scratch2[0x20000];
    uint32_t reftab[64];

    /* U4 — thread-safety : Decode (thread décodeur) et Show (thread vout)
     * partagent le device → mutex autour de TOUS les appels driver. */
    pthread_mutex_t lock;
    /* U4 — génération par surface (pool de 5). Bumpée à chaque submit rc=0 vers
     * la surface. Le contexte attaché à la picture capture la génération au
     * submit ; au present (thread vout, plus tard), on ne présente QUE si la
     * génération est encore à jour (sinon la surface a été réécrite par une
     * frame plus récente → présenter montrerait la mauvaise image → on saute). */
    unsigned surf_gen[5];
    /* U4 — rectangle de present DYNAMIQUE (coords fenêtre-locales) : quand la
     * surface est liée à la fenêtre VLC (use_ext), le vout met à jour ce rect à
     * chaque display pour suivre la géométrie vidéo (U1). -1 = pas encore posé →
     * present utilise dst_rect (valeur d'ouverture). */
    int present_x, present_y, present_w, present_h;
    bool ext_win;                    /* surface liée à la fenêtre VLC (U2/U4) */
    int (*OrderSurf)(int, int, int, int, int); /* ré-affirmation d'ordre Z */
    unsigned n_order_reassert;
    /* Diagnostic « retours en arrière » : combien d'appels Show par chemin. */
    unsigned n_show_target;   /* l'image que le vout demande         */
    unsigned n_show_drain;    /* boucle de drainage du present       */
    unsigned n_show_recycle;  /* dd_recycle_locked (contre-pression) */
    /* ★ « clic automatique » : ordre + flush de FENÊTRE côté WindowServer,
     * rejoués aux presents n°1 et n°50 (cf. résolution des symboles). */
    int (*OrderWin)(int, int, int, int);
    int (*FlushWin)(int, int, int);
    /* ★ transaction d'update explicite autour de chaque present */
    int (*DisUpd)(int);
    int (*ReenUpd)(int);
    /* ★ anti-tearing (cf. résolution des symboles) */
    int (*WaitBeam)(uint32_t, unsigned, unsigned);
    uint32_t (*MainDispID)(void);
    int (*WinBoundsF)(int, int, CGRect *);
    float win_top;                   /* haut de la fenêtre à l'écran (lignes) */
    unsigned n_beam_tick;            /* rafraîchissement périodique de win_top */
    /* PERF — dernier rectangle réellement posé par CGSSetSurfaceBounds. Ce rect
     * est IDENTIQUE d'une frame à l'autre en régime établi ; re-poser les bounds
     * à chaque present est un aller-retour WindowServer synchrone pour rien. */
    CGRect last_bounds;
    bool   has_bounds;

    /* PERF (chantier 720×576) — comptage/chronométrage MINIMAL : deux
     * gettimeofday par Decode et par present, rien dans les boucles internes
     * (une instrumentation par-bloc a déjà été retirée : son overhead faussait
     * la mesure). Lu par dvddriver_perf_get(), logué périodiquement par le codec. */
    unsigned      n_decode, n_present;
    unsigned long us_decode, us_present;
    /* Presents REFUSÉS parce que la surface avait déjà été réécrite (génération
     * périmée) : distingue « le vout n'appelle pas » de « on rejette ». */
    unsigned      n_present_stale;
    int           rr_out;            /* dernière surface de sortie (round-robin) */
    int           last_shown;       /* surface actuellement À L'ÉCRAN (dernier Show) */
    int           prev_shown;       /* l'avant-dernier (double-buffer driver possible) */

    /* ★ CONTRÔLE DE FLUX SUR LE POOL DE SURFACES ==========================
     * Le GPU n'a que 5 surfaces, alors que VLC laisse le décodeur prendre une
     * dizaine de pictures d'avance sur l'affichage. Sans réservation, chaque
     * surface est réécrite 2-3 fois avant que le vout ne l'affiche : la
     * vérification de génération (U4) rejette alors TOUS les presents (mesuré :
     * 301 « périmés » sur 303). On réserve donc la surface tant que la picture
     * VLC qui la porte est vivante (hold au moment où le contexte est créé,
     * release quand VLC détruit le contexte — que la picture ait été affichée
     * OU droppée), et le décodeur ATTEND une surface libre. Effet de bord
     * bienvenu : le décodeur est cadencé sur l'affichage au lieu de courir
     * devant. */
    unsigned        surf_hold[5];
    pthread_cond_t  surf_cv;
    unsigned        n_surf_wait;     /* diagnostics : attentes de surface */
    unsigned long   us_surf_wait;    /* durée cumulée de ces attentes */
    unsigned long   us_last_surf_wait; /* attente de la derniere picture (diag) */


    /* ⚠ DURÉE DE VIE. Les picture_context_t de VLC survivent au décodeur : à
     * l'arrêt en cours de lecture, VLC détruit des contextes APRÈS le
     * CloseDecoder, et chacun appelle dvddriver_surface_release() sur ce ctx.
     * Sans compteur de références, c'était un accès à de la mémoire libérée
     * (segfault observé à l'arrêt d'un VOB). Le ctx est donc partagé : 1 pour le
     * codec + 1 par surface réservée ; le dernier qui lâche libère. `closed`
     * marque le device fermé (plus aucun appel driver). */
    unsigned        refs;
    bool            closed;

    /* DIAGNOSTIC QUALITÉ — répartition des macroblocs réellement soumis, par type
     * (0=intra 1=fwd 2=bwd 3=bidir 4=skip 5/6/7=field fwd/bwd/bidir) et par type
     * de DCT (frame/champ). Sert à comparer ce qu'un VRAI DVD utilise avec les
     * clips de synthèse qui sortent propres : ce que le DVD a EN PLUS est le
     * suspect. Compté sur le mb_type d'ORIGINE (avant conversion du mode 4). */
    unsigned        mb_stat[8];
    unsigned        dct_stat[2];
    /* [0] = MB field convertis EXACTEMENT en frame ; [1] = laissés au
     * moteur field natif faute d'équivalent frame. */
    /* [0]=converti exactement  [1]=laissé au moteur field  [2]=converti par
     * approximation (cf. /tmp/hw_fieldcvt dans dvddriver_picture_mb_begin). */
    unsigned        cvt_stat[3];

    /* ★ RECYCLAGE DES BUFFERS MP (correctif du « mur » 720×576) ==============
     * `DVDDriverShowMPBuffer(ctx, idx)` n'est pas seulement l'affichage : c'est
     * le signal qui rend le buffer MP interne du driver de nouveau disponible.
     * Depuis U4, le present est piloté par le VOUT : une picture DROPPÉE par la
     * synchro n'est jamais présentée → son buffer n'est JAMAIS rendu. Après 4-5
     * pictures droppées, le pool interne est vide et `DVDDriverDecode` BLOQUE en
     * attendant un buffer libre (mesuré : ~6 ms/picture tant qu'il reste des
     * buffers, puis ~36 s/picture, puis wedge GPU au close).
     *
     * C'est ce qui faisait passer le 720×576 pour un mur de débit GPU : la
     * première picture coûte ~850 ms (setup one-shot) → la synchro déclare le
     * décodeur en retard → elle droppe → plus aucun buffer n'est rendu → tout
     * s'effondre. À CIF le retard initial est absorbé, le vout présente, les
     * buffers tournent : d'où « CIF marche, DVD non ».
     *
     * Correctif : file des surfaces soumises mais pas encore montrées. Avant
     * chaque Decode on rend les plus anciennes (Show seul, sans compositing CGS)
     * pour garder au plus DD_MAX_PENDING soumissions en vol. Le present du vout
     * (ordre PTS, synchro A/V) reste le chemin normal pour les pictures
     * réellement affichées. */
    int pending[5];
    int n_pending;

    /* ★ GARDE-FOU ANTI-WEDGE. Un `Decode()` qui dure des SECONDES signifie que le
     * driver attend un buffer/FIFO qui ne vient pas. Continuer dans cet état mène
     * au wedge GPU (process en état U inkillable, GPU à réinitialiser par une
     * extinction complète de la machine). On réagit en deux temps : rendre TOUS
     * les buffers, puis, si ça recommence, refuser définitivement le matériel
     * (submit renvoie -4, l'appelant repasse 100 % CPU). Mieux vaut une
     * dégradation propre qu'une machine à éteindre. */
    unsigned stalls;
    bool     gpu_disabled;
};

/* Bornes du contexte privé — cf. la déclaration de `ctx_bytes`. */
static bool dd_ctx_has(const dvddriver_ctx *ctx, unsigned off, unsigned len)
{
    if (ctx == NULL || ctx->dev_ctx == NULL)
        return false;
    if (ctx->ctx_bytes == 0)
        return true;               /* borne inconnue : ne rien interdire */
    return off <= ctx->ctx_bytes && len <= ctx->ctx_bytes - off;
}

/* Lecture d'un mot du contexte. Rend 0 hors bornes — un zéro dit « inconnu »
 * là où la valeur du tas voisin mentirait (même règle que `lay_mp_pitch`). */
static uint32_t dd_ctx_u32(const dvddriver_ctx *ctx, unsigned off)
{
    if (!dd_ctx_has(ctx, off, 4))
        return 0;
    return ((const volatile uint32_t *) ctx->dev_ctx)[off / 4];
}

/* Au-delà, un Decode est considéré comme anormal. Le nominal mesuré à 720×576 est
 * ~5-6 ms (le tout premier appel, qui porte le setup one-shot, est exclu). Le
 * seuil est volontairement BAS (150 ms = 25× le nominal) : la signature de la
 * famine de buffers MP est un Decode qui grimpe à plusieurs centaines de ms, et
 * il vaut mieux rendre la main au CPU que de s'y enfoncer — c'est ce régime qui
 * mène au wedge GPU. DD_STALL_MAX évite de réagir à un pic isolé (changement de
 * mode d'affichage, machine chargée). */
/* 150 ms à l'origine, calibré sur le pipeline au CPU lent : tout Decode long y
 * signait une famine de buffers. Avec la capture run/level le CPU soumet par
 * rafales et le GPU répond par de la contre-pression LÉGITIME de 150-200 ms qui
 * se résout seule — un vrai wedge, lui, se mesure en secondes et en série. */
#define DD_STALL_US      250000ul
#define DD_STALL_MAX     8

/* Nombre max de surfaces soumises non encore rendues. 2 laisse au vout la marge
 * de présenter dans l'ordre PTS (une picture en cours + la suivante) tout en
 * garantissant au driver des buffers libres. */
#define DD_MAX_PENDING 2

static unsigned long dd_now_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (unsigned long) tv.tv_sec * 1000000ul + (unsigned long) tv.tv_usec;
}

/* Retire idx de la file des soumissions en vol (il vient d'être montré). LOCK TENU. */
static void dd_pending_drop(dvddriver_ctx *ctx, int idx)
{
    int w = 0;
    for (int r = 0; r < ctx->n_pending; r++)
        if (ctx->pending[r] != idx)
            ctx->pending[w++] = ctx->pending[r];
    ctx->n_pending = w;
}

/* Rend au driver les buffers des surfaces soumises les plus anciennes tant qu'il
 * y en a plus de `keep` en vol. Show SEUL (pas de compositing CGS) : on rend le
 * buffer, on n'affiche rien de nouveau. LOCK TENU. */
/* Libère le ctx quand plus personne (codec ni surface réservée) ne le référence.
 * LOCK TENU à l'entrée ; le lock est relâché dans tous les cas. */
static void dd_unref_unlock(dvddriver_ctx *ctx)
{
    bool last = (--ctx->refs == 0);
    pthread_mutex_unlock(&ctx->lock);
    if (!last)
        return;
    pthread_cond_destroy(&ctx->surf_cv);
    pthread_cond_destroy(&ctx->async_in_cv);
    pthread_cond_destroy(&ctx->async_done_cv);
    pthread_mutex_destroy(&ctx->lock);
    free(ctx->desc_store[0]);
    free(ctx->desc_store[1]);
    free(ctx->coeff_store[0]);
    free(ctx->coeff_store[1]);
    free(ctx);
}

static void dd_recycle_locked(dvddriver_ctx *ctx, int keep)
{
    while (ctx->n_pending > keep && !ctx->closed
           && ctx->Show != NULL && ctx->dev_ctx != NULL) {
        int idx = ctx->pending[0];
        /* ★ SECOND chemin d'affichage de surfaces PÉRIMÉES — il faut le traiter
         * comme la boucle de drainage de `dvddriver_present_index`, sinon les
         * « retours en arrière » subsistent. Celui-ci se déclenche sur
         * contre-pression (Decode trop long) et en filet anti-famine : sur une
         * machine saturée il tire souvent, ce qui explique que corriger la seule
         * boucle de present n'ait rien changé à l'œil.
         * Même principe : on garde l'APPEL, qui est ce qui vide la file interne
         * du pilote, mais on ré-affiche la surface DÉJÀ à l'écran. */
        if (ctx->drain_shows_current
            && ctx->last_shown >= 0 && ctx->last_shown < 5)
            idx = ctx->last_shown;
        ctx->n_show_recycle++;
        ctx->Show(ctx->dev_ctx, (uint32_t) idx, NULL, NULL);
        for (int r = 1; r < ctx->n_pending; r++)
            ctx->pending[r - 1] = ctx->pending[r];
        ctx->n_pending--;
    }
}

/* ==== DISPONIBILITÉ ======================================================
 * Le bundle ATIRadeonDVDDriver se charge ET un service "ATIRadeon" existe. */
bool dvddriver_available(void)
{
    /* Reverse-engineered and validated on Darwin 8 (Mac OS X 10.4) with an
     * RV200. Enabling it on hardware it had not been reversed for has
     * already WEDGED a GPU once (the RV280 of the Mac mini G4, 2026-07-23:
     * the machine needed a full power cycle), so the rule stands -- only
     * what has been checked runs.
     *
     * Mac OS X 10.2 ships its own build of ATIRadeonDVDDriver.bundle (Oct
     * 2002, 51320 bytes). Checked before opening it up, by disassembly:
     *   - the same 26 entry points, DVDDriverOpenDevice/Decode included;
     *   - DVDDriverDecode(ctx, pic, rect) still reads the rect as four
     *     int16, the picture type at pic[2] and the buffer pointers from
     *     pic[0x10] onwards -- the argument contract this code depends on;
     *   - an IOKit service of class ATIRadeon is present.
     * The PRIVATE context layout is shared too -- see dvddriver_open(), which
     * documents the field-by-field comparison of the three bundles and the one
     * genuine difference (10.2 does not memoise the video-plane rect).
     *
     * Darwin 7 (10.3 Panther) likewise: measured on the same iBook
     * G3 / RV200, the surface is presented properly there -- 765 present
     * callbacks for 810 displayed pictures, 0 stale present, 15,3 ms per
     * DVDDriverDecode against a 40 ms budget, and the image is correct on
     * screen. It behaves like 10.4, so it gets the hardware decoder like
     * 10.4. (Its presentation cadence is still uneven; that is the same
     * pacing problem 10.2 shows, not a reason to fall back to a CPU path a
     * 750 cannot sustain at all -- 2 to 39 displayed frames per 5 s there.) */
    /* ✅ 2026-07-29 : LE DÉCODEUR MATÉRIEL EST ACTIVÉ SUR 10.2 AUSSI.
     * Une note antérieure l'y désactivait par défaut, au motif que « le vout ne
     * présente jamais sa surface » sur 10.2 ; elle est RÉFUTÉE par la mesure
     * sur un
     * iBook G3 / RV200 sous 10.2.8 : le vout présente bel et bien sa surface —
     * 2603 rappels de present, 0 périmé, géométrie correctement publiée
     * (wid=162, rect 0,62 1024x576, fenêtre-local 0,22) et Decode à 13,7 ms
     * pour un budget de 40 ms. Fluidité confirmée à l'œil par l'utilisateur,
     * fenêtré ET plein écran, cadrage correct. (L'image « agrandie et
     * déchirée » d'une capture était un artefact de `screencapture` lisant le
     * framebuffer pendant l'affichage direct, pas un défaut de placement.)
     * Le chemin logiciel, lui, ne décodait qu'UNE IMAGE SUR TROIS sur cette
     * machine (39/110, 30/108, 43/108) : c'était lui, et non le matériel, la
     * cause du « pas fluide du tout » de 10.2. */
    /* Une famille supportée doit être présente (service IOKit + bundle portant
     * l'API). L'override de banc d'essai, lui, court-circuite le choix du
     * bundle mais pas celui du service : il sert à comparer deux VERSIONS du
     * même pilote, pas à en imposer un que la carte ne réclame pas. */
    const struct dd_family *fam = dd_find_family(NULL);
    if (fam == NULL)
        return false;

    const char *path = ati_bundle_path(fam);
    if (path != fam->bundle) {
        void *dl = dlopen(path, RTLD_NOW | RTLD_LOCAL);
        if (dl == NULL)
            return false;
        bool has_sym = dlsym(dl, "DVDDriverOpenDevice") != NULL
                    && dlsym(dl, "DVDDriverDecode")     != NULL;
        dlclose(dl);
        if (!has_sym)
            return false;
    }
    return true;
}

/* Résout une SPI CGS depuis ApplicationServices. */
#define CGS_SYM(h, n) dlsym((h), (n))

/* ==== OUVERTURE ==========================================================
 * Crée une surface CGS offscreen, récupère le service ATIRadeon, initialise
 * la lib DVDDriver et ouvre le device. Renvoie NULL → l'appelant fait le
 * fallback CPU. */
dvddriver_ctx *dvddriver_open(unsigned width, unsigned height, int display_mode,
                              int external_wid, int field_exp, bool subs_overlay)
{
    /* U2 (expérience-GATE, A-idéal) : external_wid > 0 → au lieu de créer notre
     * propre fenêtre Carbon, on lie la surface décodeur à la FENÊTRE VLC (son
     * numéro CGS publié par le vout en U1). But : tester si le WindowServer
     * composite la surface DVDDriver sur la NSWindow d'une app au 1er plan (jamais
     * testé — les harnais précédents ont échoué sur NSWindow autonome / CGS nue).
     * Si ça marche → plus de fenêtre séparée. Gate revertable : external_wid=0
     * (défaut) garde la recette Carbon connue. */
    bool use_ext = (external_wid > 0);

    /* ⚠ La famille GPU est résolue DÈS ICI (et non au moment d'ouvrir le device,
     * plus bas) parce qu'elle décide de la GÉOMÉTRIE de la fenêtre d'affichage,
     * qui se crée avant. Résolution sans retenir le service : celui-ci est repris
     * plus loin, sur le chemin normal. */
    const struct dd_family *fam_geo = dd_find_family(NULL);

    /* ⚠ Familles qui exigent NOTRE fenêtre Carbon (Rage 128) : lier la surface à
     * la fenêtre Cocoa de VLC y donne un écran NOIR. On garde donc la fenêtre
     * Carbon dédiée, seule configuration qui affiche sur ce matériel. */
    if (fam_geo != NULL && fam_geo->needs_own_window && use_ext)
        use_ext = false;

    /* U4 — instance unique : un seul décodeur HW à la fois. */
    if (s_dd_instances > 0)
        return NULL;

    /* Déclarées en tête pour que les chemins d'erreur (goto err_*) puissent
     * disposer la fenêtre Carbon même si l'échec survient avant/après sa création
     * (sinon : fenêtre plein écran zombie au niveau 1000 si OpenDevice échoue). */
    bool  on_screen = false;
    void *win = NULL;
    void (*DisposeWin)(void *) = NULL;

    void *as = dlopen("/System/Library/Frameworks/ApplicationServices.framework/"
                      "ApplicationServices", RTLD_NOW | RTLD_GLOBAL);
    if (as == NULL)
        return NULL;

    /* CGSMainConnectionID() is 10.3. Jaguar's CoreGraphics exports neither it
     * nor CGSDefaultConnection; what it has is CGSGetActiveConnection(), the
     * older way of asking for the connection the WindowServer already gave
     * this process. Everything else of the surface API -- CGSAddSurface,
     * CGSBindSurface, CGSSetSurfaceBounds, CGSOrderSurface, CGSFlushSurface
     * -- is present in the 10.2 build, checked symbol by symbol. */
    /* Ce que fait le CLIENT D'APPLE, relevé sur 10.2 : DVDPlayback.framework
     * (embarqué dans DVD Player.app, c'est lui et non l'application qui pilote
     * ce driver) n'importe NI CGSMainConnectionID NI CGSGetConnectionIDForPSN.
     * Il demande GetCGSConnectionID(), exporté par QD -- un sous-framework
     * d'ApplicationServices, d'où l'importance du repli dlsym de dlcompat.c.
     * Désassemblé : aucun argument, la connexion revient dans r3 depuis un
     * global qu'INIT_CGSSupport remplit au premier appel. C'est la connexion
     * DU PROCESSUS quel que soit le thread appelant -- exactement ce que
     * réclament les appels de surface, et sans le détour par le PSN. */
    int (*QDConnID)(void)                      = CGS_SYM(as, "GetCGSConnectionID");
    int (*MainConn)(void)                      = CGS_SYM(as, "CGSMainConnectionID");
    int (*ActiveConn)(int *)                   = CGS_SYM(as, "CGSGetActiveConnection");
    int (*NewConn)(int, int *)                 = CGS_SYM(as, "CGSNewConnection");
    int (*ConnForPSN)(int, const uint32_t *, int *)
                                 = CGS_SYM(as, "CGSGetConnectionIDForPSN");
    int (*NewRegion)(const CGRect *, void **)  = CGS_SYM(as, "CGSNewRegionWithRect");
    int (*NewWindow)(int, int, float, float, void *, int *) = CGS_SYM(as, "CGSNewWindow");
    int (*AddSurf)(int, int, int *)            = CGS_SYM(as, "CGSAddSurface");
    int (*SetBounds)(int, int, int, CGRect)    = CGS_SYM(as, "CGSSetSurfaceBounds");
    int (*OrderSurf)(int, int, int, int, int)  = CGS_SYM(as, "CGSOrderSurface");
    int (*FlushSurf)(int, int, int, void *)    = CGS_SYM(as, "CGSFlushSurface");
    int (*SetWinLevel)(int, int, int)          = CGS_SYM(as, "CGSSetWindowLevel");
    /* Opacité de fenêtre : Apple la met à 0 (non opaque) AVANT de créer la
     * surface. Sans cela, le fond de la fenêtre recouvre la surface décodée. */
    int (*SetWinOpacity)(int, int, int)        = CGS_SYM(as, "CGSSetWindowOpacity");
    /* ★ « clic automatique » (10.3, scintillement) : un clic souris N'IMPORTE
     * OÙ dans la fenêtre répare le scintillement de façon collante — pas un
     * seek, pas un [window display] AppKit (testés). L'effet réparateur du
     * clic est donc côté WindowServer : l'opération d'ordre de fenêtre (et le
     * flush fenêtre) qu'il exécute en amenant la fenêtre cliquée devant. On
     * rejoue les deux au niveau CGS à l'engagement. */
    int (*OrderWin)(int, int, int, int)        = CGS_SYM(as, "CGSOrderWindow");
    int (*FlushWin)(int, int, int)             = CGS_SYM(as, "CGSFlushWindow");
    /* ★ ANTI-TEARING : depuis que la surface est COMPOSÉE (cf. le pixel de
     * recouvrement du vout), le blit vers le framebuffer n'est plus synchronisé
     * au balayage — d'où les « vagues » sur les panoramiques. 10.3 expose la
     * parade de l'époque : attendre que le faisceau soit hors des lignes qu'on
     * s'apprête à réécrire. /tmp/hw_nobeam désactive pour l'A/B. */
    int (*WaitBeam)(uint32_t, unsigned, unsigned)
                                 = CGS_SYM(as, "CGDisplayWaitForBeamPositionOutsideLines");
    uint32_t (*MainDispID)(void) = CGS_SYM(as, "CGMainDisplayID");
    int (*WinBoundsF)(int, int, CGRect *) = CGS_SYM(as, "CGSGetWindowBounds");
    /* ★ UPDATES DIFFÉRÉES (10.3, scintillement) : Panther a introduit les
     * « coalesced updates » — le WindowServer coalesce les flushes d'une
     * fenêtre et recompose à sa propre cadence. Signature mesurée : flush
     * ~400 µs (coalescé, écran qui MÉLANGE des images successives de la
     * surface GPU = le dédoublement) contre ~2 ms (recomposition synchrone,
     * propre) ; l'activité souris force le mode synchrone — d'où le « clic
     * réparateur » de l'utilisateur. On demande la désactivation des updates
     * différées pour notre connexion, comme QuickTime à l'époque. */
    /* ⚠ ABI 10.3 : la propriété se passe en CGSValue PRIVÉS (CGSCreateCString/
     * CGSCreateBoolean), PAS en CFTypes — un CFStringRef ici a SIGSEGV
     * (rapport du 29/07 13h01, saut dans les données du CFString constant). */
    int (*SetConnProp)(int, int, void *, void *)
                                 = CGS_SYM(as, "CGSSetConnectionProperty");
    void *(*CGSCreateCStr)(const char *) = CGS_SYM(as, "CGSCreateCString");
    void *(*CGSCreateBool)(unsigned char) = CGS_SYM(as, "CGSCreateBoolean");
    /* ★ Transaction d'update explicite (anti-composition-paresseuse) : le
     * WindowServer compose SYNCHRONEMENT à la ré-activation. Autour de chaque
     * present (cf. dd_show_locked). /tmp/hw_noupd la désactive pour l'A/B. */
    int (*DisUpd)(int)                          = CGS_SYM(as, "CGSDisableUpdate");
    int (*ReenUpd)(int)                         = CGS_SYM(as, "CGSReenableUpdate");
    int (*WinList)(int, int, int, int *, int *) = CGS_SYM(as, "CGSGetOnScreenWindowList");
    int (*WinBounds)(int, int, CGRect *)       = CGS_SYM(as, "CGSGetWindowBounds");
    s_CGSBindSurface = (int (*)(int,int,int,int,int,uint32_t)) CGS_SYM(as, "CGSBindSurface");
    if ((MainConn == NULL && ActiveConn == NULL && NewConn == NULL)
     || AddSurf == NULL || s_CGSBindSurface == NULL)
        goto err_as;

    int cid = 0;

    /* Mac OS X 10.2 has no CGSMainConnectionID(), and its CGS connections are
     * per-thread: from the decoder thread CGSGetActiveConnection() answers
     * kCGErrorInvalidConnection (1002). A connection made here with
     * CGSNewConnection() is valid but owns no window, and CGSAddSurface() on
     * the VLC window then answers kCGErrorIllegalArgument (1001) -- measured,
     * both of them. What is needed is the connection of THIS PROCESS, the one
     * AppKit's main thread opened, and CGSGetConnectionIDForPSN() maps it
     * from the process serial number. Its three arguments were read off the
     * disassembly: (connection, ProcessSerialNumber *, out). */
    /* ⚠ CGSMainConnectionID() FIRST wherever it exists, and QD's
     * GetCGSConnectionID() only where it does not. Both are exported from
     * 10.3 on -- QD has _GetCGSConnectionID on Tiger too, checked with nm on
     * the machine -- so preferring QD unconditionally, as the 10.2 port did,
     * silently changed which connection 10.3 and 10.4 use. On 10.4 that
     * WEDGED the GPU on the first pictures of a DVD: the surface ends up on a
     * connection the compositor does not consume, the driver never gets its
     * MP buffers back, DVDDriverDecode blocks and the process goes into
     * uninterruptible state (reproduced twice from a cold boot, zero present
     * callbacks, "waiting decoder fifos to empty" forever). Hardware DVD
     * playback was reliable on Tiger in 1.0.0, before that commit.
     * Jaguar is the only system that needs the QD route, and it is the only
     * one that takes it: its CoreGraphics exports neither CGSMainConnectionID
     * nor CGSDefaultConnection. */
    if (MainConn != NULL)
        cid = MainConn();

    if (cid == 0 && QDConnID != NULL)
        cid = QDConnID();

    if (cid == 0 && NewConn != NULL && NewConn(0, &cid) != 0)
        cid = 0;

    /* Repli seulement : avec GetCGSConnectionID() la connexion est déjà la
     * bonne, et repasser par le PSN la remplacerait par une autre. */
    if (QDConnID == NULL && ConnForPSN != NULL) {
        void *carbon_psn = dlopen(CARBON_FW, RTLD_NOW | RTLD_GLOBAL);

        if (carbon_psn != NULL) {
            int (*GetCurProc)(uint32_t *) = CGS_SYM(carbon_psn,
                                                    "GetCurrentProcess");
            uint32_t psn[2] = { 0, 0 };
            int app_cid = 0;

            if (GetCurProc != NULL && GetCurProc(psn) == 0
             && ConnForPSN(cid, psn, &app_cid) == 0 && app_cid != 0)
                cid = app_cid;
        }
    }

    if (cid == 0 && ActiveConn != NULL && ActiveConn(&cid) != 0)
        cid = 0;
    if (cid == 0)
        goto err_as;                     /* pas de connexion WindowServer */

    /* ★ Désactiver les updates différées/coalescées pour cette connexion
     * (cf. résolution de CGSSetConnectionProperty) — le « clic réparateur »
     * en boîte, via l'API CGSValue historique de 10.3 (le snippet
     * « DisableDeferredUpdates » de l'époque QuickTime/jeux). Silencieux si
     * un des symboles manque. */
    if (SetConnProp != NULL && CGSCreateCStr != NULL && CGSCreateBool != NULL) {
        void *k = CGSCreateCStr("DisableDeferredUpdates");
        void *v = CGSCreateBool(1);
        if (k != NULL && v != NULL) {
            int rc_du = SetConnProp(cid, cid, k, v);
            fprintf(stderr, "DVDDriver: DisableDeferredUpdates=true rc=%d\n",
                    rc_du);
        }
    }

    /* M4 mode AFFICHAGE : dimensionner la fenêtre + le rectangle destination de la
     * surface. En display_mode, fenêtre plein écran et surface letterboxée (le
     * compositeur WindowServer met la surface native width×height à l'échelle).
     * Sinon, petite fenêtre native 1:1 en {90,150}. */
    unsigned long (*DispWide)(uint32_t) = CGS_SYM(as, "CGDisplayPixelsWide");
    unsigned long (*DispHigh)(uint32_t) = CGS_SYM(as, "CGDisplayPixelsHigh");
    uint32_t (*MainDisp)(void)          = CGS_SYM(as, "CGMainDisplayID");
    float scr_w = 0, scr_h = 0;
    if (display_mode && MainDisp && DispWide && DispHigh) {
        uint32_t d = MainDisp();
        scr_w = (float) DispWide(d);
        scr_h = (float) DispHigh(d);
    }
    if (scr_w < 1 || scr_h < 1) { display_mode = 0; scr_w = width; scr_h = height; }

    /* dst_rect = rectangle destination de la surface (letterbox en display_mode). */
    CGRect dst_rect;
    if (use_ext) {
        /* U2 : surface liée à la fenêtre VLC → bounds en coords FENÊTRE-LOCALES
         * (origine haut-gauche). On letterbox la surface native (ratio préservé)
         * DANS le contenu de la fenêtre : si ça composite, on voit la vidéo au bon
         * ratio avec le contenu GL de VLC (vert en remplacement) dans les marges →
         * preuve que la surface est bien DANS la fenêtre VLC. (Le placement exact —
         * suivi du rect vidéo publié en U1, gestion toolbar — est le travail U4.) */
        float ww = width, wh = height;
        CGRect wb;
        if (WinBounds && WinBounds(cid, external_wid, &wb) == 0
            && wb.size.width >= 1 && wb.size.height >= 1) {
            ww = wb.size.width; wh = wb.size.height;
        }
        float sc = ww / (float) width, sy = wh / (float) height;
        if (sy < sc) sc = sy;
        float dw = (float) width * sc, dh = (float) height * sc;
        /* ⚠ EXPÉRIENCE (sp_needs_native_scale) : surface à la TAILLE NATIVE,
         * centrée dans la fenêtre, sans mise à l'échelle — c'est la seule
         * configuration où le harnais rend le subpicture visible. Le test
         * précédent avait été posé dans la branche `display_mode`, jamais prise
         * ici puisque la surface est liée à la fenêtre de VLC (`use_ext`). */
        if (fam_geo != NULL && fam_geo->sp_needs_native_scale) {
            dw = (float) width; dh = (float) height;
        }
        dst_rect = CGRectMake((ww - dw) / 2.0f, (wh - dh) / 2.0f, dw, dh);
    } else if (display_mode && fam_geo != NULL && fam_geo->sp_needs_native_scale) {
        /* ⚠ TEST : surface à la TAILLE NATIVE, centrée, sans mise à l'échelle.
         * Le harnais affiche le subpicture ainsi ; dans VLC, où la surface est
         * letterboxée et redimensionnée, le SP est soumis sans erreur (« 10
         * incrustés ») mais reste invisible. On vérifie si la mise à l'échelle
         * est bien ce qui l'envoie hors champ. */
        dst_rect = CGRectMake((scr_w > width)  ? (scr_w - width)  / 2.0f : 0.0f,
                              (scr_h > height) ? (scr_h - height) / 2.0f : 0.0f,
                              (float) width, (float) height);
    } else if (display_mode) {
        float sc = scr_w / (float) width;
        float sy = scr_h / (float) height;
        if (sy < sc) sc = sy;                    /* fit préservant le ratio natif */
        float dw = (float) width * sc, dh = (float) height * sc;
        dst_rect = CGRectMake((scr_w - dw) / 2.0f, (scr_h - dh) / 2.0f, dw, dh);
    } else {
        dst_rect = CGRectMake(0, 0, width, height);
    }

    /* rect = bounds de surface passés à SetBounds/flush (= dst_rect). */
    CGRect rect = dst_rect;
    void *region = NULL;
    if (NewRegion) NewRegion(&rect, &region);

    /* --- Chemin d'AFFICHAGE : VRAIE fenêtre CARBON compositing (recette
     * crackée ati_carbon.c). Fonctions Carbon résolues par dlsym pour ne pas
     * lier Carbon dans un module codec. Si indisponible → repli sur une fenêtre
     * CGS offscreen : le décodage HW marche, mais rien n'est affiché (l'appelant
     * conserve alors son vout logiciel). --- */
    int   wid = 0;

    /* U2 : chemin A-idéal — on NE crée PAS de fenêtre, on cible directement la
     * fenêtre VLC (external_wid). on_screen=true → present fera SetBounds+flush
     * sur cette fenêtre. On ne touche NI son niveau NI son ordre d'activation. */
    void *carbon = NULL;
    if (use_ext)
    {
        wid = external_wid;
        on_screen = true;
    }
    else
    carbon = dlopen(CARBON_FW, RTLD_NOW | RTLD_GLOBAL);
    if (carbon != NULL)
    {
        int32_t (*CreateNewWindow)(uint32_t, uint32_t, const dd_Rect *, void **)
                                      = dlsym(carbon, "CreateNewWindow");
        void (*ShowWin)(void *)       = dlsym(carbon, "ShowWindow");
        void (*SelectWin)(void *)     = dlsym(carbon, "SelectWindow");
        void (*BringFront)(void *)    = dlsym(carbon, "BringToFront");
        int32_t (*RunLoop)(double)    = dlsym(carbon, "RunCurrentEventLoop");
        uint32_t (*GetCGWindowID)(void *) = dlsym(carbon, "HIWindowGetCGWindowID");
        DisposeWin                    = dlsym(carbon, "DisposeWindow");

        if (CreateNewWindow != NULL)
        {
            /* display_mode : fenêtre plein écran (la surface letterboxée dedans
             * DEVIENT l'affichage) ; sinon petite fenêtre native en {90,150}. */
            dd_Rect wr = display_mode
                ? (dd_Rect){ 0, 0, (int16_t) scr_h, (int16_t) scr_w }
                : (dd_Rect){ 90, 150,
                             (int16_t)(90 + height), (int16_t)(150 + width) };
            void *w = NULL;
            /* ⚠ M4 intégration UI (Option A) EN COURS — cf. mémoire handoff.
             * TENTATIVES QUI CASSENT LA VISIBILITÉ (à NE PAS refaire tel quel) :
             *  - kPlainWindowClass (borderless) : incompatible compositing/CGS →
             *    CreateNewWindow échoue → repli offscreen → RIEN affiché (bureau).
             *  - kWindowNoActivatesAttribute + sans SelectWindow/BringToFront +
             *    niveau bas (2) : l'app ne passe plus au 1er plan → rien affiché.
             * On RESTE donc sur la config VISIBLE connue (kDocumentWindowClass +
             * StandardHandler + Select/BringFront + niveau 1000). Conséquence : le
             * CONTOUR BLANC (barre de titre) et les CONTRÔLES cachés / non-clickable
             * restent À FAIRE (voir mémoire : lier la surface à la fenêtre de VLC,
             * ou trouver une classe borderless+compositing, ou click-through CGS). */
            /* ⚠⚠ Photo AVANT création : le repli d'identification ci-dessous
             * compare les deux listes. Indispensable — voir le commentaire du
             * repli. */
            int before[256], n_before = 0;
            if (WinList != NULL && WinList(cid, cid, 256, before, &n_before) != 0)
                n_before = 0;

            int32_t st = CreateNewWindow(DD_kDocumentWindowClass,
                    DD_kWindowStandardHandlerAttr | DD_kWindowCompositingAttribute,
                    &wr, &w);
            if (st == 0 && w != NULL)
            {
                if (ShowWin)    ShowWin(w);
                if (SelectWin)  SelectWin(w);
                if (BringFront) BringFront(w);
                for (int i = 0; RunLoop && i < 10; i++) RunLoop(0.05);

                if (GetCGWindowID) wid = (int) GetCGWindowID(w);
                /* ⚠⚠⚠ `HIWindowGetCGWindowID` N'EXISTE PAS sur tous les Tiger
                 * (absent du build 8S165 de l'iBook G3 — dlsym rend NULL), d'où
                 * ce repli. Il identifiait la fenêtre par ses SEULES dimensions
                 * (« la première au moins aussi grande que la vidéo ») : correct
                 * dans un harnais qui n'a qu'une fenêtre, FAUX dans PowerVLC, qui
                 * en a une vingtaine (interface). Il attrapait alors une fenêtre
                 * de l'INTERFACE, la surface décodée s'y liait, et l'écran
                 * restait blanc/noir alors que tout le reste était correct
                 * (diagnostiqué au spy CGS interposé, 2026-08-04 : AddSurface
                 * partait sur le wid de la fenêtre VLC).
                 * On identifie donc la fenêtre par DIFFÉRENCE avec la photo
                 * prise juste avant CreateNewWindow — la nôtre est celle qui
                 * vient d'apparaître. */
                if (wid == 0 && WinList != NULL && WinBounds != NULL)
                {
                    /* Dimensions DEMANDÉES à CreateNewWindow : c'est sur elles
                     * qu'on reconnaît notre fenêtre, pas sur « au moins aussi
                     * grande que la vidéo ». ⚠ Le pompage de la boucle
                     * d'événements ci-dessus laisse l'interface de VLC créer SES
                     * propres fenêtres dans l'intervalle : « apparue après » ne
                     * suffit donc pas non plus à elle seule. La hauteur CGS
                     * inclut la barre de titre, d'où la tolérance asymétrique. */
                    const float want_w = (float)(wr.right  - wr.left);
                    const float want_h = (float)(wr.bottom - wr.top);
                    int after[256], n_after = 0;
                    if (WinList(cid, cid, 256, after, &n_after) == 0)
                    {
                        for (int i = 0; i < n_after && wid == 0; i++) {
                            bool seen = false;
                            for (int j = 0; j < n_before; j++)
                                if (before[j] == after[i]) { seen = true; break; }
                            if (seen)
                                continue;           /* déjà là avant : pas la nôtre */
                            CGRect b;
                            if (WinBounds(cid, after[i], &b) != 0)
                                continue;
                            float dw = b.size.width - want_w;
                            if (dw < 0) dw = -dw;
                            /* la hauteur CGS dépasse la hauteur demandée de la
                             * barre de titre : écart attendu dans [-4, +40] */
                            float dh = b.size.height - want_h;
                            if (dw <= 12.0f && dh >= -4.0f && dh <= 40.0f)
                                wid = after[i];
                        }
                    }
                }
                if (wid != 0) { win = w; on_screen = true; }
                /* ★ FOND NOIR. La surface ne couvre que le rectangle vidéo ; les
                 * marges du letterbox laissent voir le fond de la fenêtre, BLANC
                 * par défaut (signalé à l'écran : « l'image est centrée, le
                 * contour est blanc »). Le vout GL les noircissait avec glClear,
                 * mais sur les machines qui retombent sur le vout QuickDraw il
                 * n'y a pas de contexte GL : on peint donc le fond nous-mêmes, en
                 * QuickDraw, fonctions résolues par dlsym comme le reste de
                 * Carbon. Sans effet si l'une manque. */
                if (on_screen)
                {
                    typedef struct { uint16_t red, green, blue; } dd_RGBColor;
                    void *(*GetWinPort)(void *) = dlsym(carbon, "GetWindowPort");
                    void  (*SetPortQD)(void *)  = dlsym(carbon, "SetPort");
                    void  (*BackColorQD)(const dd_RGBColor *)
                                                = dlsym(carbon, "RGBBackColor");
                    void  (*EraseRectQD)(const dd_Rect *)
                                                = dlsym(carbon, "EraseRect");
                    if (GetWinPort && SetPortQD && BackColorQD && EraseRectQD) {
                        void *port = GetWinPort(w);
                        if (port != NULL) {
                            dd_RGBColor black = { 0, 0, 0 };
                            dd_Rect all = { 0, 0,
                                            (int16_t)(wr.bottom - wr.top),
                                            (int16_t)(wr.right  - wr.left) };
                            SetPortQD(port);
                            BackColorQD(&black);
                            EraseRectQD(&all);
                        }
                    }
                }
            }
        }
    }

    if (!on_screen)   /* repli offscreen : pas d'affichage, décodage seul */
    {
        if (NewWindow == NULL
            || NewWindow(cid, 2 /*buffered*/, 0, 0, region, &wid) != 0
            || wid == 0)
            goto err_as;
    }

    int sid = 0;
    /* ★★★ SÉQUENCE D'APPLE — relevée le 2026-08-04 au spy DYLD interposé sur
     * « DVD Player » (scratchpad/cgs_spy.c), sur l'iBook G3 / Rage 128 :
     *
     *   CGSSetWindowOpacity(wid, 0)        <- AVANT toute surface
     *   CGSAddSurface -> sid
     *   CGSSetSurfaceBounds(rect)
     *   CGSOrderSurface(order=0)           <- 0 d'abord
     *   CGSBindSurface(2, 35, disp)        <- fait par OpenDevice via dd_bind_thunk
     *   CGSSetSurfaceBounds(rect)          <- RE-POSÉ après le bind
     *   CGSOrderSurface(order=1)           <- puis 1
     *
     * C'est ce protocole, et lui seul, qui empêche le fond de la fenêtre de
     * RECOUVRIR la surface : sans lui, le Rage 128 montrait l'image ~2 s puis un
     * écran blanc. Vérifié à l'œil en fenêtre PLEIN ÉCRAN, le cas qui échouait.
     * (Apple n'appelle par ailleurs jamais CGSFlushSurface, ni CGSSetWindowLevel
     * sur la fenêtre vidéo — nous gardons les deux, éprouvés sur le RV200.)
     *
     * ⚠ L'opacité se pose sur NOTRE fenêtre seulement : toucher celle de VLC
     * (use_ext) changerait le rendu de toute l'interface. */
    if (on_screen && !use_ext && SetWinOpacity)
        SetWinOpacity(cid, wid, 0);

    if (AddSurf(cid, wid, &sid) != 0)
        goto err_as;
    if (SetBounds) SetBounds(cid, wid, sid, rect);
    if (on_screen && OrderSurf)
        OrderSurf(cid, wid, sid, 0, 0);   /* order=0 AVANT le bind (Apple) */
    /* Ordre de composition de la surface dans la fenêtre : AU-DESSUS du contenu.
     * ⚠ RÉSULTAT DE MESURE (G3/Tiger, RV200) : deux surfaces CGS d'une même
     * fenêtre ne se MÉLANGENT PAS — la plus haute masque l'autre, quelle que
     * soit son alpha (testé : surface GL transparente au-dessus → zone vidéo
     * noire ; surface décodeur au-dessus → sous-titres invisibles ; fenêtre
     * non opaque n'y change rien). Les sous-titres ne peuvent donc PAS être
     * incrustés par la vue GL : le vout passe par une FENÊTRE de superposition
     * distincte (les fenêtres, elles, se composent avec alpha). D'où : ordre
     * +1 dans tous les cas. */
    if (on_screen && OrderSurf)
        OrderSurf(cid, wid, sid, 1, 0);

    (void) subs_overlay;
    /* Niveau de fenêtre. ⚠ INTÉGRATION UI (Option A) EN COURS : l'idéal serait un
     * niveau JUSTE sous le FSPanel de contrôles (NSFloatingWindowLevel=3) pour laisser
     * les contrôles plein écran visibles ; mais niveau=2 a cassé la visibilité sur le
     * G3 (corresp. niveaux CGS/Cocoa non triviale — à calibrer). On reste sur 1000
     * (visible, mais recouvre le FSPanel) le temps du handoff. Cf. mémoire Option A. */
    /* ⚠ Apple ne pose AUCUN niveau sur sa fenêtre vidéo (trace du spy). Sur le
     * Rage 128, la sortir de la couche normale par un niveau 1000 empêche la
     * composition de la surface — c'est ce qui restait à l'écran blanc alors que
     * le reste de la séquence était déjà correct. */
    if (on_screen && !use_ext && SetWinLevel
        && !(fam_geo != NULL && fam_geo->apple_display_seq))
        SetWinLevel(cid, wid, 1000);   /* notre fenêtre ; PAS celle de VLC (use_ext) */

    /* service GPU ATI : la famille présente sur cette machine (RV200 "ATIRadeon",
     * Rage Mobility M3 "ATIRage128"), avec le bundle DVDDriver qui lui correspond. */
    io_service_t svc = 0;
    const struct dd_family *fam = dd_find_family(&svc);
    if (fam == NULL || svc == 0)
        goto err_as;
    uint32_t serviceTable[8];
    memset(serviceTable, 0, sizeof(serviceTable));
    serviceTable[0] = svc;

    /* bundle DVDDriver */
    void *b = dlopen(ati_bundle_path(fam), RTLD_NOW | RTLD_LOCAL);
    if (b == NULL)
        goto err_svc;
    dvd_init_fn   DVDInit = (dvd_init_fn)   dlsym(b, "DVDInitializeLibrary");
    dvd_open_fn   OpenDev = (dvd_open_fn)   dlsym(b, "DVDDriverOpenDevice");
    dvd_decode_fn Decode  = (dvd_decode_fn) dlsym(b, "DVDDriverDecode");
    dvd_show_fn   Show    = (dvd_show_fn)   dlsym(b, "DVDDriverShowMPBuffer");
    dvd_close_fn  CloseD  = (dvd_close_fn)  dlsym(b, "DVDDriverCloseDevice");
    dvd_term_fn   Term    = (dvd_term_fn)   dlsym(b, "DVDTerminateLibrary");
    if (DVDInit == NULL || OpenDev == NULL || Decode == NULL)
        goto err_bundle;

    CGDirectDisplayID disp = CGMainDisplayID();
    uint32_t mask = CGDisplayIDToOpenGLDisplayMask(disp);

    DVDInit(serviceTable, mask, (void *)dd_flush_thunk, (void *)dd_bind_thunk);

    void *dev = NULL;
    uint32_t dims[4] = { 0 }, caps = 0;
    uint16_t five = 0, eight = 0;
    static uint32_t ctx_caps_out, ctx_dims_out[4];
    static uint16_t ctx_five_out, ctx_eight_out;
    int rc = OpenDev(&dev, dims, (uint32_t)disp, (uint32_t)cid, (uint32_t)wid,
                     (uint32_t)sid, &caps, 0, &five, &eight);
    /* SP3b — `caps` est une SORTIE que ce backend jetait depuis le début. Le
     * désassemblage de DVDVideoOpenDevice (couche DVD.framework, celle
     * qu'utilise le lecteur d'Apple) montre qu'elle teste le BIT 1 de ce même
     * mot — le bit qui gouverne l'armement du plan subpicture. On le relève. */
    ctx_caps_out = caps;
    ctx_five_out = five;
    ctx_eight_out = eight;
    for (int i = 0; i < 4; i++) ctx_dims_out[i] = dims[i];
    if (rc != 0 || dev == NULL) {
        if (Term) Term();
        goto err_bundle;
    }

    /* ★ Fin de la séquence d'Apple : OpenDevice vient de faire le CGSBindSurface
     * (via dd_bind_thunk) ; on re-pose les bornes puis on passe la surface en
     * order=1. C'est CE doublet post-bind qui la rend visible par-dessus le
     * contenu de la fenêtre — cf. le commentaire de la séquence, plus haut. */
    if (on_screen) {
        if (SetBounds) SetBounds(cid, wid, sid, rect);
        if (OrderSurf) OrderSurf(cid, wid, sid, 1, 0);
    }

    dvddriver_ctx *ctx = calloc(1, sizeof(*ctx));
    if (ctx == NULL) {
        if (CloseD) CloseD(dev);
        if (Term) Term();
        goto err_bundle;
    }
    ctx->dl_bundle = b;
    ctx->dl_as     = as;
    ctx->dev_ctx   = dev;
    ctx->Decode    = Decode;
    ctx->Show      = Show;
    ctx->Close     = CloseD;
    ctx->Term      = Term;
    ctx->SetMVLevel = (dvd_setmvlevel_fn) dlsym(b, "DVDDriverSetMVLevel");

    /* Chantier SP — résolution du plan subpicture matériel + SONDE : on relève
     * ce que GetSPBuffer renvoie réellement (les 8 descripteurs de tampons) et
     * la couleur-clé. Objectif : savoir si ces valeurs sont des ADRESSES
     * exploitables côté CPU ou des poignées GPU, ce que le désassemblage seul
     * ne dit pas. Aucun effet de bord : uniquement des lectures. */
    ctx->GetSPBuffer  = (dvd_getspbuf_fn)    dlsym(b, "DVDDriverGetSPBuffer");
    ctx->SetSPBuffer  = (dvd_setspbuf_fn)    dlsym(b, "DVDDriverSetSPBuffer");
    ctx->ShowSPBuffer = (dvd_showspbuf_fn)   dlsym(b, "DVDDriverShowSPBuffer");
    ctx->SetSPPalette = (dvd_setsppal_fn)    dlsym(b, "DVDDriverSetSPPalette");
    ctx->ApplySPDCSQ  = (dvd_applydcsq_fn)   dlsym(b, "DVDDriverApplySPDCSQ");
    ctx->EnableSP     = (dvd_enablesp_fn)    dlsym(b, "DVDDriverEnableSP");
    ctx->ClearSP      = (dvd_clearsp_fn)     dlsym(b, "DVDDriverClearSP");
    ctx->PrepareButton = (dvd_preparebutton_fn) dlsym(b, "DVDDriverPrepareButton");
    ctx->EnableButton  = (dvd_enablebutton_fn)  dlsym(b, "DVDDriverEnableButton");
    ctx->GetKeyColor  = (dvd_getkeycolor_fn) dlsym(b, "DVDDriverGetKeyColor");
    ctx->SetMPRects   = (dvd_setmprects_fn)  dlsym(b, "DVDDriverSetMPRects");
    ctx->EnableMP     = (dvd_enablemp_fn)    dlsym(b, "DVDDriverEnableMP");
    ctx->open_caps  = ctx_caps_out;
    ctx->open_five  = ctx_five_out;
    ctx->open_eight = ctx_eight_out;
    for (int i = 0; i < 4; i++) ctx->open_dims[i] = ctx_dims_out[i];
    /* ⚠ La présence des symboles ne suffit PAS : le plan SP lit et écrit le
     * contexte privé par des offsets qui ne valent que pour le layout où ils ont
     * été relevés. Le Rage 128 exporte toute la famille SP mais son contexte est
     * plus petit (760 o) et sa carte n'est pas relevée → `sp_layout_ok` faux. */
    ctx->sp_available = (ctx->GetSPBuffer && ctx->SetSPBuffer && ctx->ShowSPBuffer
                         && ctx->SetSPPalette && ctx->EnableSP
                         && fam->sp_layout_ok);
    ctx->no_flush      = fam->apple_display_seq;
    ctx->sp_flag_off   = fam->sp_flag_off;
    ctx->sp_needs_reshow = fam->sp_needs_reshow;
    ctx->sp_native_scale = fam->sp_needs_native_scale;
    ctx->sp_swap_words   = fam->sp_swap_words;
    ctx->drain_shows_current = fam->drain_shows_current;
    ctx->sp_cc_off_102   = fam->sp_cc_off_102;
    /* ★★★ Borne de TOUS les accès au contexte privé. Elle dépend du SYSTÈME et
     * pas seulement de la famille : sous 10.2 le pilote est un autre binaire,
     * au contexte bien plus petit. Posée AVANT la première sonde ci-dessous. */
    ctx->ctx_bytes = fam->ctx_size;

    /* ★★★ ARMEMENT DU PLAN VIDÉO — indispensable, et il manquait ici.
     * `DVDDriverSetMPRects` (géométrie) et `DVDDriverEnableMP(1)` (activation)
     * n'étaient appelés QUE depuis le chemin subpicture, lui-même gardé par
     * `sp_available`. Sur le RV200 ce chemin est actif, donc le plan se trouvait
     * armé « par ricochet » ; sur le Rage 128, où le plan SP est coupé
     * (`sp_layout_ok` faux), plus personne ne l'armait : la surface était bien
     * liée et composée — elle apparaissait VERTE, c'est-à-dire Y=0/chroma=0 —
     * mais ShowMPBuffer n'y écrivait jamais rien, quel que soit le thread
     * appelant. Le harnais, lui, les appelait : c'est toute la différence.
     * On les joue donc à l'ouverture, indépendamment du plan SP. */
    {
        int16_t mpr[4] = { 0, 0, (int16_t) height, (int16_t) width };
        if (ctx->SetMPRects) ctx->SetMPRects(dev, mpr, 0, 0);
        if (ctx->EnableMP)   ctx->EnableMP(dev, 1);
    }

    /* The hardware subpicture plane addresses the driver's private context by
     * offsets read off the 10.4 build of the bundle, so it is only safe where
     * that layout holds. Settled by disassembling all three builds side by
     * side (legacy otool: the modern one refuses these Mach-O):
     *
     *   10.3 Panther (43332 bytes, same size as 10.4) -- THE SAME CODE,
     *     recompiled. Its text is shifted by 0x10 and a few registers are
     *     scheduled differently; every context offset is unchanged.
     *     GetSPBuffer still reads ctx[0x2F4+4i] and ctx[0x2D4+4i] instruction
     *     for instruction; ShowMPBuffer still gates the subpicture on
     *     ctx[0x1C4] then ctx[0x1C8]; and the three writes of the display flag
     *     in the ApplySPDCSQ engine sit at the very same addresses 0x79bc /
     *     0x79d8 / 0x7a04, with the same registers. The plane is therefore
     *     ENABLED on Panther.
     *
     *   10.2 Jaguar (51320 bytes) -- a genuinely different driver. Its
     *     GetSPBuffer ignores the ctx argument altogether and dereferences a
     *     GLOBAL (0x73f8), reading the two series at +0x44 and +0x24 of what
     *     it points to. Nothing of the 10.4 layout applies; poking those
     *     offsets would write into whatever happens to live there. Wiring it
     *     up means deriving that build's layout on its own -- and is moot for
     *     now, since the hardware decoder itself is off by default on 10.2
     *     (the vout never presents its surface there, see below).
     *
     * ⚠ The earlier note claimed the flag "is not even referenced" in the 10.2
     * binary, from a grep for "452(" -- the DECIMAL form of 0x1C4. This otool
     * only ever prints displacements in hex, so that grep found nothing in ANY
     * of the three builds, Tiger included. It proved nothing, and it cost
     * Panther its hardware subtitles. */
    {
        struct utsname uts;
        int darwin = (uname(&uts) == 0) ? atoi(uts.release) : 0;

        /* Layout du contexte privé (cf. la description des champs lay_*).
         * Darwin 7+ = le bundle 10.4, dont tous les offsets sont connus.
         * Darwin 6 = le bundle 10.2 : mêmes offsets pour tout ce que nous
         * lisons, SAUF le cache de rect du plan vidéo, qui n'y existe pas. */
        ctx->lay_mp_pitch = (darwin == 0 || darwin >= 7) ? 0x414 : 0;
        /* ⚠ Et zéro si le layout n'est pas celui du RV200 : sur le Rage 128,
         * 0x414 est au-delà des 760 o alloués — le lire reviendrait à sonder le
         * tas voisin, et à en tirer une décision (rejouer SetMPRects) au hasard. */
        if (!fam->sp_layout_ok)
            ctx->lay_mp_pitch = 0;
        /* ⚠⚠ ET ZÉRO AUSSI s'il sort du contexte. La condition ci-dessus ne
         * suffit PAS : `sp_layout_ok` a été remis à vrai sur le Rage 128 pour le
         * chantier subpicture, si bien que 0x414 (1044) restait actif sur un
         * contexte de 760 o. Sa géométrie de plan vidéo est ailleurs
         * (0x2A4/0x2A8/0x2AC), donc 0x414 n'y veut rien dire de toute façon.
         * ⚠ Ce n'est pas qu'une lecture sale : la valeur DÉCIDE de rejouer
         * SetMPRects, et le rejouer déplace l'image et éteint le plan
         * subpicture. Mettre 0 = « inconnu » = ne pas y toucher, qui est le
         * comportement validé à l'écran sur les trois systèmes. La bascule est
         * faite ICI, après `ctx_bytes`, pour que la borne soit connue. */
        /* ctx[0x204] (base de la destination du blit) est au MÊME offset sur les
         * trois bundles — cinq occurrences dans chacun, comme tous les autres
         * champs SP. Le suivre comme un pointeur y est donc aussi légitime que
         * sur 10.4, la garde NULL restant en place. Ce drapeau n'existe que pour
         * refuser le déréférencement sur un layout NON relevé (une version
         * future, ou un pilote inconnu). */
        ctx->lay_sp_stub  = (darwin > 0 && darwin < 7);
        /* ⚠⚠ La taille du contexte CHANGE avec le système. Sur le Rage 128 elle
         * tombe de 760 o (10.3/10.4) à 348 o (10.2) : sans cette correction, les
         * offsets 0x1B0, 0x1C8, 0x1FC, 0x204… relevés sur 10.4 débordent tous, et
         * ctx[0x204] — SUIVI COMME UN POINTEUR par dd_sp_dest() — devient une
         * adresse arbitraire prise dans le tas voisin. C'est un déréférencement
         * sauvage, exécuté à l'ouverture, donc AVANT tout garde-fou GPU. */
        if (ctx->lay_sp_stub && fam->ctx_size_102 != 0)
            ctx->ctx_bytes = fam->ctx_size_102;
        /* Suivre ctx[0x204] comme un pointeur n'est légitime que si ce mot est
         * DANS le contexte : sinon on lirait une adresse qui ne veut rien dire. */
        ctx->lay_deref_ok = fam->sp_layout_ok && dd_ctx_has(ctx, 0x204, 4);
        if (ctx->lay_mp_pitch != 0 && !dd_ctx_has(ctx, ctx->lay_mp_pitch, 4))
            ctx->lay_mp_pitch = 0;   /* cf. la note ci-dessus */
        /* ⚠ Famille DÉCOUVERTE et non tabulée (`ctx_size` nul) : on ne connaît
         * NI la taille de son contexte NI ses offsets. Aucun accès à un offset
         * codé en dur ne doit avoir lieu — `lay_mp_pitch` est le seul qui ne
         * dépende pas de `sp_layout_ok`, on le neutralise donc explicitement. */
        if (fam->ctx_size == 0) {
            ctx->lay_mp_pitch = 0;
            ctx->lay_deref_ok = false;
        }
        /* ⚠ Offsets SP relevés sur les bundles 10.3/10.4 UNIQUEMENT. Le bundle
         * 10.2 du Rage 128 est un autre pilote (séries dans un global, pas dans
         * le contexte) : on n'y écrit donc PAS le champ 1 à un offset qui n'y
         * veut rien dire, et le plan SP y est laissé au chemin logiciel tant que
         * son layout n'a pas été dérivé. (Sur le RV200, le SP 10.2 marche via
         * `lay_sp_stub` — mais avec des offsets qui lui sont propres.) */
        /* ★★★ Rage 128 sous 10.2 : carte RELEVÉE (2026-08-05), SP ACTIVÉ.
         * Le bundle de 10.2 est un AUTRE pilote (42 748 o) au contexte de
         * 348 o (0x15C) seulement. Offsets relevés au désassemblage, en
         * suivant le registre de contexte uniquement :
         *     tampon courant 0x144  |  mode SP 0x148   (IDENTIQUES à 10.3/10.4)
         *     drapeau EnableSP 0x14C
         *     drapeau d'affichage 0x14F (un OCTET, armé par ApplySPDCSQ)
         *     tampons : PAS dans le contexte — `GetSPBuffer` déréférence un
         *     GLOBAL et rend les deux séries (+0x44 pixels / +0x24 commandes),
         *     donc l'API suffit, rien à lire nous-mêmes.
         * ⚠⚠ AUCUN équivalent du mot couleurs/contrastes du RV200
         * (ctx[0x1DC]) : `sp_cc_off_102` vaut 0 pour cette famille, ce qui
         * INTERDIT l'écriture — 0x1DC tomberait 128 octets après la fin du
         * contexte. C'est la seule raison pour laquelle le SP était coupé ici.
         * `sp_swap_words` et le reste de la recette 10.3/10.4 restent valables :
         * même puce, même moteur 2D. */
        /* ⚠⚠ ACTIVATION SUR OPT-IN SEULEMENT (/tmp/hw_jaguar_sp) tant que ce
         * chemin n'a pas été VU à l'écran.
         * ⛔ NE PAS RÉÉCRIRE L'HISTOIRE ICI : le premier essai (2026-08-05) a
         * donné « rafale d'incoming request - stopping current input, 0 image »
         * et j'en ai conclu que le plan SP déstabilisait la lecture. C'ÉTAIT
         * FAUX. Le MÊME run, SP COUPÉ, sur le MÊME disque, donne exactement la
         * même rafale : elle vient de la playlist (item Médiathèque + MRL mal
         * formée résolue en LISTAGE DE RÉPERTOIRE), pas du pilote. Les deux
         * runs comparés n'avaient tout simplement pas le même disque dans le
         * lecteur. ⇒ Comparer À DISQUE ET À INVOCATION IDENTIQUES, et lire
         * « using access module » : si c'est `filesystem`+`directory`, la MRL
         * n'a pas été comprise et le run ne mesure rien.
         * Le gate reste néanmoins : ce chemin n'a jamais été VU à l'écran, et
         * c'est cela qui manque — pas une instabilité démontrée. */
        /* ★★★ ACTIVÉ PAR DÉFAUT (2026-08-05). Le « blocage » qui justifiait de
         * le couper — l'absence d'équivalent au mot couleurs/contrastes
         * `ctx[0x1DC]` du RV200 — N'EXISTE PAS. Vérifié au désassemblage du
         * pilote 10.2 de cette puce :
         *   - les seuls offsets libres sous la fin du contexte (0x150/0x154/
         *     0x158) ne sont JAMAIS lus depuis le contexte ;
         *   - `DVDDriverApplySPDCSQ(ctx, idx, offset, len)` INTERPRÈTE lui-même
         *     le paquet SPU : il prend le tampon DCSQ dans le global du pilote
         *     (série b à +0x24+4*idx), lit ctx[0x14F], et passe l'intervalle
         *     d'octets à son interpréteur interne.
         * ⇒ Les couleurs et contrastes arrivent donc par les commandes SPU
         * (SET_COLOR 0x03 / SET_CONTR 0x04), exactement comme dans la recette
         * validée à l'écran en 10.3/10.4 sur cette même puce. `sp_cc_off_102`
         * vaut 0 non pas parce qu'il est inconnu, mais parce qu'il n'y a RIEN à
         * écrire à la main ici — et la garde de bornes empêche de toute façon
         * l'écriture hors du bloc de 348 octets.
         * Échappatoire d'A/B si ce plan se révélait mauvais à l'écran :
         * `/tmp/hw_jaguar_sp_off`. ⚠ /tmp est vidé au démarrage. */
        if (ctx->lay_sp_stub && fam->apple_display_seq) {
            if (dd_gate_read("/tmp/hw_jaguar_sp_off") > 0) {
                ctx->sp_flag_off  = 0;
                ctx->sp_available = false;
            } else {
                ctx->sp_flag_off = 0x14F;
            }
        }
        /* ⚠ PLUS AUCUNE VERSION N'EST EXCLUE : le layout des trois bundles est
         * relevé, et nous ne faisons que LIRE. Sur 10.2 cela ne change rien en
         * configuration par défaut — le décodeur matériel y est désactivé, donc
         * il n'y a pas de contexte et le sous-module SPU décline de lui-même.
         * Cela n'a d'effet qu'avec /tmp/hw_jaguar, et le plan SP n'a JAMAIS été
         * éprouvé sur 10.2 : c'est une expérimentation, pas un acquis. */
    }
    if (ctx->sp_available && ctx->dev_ctx) {
        uint32_t a[8], bb[8];
        memset(a, 0, sizeof(a)); memset(bb, 0, sizeof(bb));
        ctx->GetSPBuffer(ctx->dev_ctx, a, bb);
        for (int i = 0; i < 8; i++) { ctx->sp_probe[i] = a[i]; ctx->sp_probe[8+i] = bb[i]; }
        if (ctx->GetKeyColor)
            ctx->GetKeyColor(ctx->dev_ctx, &ctx->sp_keycolor);
        /* Les descripteurs ressemblent à des ADRESSES (0x081…, espacées de
         * 0x32000). Vérifions qu'elles sont bien mappées dans NOTRE espace :
         * lecture de 4 octets au début de chaque tampon. ⚠ fait ICI, juste
         * après l'ouverture et donc AVANT le moindre Decode : si l'adresse
         * n'était pas mappée, le SIGBUS ne surviendrait pas pendant que le GPU
         * décode (règle de sûreté anti-wedge). */
        /* ⚠⚠ Sur 10.2, `GetSPBuffer` IGNORE le contexte et déréférence un GLOBAL
         * du pilote : tant que le plan n'a pas été armé, ce global peut n'avoir
         * jamais été rempli, et les « adresses » rendues sont alors ce qui
         * traînait dans nos tableaux de sortie. Déréférencer cela, c'est un
         * SIGBUS à l'ouverture. On n'accepte donc que ce qui RESSEMBLE à une
         * adresse : non nulle, alignée sur 4, hors de la première page. */
        for (int i = 0; i < 8; i++) {
            const uint32_t v = a[i];
            const bool plausible = (v != 0) && ((v & 3u) == 0) && (v >= 0x1000u);
            ctx->sp_first_word[i] =
                plausible ? *(const volatile uint32_t *) v : 0;
        }
        /* Le plan SP est gouverné par un DRAPEAU DE MODE en ctx+0x1FC :
         * EnableSP ne fait RIEN quand il vaut 0, et SetSPPalette/SetSPBuffer
         * changent de chemin selon lui. On relève ce mot et ses voisins
         * utiles (ctx[0] = profondeur d'écran lue par GetKeyColor,
         * ctx+0x1B0 = tampon SP courant, ctx+0x1C8 = état d'EnableSP). */
        ctx->sp_mode_flag = dd_ctx_u32(ctx, 0x1FC);
        ctx->sp_ctx_word0 = dd_ctx_u32(ctx, 0);
        ctx->sp_cur_buf   = dd_ctx_u32(ctx, 0x1B0);
        ctx->sp_enable_st = dd_ctx_u32(ctx, 0x1C8);
        /* ctx[0x20] : mot de CAPACITÉS lu par OpenDevice — son bit 1 est la
         * seule chose qui arme le mode SP (ctx+0x1FC = 1). S'il est absent, le
         * plan subpicture est inerte quoi qu'on appelle. */
        ctx->sp_caps = dd_ctx_u32(ctx, 0x20);
    }
    ctx->width     = width;
    ctx->height    = height;
    ctx->cid = cid; ctx->wid = wid; ctx->sid = sid;
    ctx->OrderSurf = OrderSurf;   /* ré-affirmation d'ordre Z au present */
    ctx->OrderWin  = OrderWin;    /* « clic automatique » à l'engagement */
    ctx->FlushWin  = FlushWin;
    ctx->DisUpd    = DisUpd;      /* transaction d'update autour du present */
    ctx->ReenUpd   = ReenUpd;
    ctx->WaitBeam  = WaitBeam;    /* anti-tearing */
    ctx->MainDispID = MainDispID;
    ctx->WinBoundsF = WinBoundsF;
    ctx->win_top   = -1.0f;
    ctx->n_beam_tick = 0;
    ctx->ref_idx[0] = ctx->ref_idx[1] = -1;
    ctx->last_shown = -1;
    ctx->prev_shown = -1;   /* aucune référence au départ */
    ctx->out_idx = 0;
    /* Phase 2 : mode de déblocage field, reçu en paramètre (option
     * mpeg2-hwaccel-field ; 0 = field non soumis, défaut sûr). */
    ctx->field_exp = field_exp;
    /* ⚠ En mode REMPLACEMENT (display_mode), une picture field refusée au submit
     * (field_exp=0 → rc=-3) est perdue des DEUX côtés : slice.c a déjà sauté
     * IDCT+MC CPU (hw_capture vrai) et le GPU ne la décode pas → image figée /
     * réfs SW corrompues sur flux entrelacé. On promeut donc field_exp au clamp
     * sûr (2) : sortie field imparfaite mais regardable > picture perdue.
     * En additif (display_mode=0), le défaut 0 reste le bon (le CPU couvre). */
    /* ⚠ NE PAS auto-promouvoir field_exp ici. Une promotion 0→2 puis 0→4 existait
     * pour éviter de perdre une picture field en mode remplacement ; ce risque est
     * désormais couvert proprement par le contexte picture INVALIDE (la picture
     * n'est pas affichée, la précédente reste). Promouvoir reviendrait à imposer
     * un mode field alors qu'aucun ne donne une image correcte (cf. libmpeg2.c). */
    ctx->on_screen  = on_screen;
    ctx->win        = win;
    ctx->region     = region;
    ctx->SetBounds  = SetBounds;
    ctx->FlushSurf  = FlushSurf;
    ctx->NewRegion  = NewRegion;
    ctx->ReleaseRegion = (void (*)(void *)) CGS_SYM(as, "CGSReleaseRegion");
    ctx->DisposeWin = DisposeWin;
    ctx->display_mode = display_mode ? true : false;
    ctx->dst_rect     = dst_rect;   /* destination surface (letterbox en display_mode) */
    ctx->ext_win      = use_ext;
    pthread_mutex_init(&ctx->lock, NULL);
    pthread_cond_init(&ctx->surf_cv, NULL);
    pthread_cond_init(&ctx->async_in_cv, NULL);
    pthread_cond_init(&ctx->async_done_cv, NULL);
    ctx->refs = 1;                   /* référence du codec (lâchée par close) */
    ctx->present_x = ctx->present_y = ctx->present_w = ctx->present_h = -1;
    s_dd_instances++;

    /* ★ PRÉ-CHAUFFAGE DU DÉCODEUR (correctif du « mur » 720×576) ============
     * Le PREMIER DVDDriverDecode porte tout le setup one-shot du driver
     * (SetMPRects, mapping des command buffers, init du moteur MC) : mesuré
     * ~850-865 ms à 720×576, contre ~6 ms pour les suivants. Payé pendant la
     * lecture, ce coût met le décodeur ~850 ms en retard sur l'horloge dès la
     * première picture : la synchro passe en saut agressif, plus aucune picture
     * n'est affichée, donc plus aucun buffer MP n'est rendu au driver (le
     * present est piloté par le vout depuis U4), le pool interne se vide et les
     * Decode suivants bloquent — jusqu'au wedge GPU. Tout l'effondrement du
     * 720×576 découle de cette seule première picture.
     *
     * On paie donc le setup ICI, dans l'Open du décodeur, hors de la boucle de
     * synchro : une picture INTRA sans aucun coefficient (tous les MB en
     * mb_type=0, cbp=0) — c'est la soumission la plus inoffensive possible : pas
     * de référence à lire, pas de vecteur de mouvement, pas de coefficient.
     * /tmp/hw_nowarmup désactive (A/B). */
    if (dd_gate_read("/tmp/hw_nowarmup") <= 0)
    {
        unsigned nb_mbs = ((width + 15) / 16) * ((height + 15) / 16);
        if (dvddriver_picture_begin(ctx, 1 /*I*/, 3 /*frame*/, nb_mbs) == 0) {
            static const int16_t zmv[8]  = { 0, 0, 0, 0, 0, 0, 0, 0 };
            static const uint8_t zfs[4]  = { 0, 0, 0, 0 };
            for (unsigned m = 0; m < nb_mbs; m++) {
                dvddriver_picture_mb_begin(ctx, 0 /*intra*/, 0 /*frame-DCT*/,
                                           0 /*cbp: aucun bloc codé*/, zmv, zfs);
                dvddriver_picture_mb_end(ctx);
            }
            (void) dvddriver_picture_submit(ctx);
            pthread_mutex_lock(&ctx->lock);
            dd_recycle_locked(ctx, 0);      /* rendre le buffer tout de suite */
            pthread_mutex_unlock(&ctx->lock);
        }
        /* Repartir d'un état vierge : le pré-chauffage ne doit pas laisser la
         * surface 0 marquée comme référence ni de picture en cours. */
        ctx->ref_idx[0] = ctx->ref_idx[1] = -1;
        ctx->out_idx = 0;
        ctx->mb_index = ctx->coeffs_len = 0;
    }
    return ctx;

err_bundle:
    dlclose(b);
err_svc:
    IOObjectRelease(svc);
err_as:
    if (DisposeWin && win)
        DisposeWin(win);   /* sinon fenêtre Carbon zombie à l'écran */
    dlclose(as);
    return NULL;
}

/* ==== RÉ-ENCODEUR COEFFICIENTS (DCTblock déquantifié → run-level) ========
 * Identique au format IDCTMCP (spec §6.4). scan[zz] = index de stockage du
 * coeff zigzag zz → DCTblock[scan[zz]] = coeff zigzag zz. Pas de re-quant.
 *
 * dc_bias : retranché du coefficient DC (zz=0, APRÈS mise à l'échelle /16). Sert
 * au RECENTRAGE : le driver ATI centre TOUTES les composantes (Y, Cb, Cr) sur
 * 128 (DC=0 → pixel 128). Après /16 le DC vaut pixel*8 (neutre 128 → 1024) ;
 * on retranche 1024 pour obtenir (pixel-128)*8 → le driver reconstruit pixel.
 * Validé au harnais ati_color.c (barres SMPTE pures + rampe noir→blanc). Vaut
 * 1024 pour luma ET chroma. Les AC (déjà centrés sur 0) ne bougent pas. */
unsigned dvddriver_encode_block(const int16_t *dctblock, const uint8_t *scan,
                                int dc_bias, uint8_t *out)
{
    int last = -1;
    unsigned n = 0;
    /* ★ PERF — sortir les zéros AVANT tout calcul. Mesuré sur le DVD de Chihiro
     * (720x576) : une picture I coûtait 76 ms pour un budget de 40, une toutes
     * les 9 images, soit précisément les 10 % d'images manquantes (22,6 des
     * 25 im/s). Une I porte 1620 macroblocs tous intra = 9720 blocs = 622 000
     * coefficients, et la boucle faisait pour CHACUN une division arrondie avec
     * branchement puis un memcpy de deux octets — alors que la grande majorité
     * sont nuls et ne produisent rien. Seul le coefficient DC doit être traité
     * même nul : le recentrage chroma peut le rendre non nul. */
    {
        int v0 = dctblock[scan[0]];
        v0 = (v0 >= 0) ? (v0 + 8) / 16 : -(((-v0) + 8) / 16);
        v0 -= dc_bias;
        if (v0 != 0) {
            if (v0 > 2047) v0 = 2047; else if (v0 < -2047) v0 = -2047;
            out[0] = 0;                      /* run : premier coefficient */
            out[1] = 0;
            int16_t lv0 = (int16_t) v0;
            memcpy(out + 2, &lv0, sizeof lv0);   /* ordre-octet NATIF */
            out += 4;
            n++;
            last = 0;
        }
    }
    for (int zz = 1; zz < 64; zz++) {
        int v = dctblock[scan[zz]];
        if (v == 0)
            continue;              /* ni division, ni branchement, ni écriture */
        /* libmpeg2 travaille dans une échelle 16× celle attendue par le driver
         * (son iDCT veut pixel=DC/128, neutre DC=16384=128*128 ; le driver veut
         * pixel=DC/8, neutre 1024 — validé au harnais). On ramène chaque coeff à
         * l'échelle driver en divisant par 16 (arrondi au plus proche). Sans ça :
         * luma 16× surexposé + chroma jamais recentrable → contours magenta. */
        v = (v >= 0) ? (v + 8) / 16 : -(((-v) + 8) / 16);
        if (v != 0) {
            if (v >  2047) v =  2047;                       /* borne coeff driver (12 bits signés) */
            else if (v < -2047) v = -2047;
            out[0] = (uint8_t)(zz - last - 1);            /* run (écart zigzag) */
            out[1] = 0;                                    /* pad */
            /* level : i16 en ordre-octet NATIF (big-endian sur PPC), comme le
             * driver et le harnais ati_carbon.c (qui stockait un int16_t natif).
             * Un octet-à-octet little-endian inverse les octets sur le G3 →
             * coefficients corrompus → bruit à l'écran.
             * ⚠ GARDER memcpy : écrire par `*(int16_t *)(out + 2)` dans un
             * tampon manipulé en uint8_t viole l'aliasing strict — essayé, GCC 13
             * a produit un flux que le GPU n'a pas digéré et DVDDriverDecode
             * s'est bloqué à répétition (garde-fou anti-wedge déclenché). */
            int16_t lv = (int16_t) v;
            memcpy(out + 2, &lv, sizeof lv);
            out += 4;
            n++;
            last = zz;
        }
    }
    return n;
}

/* ==== ASSEMBLAGE + SOUMISSION D'UNE PICTURE ============================== */

/* Choisit une surface de sortie (0..4) qui n'est PAS une référence courante :
 * une P ne doit pas écrire dans sa propre réf (motion-comp lit ≠ écrit). */
/* Choisit une surface de sortie LIBRE : ni référence courante (motion-comp lit ≠
 * écrit), ni réservée par une picture VLC encore vivante. Round-robin pour ne pas
 * réécrire toujours la même. Si aucune n'est libre, ATTEND que le vout en relâche
 * une (c'est le cadençage du décodeur sur l'affichage). Renvoie -1 si rien ne se
 * libère (le vout est bloqué) → l'appelant renonce au matériel pour cette picture.
 * Le LOCK N'EST PAS tenu à l'entrée. */
static int dd_pick_output(dvddriver_ctx *ctx)
{
    pthread_mutex_lock(&ctx->lock);
    int sel = -1;
    for (int attempt = 0; attempt < 6 && sel < 0 && !ctx->closed; attempt++) {
        for (int k = 1; k <= 5; k++) {
            int s = (ctx->rr_out + k) % 5;
            /* ★ Ne JAMAIS choisir la surface actuellement à l'écran. Elle
             * n'était protégée que tant que VLC détenait sa picture ; dès la
             * destruction du contexte, `surf_hold` retombe à 0 et l'image
             * suivante se décodait PAR-DESSUS celle en cours de balayage.
             * Mesuré : 59 surfaces présentées deux fois de suite sur 1441
             * (≈ une par seconde) — invisible pour l'histogramme de cadence,
             * mais bien visible à l'œil, la première image n'ayant qu'un cycle
             * pour être composée avant d'être écrasée. */
            /* ★★ Ne JAMAIS décoder dans la surface À L'ÉCRAN, même si VLC a
             * déjà relâché sa picture : quand la surface est composée en
             * direct (app active à la création — 10.3), la réécrire fait
             * apparaître l'image FUTURE à l'écran avant l'heure, puis le
             * present suivant revient en arrière — mesuré sur film au ralenti
             * (trajectoire du panoramique : bonds +16 puis reculs -2). */
            /* ⚠ /tmp/hw_noprev : lève la SEULE exclusion qui ne protège pas une
             * référence ni l'image à l'écran. Avec 5 surfaces imposées par le
             * pilote (constante `li 0,5` d'OpenDevice), quatre exclusions ne
             * laissent qu'un candidat : le décodeur attend 40 % du temps et le
             * moindre Decode long (mesuré jusqu'à 80 ms) devient une saccade,
             * faute de coussin. `prev_shown` avait été ajouté pour la
             * composition DIRECTE de 10.3 ; à vérifier à l'œil avant d'en faire
             * un défaut, l'artefact d'origine étant une image future montrée en
             * avance. */
            static int s_noprev = -1;
            if (s_noprev < 0) s_noprev = (dd_gate_read("/tmp/hw_noprev") > 0);
            if (s != ctx->ref_idx[0] && s != ctx->ref_idx[1]
                && s != ctx->last_shown
                && (s_noprev || s != ctx->prev_shown)
                && ctx->surf_hold[s] == 0) {
                    sel = s;
                break;
            }
        }
        if (sel >= 0)
            break;
        struct timeval tv;
        gettimeofday(&tv, NULL);
        struct timespec ts;
        ts.tv_sec  = tv.tv_sec;
        ts.tv_nsec = (long) tv.tv_usec * 1000L + 200000000L;   /* +200 ms */
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        ctx->n_surf_wait++;
        {
            unsigned long w0 = dd_now_us();
            pthread_cond_timedwait(&ctx->surf_cv, &ctx->lock, &ts);
            unsigned long w = dd_now_us() - w0;
            ctx->us_surf_wait += w;
            ctx->us_last_surf_wait += w;
        }
    }
    if (sel >= 0)
        ctx->rr_out = sel;
    pthread_mutex_unlock(&ctx->lock);
    return sel;
}

/* Réserve / relâche une surface pour le compte d'une picture VLC. hold est appelé
 * quand le décodeur attache le contexte à la picture, release quand VLC détruit
 * ce contexte (picture affichée OU droppée — les deux passent par destroy). */
void dvddriver_surface_hold(dvddriver_ctx *ctx, int idx)
{
    if (ctx == NULL || idx < 0 || idx >= 5)
        return;
    pthread_mutex_lock(&ctx->lock);
    ctx->surf_hold[idx]++;
    ctx->refs++;                 /* le contexte picture maintient le ctx en vie */
    pthread_mutex_unlock(&ctx->lock);
}

void dvddriver_surface_release(dvddriver_ctx *ctx, int idx)
{
    if (ctx == NULL || idx < 0 || idx >= 5)
        return;
    pthread_mutex_lock(&ctx->lock);
    if (ctx->surf_hold[idx] > 0 && --ctx->surf_hold[idx] == 0)
        pthread_cond_broadcast(&ctx->surf_cv);
    dd_unref_unlock(ctx);        /* peut libérer le ctx (arrêt en cours de lecture) */
}

int dvddriver_picture_begin(dvddriver_ctx *ctx, int coding_type,
                            int pic_structure, unsigned nb_mbs)
{
    if (ctx != NULL) { ctx->us_last_surf_wait = 0; ctx->us_last_submit_wait = 0; }
    unsigned coeffs_cap = nb_mbs * 6u * 64u * 4u;   /* pire cas */
    /* Jeu de tampons actif : en asynchrone submit() bascule wset après chaque
     * enqueue, si bien qu'on écrit ici le jeu que le worker ne lit PAS. */
    int w = ctx->wset & 1;
    if (nb_mbs != ctx->desc_cap_mbs[w]) {
        uint8_t *d = realloc(ctx->desc_store[w], nb_mbs * MB_DESC_SIZE);
        if (d == NULL) {
            free(ctx->desc_store[w]); ctx->desc_store[w] = NULL;
            ctx->desc_cap_mbs[w] = 0; ctx->descriptors = NULL; ctx->nb_mbs = 0;
            return -1;
        }
        ctx->desc_store[w] = d;
        ctx->desc_cap_mbs[w] = nb_mbs;
    }
    if (coeffs_cap > ctx->coeff_store_cap[w]) {
        uint8_t *co = realloc(ctx->coeff_store[w], coeffs_cap);
        if (co == NULL)
            return -1;
        ctx->coeff_store[w] = co;
        ctx->coeff_store_cap[w] = coeffs_cap;
    }
    ctx->descriptors = ctx->desc_store[w];
    ctx->coeffs      = ctx->coeff_store[w];
    ctx->coeffs_cap  = ctx->coeff_store_cap[w];
    ctx->nb_mbs      = nb_mbs;
    memset(ctx->descriptors, 0, nb_mbs * MB_DESC_SIZE);
    ctx->mb_index = 0;
    ctx->coeffs_len = 0;
    ctx->coding_type = coding_type;
    ctx->pic_structure = pic_structure;
    ctx->field_seen = 0;      /* Phase 2 : aucun MB field vu pour l'instant */

    /* Attribution surface de sortie + indices de référence (pic_desc[6/7/8]).
     * coding_type : 1=I, 2=P, 3=B. Prouvé sur G3 (ati_surf.c) : [0x06]=sortie,
     * [0x07]=réf forward, [0x08]=réf backward, 0xff=aucune. */
    ctx->out_idx = dd_pick_output(ctx);
    if (ctx->out_idx < 0) {
        /* aucune surface libre : le vout ne relâche plus rien → pas de matériel
         * pour cette picture (l'appelant retombe sur le chemin logiciel). */
        ctx->out_idx = 0;
        return -1;
    }
    if (coding_type == 1) {                 /* I : aucune référence */
        ctx->fwd_ref = 0xff; ctx->bwd_ref = 0xff;
    } else if (coding_type == 2) {          /* P : forward = dernière I/P */
        ctx->fwd_ref = (ctx->ref_idx[0] >= 0) ? ctx->ref_idx[0] : 0xff;
        ctx->bwd_ref = 0xff;
    } else {                                /* B : fwd=avant-dernière, bwd=dernière */
        ctx->fwd_ref = (ctx->ref_idx[1] >= 0) ? ctx->ref_idx[1] : 0xff;
        ctx->bwd_ref = (ctx->ref_idx[0] >= 0) ? ctx->ref_idx[0] : 0xff;
    }
    return 0;
}

/* Débute un macrobloc : mb_desc[0x14]=mb_type, [0x15]=dct_type, arme le walker.
 * dct_type : 0=frame-DCT, 1=field-DCT (entrelacé). Sans ça, les macroblocs
 * field-DCT (détail fin/mouvement) sont recombinés en frame → artefact « peigne ». */
void dvddriver_picture_mb_begin(dvddriver_ctx *ctx, int mb_type, int dct_type,
                                uint8_t cbp, const int16_t *mv,
                                const uint8_t *field_select)
{
    if (ctx->mb_index >= ctx->nb_mbs)
        return;
    uint8_t *desc = ctx->descriptors + ctx->mb_index * MB_DESC_SIZE;

    /* Phase 2 — field prediction (MC_FIELD, mb_type 5/6/7). Le scaling vertical
     * calibré est fait côté slice.c (pmv>>2 ; le driver re-<<1). Le hang GPU
     * d'origine venait d'un MV vertical 2× trop grand (hors-bornes à 720×576) ;
     * corrigé → anime lent PROPRE, plus de hang. ⚠ mouvement RAPIDE (grand MV
     * field) encore imparfait (adressage réf 0x5e24 à finir). La SOUMISSION field
     * est conditionnée par field_exp (0=off/fallback CPU, défaut sûr ; >=1=on),
     * lu depuis /tmp/field_exp — cf. dvddriver_open + submit. */
    if (mb_type >= 5)
        ctx->field_seen = 1;
    if (mb_type >= 0 && mb_type < 8) ctx->mb_stat[mb_type]++;
    ctx->dct_stat[dct_type ? 1 : 0]++;

    /* MV : 8× i16 @[0x00..0x0f] en ordre-octet NATIF (BE sur PPC, comme les coeffs).
     * Le driver ajoute la composante au pos×2 en demi-pel (+ <<1 vertical interne
     * pour les mb_type field 5/6/7). */
    int16_t lmv[8];
    for (int i = 0; i < 8; i++)
        lmv[i] = mv[i];
    uint8_t lfs[4] = { 0, 0, 0, 0 };
    bool b_fs = (field_select != NULL);
    if (b_fs)
        for (int i = 0; i < 4; i++) lfs[i] = field_select[i];

    /* ★★★ METTRE À ZÉRO LA DIRECTION INUTILISÉE — relevé sur le LECTEUR D'APPLE.
     *
     * `slice.c` recopie les huit vecteurs depuis `f_motion` ET `b_motion` sans
     * condition, ainsi que les quatre bits de parité. Sur un macrobloc AVANT
     * SEUL — 94 % des macroblocs à prédiction par champ de ces menus — la moitié
     * « arrière » du descripteur est donc un RESTE du macrobloc précédent, et on
     * l'envoyait telle quelle au pilote.
     *
     * Trace du lecteur d'Apple sur les menus animés de ce disque
     * (`scratchpad/decspy.c`, ~57 000 macroblocs par champ observés) : la
     * combinaison de parité de loin la plus fréquente y est `0b0100` — parité de
     * la seule prédiction 1 AVANT, les bits ARRIÈRE à zéro. Chez nous c'était
     * `0b1100` qui écrasait tout, c'est-à-dire le bit arrière parasite. En
     * mettant à zéro ce que la direction n'utilise pas, notre distribution
     * rejoint la sienne (dominante `0b0100`, et `0b1100` retombe au niveau
     * observé chez Apple) — comparaison faite hors machine avec
     * `scratchpad/mb/mbstat.c`.
     *
     * ⚠ Cela vaut aussi pour la prédiction par TRAME (types 1 et 2), où le même
     * reste est envoyé ; il y est apparemment ignoré, mais Apple ne l'envoie pas
     * davantage. `/tmp/hw_nozero` rétablit l'ancien comportement pour l'A/B. */
    {
        static int s_nozero = -1;
        if (s_nozero < 0) s_nozero = (dd_gate_read("/tmp/hw_nozero") > 0);
        if (!s_nozero) {
            if (mb_type == 1 || mb_type == 5) {        /* AVANT seul */
                lmv[2] = lmv[3] = lmv[6] = lmv[7] = 0;
                lfs[1] = lfs[3] = 0;
            } else if (mb_type == 2 || mb_type == 6) { /* ARRIÈRE seul */
                lmv[0] = lmv[1] = lmv[4] = lmv[5] = 0;
                lfs[0] = lfs[2] = 0;
            }
        }
    }

    /* ★★ MODE 4 — PRÉDICTION FRAME ÉQUIVALENTE (défaut pour l'entrelacé).
     *
     * Le moteur de motion-compensation PAR CHAMP du RV200 produit des traînées et
     * des blocs déplacés dès qu'il y a du mouvement, et l'erreur s'accumule sur
     * tout le GOP (P référençant P) — très visible sur un arrêt sur image. Isolé
     * par deux clips de contrôle 720×576 : le clip encodé en DCT-par-champ seule
     * sort PROPRE, le clip encodé en estimation-de-mouvement-par-champ sort CASSÉ.
     * Ce n'est donc ni notre descripteur, ni la DCT : c'est le moteur field, dont
     * la sémantique d'adressage n'est ni documentée ni observable.
     *
     * Contournement exact plutôt qu'approximatif : `motion_fr_field` de libmpeg2
     * range déjà `pmv[i][1]` en demi-pel de TRAME (il applique `motion_y << 1`
     * pour passer des lignes de champ aux lignes de trame). Les deux prédictions
     * de champ sont donc directement comparables à un MV frame : on les moyenne
     * et on soumet le macrobloc au chemin MC FRAME du driver — celui qui, lui,
     * est exact (tout le progressif en dépend). Sur une source FILM (la quasi
     * totalité des DVD de cinéma), les deux champs proviennent de la même image
     * et portent le même mouvement : la moyenne est alors la valeur exacte, et le
     * rendu est identique à celui du décodage logiciel. Sur une source vidéo
     * native au mouvement franchement différent entre champs, la moyenne est une
     * approximation — mais une approximation LISSE, sans déchirure.
     *
     * Les modes 1/2/3 (moteur field natif) restent disponibles pour la RE. */
    /* Mode 4 : la conversion en prédiction frame n'est EXACTE que si les deux
     * prédictions de champ portent le même vecteur ET lisent le même champ de
     * référence — c'est le cas d'une source FILM, où les deux champs viennent de
     * la même image. Quand elles diffèrent (vrai mouvement par champ), il n'existe
     * pas de vecteur frame équivalent : moyenner fabrique un vecteur qui ne
     * correspond à AUCUNE des deux prédictions et déplace des blocs entiers. On
     * laisse alors le macrobloc au moteur field natif (imparfait, mais qui prédit
     * au moins ce que le flux demande). */
    bool b_cvt_exact = false;
    if (mb_type >= 5) {
        /* ⚠⚠ NE COMPARER QUE LES DIRECTIONS RÉELLEMENT UTILISÉES. slice.c
         * remplit les huit vecteurs depuis `f_motion` ET `b_motion` sans
         * condition : sur un macrobloc AVANT SEUL (mb_type 5), la moitié
         * « arrière » du descripteur est un RESTE du macrobloc précédent. La
         * comparer revenait à trancher sur des données qui ne servent pas, et
         * faisait refuser des macroblocs parfaitement convertibles. */
        const bool b_fwd = (mb_type == 5 || mb_type == 7);
        const bool b_bwd = (mb_type == 6 || mb_type == 7);
        b_cvt_exact = true;
        if (b_fwd)
            b_cvt_exact = lmv[0] == lmv[4] && lmv[1] == lmv[5]
                && (!b_fs || lfs[0] == lfs[2]);
        if (b_bwd)
            b_cvt_exact = b_cvt_exact && lmv[2] == lmv[6] && lmv[3] == lmv[7]
                && (!b_fs || lfs[1] == lfs[3]);

        /* ★★★ TRAITEMENT DES MACROBLOCS NON CONVERTIBLES EXACTEMENT.
         *
         * Mesuré hors machine sur le VOB de menu du disque de test (harnais
         * `scratchpad/mb/mbstat.c`, qui rejoue la MÊME libmpeg2) : les menus
         * animés ne comptent que **3,5 % de macroblocs à prédiction par champ**
         * — le reste est déjà en prédiction TRAME, donc exact sur ce GPU. Sur
         * ces 3,5 %, moins de 1 % est convertible exactement.
         * Trois traitements possibles pour cette minorité, au choix à chaud :
         *   0 = les laisser au moteur field natif de l'ATI (comportement
         *       historique ; c'est lui dont l'adressage n'est pas maîtrisé) ;
         *   1 = dupliquer la prédiction du champ 0 sur les deux champs ;
         *   2 = moyenner les deux prédictions.
         * 1 et 2 renvoient le macrobloc au chemin MC TRAME, qui est exact : ils
         * remplacent une erreur d'adressage non bornée par une erreur de
         * vecteur bornée par l'écart entre les deux champs. */
        static int s_cvt = -1;
        if (s_cvt < 0) { int v = dd_gate_read("/tmp/hw_fieldcvt");
                         s_cvt = (v >= 0 && v <= 2) ? v : 0; }
        if (!b_cvt_exact && ctx->field_exp == 4 && s_cvt > 0) {
            if (s_cvt == 1) {
                lmv[4] = lmv[0]; lmv[5] = lmv[1];
                lmv[6] = lmv[2]; lmv[7] = lmv[3];
            } else {
                for (int i = 0; i < 4; i++) {
                    int m = ((int) lmv[i] + (int) lmv[i + 4]) / 2;
                    lmv[i] = lmv[i + 4] = (int16_t) m;
                }
            }
            b_cvt_exact = true;               /* → chemin MC TRAME ci-dessous */
            ctx->cvt_stat[2]++;               /* converti, mais APPROCHÉ */
        }
        else if (b_cvt_exact)
            ctx->cvt_stat[0]++;               /* converti EXACTEMENT */
        else
            /* cvt_stat[1] = ce qui part VRAIMENT au moteur field. C'est ce
             * chiffre, rapporté au TOTAL des macroblocs, que pèse la garde de
             * libmpeg2.c — et non plus sa part parmi les seuls macroblocs field. */
            ctx->cvt_stat[1]++;
    }
    if (mb_type >= 5 && ctx->field_exp == 4 && b_cvt_exact) {
        /* Les deux prédictions étant identiques (vérifié ci-dessus), le vecteur
         * frame équivalent est simplement celui-là : aucune approximation.
         * ★ Le descripteur doit être INDISCERNABLE de celui d'un macrobloc
         * frame-predicted natif. Or en prédiction FRAME, libmpeg2 met les DEUX
         * prédicteurs à la même valeur (`motion_fr_frame` recopie pmv[0] dans
         * pmv[1]) : desc+8/+0x0a portent donc le MÊME vecteur que desc+0/+2.
         * Mettre desc+8.. à ZÉRO (ce que faisait la première version) donne au
         * driver un descripteur qu'aucun macrobloc natif ne produit — d'où des
         * blocs faux là où ça bouge. On DUPLIQUE donc, comme libmpeg2. */
        lmv[4] = lmv[0]; lmv[5] = lmv[1];
        lmv[6] = lmv[2]; lmv[7] = lmv[3];
        mb_type -= 4;                     /* 5/6/7 → 1/2/3 : chemin MC FRAME */
        b_fs = false;                     /* pas de parité en prédiction frame */
    }
    else if (mb_type >= 5) {
        /* ★★ MISE À L'ÉCHELLE VERTICALE DU MV FIELD — dérivée de la SOURCE, pas
         * d'une calibration empirique.
         * `motion_fr_field` (slice.c) décode `motion_y` en demi-pel de CHAMP puis
         * range `pmv[i][1] = motion_y << 1` (unité doublée, pour que la prédiction
         * de vecteur `pmv >> 1` retombe juste). Le driver, lui, calcule
         * `refpos_vert = V + 2·pos_y` — le même idiome que la MC frame — donc il
         * attend `V = motion_y`, c'est-à-dire **`pmv >> 1`**.
         * ⚠ Les sessions précédentes avaient retenu `>> 2` parce que `>> 1`
         * « faisait hanguer » le GPU à 720×576. Ce hang était en réalité la FAMINE
         * DE BUFFERS MP (corrigée depuis) : toute cette calibration a été faite sur
         * un pipeline cassé. Un vecteur vertical DEUX FOIS TROP COURT explique
         * exactement le symptôme observé — la compensation de mouvement traîne
         * derrière l'image, laissant des bavures sur les zones en mouvement, qui
         * s'accumulent sur le GOP.
         * Dial d'A/B : /tmp/hw_fieldshift (0, 1 ou 2 ; défaut 1). */
        static int s_shift = -1;
        if (s_shift < 0) { int v = dd_gate_read("/tmp/hw_fieldshift");
                           s_shift = (v >= 0 && v <= 2) ? v : 1; }
        if (s_shift > 0)
            for (int i = 1; i < 8; i += 2)
                lmv[i] = (int16_t) (lmv[i] >> s_shift);
    }

    /* E-B (field_exp==3) — FULL-PEL VERTICAL field. Hypothèse la plus prometteuse
     * de la campagne 2b : l'interpolation DEMI-PEL VERTICALE du moteur field ATI
     * (offset demi-ligne inter-champs, arrondi sous-pixel) diverge de celle de
     * libmpeg2 → smear en mouvement rapide. On force la composante verticale des
     * prédictions field à PLEINE-PEL en effaçant le bit demi-pel (bit0, la verticale
     * étant en demi-pel comme le MV frame). Si le smear cède au prix d'un léger flou
     * vertical, le mode est LIVRABLE (qualité très supérieure au smear). Isolé de
     * exp==2 par exactement une variable (le snap full-pel) ; le clamp ci-dessous
     * s'applique quand même (sécurité hors-bornes). */
    if (mb_type >= 5 && ctx->field_exp == 3) {
        for (int i = 1; i < 8; i += 2)
            lmv[i] &= ~1;                 /* verticales field → full-pel */
    }

    /* Phase 2 — CLAMP du MV VERTICAL field (field_exp 2 ET 3), pour garder la réf
     * dans la surface (le field vertical n'est PAS borné par libmpeg2, cf.
     * motion_fr_field ; le path SW survit via edge-extension émulée, le GPU non).
     *
     * ⚠ UNITÉS (corrigé après disasm fin de 0x5af8) : le driver calcule
     *   refpos_vert = V + 2·pos_y   (demi-pel)
     * où V = ce qu'on écrit dans desc (le handler fait <<1 PUIS 0x5af8 fait >>1 en
     * entrée @5b60 → les deux s'annulent, exactement comme la MC frame `MV.y + 2·pos_y`).
     * V est donc en DEMI-PEL (comme le MV frame), pas en pixels. Le bloc réf (16 px =
     * 32 demi-pel) doit tenir dans la surface [0, 2·height] :
     *   0 <= V + 2·pos_y <= 2·(height-16)   →   V ∈ [-2·pos_y, 2·(height-16-pos_y)].
     * L'ancienne borne [-pos_y, height-16-pos_y] était 2× TROP SERRÉE (traitait V en
     * pixels) → tronquait les MV field moyens/grands légitimes → smear qui S'ACCUMULE
     * sur le GOP (P référençant P). Borne correcte = laisse passer tout MV légitime,
     * ne coupe que le vraiment hors-surface (protège du hang). */
    if (mb_type >= 5 && (ctx->field_exp == 2 || ctx->field_exp == 3)
        && ctx->width > 0) {
        unsigned mb_w = (ctx->width + 15) / 16;
        int pos_y = (int)((ctx->mb_index / mb_w) * 16);   /* pixels, coin haut du MB */
        int lo = -2 * pos_y;                              /* refpos >= 0 (demi-pel) */
        int hi = 2 * ((int)ctx->height - 16 - pos_y);     /* refpos <= 2·(height-16) */
        if (hi < lo) hi = lo;
        for (int i = 1; i < 8; i += 2) {                  /* mv[1,3,5,7] = verticales */
            if (lmv[i] < lo) lmv[i] = (int16_t) lo;
            else if (lmv[i] > hi) lmv[i] = (int16_t) hi;
        }
    }

    for (int i = 0; i < 8; i++) {
        int16_t v = lmv[i];
        memcpy(desc + i * 2, &v, sizeof v);
    }
    if (b_fs) {
        desc[0x10] = lfs[0]; desc[0x11] = lfs[1];
        desc[0x12] = lfs[2]; desc[0x13] = lfs[3];
    } else {
        desc[0x10] = desc[0x11] = desc[0x12] = desc[0x13] = 0;
    }
    desc[0x14] = (uint8_t) mb_type;
    /* SONDE — `/tmp/hw_dct0` force la DCT de TRAME sur tous les macroblocs.
     * Raison d'être : la prédiction par champ est désormais DISCULPÉE (avec
     * `/tmp/hw_fieldcvt` à 1 ou 2, plus aucun macrobloc ne va au moteur field —
     * les compteurs le confirment — et l'image reste cassée). Or la DCT PAR CHAMP
     * est l'autre trait propre à l'entrelacé : ~3 % des macroblocs de ces menus,
     * et ZÉRO sur le film qui, lui, s'affiche parfaitement. Elle n'a jamais été
     * validée contre une référence sur ce GPU.
     * Le test est discriminant par la NATURE de l'artefact : forcer la DCT de
     * trame sur un macrobloc codé par champ donne un effet de PEIGNE sur le
     * détail fin, pas des blocs déplacés dans toute l'image. */
    {
        static int s_dct0 = -1;
        if (s_dct0 < 0) s_dct0 = (dd_gate_read("/tmp/hw_dct0") > 0);
        if (s_dct0) dct_type = 0;
    }
    desc[0x15] = (uint8_t) dct_type;
    ctx->cur_cbp = cbp;
    ctx->cur_block = 0;
}

/* Ajoute le prochain bloc CODÉ : mb_desc[0x16+block]=nb_coeffs + flux coeffs. */
void dvddriver_picture_mb_block(dvddriver_ctx *ctx, const int16_t *dctblock,
                                const uint8_t *scan)
{
    if (ctx->mb_index >= ctx->nb_mbs)
        return;
    while (ctx->cur_block < 6 && !(ctx->cur_cbp & (0x20 >> ctx->cur_block)))
        ctx->cur_block++;
    if (ctx->cur_block >= 6)
        return;
    uint8_t *desc = ctx->descriptors + ctx->mb_index * MB_DESC_SIZE;
    /* INTRA (mb_type 0) : pixels absolus → le driver centre toutes les composantes
     * sur 128, donc recentrage DC=1024 (validé ati_color.c). INTER (P/B) : le bloc
     * est un RÉSIDU (déjà centré sur 0), ajouté à la référence → dc_bias=0. */
    int dc_bias = (desc[0x14] == 0) ? 1024 : 0;
    unsigned n = dvddriver_encode_block(dctblock, scan, dc_bias,
                                        ctx->coeffs + ctx->coeffs_len);
    desc[0x16 + ctx->cur_block] = (uint8_t) n;
    ctx->coeffs_len += n * 4u;
    ctx->cur_block++;
}

/* Variante ALIMENTÉE PAR LA VLD : paires (position zigzag, valeur) capturées au
 * moment même du parse (mpeg2_hw_rl dans slice.c) — plus aucun re-balayage des
 * 64 positions ni lecture indirecte par la table de scan. Mêmes conventions que
 * dvddriver_encode_block : échelle /16 arrondie, recentrage DC intra, clamp
 * 12 bits, run = écart zigzag, level en ordre-octet natif. */
void dvddriver_picture_mb_block_rl(dvddriver_ctx *ctx, const int16_t (*rl)[2],
                                   int n)
{
    if (ctx->mb_index >= ctx->nb_mbs)
        return;
    while (ctx->cur_block < 6 && !(ctx->cur_cbp & (0x20 >> ctx->cur_block)))
        ctx->cur_block++;
    if (ctx->cur_block >= 6)
        return;
    uint8_t *desc = ctx->descriptors + ctx->mb_index * MB_DESC_SIZE;
    int dc_bias = (desc[0x14] == 0) ? 1024 : 0;
    uint8_t *out = ctx->coeffs + ctx->coeffs_len;
    unsigned cnt = 0;
    int last = -1;
    for (int k = 0; k < n; k++) {
        int pos = rl[k][0];
        int v   = rl[k][1];
        if (pos <= last)
            continue;               /* garde : positions strictement croissantes */
        v = (v >= 0) ? (v + 8) / 16 : -(((-v) + 8) / 16);
        if (pos == 0)
            v -= dc_bias;           /* recentrage DC (échelle driver) */
        if (v == 0)
            continue;
        if (v > 2047) v = 2047; else if (v < -2047) v = -2047;
        out[0] = (uint8_t)(pos - last - 1);
        out[1] = 0;
        int16_t lv = (int16_t) v;
        memcpy(out + 2, &lv, sizeof lv);
        out += 4;
        cnt++;
        last = pos;
    }
    desc[0x16 + ctx->cur_block] = (uint8_t) cnt;
    ctx->coeffs_len += cnt * 4u;
    ctx->cur_block++;
}

void dvddriver_picture_mb_end(dvddriver_ctx *ctx)
{
    if (ctx->mb_index < ctx->nb_mbs)
        ctx->mb_index++;
}

/* Type de picture tel que le backend l'a mémorisé au dernier picture_begin.
 * Diagnostic : s'il diffère de celui que libmpeg2 croit soumettre, c'est qu'un
 * picture_begin s'est glissé entre la capture et la soumission — et il remet
 * mb_index à zéro, d'où un [0/nb_mbs] alors que les macroblocs ont bien été vus. */


/* Nombre de fois où le décodeur a dû ATTENDRE qu'une surface GPU se libère.
 * Le pool est de 5, mais les deux références en occupent deux : il n'en reste
 * que TROIS pour la sortie, et chacune reste prise tant que VLC détient la
 * picture. Si ce compteur monte, le décodeur est cadencé par l'affichage et ne
 * peut plus tenir le débit de la source. */

unsigned dvddriver_surf_waits(const dvddriver_ctx *ctx)
{
    return (ctx != NULL) ? ctx->n_surf_wait : 0;
}

void dvddriver_show_counts(const dvddriver_ctx *ctx, unsigned out[3])
{
    out[0] = (ctx != NULL) ? ctx->n_show_target  : 0;
    out[1] = (ctx != NULL) ? ctx->n_show_drain   : 0;
    out[2] = (ctx != NULL) ? ctx->n_show_recycle : 0;
}




void dvddriver_last_progress(const dvddriver_ctx *ctx, unsigned *captured,
                             unsigned *total)
{
    if (captured) *captured = ctx->mb_index;
    if (total)    *total    = ctx->nb_mbs;
}

uint8_t dvddriver_cbp_from_libmpeg2(unsigned mpeg2_cbp)
{
    uint8_t g = 0;
    for (int b = 0; b < 6; b++)
        if (mpeg2_cbp & (1u << b))
            g |= (uint8_t)(0x20 >> b);
    return g;
}

/* Construit pic_desc et appelle DVDDriverDecode. Retourne rc (0=succès ;
 * -4 = matériel abandonné après stalls répétés, l'appelant doit repasser CPU). */
/* Attend, VERROU TENU, que le worker asynchrone ne soit plus dans Decode.
 * À appeler avant tout appel driver hors worker (Show, SP) : on conserve la
 * sérialisation historique « un seul appel driver à la fois ». */
static void dd_wait_gpu_idle_locked(dvddriver_ctx *ctx)
{
    /* ⚠⚠ NE JAMAIS laisser Show/SP s'exécuter PENDANT un Decode. Essayé le
     * 2026-07-28 sur 10.3.9 (gate /tmp/hw_showpar, retiré depuis) : GEL COMPLET
     * de la machine dès les premières images du film. La sérialisation
     * historique « un seul appel driver à la fois » n'est pas une précaution
     * excessive, c'est une exigence du kext. */
    while (ctx->async_busy) {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        struct timespec ts;
        ts.tv_sec  = tv.tv_sec;
        ts.tv_nsec = (long) tv.tv_usec * 1000L + 200000000L;   /* +200 ms */
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec++; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&ctx->async_done_cv, &ctx->lock, &ts);
    }
}

/* Fin de Decode + comptabilité, VERROU TENU. Partagé entre le chemin synchrone
 * et le worker pour que les deux modes produisent les mêmes statistiques et le
 * même garde-fou anti-wedge. */
static void dd_decode_done_locked(dvddriver_ctx *ctx, int rc, unsigned long dt,
                                  int out_idx)
{
    ctx->us_decode += dt;
    ctx->n_decode++;
    ctx->us_last_decode = dt;
    {
        int b = dt <  4000 ? 0 : dt <  8000 ? 1 : dt < 12000 ? 2
              : dt < 16000 ? 3 : dt < 24000 ? 4 : dt < 40000 ? 5
              : dt < 80000 ? 6 : 7;
        ctx->dec_hist[b]++;
    }
    if (dt > DD_STALL_US && ctx->n_decode > 1) {
        ctx->stalls++;
        dd_recycle_locked(ctx, 0);
        if (ctx->stalls >= DD_STALL_MAX)
            ctx->gpu_disabled = true;
    } else if (ctx->stalls > 0 && dt < DD_STALL_US / 4) {
        /* « répétés » = CONSÉCUTIFS : un Decode redevenu rapide prouve que le
         * driver draine. Un compteur cumulatif transformait une poignée de
         * contre-pressions étalées sur 35 s en faux abandon du matériel. */
        ctx->stalls = 0;
    }
    if (rc == 0 && out_idx >= 0 && out_idx < 5) {
        dd_pending_drop(ctx, out_idx);
        if (ctx->n_pending < (int)(sizeof ctx->pending / sizeof ctx->pending[0]))
            ctx->pending[ctx->n_pending++] = out_idx;
    }
}

static void *dd_async_worker(void *arg)
{
    dvddriver_ctx *ctx = arg;

    pthread_mutex_lock(&ctx->lock);
    for (;;) {
        while (!ctx->async_quit && !ctx->async_job)
            pthread_cond_wait(&ctx->async_in_cv, &ctx->lock);
        if (ctx->async_quit)
            break;

        uint8_t  pic[0x40];
        int16_t  rect[4];
        memcpy(pic,  ctx->async_pic,  sizeof(pic));
        memcpy(rect, ctx->async_rect, sizeof(rect));
        int out_idx = ctx->async_out_idx;
        int ctype   = ctx->async_coding;
        ctx->async_job  = false;
        ctx->async_busy = true;

        if (ctx->closed || ctx->Decode == NULL || ctx->dev_ctx == NULL) {
            ctx->async_last_rc = -1;
            ctx->async_busy = false;
            pthread_cond_broadcast(&ctx->async_done_cv);
            continue;
        }
        dd_recycle_locked(ctx, 4);   /* filet anti-famine, cf. chemin synchrone */

        dvd_decode_fn dec = ctx->Decode;
        void *dev = ctx->dev_ctx;
        /* Decode HORS verrou : pendant ce temps le thread décodeur fait la VLD
         * de la picture suivante et le vout fait pick/hold/release librement.
         * Les appels DRIVER concurrents, eux, attendent async_busy. */
        pthread_mutex_unlock(&ctx->lock);
        unsigned long t0 = dd_now_us();
        int rc = dec(dev, pic, rect);
        unsigned long dt = dd_now_us() - t0;
        pthread_mutex_lock(&ctx->lock);

        dd_decode_done_locked(ctx, rc, dt, out_idx);
        ctx->async_last_rc = rc;
        if (rc != 0 && ctx->async_fail_type == 0)
            ctx->async_fail_type = ctype;
        ctx->async_busy = false;
        pthread_cond_broadcast(&ctx->async_done_cv);
    }
    pthread_mutex_unlock(&ctx->lock);
    return NULL;
}

void dvddriver_set_async(dvddriver_ctx *ctx, bool on)
{
    if (ctx == NULL)
        return;
    if (on && !ctx->async_started) {
        ctx->async_quit = false;
        if (pthread_create(&ctx->async_th, NULL, dd_async_worker, ctx) == 0) {
            ctx->async_started = true;
            ctx->async_on = true;
        }
    } else if (!on) {
        ctx->async_on = false;   /* le thread éventuel reste idle */
    }
}

int dvddriver_async_take_failure(dvddriver_ctx *ctx)
{
    if (ctx == NULL)
        return 0;
    pthread_mutex_lock(&ctx->lock);
    int v = ctx->async_fail_type;
    ctx->async_fail_type = 0;
    pthread_mutex_unlock(&ctx->lock);
    return v;
}

int dvddriver_picture_submit(dvddriver_ctx *ctx)
{

    if (ctx->dev_ctx == NULL || ctx->Decode == NULL)
        return -1;
    if (ctx->gpu_disabled)
        return -4;
    /* Sécurité d'alignement raster : si tous les macroblocs n'ont pas été
     * capturés (nb_desc != nb_mbs, ex. P non frame-predicted), NE PAS soumettre
     * — sinon le driver lit des descripteurs désalignés → corruption totale. */
    if (ctx->mb_index != ctx->nb_mbs)
        return -2;
    /* Phase 2 : picture avec MB field-predicted → soumise seulement si une
     * expérience de déblocage est active (field_exp>=1) ; sinon fallback CPU
     * (le descripteur field mal calibré fait HANG le GPU). */
    if (ctx->field_seen && ctx->field_exp == 0)
        return -3;

    uint8_t pic[0x40];
    memset(pic, 0, sizeof(pic));
    pic[0x02] = (uint8_t) ctx->pic_structure;      /* 3=frame */

    /* ★ CHAMPS PAR-PASSE de pic_desc (piste field, jamais testée jusqu'ici).
     * Une picture FRAME est décodée en DEUX passes (`0x25e4` appelé avec r5=0 puis
     * r5=1). Le disasm montre que le driver indexe plusieurs champs PAR LE NUMÉRO
     * DE PASSE (`r2 = pic_desc + pass` @0x25f8) :
     *   pic_desc[0x00 + passe] = type de picture (1=I, 2=P, 3=B — déduit de la
     *                            capture live de DVD Player : [0x00] vaut 3 quand
     *                            fwd≠bwd, 2 quand une seule réf, 1 sur les I) ;
     *   pic_desc[0x02 + passe] = picture_structure ;
     *   pic_desc[0x04 + passe] = (rôle non élucidé).
     * Nous ne remplissions QUE `[0x02]` → la passe 1 lisait `[0x03]==0`, et
     * `@0x26bc` le driver **DIVISE PAR DEUX le nombre de macroblocs** quand la
     * structure de la passe n'est pas 3 : la seconde passe ne traiterait donc que
     * la MOITIÉ des macroblocs. Sur du field prediction, la 2e passe porte la 2e
     * prédiction de champ — d'où une erreur INVISIBLE en mouvement lent (les deux
     * prédictions de champ sont quasi identiques) et TRÈS visible en mouvement
     * rapide, exactement la signature observée.
     * Dial d'expérience `/tmp/hw_picdesc` (bitmask) : 1 = type de picture en
     * [0x00]/[0x01], 2 = structure aussi en [0x03], 4 = type en [0x04]/[0x05]. */
    {
        static int s_pd = -2;
        if (s_pd == -2) { int v = dd_gate_read("/tmp/hw_picdesc"); s_pd = (v > 0) ? v : 0; }
        if (s_pd & 1) { pic[0x00] = (uint8_t) ctx->coding_type;
                        pic[0x01] = (uint8_t) ctx->coding_type; }
        if (s_pd & 2)   pic[0x03] = (uint8_t) ctx->pic_structure;
        if (s_pd & 4) { pic[0x04] = (uint8_t) ctx->coding_type;
                        pic[0x05] = (uint8_t) ctx->coding_type; }
    }
    pic[0x06] = (uint8_t) ctx->out_idx;            /* surface de SORTIE */
    pic[0x07] = (uint8_t) ctx->fwd_ref;            /* réf FORWARD (0xff=aucune) */
    pic[0x08] = (uint8_t) ctx->bwd_ref;            /* réf BACKWARD */
    *(uint32_t *)(pic + 0x0c) = (uint32_t)(uintptr_t) ctx->descriptors;
    *(uint32_t *)(pic + 0x10) = (uint32_t)(uintptr_t) ctx->coeffs;
    *(uint32_t *)(pic + 0x14) = (uint32_t)(uintptr_t) ctx->scratch1;
    *(uint32_t *)(pic + 0x18) = (uint32_t)(uintptr_t) ctx->scratch2;
    *(uint32_t *)(pic + 0x1c) = (uint32_t)(uintptr_t) ctx->reftab;
    /* RE perf (test) : champs que DVD Player remplit et qu'on laissait à 0 (capture
     * live, scratchpad/dvdplayer_picdesc.txt). Hypothèse : l'un active un chemin
     * décode plus rapide. Gate /tmp/hw_flags (absent = comportement actuel). */
    {
        static int s_flags = -1;
        if (s_flags < 0) { FILE *f = fopen("/tmp/hw_flags", "r");
                           s_flags = f ? (fclose(f), 1) : 0; }
        if (s_flags) {
            pic[0x20] = 0x00; pic[0x21] = 0x02;      /* halfword @0x20 = 2 */
            pic[0x27] = 0x01;
            *(uint32_t *)(pic + 0x3c) = 0xffffffffu;
        }
    }

    int16_t rect[4] = { 0, 0, (int16_t) ctx->height, (int16_t) ctx->width };

    /* MESURE (temporaire, chantier perf) — DEUX gates INDÉPENDANTS :
     *
     *  /tmp/hw_nosubmit : saute Decode() SANS bumper la génération de surface.
     *      ⚠ Effet de bord : gen inchangée → le vout SAUTE AUSSI tout le present
     *      (ShowMPBuffer + CGSSetSurfaceBounds + CGSFlushSurface). Ce gate mesure
     *      donc « CPU seul », pas « CPU + present ». C'est ce biais qui a fait
     *      attribuer à tort les ~380 ms/pic 720×576 au seul Decode() GPU.
     *  /tmp/hw_nodecode : saute Decode() mais BUMPE la génération → le chemin de
     *      present s'exécute normalement. Différence avec hw_nosubmit = coût du
     *      present ; différence avec le baseline = coût de Decode().
     *
     * Aucun appel GPU supplémentaire n'est fait par ces gates (ils en RETIRENT) →
     * pas de risque de wedge. À retirer une fois le chantier tranché. */
    static int s_no_gpu = -2, s_no_dec = -2;
    if (s_no_gpu == -2) s_no_gpu = (dd_gate_read("/tmp/hw_nosubmit") > 0);
    if (s_no_dec == -2) s_no_dec = (dd_gate_read("/tmp/hw_nodecode") > 0);
    int rc;
    if (s_no_gpu) {
        rc = 0;   /* pas de Decode → pas de GPU ; surface non réécrite (gen inchangée) */
    } else if (s_no_dec) {
        rc = 0;   /* pas de Decode, mais on fait comme si la surface était produite */
        if (ctx->out_idx >= 0 && ctx->out_idx < 5) {
            pthread_mutex_lock(&ctx->lock);
            ctx->surf_gen[ctx->out_idx]++;
            pthread_mutex_unlock(&ctx->lock);
        }
    } else if (ctx->async_on && ctx->async_started) {
        /* ── Chemin ASYNCHRONE ── */
        pthread_mutex_lock(&ctx->lock);
        /* Profondeur 1 : attendre la fin du job précédent. C'est ici que le
         * recouvrement se paie : la VLD de CETTE picture a déjà eu lieu
         * pendant le Decode de la précédente. */
        {
            unsigned long w0 = dd_now_us();
            while ((ctx->async_job || ctx->async_busy) && !ctx->closed)
                pthread_cond_wait(&ctx->async_done_cv, &ctx->lock);
            unsigned long w = dd_now_us() - w0;
            ctx->us_submit_wait += w;
            ctx->us_last_submit_wait = w;
        }
        if (ctx->closed) {
            pthread_mutex_unlock(&ctx->lock);
            return -1;
        }
        if (ctx->gpu_disabled) {
            pthread_mutex_unlock(&ctx->lock);
            return -4;
        }
        memcpy(ctx->async_pic,  pic,  sizeof(pic));
        memcpy(ctx->async_rect, rect, sizeof(rect));
        ctx->async_out_idx = ctx->out_idx;
        ctx->async_coding  = ctx->coding_type;
        ctx->async_job = true;
        /* Génération bumpée DÈS l'enqueue : le codec attache le contexte
         * {surface, génération} sitôt ce retour, et le present du vout doit
         * retrouver cette valeur. Si le Decode échoue ensuite, le codec gèle
         * l'affichage via async_fail_type — même politique que le rc≠0
         * synchrone, décalée d'une picture. */
        if (ctx->out_idx >= 0 && ctx->out_idx < 5)
            ctx->surf_gen[ctx->out_idx]++;
        pthread_cond_broadcast(&ctx->async_in_cv);
        pthread_mutex_unlock(&ctx->lock);
        /* Rotation OPTIMISTE des références (rc supposé 0) : picture_begin de
         * la picture suivante — même thread — doit voir la rotation sans
         * attendre le GPU. Un échec est rattrapé par le gel jusqu'à l'I
         * suivante, comme sur le chemin synchrone. */
        if (ctx->coding_type != 3) {
            ctx->ref_idx[1] = ctx->ref_idx[0];
            ctx->ref_idx[0] = ctx->out_idx;
        }
        /* La picture suivante s'écrira dans l'autre jeu de tampons. */
        ctx->wset ^= 1;
        return 0;
    } else {
        /* U4 — le device est partagé avec le thread vout (Show) → sérialiser. */
        pthread_mutex_lock(&ctx->lock);
        /* RE perf (test, gate /tmp/hw_mvlevel) : DVD Player appelle SetMVLevel(ctx,0)
         * ~1×/picture avant Decode ; nous jamais. Hypothèse : configure un chemin MC
         * rapide. dev_ctx a le port io_connect à +0x14 (comme la struct de DVD Player). */
        static int s_mvl = -1;
        if (s_mvl < 0) { FILE *f = fopen("/tmp/hw_mvlevel", "r");
                         s_mvl = f ? (fclose(f), 1) : 0; }
        if (s_mvl && ctx->SetMVLevel)
            ctx->SetMVLevel(ctx->dev_ctx, 0);
        /* ★ Rendre les buffers MP des soumissions les plus anciennes que le vout
         * n'a pas présentées (pictures droppées par la synchro). Sans ça, le pool
         * interne du driver se vide et Decode BLOQUE (cf. commentaire struct).
         * /tmp/hw_norecycle rétablit l'ancien comportement pour l'A/B. */
        static int s_norecyc = -2;
        if (s_norecyc == -2) s_norecyc = (dd_gate_read("/tmp/hw_norecycle") > 0);
        /* keep=4 et non DD_MAX_PENDING : le drainage nominal se fait désormais
         * AU PRESENT (dd_show_locked, dans l'ordre) ; ici ce n'est plus qu'un
         * filet anti-famine, et chaque Show hors present est une image hors
         * ordre à l'écran — n'y recourir qu'en dernier ressort. */
        if (!s_norecyc)
            dd_recycle_locked(ctx, 4);
        unsigned long t0 = dd_now_us();
        rc = ctx->Decode(ctx->dev_ctx, pic, rect);
        unsigned long dt = dd_now_us() - t0;
        if (rc == 0 && ctx->out_idx >= 0 && ctx->out_idx < 5)
            ctx->surf_gen[ctx->out_idx]++;   /* surface réécrite → nouvelle génération */
        dd_decode_done_locked(ctx, rc, dt, ctx->out_idx);
        pthread_mutex_unlock(&ctx->lock);
    }

    /* Rotation des références : la sortie d'une I/P devient la réf la plus
     * récente ; l'avant-dernière glisse. Une B n'est JAMAIS référence. */
    if (rc == 0 && ctx->coding_type != 3) {
        ctx->ref_idx[1] = ctx->ref_idx[0];
        ctx->ref_idx[0] = ctx->out_idx;
    }
    return rc;
}

/* U4 — génération courante d'une surface (0..4). Le codec la capture au submit
 * pour l'attacher à la picture ; le vout la compare au present pour ne présenter
 * qu'une surface encore à jour. Sous mutex (lue par le thread vout). */
unsigned dvddriver_surf_generation(dvddriver_ctx *ctx, int idx)
{
    if (ctx == NULL || idx < 0 || idx >= 5)
        return 0;
    pthread_mutex_lock(&ctx->lock);
    unsigned g = ctx->surf_gen[idx];
    pthread_mutex_unlock(&ctx->lock);
    return g;
}

/* U4 — rectangle de present dynamique (coords fenêtre-locales) : le vout le met
 * à jour à chaque display pour que la surface liée à la fenêtre VLC suive la
 * géométrie vidéo (U1). Sous mutex (Show s'exécute sur le thread vout aussi,
 * mais SetBounds lit ces champs). */
/* ── SP1 : le tampon SP est-il accessible en ÉCRITURE ? ─────────────────────
 * Écrit un motif au début du tampon idx, le relit, puis remet à zéro.
 * ⚠ À n'appeler qu'AVANT le premier Decode (règle anti-wedge). */
bool dvddriver_sp_write_test(dvddriver_ctx *ctx, int idx, uint32_t *read_back)
{
    if (ctx == NULL || !ctx->sp_available || idx < 0 || idx >= 8)
        return false;
    volatile uint32_t *p = (volatile uint32_t *) ctx->sp_probe[idx];
    if (p == NULL)
        return false;
    p[0] = 0xa5a5f00du;
    p[1] = 0x12345678u;
    if (read_back) {
        read_back[0] = p[0];
        read_back[1] = p[1];
    }
    p[0] = 0; p[1] = 0;
    return true;
}

/* ── SP2 : fabrique un paquet SPU DVD minimal (rectangle plein) ─────────────
 * Format natif du disque, celui qu'ApplySPDCSQ sait interpréter :
 *   en-tête  : u16 taille totale, u16 offset de la première DCSQ
 *   données  : deux trames RLE (lignes paires / impaires), 2 bits par pixel
 *   DCSQ     : u16 délai, u16 DCSQ suivante, puis des commandes :
 *              0x03 couleurs, 0x04 contrastes, 0x05 zone d'affichage,
 *              0x06 adresses des deux trames, 0x01 démarrer, 0xff fin.
 * Chaque ligne est codée par un seul mot de 16 bits « compte=0 » = jusqu'au
 * bout de la ligne, avec l'index de couleur voulu.
 * Renvoie la taille écrite, 0 si le tampon est trop petit. */
static size_t dd_build_test_spu(uint8_t *out, size_t max, int x1, int y1,
                                int x2, int y2, int color_index)
{
    const int lines = y2 - y1 + 1;
    const int half  = (lines + 1) / 2;          /* lignes par trame */
    const size_t hdr = 4;
    const size_t top_off = hdr;
    const size_t bot_off = top_off + (size_t) half * 2;
    const size_t dcsq_off = bot_off + (size_t) (lines / 2) * 2;
    const size_t total = dcsq_off + 4 + 3 + 3 + 7 + 5 + 1 + 1;
    if (total > max || lines <= 0)
        return 0;

    memset(out, 0, total);
    out[0] = (uint8_t) (total >> 8);   out[1] = (uint8_t) total;
    out[2] = (uint8_t) (dcsq_off >> 8); out[3] = (uint8_t) dcsq_off;

    /* RLE : un mot de 16 bits par ligne — compte nul = « jusqu'à la fin » */
    const uint16_t run = (uint16_t) (color_index & 3);
    for (int i = 0; i < half; i++) {
        out[top_off + 2 * i]     = (uint8_t) (run >> 8);
        out[top_off + 2 * i + 1] = (uint8_t) run;
    }
    for (int i = 0; i < lines / 2; i++) {
        out[bot_off + 2 * i]     = (uint8_t) (run >> 8);
        out[bot_off + 2 * i + 1] = (uint8_t) run;
    }

    uint8_t *d = out + dcsq_off;
    size_t k = 0;
    d[k++] = 0; d[k++] = 0;                       /* délai 0                  */
    d[k++] = (uint8_t) (dcsq_off >> 8);           /* DCSQ suivante = elle-même*/
    d[k++] = (uint8_t) dcsq_off;
    /* ⚠ Les nibbles des commandes 0x03/0x04 vont dans l'ordre 3,2,1,0 (comme
     * les lit spudec). Pour un test SANS ambiguïté : les quatre index de
     * couleur pointent la même entrée de palette (2 = blanc) et les quatre
     * contrastes sont opaques — quel que soit le motif RLE, la zone doit
     * apparaître pleine et blanche. */
    d[k++] = 0x03; d[k++] = 0x22; d[k++] = 0x22;  /* couleurs : toutes = 2     */
    d[k++] = 0x04; d[k++] = 0xff; d[k++] = 0xff;  /* contrastes : tout opaque  */
    d[k++] = 0x05;                                /* zone d'affichage          */
    d[k++] = (uint8_t) (x1 >> 4);
    d[k++] = (uint8_t) (((x1 & 0xf) << 4) | ((x2 >> 8) & 0xf));
    d[k++] = (uint8_t) x2;
    d[k++] = (uint8_t) (y1 >> 4);
    d[k++] = (uint8_t) (((y1 & 0xf) << 4) | ((y2 >> 8) & 0xf));
    d[k++] = (uint8_t) y2;
    d[k++] = 0x06;                                /* adresses des trames       */
    d[k++] = (uint8_t) (top_off >> 8); d[k++] = (uint8_t) top_off;
    d[k++] = (uint8_t) (bot_off >> 8); d[k++] = (uint8_t) bot_off;
    d[k++] = 0x01;                                /* démarrer l'affichage      */
    d[k++] = 0xff;                                /* fin de commandes          */
    return total;
}

/* ★ SP8 — écrit un bitmap de test DIRECTEMENT dans le plan source du driver.
 * En mode « surface » (ctx[0x1FC]==0), le moteur d'ApplySPDCSQ (0x7934) sort
 * aussitôt sur les commandes 0/1/2 et IGNORE la commande 0x06 — celle qui porte
 * les adresses des deux trames RLE. Le driver ne décode donc JAMAIS le RLE dans
 * ce mode : le bitmap 2 bits/pixel doit être produit par l'hôte, ce qui explique
 * pourquoi cette région est mappée côté CPU et fait exactement 192 o × 576.
 * Format, relevé sur la boucle du blit (39f0…3a2c) : 192 octets par ligne,
 * 4 pixels par octet, POIDS FORT D'ABORD. */
static void dd_write_test_bitmap(volatile uint8_t *bm, unsigned width,
                                 unsigned height)
{
    memset((void *) bm, 0, 192u * 576u);
    const unsigned y1 = height > 100 ? height - 100 : 0;
    const unsigned y2 = height >  40 ? height -  40 : height;
    const unsigned x1 = 40;
    const unsigned x2 = width  >  40 ? width  -  40 : width;
    for (unsigned y = y1; y < y2 && y < 576; y++) {
        volatile uint8_t *row = bm + (size_t) y * 192u;
        for (unsigned x = x1; x < x2 && x < 768; x++) {
            const unsigned sh = 6u - 2u * (x & 3u);
            row[x >> 2] = (uint8_t) (row[x >> 2] | (1u << sh));
        }
    }
}

/* SP7b — empreinte d'une région mappée, en LECTURE SEULE. Un mot sur `step`,
 * sur `words` mots. Renvoie (nombre de mots non nuls << 16) | hachage, de quoi
 * distinguer « rien écrit » de « écrit puis remis à zéro ». */
static uint32_t dd_fingerprint(const volatile uint32_t *p, unsigned words,
                               unsigned step)
{
    if (p == NULL)
        return 0;
    uint32_t h = 0, nz = 0;
    for (unsigned w = 0; w < words; w += step) {
        const uint32_t v = p[w];
        h = (h * 31u) ^ v;
        if (v != 0 && nz < 0xffff)
            nz++;
    }
    return (nz << 16) | (h & 0xffffu);
}

/* SP2 — pose un sous-titre de test dans le plan matériel et l'affiche.
 * Renvoie les codes de retour du driver dans rc[6] :
 *   0 EnableSP, 1 SetSPPalette, 2 ApplySPDCSQ, 3 SetSPBuffer, 4 ShowSPBuffer. */
/* ── Accès au PLAN de destination du blit subpicture ─────────────────────────
 * Base en ctx[0x204], pas de ligne en ctx[0x414] (cf. les champs lay_* et le
 * relevé des trois bundles dans dvddriver_open). Sur 10.2 le pas de ligne n'est
 * pas mémorisé par le pilote et suivre ctx[0x204] reviendrait à déréférencer ce
 * qui traîne à cet offset : ces deux accesseurs rendent alors NULL/0, et TOUT
 * déréférencement du plan doit passer par eux. Diagnostic uniquement — le
 * chemin d'incrustation, lui, n'en a pas besoin. */
static const volatile uint32_t *dd_sp_dest(dvddriver_ctx *ctx)
{
    if (ctx == NULL || ctx->dev_ctx == NULL || !ctx->lay_deref_ok)
        return NULL;
    /* ⚠ dd_ctx_u32 rend 0 si 0x204 sort du contexte — c'est CE cas qui compte :
     * suivre un mot pris hors du bloc reviendrait à déréférencer du tas voisin. */
    const uint32_t base = dd_ctx_u32(ctx, 0x204);
    return (const volatile uint32_t *) base;
}

static unsigned dd_sp_dest_pitch(dvddriver_ctx *ctx)
{
    if (ctx == NULL || ctx->dev_ctx == NULL)
        return 0;
    if (ctx->lay_mp_pitch != 0)
        return dd_ctx_u32(ctx, ctx->lay_mp_pitch);
    /* 10.2 ne mémorise pas le pas de ligne. OpenDevice, lui, rend les
     * dimensions de la destination : mesuré 0x300 = 768 et 0x240 = 576 sur ce
     * G3, soit exactement le « 720 arrondi à 64 » attendu pour 720x576. C'est
     * donc un repli légitime, et non une valeur inventée. */
    return ctx->open_dims[0];
}

bool dvddriver_sp_show_test(dvddriver_ctx *ctx, unsigned width, unsigned height,
                            int rc[6])
{
    if (ctx == NULL || !ctx->sp_available || ctx->dev_ctx == NULL)
        return false;
    /* ⚠ Le garde-fou « ctx+0x1FC != 0 » a été RETIRÉ : la trace du lecteur
     * d'Apple, EN PLEINE LECTURE AVEC SOUS-TITRES, montre ce mot à 0 comme chez
     * nous. Ce drapeau choisit entre deux implémentations, pas entre actif et
     * inerte. Ce qui a fait planter le driver la première fois, c'est un
     * PARAMÈTRE FAUX (adresse CPU passée là où il attend un offset), pas le
     * mode. Cf. sp-hardware-subtitles-plan.md SP4. */
    uint8_t *buf = (uint8_t *) ctx->sp_probe[0];
    if (buf == NULL)
        return false;

    /* palette : 16 entrées de 4 octets (0, Y, Cr, Cb). Index 2 = blanc,
     * index 3 = noir, les autres transparents via les contrastes. */
    uint8_t pal[64];
    memset(pal, 0, sizeof(pal));
    pal[2 * 4 + 1] = 0xeb; pal[2 * 4 + 2] = 0x80; pal[2 * 4 + 3] = 0x80;
    pal[3 * 4 + 1] = 0x10; pal[3 * 4 + 2] = 0x80; pal[3 * 4 + 3] = 0x80;

    /* bande en bas de l'image, sur toute la largeur */
    const int x1 = 0, x2 = (int) width - 1;
    const int y1 = (int) height - 100, y2 = (int) height - 40;

    /* ⚠ Le paquet est écrit dans le tampon dont l'adresse est reprise par le
     * driver LUI-MÊME (ctx[0x2D4 + 4*idx], seconde série rendue par
     * GetSPBuffer) : c'est celle qu'ApplySPDCSQ transmet à son moteur. On lui
     * passe donc un OFFSET dans ce tampon, jamais une adresse — c'est
     * l'erreur qui avait fait déréférencer n'importe quoi au driver. */
    /* ⚠ Adresses RELUES À CHAQUE FOIS, jamais celles mises en cache à
     * l'ouverture : elles changent d'une session à l'autre, et les réutiliser
     * en cours de lecture revient à écrire dans de la mémoire que le driver a
     * pu réaffecter — ce qui plante à l'appel suivant (mesuré : rejeu après
     * 100 images → crash dans DVDDriverSetFeatureParam+996).
     * Série b ([0x2D4]) : c'est celle qu'ApplySPDCSQ transmet à son moteur ;
     * écrire dans la série a écrase des structures du driver. */
    uint32_t bufs_a[8], bufs_b[8];
    memset(bufs_a, 0, sizeof(bufs_a));
    memset(bufs_b, 0, sizeof(bufs_b));
    if (ctx->GetSPBuffer == NULL
        || ctx->GetSPBuffer(ctx->dev_ctx, bufs_a, bufs_b) != 0)
        return false;
    uint8_t *sp = (uint8_t *) bufs_b[0];
    if (sp == NULL)
        return false;
    const uint32_t pkt_off = 0;                        /* paquet en tête        */
    size_t n = 0;
    /* Si un PAQUET RÉEL a été capturé chez le lecteur d'Apple (sptrace.c le
     * dépose dans /tmp/spu_real.bin), on le rejoue TEL QUEL : cela élimine tout
     * doute sur notre encodage (RLE, ordre des nibbles, en-tête). Sinon, repli
     * sur le paquet synthétique. */
    { FILE *f = fopen("/tmp/spu_real.bin", "rb");
      if (f) {
          n = fread(sp + pkt_off, 1, 0xE000, f);
          fclose(f);
      } }
    if (n == 0)
        n = dd_build_test_spu(sp + pkt_off, 0xE000, x1, y1, x2, y2, 2);
    if (n == 0)
        return false;
    const uint16_t dcsq_off = (uint16_t) ((sp[pkt_off + 2] << 8) | sp[pkt_off + 3]);

    /* ★ SP7 — GÉOMÉTRIE RÉSOLUE (désassemblage de la routine de blit, 0x37ac).
     * Le rectangle SP est un **Mac Rect** { top, left, bottom, right }, EXACTEMENT
     * comme celui du décodage (cf. `rect` de dvddriver_picture_submit). Nous lui
     * passions {x1,y1,x2,y2} : les deux axes étaient donc ÉCHANGÉS. Preuves :
     *   — ShowSPBuffer aligne rect[2] sur 16 vers le bas (1ae4 : rlwinm 0,0,0,0,27)
     *     avant de le ranger : c'est un alignement d'abscisse, donc rect[2] = left ;
     *   — SetMPRects range rect[6]−rect[2] en ctx[0x410] puis son arrondi à 64 en
     *     ctx[0x414] — et ctx[0x414] est le PAS DE LIGNE du blit (0x3874/0x39cc).
     *     Avec le rect de décodage {0,0,h,w}, ctx[0x414] = align64(largeur) = 768
     *     pour du 720 : un pas de ligne, pas une hauteur ;
     *   — la boucle EXTERNE du blit est bornée par rect[0]/rect[4] et multiplie par
     *     192 octets (source) et par ctx[0x414] (destination) → c'est l'ordonnée ;
     *     la boucle INTERNE, bornée par rect[2]/rect[6], avance de 4 pixels par
     *     octet source → c'est l'abscisse.
     * Modèle complet, désormais sans inconnue :
     *   source      = ctx[0x2F4 + 4*idx], bitmap 2 bits/pixel, 192 o/ligne
     *                 (768 px), 576 lignes — ShowSPBuffer le confirme en passant
     *                 (192, 576) et (64, 576) à son moteur (0x1918/0x1934) ;
     *   destination = ctx[0x204], pixels 32 bits ARGB, pas ctx[0x414] pixels ;
     *   correspondance = identité (dest[y][x] ← palette[source[y][x]]).
     * ⚠ Le rect transposé ne « décalait » pas seulement le rendu : avec
     * {0,0,719,575} la boucle externe parcourait 720 LIGNES au lieu de 576, soit
     * ~440 Ko écrits APRÈS la fin du plan ARGB. Écriture hors bornes dans de la
     * mémoire GPU — cause plausible des gels constatés. */
    int16_t rect[4] = { 0, 0, (int16_t) height, (int16_t) width };
    (void) x1; (void) y1; (void) x2; (void) y2;
    /* ⚠ SetSPBuffer, DANS NOTRE MODE (ctx[0x1FC]==0), ne lit PAS un simple rect
     * de 4 × int16 : il lit son 3e argument jusqu'à l'offset 0x1A. Disposition
     * imposée par le code (0x1e3c…0x1e7c) :
     *   [0x10] u16 ┐ empaquetés dans ctx[0x1DC] = (0x10 << 16) | 0x12
     *   [0x12] u16 ┘
     *   [0x14] u16 → ctx[0x1EC]      [0x16] u16 → ctx[0x1EE]
     *   [0x18] u16 → ctx[0x1F0]      [0x1A] u16 → ctx[0x1F2]
     * Lui passer 8 octets le faisait lire la PILE au-delà de notre tableau. */
    uint8_t spdesc[32];
    memset(spdesc, 0, sizeof(spdesc));
    /* ⚠ [0x10]/[0x12] ne sont PAS des dimensions : SetSPBuffer les empaquette
     * dans ctx[0x1DC], que la boucle du blit (0x3888) lit PAR QUARTETS —
     * 16 bits hauts = les quatre INDEX DE PALETTE, 16 bits bas = les quatre
     * CONTRASTES (alpha). C'est exactement ce que portent les commandes SPU
     * 0x03 (couleurs) et 0x04 (contrastes). Y mettre 720×576 revenait à
     * demander des couleurs arbitraires — d'où les traits blancs constatés.
     * Valeurs du paquet réel d'Apple : `03 22 37` et `04 f0 f0`. */
    { uint16_t *u = (uint16_t *) spdesc;
      /* ⚠ La boucle du blit (3888…38cc) lit le quartet i de CHAQUE moitié pour
       * bâtir l'entrée i de sa table : moitié HAUTE = index de palette, moitié
       * BASSE = contraste (alpha = n × 15, 15 → 255). Pour un test SANS
       * ambiguïté on met les quatre index sur l'entrée 2 (blanche) et on rend la
       * valeur 0 transparente, les autres opaques. (Les valeurs d'Apple
       * 0x2237/0xf0f0 rendaient les valeurs 0 ET 2 transparentes.) */
      u[0x10 / 2] = 0x2222;                /* index de palette, 4 × 4 bits   */
      u[0x12 / 2] = 0xfff0;                /* contrastes,       4 × 4 bits   */
      /* [0x14…0x1A] : SetSPBuffer les range en ctx[0x1EC]/[0x1EE]/[0x1F0]/[0x1F2]
       * (1e58…1e7c). Le blit ne relit que ctx[0x1EC] et ctx[0x1F0], et il les
       * compare à rect[0] et rect[4] — les ORDONNÉES (38e8/38fc) : ce sont donc
       * une borne HAUTE et une borne BASSE de découpe, pas une largeur. Même
       * transposition que le rect ci-dessus. On déclare l'image entière. */
      u[0x14 / 2] = 0;                        /* top    */
      u[0x16 / 2] = 0;                        /* left   */
      u[0x18 / 2] = (uint16_t) height;        /* bottom */
      u[0x1A / 2] = (uint16_t) width;  }      /* right  */
    /* ⚠ Bornes EXCLUSIVES, et MÊME convention Mac Rect que partout ailleurs :
     * SetMPRects range rect[4] − rect[0] (= la hauteur) en ctx[0x418] et
     * rect[6] − rect[2] (= la largeur) en ctx[0x410], puis l'arrondi à 64 de
     * cette largeur en ctx[0x414] — le PAS DE LIGNE du blit subpicture.
     * L'ancien {0,0,largeur,hauteur} annonçait donc au driver une image de
     * 576 × 720 et un pas de ligne de 576 au lieu de 768. */
    int16_t all[4]  = { 0, 0, (int16_t) height, (int16_t) width };

    /* ⚠ CONTRAT D'ApplySPDCSQ, établi en lisant un VRAI paquet posé par le
     * lecteur d'Apple (trace sptrace.c) : il applique UNE SEULE COMMANDE par
     * appel — `base` = offset de la commande dans le tampon, `off` = sa
     * LONGUEUR. C'est l'appelant qui parcourt la liste. (Relevé chez Apple :
     * base=0xdca off=1 pour `01`, off=3 pour `03 …`, off=7 pour `05 …`,
     * off=5 pour `06 …`.) Un appel unique avec l'offset de la table entière,
     * comme nous le faisions, ne veut rien dire pour le driver. */
    pthread_mutex_lock(&ctx->lock);
    /* ⚠ Le plan VIDÉO d'abord : c'est lui qui pose ctx[0x414], le pas de ligne
     * de la destination du blit. Sans lui ce pas vaut 0 (valeur d'OpenDevice,
     * 0x9bc) et toutes les lignes s'écrasent sur la première.
     * ⚠ MAIS : `DVDDriverDecode` appelle LUI-MÊME SetMPRects dès que le rect
     * soumis diffère de ctx[0x410]/[0x418] (2538…2574) — en lecture, la
     * géométrie est donc déjà posée, et rejouer SetMPRects relance ses memset
     * et ses appels IOKit sous le décodeur. On ne l'appelle donc QUE si le pas
     * de ligne n'est pas encore établi (cas de la sonde à l'ouverture). */
    if (dd_ctx_u32(ctx, 0x414) == 0 && ctx->SetMPRects)
        ctx->SetMPRects(ctx->dev_ctx, all, 0, 0);
    if (ctx->EnableMP)   ctx->EnableMP(ctx->dev_ctx, 1);
    /* ★ SP7 — ORDRE CORRIGÉ. La séquence d'Apple (trace sptrace.c) est un FLUX
     * APLATI sur toute une session : elle mélange les tampons (ApplySPDCSQ sur
     * l'index 1 pendant qu'on affiche le 0). La causalité par tampon, elle, est
     * imposée par le code du driver et va dans l'autre sens que ce que nous
     * faisions :
     *   1. `ApplySPDCSQ(idx, …)` décode le RLE dans le bitmap du tampon idx ;
     *   2. `SetSPBuffer(idx, desc)` pose couleurs/découpe, met le drapeau
     *      « à redessiner » ctx[0x1D0] = 1 (1e54) PUIS APPELLE LE BLIT (1e80) ;
     *   3. `ShowSPBuffer(idx, rect)` range le rect, rappelle le blit SI le
     *      drapeau est encore posé (1b08…1b1c), et fait l'affichage IOKit.
     * Or le blit REMET CE DRAPEAU À ZÉRO en sortie (3ad0). Enchaîner
     * SetSPBuffer AVANT ApplySPDCSQ, comme nous le faisions, blitte donc un
     * bitmap encore vide et consomme le drapeau : au rejeu suivant, ShowSPBuffer
     * ne redessine plus rien. Cela n'a fonctionné en SP6 que par accident — le
     * rect étant nul à ce stade, le blit sortait par son contrôle de validité
     * (3844…386c) sans atteindre la remise à zéro.
     * D'où l'ordre ci-dessous : armer → poser le rect → palette → DÉCODER →
     * SetSPBuffer (c'est LUI qui dessine) → afficher. */
    if (ctx->EnableSP)     ctx->EnableSP(ctx->dev_ctx, 0);
    if (ctx->ClearSP)      ctx->ClearSP(ctx->dev_ctx, 7);
    rc[0] = ctx->EnableSP     ? ctx->EnableSP(ctx->dev_ctx, 1)       : -999;
    /* ⚠ APRÈS EnableSP(1), sans quoi c'est un coup dans l'eau : en mode
     * ctx[0x1FC]==0, ShowSPBuffer sort immédiatement quand ctx[0x1C8] (posé par
     * EnableSP, 1218) est nul (1ac4) — et le rect n'est alors jamais rangé. */
    if (ctx->ShowSPBuffer) ctx->ShowSPBuffer(ctx->dev_ctx, 0, rect);
    rc[1] = ctx->SetSPPalette ? ctx->SetSPPalette(ctx->dev_ctx, pal) : -999;
    if (ctx->ClearSP)      ctx->ClearSP(ctx->dev_ctx, 0);
    /* SP7b — relevés par étape. Source = le bitmap 2 bits/pixel de la série a
     * (192 o × 576 lignes = 0x1B000), destination = ctx[0x204]. */
    {
        const volatile uint32_t *src = (const volatile uint32_t *) bufs_a[0];
        const volatile uint32_t *dst = dd_sp_dest(ctx);
        ctx->sp_stage[0] = dd_fingerprint(src, 0x1B000 / 4, 4);
        ctx->sp_stage[2] = dd_fingerprint(dst, 0x40000 / 4, 4);
        ctx->sp_stage_valid = 1;
    }
    /* Parcours de la séquence de commandes : délai (2 o) + DCSQ suivante (2 o),
     * puis les commandes jusqu'à 0xff. Longueurs SPU : 00/01/02 = 1 octet,
     * 03/04 = 3, 05 = 7, 06 = 5. */
    rc[2] = 0;
    {
        unsigned pos = dcsq_off + 4;
        int guard = 0;
        while (pos < n && guard++ < 32) {
            const uint8_t cmd = sp[pos];
            unsigned len;
            switch (cmd) {
                case 0x00: case 0x01: case 0x02: len = 1; break;
                case 0x03: case 0x04: len = 3; break;
                case 0x05:            len = 7; break;
                case 0x06:            len = 5; break;
                default:              len = 0; break;   /* 0xff : fin */
            }
            if (len == 0)
                break;
            if (ctx->ApplySPDCSQ) {
                int r = ctx->ApplySPDCSQ(ctx->dev_ctx, 0,
                                         (const void *) (unsigned long) pos, len);
                if (r != 0)
                    rc[2] = r;
            }
            pos += len;
        }
    }
    /* ★ SP8 — c'est NOUS qui produisons le bitmap 2 bits/pixel : en mode
     * surface, le driver ne décode pas le RLE (cf. dd_write_test_bitmap). */
    dd_write_test_bitmap((volatile uint8_t *) bufs_a[0], width, height);
    /* Le bitmap est décodé : SetSPBuffer arme le drapeau et déclenche le blit. */
    ctx->sp_stage[1] = dd_fingerprint((const volatile uint32_t *) bufs_a[0],
                                      0x1B000 / 4, 4);
    rc[3] = ctx->SetSPBuffer  ? ctx->SetSPBuffer(ctx->dev_ctx, 0, spdesc) : -999;
    ctx->sp_stage[3] = dd_fingerprint(dd_sp_dest(ctx), 0x40000 / 4, 4);
    ctx->sp_stage[5] = dd_ctx_u32(ctx, 0x1D0);
    rc[4] = ctx->ShowSPBuffer ? ctx->ShowSPBuffer(ctx->dev_ctx, 0, rect) : -999;
    ctx->sp_stage[4] = dd_fingerprint(dd_sp_dest(ctx), 0x40000 / 4, 4);
    rc[5] = (int) n;
    for (int i = 0; i < 4; i++)
        ctx->sp_rect[i] = rect[i];
    pthread_mutex_unlock(&ctx->lock);
    return true;
}

/* Mots de contexte gouvernant le plan SP (diagnostic). */
/* Sorties d'OpenDevice : [0] caps, [1..4] dims, [5] five, [6] eight. */
bool dvddriver_open_outputs(dvddriver_ctx *ctx, uint32_t out[7])
{
    if (ctx == NULL)
        return false;
    out[0] = ctx->open_caps;
    for (int i = 0; i < 4; i++) out[1 + i] = ctx->open_dims[i];
    out[5] = ctx->open_five;
    out[6] = ctx->open_eight;
    return true;
}

bool dvddriver_sp_state(dvddriver_ctx *ctx, uint32_t out[5])
{
    if (ctx == NULL || !ctx->sp_available)
        return false;
    out[0] = ctx->sp_mode_flag;
    out[1] = ctx->sp_ctx_word0;
    out[2] = ctx->sp_cur_buf;
    out[3] = ctx->sp_enable_st;
    out[4] = ctx->sp_caps;
    return true;
}

/* Réaffiche l'incrustation déjà montée (ShowSPBuffer seul, sans reconstruire).
 * ⚠ À N'APPELER QUE DE FAÇON ESPACÉE (au plus quelques fois par seconde) et
 * jamais sur le chemin de present : des appels driver répétés à la cadence des
 * images ont figé la machine. */
/* Destination du blit subpicture (ctx[0x204]) — lecture seule. Nulle chez nous
 * jusqu'ici : c'est ce qui fait échouer l'incrustation. On veut savoir si elle
 * se renseigne à un moment du cycle (après un Decode, après un Show…). */
/* SP5c — relevés avant/après Show : out[i][0..3] = avant, out[i][4..7] = après. */
int dvddriver_sp_dest_probes(dvddriver_ctx *ctx, uint32_t out[3][8])
{
    if (ctx == NULL)
        return 0;
    int i, w;
    for (i = 0; i < ctx->sp_dest_probes && i < 3; i++)
        for (w = 0; w < 4; w++) {
            out[i][w]     = ctx->sp_dest_before[i][w];
            out[i][4 + w] = ctx->sp_dest_after[i][w];
        }
    return ctx->sp_dest_probes;
}

/* ════════════════════════════════════════════════════════════════════════════
 * SP4 — exploitation réelle : les paquets SPU du disque, incrustés par le GPU
 * ════════════════════════════════════════════════════════════════════════════
 * Le module « spu decoder » (dvddriver_spu.c) décode le RLE et remet ici un
 * bitmap 2 bits/pixel déjà au format du driver. Ce qui suit ne fait que le
 * poser dans le plan matériel — aucune analyse de paquet.
 *
 * ⚠ RÈGLES DE SÛRETÉ tenues par cette couche :
 *   — un montage par SOUS-TITRE (quelques-uns par minute), jamais par image ;
 *   — armement (EnableSP + palette) une seule fois, pas à chaque incrustation ;
 *   — cadence PLAFONNÉE (dd_sp_rate_ok) : deux montages ne peuvent pas être
 *     plus rapprochés que 100 ms, quoi qu'envoie le flux. Un disque au DCSQ
 *     pathologique ne peut donc pas dégénérer en appels par image, ce qui est
 *     exactement ce qui a figé la machine le 2026-07-22.
 */

/* Compte les pixels opaques du plan ARGB (lecture seule, un mot sur deux).
 * ⚠ Il faut balayer TOUT le plan : une empreinte sur les premiers 256 Ko ne
 * couvre que les ~85 premières lignes, où il n'y a que du fond — elle vaut 0
 * même quand l'incrustation est parfaite. */
static uint32_t dd_sp_plane_opaque(dvddriver_ctx *ctx)
{
    const volatile uint32_t *pl  = dd_sp_dest(ctx);
    const unsigned pitch = dd_sp_dest_pitch(ctx);
    if (pl == NULL || pitch == 0)
        return 0;
    uint32_t n = 0;
    const unsigned words = pitch * ctx->height;
    for (unsigned w = 0; w < words; w += 2)
        if ((pl[w] >> 24) != 0)
            n++;
    return n;
}

/* ★ SP9 — pose le DRAPEAU D'AFFICHAGE du subpicture, `ctx[0x1C4]`.
 * C'est la pièce qui manquait, et le désassemblage est sans ambiguïté :
 *
 *   DVDDriverShowMPBuffer, branche ctx[0x1FC]==0 (la nôtre) :
 *     1070: bl 0x36a8      ré-expansion du subpicture à CHAQUE image
 *     1074: lwz 0, 452(30) ctx[0x1C4]
 *     107c: bt 30, 0x1098  si nul → SAUTE l'affichage
 *     1080: lwz 0, 456(30) ctx[0x1C8] (posé par EnableSP)
 *     1094: bl 0x41d8      ← seulement si les DEUX sont non nuls
 *
 * Et `ctx[0x1C4]` n'est écrit QUE par le moteur d'ApplySPDCSQ, sur les commandes
 * SPU 0x00/0x01 (`79bc`, `79d8` : = 1) et 0x02 (`7a04` : = 0). Je les avais
 * classées « sortie immédiate en mode surface » : c'est vrai de leur TRAVAIL
 * d'overlay, mais elles posent le drapeau AVANT de sortir. Sans lui, on peut
 * remplir le plan parfaitement — ce que nous faisions — sans que rien ne soit
 * jamais affiché.
 *
 * `ApplySPDCSQ(ctx, idx, base, len)` lit l'octet de commande à `base` dans le
 * tampon de la série b (ctx[0x2D4 + 4*idx]) : il suffit d'y écrire un octet.
 * `cmd` = 0x01 pour afficher, 0x02 pour masquer. Appelé sous le verrou. */
static bool dd_sp_set_display(dvddriver_ctx *ctx, const uint32_t bufs_b[8],
                              int idx, uint8_t cmd)
{
    if (ctx->ApplySPDCSQ == NULL)
        return false;
    uint8_t *pkt = (uint8_t *) bufs_b[idx];
    if (pkt == NULL)
        return false;

    /* ★★★ L'OPACITÉ NE VIENT PAS DE LA PALETTE — elle vient de `SET_CONTR`.
     * La palette du pilote est { 00, Y, Cb, Cr } : elle ne porte AUCUN alpha.
     * Sans la commande SPU 0x04, tout le plan est transparent : parfaitement
     * rempli et parfaitement invisible (des heures perdues là-dessus).
     * `ApplySPDCSQ` applique UNE COMMANDE PAR APPEL — arg3 = offset de la
     * commande dans le tampon, arg4 = sa longueur. On envoie donc, à
     * l'affichage : SET_COLOR (indices de palette) puis SET_CONTR (contraste)
     * avant STA_DSP. Séquence validée à l'écran sur le Rage 128. */
    if (cmd == 0x01) {
        /* ⚠ Les VRAIES valeurs du sous-titre, pas des constantes : figer
         * SET_COLOR à 0x2222 donnait la même entrée de palette au texte et à son
         * fond — parfait pour une mire uniforme, invisible pour un sous-titre. */
        const uint16_t col = ctx->sp_cmd_colors;
        const uint16_t con = ctx->sp_cmd_contrasts;
        pkt[0] = 0x03; pkt[1] = (uint8_t)(col >> 8); pkt[2] = (uint8_t) col;
        ctx->ApplySPDCSQ(ctx->dev_ctx, (uint32_t) idx, (const void *) 0, 3);
        pkt[3] = 0x04; pkt[4] = (uint8_t)(con >> 8); pkt[5] = (uint8_t) con;
        ctx->ApplySPDCSQ(ctx->dev_ctx, (uint32_t) idx, (const void *) 3, 3);
        pkt[6] = 0x01;                                  /* STA_DSP */
        ctx->ApplySPDCSQ(ctx->dev_ctx, (uint32_t) idx, (const void *) 6, 1);
        return true;
    }
    pkt[0] = cmd;
    ctx->ApplySPDCSQ(ctx->dev_ctx, (uint32_t) idx, (const void *) 0, 1);
    return true;
}

/* Plafond de cadence : true si un montage est permis maintenant. */
static bool dd_sp_rate_ok(dvddriver_ctx *ctx)
{
    static const int64_t MIN_GAP_US = 100000;   /* 10 montages/s au maximum */
    const int64_t now = (int64_t) dd_now_us();
    if (ctx->sp_last_apply_us != 0 && now - ctx->sp_last_apply_us < MIN_GAP_US)
        return false;
    ctx->sp_last_apply_us = now;
    return true;
}

/* Arme le plan SP : EnableSP(1) + palette. Idempotent. Appelé sous le verrou. */
static bool dd_sp_arm(dvddriver_ctx *ctx, const uint8_t palette[64])
{
    if (ctx->EnableSP == NULL || ctx->SetSPPalette == NULL)
        return false;
    /* ⚠ ARMEMENT UNE SEULE FOIS. Testé et RÉFUTÉ : réarmer à chaque sous-titre
     * (EnableSP(0) → ClearSP(7) → EnableSP(1)) fait TOMBER la visibilité à zéro
     * — le EnableSP(0) de tête désactive le plan et rien ne le rétablit
     * durablement. Mesure : 0 capture sur 12 avec réarmement, contre 1 sur 18
     * sans. Ne pas y revenir. */
    /* ⚠ ARMEMENT UNE SEULE FOIS. Deux variantes testées et RÉFUTÉES :
     *   — réarmer la séquence COMPLÈTE (EnableSP(0) → ClearSP(7) → EnableSP(1))
     *     à chaque sous-titre fait tomber la visibilité à 0 sur 12 : le
     *     `EnableSP(0)` de tête désactive le plan ;
     *   — `EnableSP(1)` seul à chaque sous-titre ne change rien (1 sur 12,
     *     comme sans).
     * On garde donc le plus simple. */
    if (!ctx->sp_armed) {
        ctx->EnableSP(ctx->dev_ctx, 0);
        if (ctx->ClearSP) ctx->ClearSP(ctx->dev_ctx, 7);
        if (ctx->EnableSP(ctx->dev_ctx, 1) != 0)
            return false;
        /* ⚠⚠ PAS D'EnableButton ICI — piège inversé, deux fois de suite.
         * La trace du DVD Player d'Apple le montre : pendant TOUTE la séquence
         * d'un sous-titre, `ctx[0x1D8]` vaut ZÉRO. Le blit du sous-titre part du
         * chemin `ctx[0x1D0]` (0x2190), le drapeau qu'arme `SetSPBuffer`, et il
         * est appelé avec l'argument 0 — lequel sélectionne le rect du PLAN
         * (ctx+0x1E4) et le mot couleurs `ctx[0x1DC]`. L'argument 1 sélectionne
         * le rect du BOUTON (ctx+0x1F4) et `ctx[0x1E0]` : c'est la SURBRILLANCE
         * DE MENU. Armer le bouton détourne donc ShowSPBuffer vers la mauvaise
         * branche. `PrepareButton`/`EnableButton` ne servent qu'aux menus — la
         * trace le confirme (rect 270,312→327,436, soit un bouton). */
        ctx->sp_armed = true;
    }
    /* La palette peut changer d'un sous-titre à l'autre (menus, pistes). */
    ctx->SetSPPalette(ctx->dev_ctx, palette);
    return true;
}

bool dvddriver_sp_usable(dvddriver_ctx *ctx)
{
    return ctx != NULL && ctx->sp_available && ctx->dev_ctx != NULL
        && ctx->GetSPBuffer && ctx->SetSPBuffer && ctx->ShowSPBuffer
        && ctx->SetSPPalette && ctx->EnableSP;
}

bool dvddriver_sp_submit(dvddriver_ctx *ctx, const dvddriver_sp_picture *sp,
                         uint32_t probes[8])
{
    if (probes != NULL)
        for (int k = 0; k < 8; k++) probes[k] = 0;
    if (!dvddriver_sp_usable(ctx) || sp == NULL || sp->bitmap == NULL)
        return false;
    if (sp->lines == 0 || sp->lines > 576)
        return false;

    pthread_mutex_lock(&ctx->lock);
    dd_wait_gpu_idle_locked(ctx);
    if (!dd_sp_rate_ok(ctx)) {
        ctx->sp_dropped++;
        pthread_mutex_unlock(&ctx->lock);
        return false;               /* cadence plafonnée : on laisse tomber */
    }

    /* ⚠ Adresses RELUES à chaque fois : elles changent d'une session à l'autre,
     * et réutiliser une adresse mise en cache revient à écrire dans de la
     * mémoire que le driver a pu réaffecter (plantage mesuré). */
    uint32_t bufs_a[8], bufs_b[8];
    memset(bufs_a, 0, sizeof(bufs_a));
    memset(bufs_b, 0, sizeof(bufs_b));
    if (ctx->GetSPBuffer(ctx->dev_ctx, bufs_a, bufs_b) != 0) {
        pthread_mutex_unlock(&ctx->lock);
        return false;
    }
    /* ★ ROTATION DES TAMPONS — rétablie, et cette fois pour une raison lue dans
     * le code. `ShowSPBuffer` bascule deux marqueurs (`ctx[0x338]`/`ctx[0x33C]`)
     * UNIQUEMENT quand son index diffère de `ctx[0x1B0]`, celui du dernier
     * `SetSPBuffer` (0x1858…0x188c) ; avec un index fixe ils ne basculent
     * jamais. Le lecteur d'Apple fait tourner ses tampons (0, 1, 2… relevé en
     * SP3). Symptôme que cela expliquerait : le plan contient le bon
     * sous-titre après CHAQUE incrustation, mais l'écran n'en montre qu'une.
     * ⚠ Une première tentative de rotation avait été jugée nocive — mesure
     * faite AVANT la découverte du drapeau d'affichage `ctx[0x1C4]` (SP9),
     * donc sur un chemin qui n'affichait de toute façon rien. Réfutation
     * caduque. */
    /* ★ DONNÉES TOUJOURS SUR LE TAMPON 0, INDEX D'AFFICHAGE TOURNANT.
     * Deux mesures se combinent ici :
     *   — en rotation complète, le blit ne produit rien pour certains tampons
     *     (mesuré : #2 et #3 vides, #1 et #4 pleins) ; le tampon 0, lui, blitte
     *     TOUJOURS ;
     *   — mais l'écran ne se met à jour que si `ShowSPBuffer` reçoit un index
     *     différent de `ctx[0x1B0]` : c'est la seule condition qui fait basculer
     *     `ctx[0x338]`/`ctx[0x33C]` (0x1858…0x188c). Index fixe = jamais de
     *     bascule = une seule incrustation visible.
     * On garde donc les DONNÉES sur le tampon 0 et on fait tourner le seul
     * index passé au ShowSPBuffer final. Ce dernier ne re-blitte pas (le
     * drapeau `ctx[0x1D0]` a déjà été consommé par SetSPBuffer, 0x1b10) : il ne
     * fait que basculer les marqueurs et lancer l'affichage. */
    const int idx = ctx->sp_next_buf & 7;
    const int show_idx = idx;
    ctx->sp_next_buf++;
    uint8_t *dst = (uint8_t *) bufs_a[idx];
    if (dst == NULL) {
        pthread_mutex_unlock(&ctx->lock);
        return false;
    }

    { static int g = -1;
      if (g < 0) { FILE *f = fopen("/tmp/hw_sp_mprects", "r");
                   g = f ? (fclose(f), 1) : 0; }
      ctx->sp_force_mprects = (g > 0); }
    { static int g = -1;
      if (g < 0) { FILE *f = fopen("/tmp/hw_sp_band", "r");
                   g = f ? (fclose(f), 1) : 0; }
      ctx->sp_test_band = (g > 0); }
    bool sp_solid;
    { static int g = -1;
      if (g < 0) g = (dd_gate_read("/tmp/hw_sp_solid") > 0);
      sp_solid = (g > 0); }

    /* Pour la bande d'essai — et pour le tout-ou-rien /tmp/hw_sp_solid —
     * reproduire AUSSI la palette de SP8 (entrée 2 blanche) : sinon l'index 2
     * pointerait une couleur quelconque du disque et l'A/B testerait deux
     * choses à la fois. */
    uint8_t pal_band[64];
    if (ctx->sp_test_band || sp_solid) {
        memset(pal_band, 0, sizeof(pal_band));
        pal_band[2 * 4 + 1] = 0xeb; pal_band[2 * 4 + 2] = 0x80;
        pal_band[2 * 4 + 3] = 0x80;
    }
    if (!dd_sp_arm(ctx, (ctx->sp_test_band || sp_solid) ? pal_band
                                                        : sp->palette)) {
        pthread_mutex_unlock(&ctx->lock);
        return false;
    }

    /* Mise au point — /tmp/hw_sp_band : remplace le sous-titre par la BANDE
     * pleine de SP8 (valeur 1 partout, couleurs 0x2222, contrastes 0xfff0), en
     * empruntant exactement ce chemin-ci. C'est le seul A/B qui sépare « le
     * contenu du sous-titre est en cause » de « la composition n'a pas lieu en
     * cours de lecture » : SP8 était visible, mais il tournait AVANT le premier
     * Decode. Une seule variable change ici : le contenu. */
    /* Le bitmap arrive déjà au pas du driver (192 o/ligne) : copie directe.
     * Les lignes au-delà sont mises à zéro (= valeur 0 = transparente). */
    /* Le bitmap 2 bits/pixel va TOUJOURS dans la série a : c'est la SOURCE que
     * lit le blit (`r29 = a[idx] + ligne × 192`, 0x404c…0x40b0). Le pilote ne
     * décode PAS le RLE, sur 10.2 pas plus que sur 10.4.
     * ⚠ J'ai cru le contraire un moment, en voyant `a[idx]` à zéro sur ses 64
     * PREMIERS OCTETS dans la trace du DVD Player — c'est le faux négatif que ce
     * fichier documente déjà deux fois : les premières lignes d'un sous-titre
     * sont transparentes, donc nulles. Ne pas s'y reprendre. */
    ctx->sp_cmd_colors    = sp->colors;
    ctx->sp_cmd_contrasts = sp->contrasts;
    memcpy(dst, sp->bitmap, (size_t) sp->lines * 192u);

    /* ⚠ DIAGNOSTIC /tmp/hw_sp_solid : remplacer le sous-titre par le motif EXACT
     * du harnais (plan ENTIER d'index 2, palette entrée 2 blanche — armée plus
     * haut —, couleurs 0x2222, contraste opaque). Isole « le chemin d'affichage
     * marche dans VLC » de « c'est le contenu ou les paramètres du sous-titre
     * qui ne conviennent pas » : si l'écran devient blanc, le chemin est bon et
     * le problème est dans le bitmap/les commandes. Le plan est rempli sur ses
     * 576 lignes pour rester visible même si la géométrie diverge. */
    if (sp_solid) {
        memset(dst, 0xAA, 576u * 192u);
        ctx->sp_cmd_colors    = 0x2222;
        ctx->sp_cmd_contrasts = 0xffff;
    }

    /* ⚠ DIAGNOSTIC /tmp/hw_sp_band — 3 BANDES pour isoler EN UN RUN ce qui
     * distingue le motif solid (VISIBLE, validé) du vrai sous-titre (invisible) :
     *   bande A : pixels valeur 1, lignes  60-120 (haut — la valeur du TEXTE réel)
     *   bande B : pixels valeur 2, lignes 160-220 (haut — la valeur du solid)
     *   bande C : pixels valeur 2, lignes 440-500 (bas — là où vit un vrai
     *             sous-titre ; teste « le matériel ne lit que les 288 premières
     *             lignes de chaque tampon de champ »)
     * Lecture du résultat : A+B+C = le bitmap/valeurs passent, chercher côté
     * couleurs/palette réelles ; A+B sans C = demi-tampon par champ ;
     * B+C sans A = la valeur 1 (empaquetage de bits) est en cause.
     * Couleurs 0x2220 (1→2, 2→2, 3→2 ; entrée 2 = blanc de pal_band),
     * contrastes 0xFFF0 (fond transparent, le reste opaque). Doit être écrit ICI,
     * AVANT la copie du champ 1, pour atteindre les deux champs. */
    if (ctx->sp_test_band) {
        /* ★ MIRE D'ADRESSAGE HORIZONTAL — remplace les bandes pleines, qui ne
         * disaient rien sur la transformation subie. Trois barres à des
         * positions CONNUES et ASYMÉTRIQUES ; leur place à l'écran donne la
         * correspondance exacte, au lieu de l'inférer d'un texte illisible :
         *   ligne 100-160 : bloc tout à GAUCHE   (x 0..63)
         *   ligne 220-280 : bloc au CENTRE-gauche (x 352..415)
         *   ligne 340-400 : deux petits blocs de 16 px espacés de 16 px
         *                   (x 0..15 et x 32..47) — détecte un retournement
         *                   LOCAL (par mot de 32 bits = 16 pixels), invisible
         *                   sur un bloc large.
         * Le plan fait 768 px de large (192 o × 4 px), l'image 720. */
        memset(dst, 0, 576u * 192u);
        struct { unsigned y0, y1, x0, x1; } marks[4] = {
            { 100, 160,   0,  64 },
            { 220, 280, 352, 416 },
            { 340, 400,   0,  16 },
            { 340, 400,  32,  48 },
        };
        for (int m = 0; m < 4; m++)
            for (unsigned y = marks[m].y0; y < marks[m].y1; y++) {
                uint8_t *row = dst + (size_t) y * 192u;
                for (unsigned x = marks[m].x0; x < marks[m].x1; x++)
                    row[x >> 2] = (uint8_t) (row[x >> 2]
                                    | (2u << (6 - 2 * (x & 3))));
            }
        ctx->sp_cmd_colors    = 0x2220;
        ctx->sp_cmd_contrasts = 0xfff0;
    }

    /* ⚠⚠⚠ NE RIEN ÉCRIRE DANS LA SÉRIE ctx[0x1A8+4i] — ce N'EST PAS un second
     * champ, et y recopier le plan la DÉBORDE de 72 Ko.
     * Tranché par `ClearSP`, qui donne la taille exacte des deux tampons :
     *     memset(ctx[0x188+4i], 0,    0x1B000)   = 192 o × 576 lignes
     *     memset(ctx[0x1A8+4i], 0xFF, 0x9000)    = 192 o × 192 lignes
     * et confirmé par le descripteur IOKit (sel=6) que le blit soumet pour
     * chacun : {…, 192, 576, …} contre {…, 192, 192, …}. Le plan de pixels est
     * donc PROGRESSIF, plein cadre, un seul tampon ; le second est un plan
     * distinct trois fois plus petit, que le pilote initialise à 0xFF et dont
     * nous n'avons pas l'usage.
     * Les trois séries sont contiguës en mémoire (0x1535000 / 0x1550000 /
     * 0x1559000, relevé live) : les 0x1B000 octets que nous y écrivions
     * écrasaient ce plan ENTIER, puis le tampon de commandes DCSQ, puis les
     * tampons des index suivants. C'était la cause des sous-titres illisibles —
     * lignes fines, décalées, franges vertes (photo du 2026-08-04). Le motif
     * uniforme du gate `hw_sp_solid` y survivait, lui, parce qu'il écrasait tout
     * avec le même octet : d'où « le plan s'affiche » et « le sous-titre non ».
     * ⚠ Ne pas se fier à un test uniforme pour valider un ADRESSAGE. */

    /* ★★★★ 10.2 — EN PLUS, LE PAQUET SPU BRUT DANS LA SÉRIE b.
     * Relevé sur le DVD Player (relais journalisant) : il y dépose le paquet
     * complet, en-tête compris (`04 f8 04 e0` = taille 0x04f8, 1re DCSQ 0x04e0).
     * Le blit de ce pilote l'ANALYSE pour en tirer la ligne de départ
     * (`ctx[0x1B4]`) : nous n'y écrivions qu'un octet, et sa boucle balayait de
     * la mémoire non initialisée. Sur 10.3/10.4 rien de tel n'est nécessaire —
     * leur `SetSPBuffer` blitte directement depuis le descripteur. */
    bool b_raw = false;
    if (ctx->lay_sp_stub && sp->packet != NULL && sp->packet_size > 0
        && bufs_b[idx] != 0) {
        memcpy((uint8_t *) bufs_b[idx], sp->packet, sp->packet_size);
        b_raw = true;
    }
    if (!sp_solid && sp->lines < 576)
        memset(dst + (size_t) sp->lines * 192u, 0,
               (576u - sp->lines) * 192u);

    /* (Pas de dés-entrelacement : le plan est progressif — cf. la note sur la
     * série 0x1A8 ci-dessus. Une tentative de découpe en deux champs a été
     * faite puis retirée le 2026-08-04, elle partait du contresens ci-dessus.) */

    /* ★★★ ORDRE DES PIXELS (familles `sp_swap_words`, Rage 128) — le moteur 2D
     * lit le plan SP par mots de 32 bits RETOURNÉS : les 16 pixels d'un mot
     * sortent dans l'ordre inverse. On pré-applique donc le retournement
     * complet — octets inversés dans le mot ET les 4 pixels inversés dans
     * chaque octet.
     * ⚠ Les deux moitiés sont nécessaires, et c'est ce qui a coûté deux essais :
     * n'inverser que les octets remet les mots et les lettres à leur place mais
     * laisse chaque lettre hachée par groupes de 4 pixels (« presque lisible »).
     * ⚠⚠ Établi à l'écran après avoir ÉLIMINÉ le miroir de ligne : une mire de
     * repères asymétriques (gate /tmp/hw_sp_band) tombe exactement à sa place,
     * donc l'adressage global est bon. Attention, cette mire ne discrimine PAS à
     * elle seule — tout bloc de 16 px ou plus est invariant par ce retournement,
     * comme un aplat l'est par n'importe quel adressage. Seul du VRAI texte
     * tranche : c'est la leçon de toute cette campagne. */
    if (ctx->sp_swap_words) {
        static uint8_t rev2[256];
        static bool rev2_ready = false;
        if (!rev2_ready) {
            for (unsigned b = 0; b < 256; b++)
                rev2[b] = (uint8_t) (((b & 0x03u) << 6) | ((b & 0x0Cu) << 2)
                                   | ((b & 0x30u) >> 2) | ((b & 0xC0u) >> 6));
            rev2_ready = true;
        }
        for (unsigned y = 0; y < 576; y++) {
            uint8_t *row = dst + (size_t) y * 192u;
            for (unsigned i = 0; i < 192u; i += 4) {
                const uint8_t b0 = row[i], b1 = row[i + 1];
                row[i]     = rev2[row[i + 3]];
                row[i + 1] = rev2[row[i + 2]];
                row[i + 2] = rev2[b1];
                row[i + 3] = rev2[b0];
            }
        }
    }

    /* Descripteur de 28 octets — cf. SP6/SP7 : [0x10] index de palette et
     * [0x12] contrastes (un quartet par valeur de pixel), [0x14…0x1A] découpe
     * verticale/horizontale en Rect Carbon. */

    uint8_t spdesc[32];
    memset(spdesc, 0, sizeof(spdesc));
    { uint16_t *u = (uint16_t *) spdesc;
      u[0x10 / 2] = ctx->sp_test_band ? 0x2220 : sp->colors;
      u[0x12 / 2] = ctx->sp_test_band ? 0xfff0 : sp->contrasts;
      u[0x14 / 2] = 0;
      u[0x16 / 2] = 0;
      u[0x18 / 2] = (uint16_t) ctx->height;
      u[0x1A / 2] = (uint16_t) ctx->width; }

    /* Le bitmap porte déjà les coordonnées absolues du sous-titre : on couvre
     * l'image entière et on laisse la transparence faire le placement. C'est
     * la configuration validée en SP7/SP8. */
    int16_t rect[4] = { 0, 0, (int16_t) ctx->height, (int16_t) ctx->width };

    /* Le pilote de 10.3/10.4 mémorise le pas de ligne de la destination du blit
     * en ctx[0x414] : on ne (re)joue SetMPRects que s'il n'est pas encore posé,
     * ce qui en lecture n'arrive jamais — `DVDDriverDecode` établit la géométrie
     * lui-même dès que le rect soumis change.
     * ⚠⚠ SUR 10.2 ON N'Y TOUCHE PAS DU TOUT. Ce pilote ne mémorise rien, donc
     * on ne peut PAS savoir si la géométrie est déjà posée ; l'appeler « une
     * fois par session » a été essayé le 2026-07-29 et RÉGRESSE : ce rect plein
     * cadre écrase la destination établie par le décodeur — la vidéo se
     * DÉPLACE de quelques pixels vers le bas au premier sous-titre (fenêtré
     * comme plein écran) et le plan subpicture cesse d'afficher. SetMPRects ne
     * pose pas que des dimensions : il écrit ctx[0x18] et fait un appel IOKit
     * avec le rectangle. Ne pas y revenir sans un moyen de LIRE l'état. */
    if (ctx->SetMPRects && ctx->lay_mp_pitch != 0) {
        if (dd_ctx_u32(ctx, ctx->lay_mp_pitch) == 0)
            ctx->SetMPRects(ctx->dev_ctx, rect, 0, 0);
    }
    /* Empreintes par étape (lecture seule) — c'est ce qui a permis d'isoler
     * l'étape muette en SP8, plutôt que de conclure d'un silence global :
     *   [0] la SOURCE que nous venons d'écrire (0 ⇒ notre RLE n'a rien produit)
     *   [1]/[2] la DESTINATION avant/après le blit (identiques ⇒ le blit ne
     *   s'exécute pas dans ce contexte). */
    if (probes != NULL) {
        probes[4] = ctx->lay_deref_ok ? dd_ctx_u32(ctx, 0x204) : 0;
        /* Empreinte de la SOURCE telle qu'on vient de l'écrire, et mot
         * couleurs/contrastes tel que SetSPBuffer va le recevoir : si la source
         * est pleine et le mot correct alors que le blit ne produit rien, la
         * faute est dans le driver ; sinon elle est chez nous. */
        probes[3] = dd_fingerprint((const volatile uint32_t *) dst,
                                   0x1B000 / 4, 4);
        probes[6] = ((uint32_t) sp->colors << 16) | sp->contrasts;
        /* État du plan AVANT notre blit : dit si ce que nous y avons mis au
         * sous-titre précédent y est encore, ou si quelque chose l'efface. */
        probes[1] = dd_sp_plane_opaque(ctx);
    }
    /* ⚠ Différence connue avec la séquence validée en SP8 : celle-ci tournait à
     * l'OUVERTURE et appelait SetMPRects + EnableMP (ctx[0x414] valant alors 0).
     * En lecture on les saute. SetMPRects ne pose pas que des dimensions : il
     * écrit ctx[0x18] et fait un appel IOKit avec le rectangle — plausiblement
     * ce qui arme la composition à l'écran. Gate pour trancher, sans changer le
     * comportement par défaut. */
    if (ctx->sp_force_mprects) {
        if (ctx->SetMPRects) ctx->SetMPRects(ctx->dev_ctx, rect, 0, 0);
        if (ctx->EnableMP)   ctx->EnableMP(ctx->dev_ctx, 1);
    }
    ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) idx, rect);   /* pose le rect  */
    /* ⚠ PAS de `ClearSP` ici. En mode surface il ne fait pas un memset CPU : il
     * SOUMET UNE COMMANDE AU RING GPU (0x1600 : écriture dans la file
     * ctx[0x30]/[0x34]/[0x38] puis appel IOKit). Placé juste avant le blit CPU
     * de `SetSPBuffer`, ce nettoyage asynchrone peut atterrir APRÈS lui et vider
     * le plan — ce qui correspond à l'intermittence observée (environ un blit
     * sur deux ne produit rien, sans qu'aucun de nos paramètres ne varie). */
    ctx->SetSPBuffer (ctx->dev_ctx, (uint32_t) idx, spdesc); /* couleurs+blit */
    /* ★★ 10.2 — LA PIÈCE MANQUANTE, ET NOTRE SEULE ÉCRITURE DANS LE CONTEXTE
     * PRIVÉ. Le `SetSPBuffer` de 10.4 extrait du descripteur un mot
     * couleurs/contrastes et le range en ctx[0x1DC] :
     *     lhz r0,0x10(r5) ; lhz r2,0x12(r5) ; r0<<=16 ; or ; stw r0,0x1dc(r3)
     * Celui de 10.2 ne le fait pas. Or son blit LIT ce mot (cinq références à
     * ctx[0x1DC] dans le bundle 10.2, autant que dans celui de 10.4), et un mot
     * de contrastes nul ne peut produire QUE du transparent — mesuré sur
     * matériel : source non nulle, drapeau armé, et pourtant zéro pixel opaque
     * dans tout le plan.
     * ⚠ On n'écrit que là où le pilote est ce stub, et JAMAIS si la valeur est
     * déjà la bonne : sur 10.3/10.4 cette branche ne s'exécute donc pas.
     * Le rectangle de découpe que 10.4 range en ctx[0x1EC…0x1F2] n'a PAS
     * d'équivalent ici (zéro référence dans le bundle 10.2) : cette
     * fonctionnalité n'y existe pas, il n'y a rien à poser. */
    /* ⚠⚠ La borne dd_ctx_has() est ici une garde d'ÉCRITURE : sur le Rage 128 de
     * 10.2 le contexte ne fait que 348 o, et l'offset 0x1DC du RV200 y tomberait
     * 128 octets APRÈS la fin du bloc — corruption silencieuse du tas. */
    if (ctx->lay_sp_stub && ctx->sp_cc_off_102 != 0
        && dd_ctx_has(ctx, ctx->sp_cc_off_102, 4)) {
        const uint32_t cc = ((uint32_t) sp->colors << 16) | sp->contrasts;
        volatile uint32_t *dcc = (volatile uint32_t *) ctx->dev_ctx;
        if (dcc[ctx->sp_cc_off_102 / 4] != cc)
            dcc[ctx->sp_cc_off_102 / 4] = cc;
    }
    /* ★ Relevé JUSTE APRÈS le blit (c'est `SetSPBuffer` qui blitte), avant tout
     * autre appel. Seule mesure capable de distinguer « le blit ne produit
     * rien » de « il produit, puis quelque chose efface » — les deux donnent un
     * plan vide à la fin, et c'est ce qui m'a fait tourner en rond. */
    if (probes != NULL) {
        probes[5] = dd_sp_plane_opaque(ctx);          /* après SetSPBuffer   */
        probes[7] = dd_ctx_u32(ctx, 0x1D0);           /* drapeau à cet instant */
    }
    /* ⚠ index DIFFÉRENT de celui de SetSPBuffer : c'est ce qui déclenche la
     * bascule des marqueurs, donc la mise à jour de l'écran. */
    ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) show_idx, rect);
    /* ⚠ Ce qu'il faut compter, ce sont les pixels OPAQUES sur TOUT le plan.
     * Une empreinte sur les premiers 256 Ko ne couvre que les ~85 premières
     * lignes — c'est-à-dire uniquement du fond : elle vaut 0 même quand
     * l'incrustation est parfaite, et le verdict « blit muet » qu'elle produit
     * est un pur artefact de mesure. Le plan fait pas × hauteur pixels. */
    if (probes != NULL) {
        const volatile uint32_t *pl = dd_sp_dest(ctx);
        const unsigned pitch = dd_sp_dest_pitch(ctx);
        if (pl != NULL && pitch != 0) {
            /* ⚠ Relever le PREMIER pixel opaque ne dit rien : sur du texte
             * c'est le contour. On collecte les couleurs DISTINCTES. */
            uint32_t opaque = 0;
            uint32_t distinct[4] = { 0, 0, 0, 0 };
            unsigned ndist = 0;
            const unsigned words = pitch * ctx->height;
            for (unsigned w = 0; w < words; w += 2) {
                const uint32_t v = pl[w];
                if ((v >> 24) == 0)
                    continue;
                opaque++;
                unsigned k;
                for (k = 0; k < ndist; k++)
                    if (distinct[k] == v) break;
                if (k == ndist && ndist < 4)
                    distinct[ndist++] = v;
            }
            probes[0] = opaque;
            probes[2] = distinct[0];
        }
    }

    /* ★ SP9 — armer l'affichage : sans ce drapeau, ShowMPBuffer saute son appel
     * d'affichage à chaque image et le plan reste invisible quoi qu'on y mette. */
    if (b_raw) {
        /* Séquence exacte du DVD Player : une ApplySPDCSQ PAR COMMANDE, avec son
         * offset RÉEL dans le paquet (Apple : 0x4e4, 0x4e5, 0x4e8, 0x4eb, 0x4f2
         * — les longueurs 1/3/3/7/5 des commandes 00-01, 03, 04, 05, 06), puis
         * un seul ShowSPBuffer, qui déclenche le blit.
         * ⚠ NE PAS appeler dd_sp_set_display() ici : elle ÉCRASE le premier
         * octet du paquet par une pseudo-commande, ce qui détruirait l'en-tête
         * de taille que le blit vient y lire. */
        unsigned k;
        for (k = 0; k < sp->cmd_count; k++)
            ctx->ApplySPDCSQ(ctx->dev_ctx, (uint32_t) idx,
                             (const void *) (unsigned long) sp->cmd_off[k], 1);
        ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) idx, rect);
    } else {
        dd_sp_set_display(ctx, bufs_b, idx, 0x01);
    }

    for (int i = 0; i < 4; i++)
        ctx->sp_rect[i] = rect[i];
    ctx->sp_visible = true;
    ctx->sp_show_idx = show_idx;
    ctx->sp_shown++;
    ctx->sp_hide_at_us = sp->hide_in_us > 0
                       ? (int64_t) dd_now_us() + sp->hide_in_us : 0;
    /* Mots d'état du plan, relus APRÈS la séquence (lecture pure) :
     * [5] ctx[0x1C8] = drapeau posé par EnableSP — s'il est retombé à 0, le
     * plan a été désarmé par le chemin vidéo et rien ne peut s'afficher ;
     * [6] ctx[0x1D0] drapeau « à redessiner » ; [7] ctx[0x18] mot de mode. */
    /* ⚠ NE PAS réutiliser probes[6] ici : il porte déjà couleurs/contrastes,
     * posé plus haut. Une deuxième écriture au même indice avait fait
     * journaliser « couleurs/contrastes = 00000000 » et m'a fait croire à un
     * défaut qui n'existait pas. */

    pthread_mutex_unlock(&ctx->lock);
    return true;
}

/* Efface l'incrustation. Sans effet si rien n'est affiché. */
bool dvddriver_sp_hide(dvddriver_ctx *ctx)
{
    if (!dvddriver_sp_usable(ctx))
        return false;
    pthread_mutex_lock(&ctx->lock);
    dd_wait_gpu_idle_locked(ctx);
    if (!ctx->sp_visible) {
        pthread_mutex_unlock(&ctx->lock);
        return false;
    }
    /* Un bitmap ENTIÈREMENT transparent est plus sûr qu'un EnableSP(0) : il
     * laisse le plan armé (donc pas de nouvelle négociation avec le driver) et
     * n'emprunte que le chemin déjà validé. */
    uint32_t bufs_a[8], bufs_b[8];
    memset(bufs_a, 0, sizeof(bufs_a));
    memset(bufs_b, 0, sizeof(bufs_b));
    if (ctx->GetSPBuffer(ctx->dev_ctx, bufs_a, bufs_b) == 0) {
        const int idx = ctx->sp_next_buf & 7;
        const int show_idx = idx;
        ctx->sp_next_buf++;
        uint8_t *dst = (uint8_t *) bufs_a[idx];
        if (dst != NULL) {
            uint8_t spdesc[32];
            memset(spdesc, 0, sizeof(spdesc));
            { uint16_t *u = (uint16_t *) spdesc;
              u[0x10 / 2] = 0x0000;
              u[0x12 / 2] = 0x0000;      /* tous les contrastes à 0 */
              u[0x18 / 2] = (uint16_t) ctx->height;
              u[0x1A / 2] = (uint16_t) ctx->width; }
            int16_t rect[4] = { 0, 0, (int16_t) ctx->height,
                                (int16_t) ctx->width };
            memset(dst, 0, 576u * 192u);
            ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) idx, rect);
            ctx->SetSPBuffer (ctx->dev_ctx, (uint32_t) idx, spdesc);
            ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) show_idx, rect);
            /* SP9 — commande SPU 0x02 : désarme le drapeau d'affichage. */
            dd_sp_set_display(ctx, bufs_b, idx, 0x02);
        }
    }
    ctx->sp_visible = false;
    ctx->sp_hide_at_us = 0;
    ctx->sp_hidden++;
    pthread_mutex_unlock(&ctx->lock);
    return true;
}

/* Échéance de disparition atteinte ? (lecture seule, sans appel driver) */
bool dvddriver_sp_hide_due(dvddriver_ctx *ctx)
{
    if (ctx == NULL || !ctx->sp_visible || ctx->sp_hide_at_us == 0)
        return false;
    return (int64_t) dd_now_us() >= ctx->sp_hide_at_us;
}

void dvddriver_sp_counters(dvddriver_ctx *ctx, uint32_t out[3])
{
    if (ctx == NULL)
        return;
    out[0] = ctx->sp_shown;
    out[1] = ctx->sp_hidden;
    out[2] = ctx->sp_dropped;
}

/* Les six mots que la routine d'affichage (0x41d8, appelée par ShowMPBuffer)
 * compose dans sa commande IOKit. Lecture seule. Relevé au désassemblage :
 *   41fc: lha 9, 486(3)   ctx[0x1E6]  gauche (alignée sur 16 par ShowSPBuffer)
 *   4200: lha 0, 490(3)   ctx[0x1EA]  droite
 *   4204: lha 11, 484(3)  ctx[0x1E4]  haut
 *   4208: lwz 8, 436(3)   ctx[0x1B4]  décalage de ligne SOURCE (écrit par le blit)
 *   4210: lha 2, 496(3)   ctx[0x1F0]  bas de découpe   (desc[0x18])
 *   4218: lha 10, 492(3)  ctx[0x1EC]  haut de découpe  (desc[0x14])
 * La commande vaut : ((gauche<<16) | (haut + décalage)) et
 *                    (((droite-gauche)<<16) | (0x1F0 - 0x1EC)).
 * Comparer la PREMIÈRE incrustation aux suivantes : c'est la seule chose qui
 * les distingue et qui n'ait pas encore été mesurée. */
void dvddriver_sp_display_words(dvddriver_ctx *ctx, int32_t out[6])
{
    if (ctx == NULL || ctx->dev_ctx == NULL)
        return;
    /* ★ CHANTIER 10.2 : ce sont les champs qui gouvernent le blit du pilote
     * stubbé. Lectures pures, à des offsets présents dans les trois bundles.
     *   [0] ctx[0x1D8] : « bouton actif » — SANS LUI ShowSPBuffer n'appelle le
     *       blit qu'avec l'argument 0, c'est-à-dire pour rien (0x2174) ;
     *   [1] ctx[0x1C4] : drapeau d'affichage, posé par ApplySPDCSQ ;
     *   [2] ctx[0x1C8] : posé par EnableSP ;
     *   [3]/[4] rect du PLAN, posé par ShowSPBuffer (0x1E4 = haut|gauche,
     *       0x1E8 = bas|droite, deux int16 par mot) ;
     *   [5] rect du BOUTON, posé par PrepareButton (0x1F4 = haut|gauche) — s'il
     *       est nul, le découpage a échoué et le blit n'a rien à copier. */
    /* ⚠ Ces offsets sont ceux des bundles 10.3/10.4 ; sur le contexte de 348 o
     * de 10.2 ils sortent tous du bloc. dd_ctx_u32 rend alors 0 = « inconnu ». */
    out[0] = (int32_t) dd_ctx_u32(ctx, 0x1B4);
    out[1] = (int32_t) dd_ctx_u32(ctx, 0x1C4);
    out[2] = (int32_t) dd_ctx_u32(ctx, 0x1D0);
    out[3] = (int32_t) dd_ctx_u32(ctx, 0x1E4);
    out[4] = (int32_t) dd_ctx_u32(ctx, 0x1E8);
    out[5] = (int32_t) dd_ctx_u32(ctx, 0x1F4);
}

/* SP7b — empreintes par ÉTAPE de la séquence SP (lecture seule) :
 *   [0] source avant ApplySPDCSQ   [1] source après   (le RLE se décode-t-il ?)
 *   [2] destination avant SetSPBuffer [3] après SetSPBuffer [4] après ShowSPBuffer
 *   [5] ctx[0x1D0] relu après SetSPBuffer (le blit a-t-il consommé le drapeau ?)
 * Isole laquelle des trois étapes reste muette, au lieu de conclure du silence
 * global. */
int dvddriver_sp_stage_probes(dvddriver_ctx *ctx, uint32_t out[6])
{
    if (ctx == NULL)
        return 0;
    for (int i = 0; i < 6; i++)
        out[i] = ctx->sp_stage[i];
    return ctx->sp_stage_valid;
}

/* SP7 — géométrie du blit subpicture, en LECTURE SEULE. Sert à vérifier le
 * modèle sur la machine plutôt qu'à le supposer :
 *   out[0] = ctx[0x204] destination ARGB   out[1] = ctx[0x410] largeur
 *   out[2] = ctx[0x414] PAS DE LIGNE       out[3] = ctx[0x418] hauteur
 * Attendu en 720×576 : 0x410 = 720, 0x414 = 768 (arrondi à 64), 0x418 = 576.
 * Si 0x414 valait 576, c'est que le rect Mac { top, left, bottom, right } est
 * encore inversé quelque part. */
bool dvddriver_sp_geometry(dvddriver_ctx *ctx, uint32_t out[4])
{
    if (ctx == NULL || ctx->dev_ctx == NULL)
        return false;
    /* Le cache de rect du plan vidéo n'existe pas sur 10.2 : ne rien inventer,
     * un zéro dit « inconnu » là où une valeur mentirait (cf. lay_mp_pitch). */
    out[0] = ctx->lay_deref_ok ? dd_ctx_u32(ctx, 0x204) : 0;
    out[1] = ctx->lay_mp_pitch ? dd_ctx_u32(ctx, 0x410) : 0;
    out[2] = ctx->lay_mp_pitch ? dd_ctx_u32(ctx, 0x414) : 0;
    out[3] = ctx->lay_mp_pitch ? dd_ctx_u32(ctx, 0x418) : 0;
    return true;
}

uint32_t dvddriver_sp_dest(dvddriver_ctx *ctx)
{
    if (ctx == NULL || ctx->dev_ctx == NULL)
        return 0;
    if (!ctx->lay_deref_ok)
        return 0;
    return dd_ctx_u32(ctx, 0x204);
}

bool dvddriver_sp_reshow(dvddriver_ctx *ctx)
{
    if (ctx == NULL || !ctx->sp_available || ctx->dev_ctx == NULL
        || ctx->ShowSPBuffer == NULL || ctx->sp_rect[2] == 0)
        return false;
    pthread_mutex_lock(&ctx->lock);
    dd_wait_gpu_idle_locked(ctx);
    ctx->ShowSPBuffer(ctx->dev_ctx, 0, ctx->sp_rect);
    pthread_mutex_unlock(&ctx->lock);
    return true;
}

bool dvddriver_sp_first_words(dvddriver_ctx *ctx, uint32_t words[8])
{
    if (ctx == NULL || !ctx->sp_available)
        return false;
    for (int i = 0; i < 8; i++)
        words[i] = ctx->sp_first_word[i];
    return true;
}

bool dvddriver_sp_probe(dvddriver_ctx *ctx, uint32_t probe[16], uint32_t *keycolor)
{
    if (ctx == NULL || !ctx->sp_available)
        return false;
    for (int i = 0; i < 16; i++)
        probe[i] = ctx->sp_probe[i];
    for (int i = 0; i < 8; i++)
        probe[i] = ctx->sp_probe[i];   /* inchangé : adresses */
    if (keycolor)
        *keycolor = ctx->sp_keycolor;
    return true;
}

void dvddriver_set_present_rect(dvddriver_ctx *ctx, int x, int y, int w, int h)
{
    if (ctx == NULL || w <= 0 || h <= 0)
        return;
    if (!ctx->ext_win)
        return;   /* fenêtre Carbon : garde son dst_rect (letterbox plein écran) */
    pthread_mutex_lock(&ctx->lock);
    ctx->present_x = x; ctx->present_y = y;
    ctx->present_w = w; ctx->present_h = h;
    pthread_mutex_unlock(&ctx->lock);
}

/* Présente la surface décodée à l'écran (recette Carbon crackée) :
 *   DVDDriverShowMPBuffer → CGSSetSurfaceBounds (2e) → CGSFlushSurface(région).
 * Sur une surface offscreen (on_screen faux), seul ShowMPBuffer est fait ; le
 * flush est inutile (rien à composer) et surtout CGSFlushSurface CRASHE sur une
 * fenêtre CGS nue (région interne 0xffffffff invalide) → on le saute. */
/* M3 — index de la surface de SORTIE de la dernière picture soumise (0..4).
 * L'appelant l'enregistre (picture_t* → idx) pour présenter en ordre d'AFFICHAGE. */
int dvddriver_out_index(const dvddriver_ctx *ctx)
{
    return ctx ? ctx->out_idx : -1;
}

/* Show + placement d'une surface. LOCK DÉJÀ TENU par l'appelant. */
static void dd_show_locked(dvddriver_ctx *ctx, int idx)
{
    if (ctx->closed || ctx->Show == NULL || ctx->dev_ctx == NULL || idx < 0)
        return;
    /* MESURE (temporaire, chantier perf) : /tmp/hw_nopresent
     *   1 → saute CGSSetSurfaceBounds + CGSFlushSurface (garde ShowMPBuffer) ;
     *   2 → saute TOUT le present (y compris ShowMPBuffer).
     * Combiné à /tmp/hw_nodecode, isole les trois postes (CPU / Decode / present). */
    static int s_nopres = -2;
    if (s_nopres == -2) { int v = dd_gate_read("/tmp/hw_nopresent");
                          s_nopres = (v > 0) ? v : 0; }
    if (s_nopres >= 2)
        return;
    /* ★★ ORDRE Z (10.3, découverte utilisateur) : quand l'app est ACTIVE au
     * démarrage du film, le WindowServer se met à alterner la surface GPU et
     * le backing de la fenêtre (on revoit la derniere image GL d'avant
     * l'engagement matériel) — le processus est parfaitement sain au sample,
     * le combat est côté compositeur. Ré-affirmer « surface au-dessus »
     * périodiquement est quasi gratuit et stoppe l'alternance. */
    if (ctx->OrderSurf != NULL && ctx->ext_win
        && (ctx->n_order_reassert++ % 25) == 0)
        ctx->OrderSurf(ctx->cid, ctx->wid, ctx->sid, 1, 0);

    /* (« clic automatique » CGSOrderWindow/CGSFlushWindow essayé ici aux
     * presents n°1/n°50 : SANS effet sur le scintillement — retiré. Le clic
     * manuel de l'utilisateur répare par un mécanisme WindowServer encore non
     * identifié ; mais la vraie parade est de ne jamais rouvrir le décodeur en
     * cours de lecture, cf. libmpeg2.c Reset().) */

    /* ★ SCINTILLEMENT (Panther/Jaguar) : les tampons soumis puis jamais
     * présentés (pictures que le vout n'affichera pas) doivent être rendus au
     * driver par ShowMPBuffer — qui AFFICHE. Les rendre au fil de l'eau avant
     * chaque Decode intercalait des images HORS ORDRE entre les présents du
     * vout : invisible sur Tiger (2 jetées/108), 1-2 images/s de travers sur
     * Panther (26 %% de jetées) — le scintillement constaté à l'œil. Ici on les
     * draine DANS L'ORDRE DE SOUMISSION, juste avant l'image courante, sous le
     * même verrou : entre deux composites du WindowServer seul le DERNIER Show
     * est visible, les périmées ne touchent jamais l'écran. */
    for (int guard = 0; ctx->n_pending > 0 && guard < 8; guard++) {
        int p0 = ctx->pending[0];
        if (p0 == idx)
            break;                       /* la cible sera montrée ci-dessous */
        /* ⚠⚠⚠ CAUSE CONNUE, DEUX REMÈDES ESSAYÉS ET RÉGRESSIFS (2026-08-05).
         * DIAGNOSTIC (solide) : `pending` est en ordre de SOUMISSION, qui n'est
         * PAS l'ordre d'affichage dès qu'il y a des images B. Sur `I P B B`,
         * présenter le premier B trouve le P en tête de file et l'AFFICHE juste
         * avant : image FUTURE poussée à l'écran, puis retour en arrière. C'est
         * l'origine des 2-3 « retours en arrière » par lecture vus à l'œil sur
         * le Rage 128, où l'absence de `CGSFlushSurface` (`apple_display_seq`)
         * laisse la composition asynchrone échantillonner un Show intermédiaire.
         *
         * ⛔ NE PAS retenir un Show au motif que la surface sera présentée plus
         * tard (`surf_hold != 0`). MESURÉ, les deux variantes régressent :
         *   - `break` sur la 1re surface portée   -> saccades ÉNORMES ;
         *   - `continue` (sauter, drainer les orphelines plus loin dans la file)
         *     -> 874 images décodées en 55 s au lieu de ~1265 (16 im/s), attente
         *        de surface 29,5 s au lieu de 20,5.
         * Ce `Show` n'est donc pas qu'un affichage : c'est ce qui vide la file
         * interne du pilote, et la retarder met Decode en contre-pression.
         * ⇒ La seule sortie propre est de RENDRE UN TAMPON SANS L'AFFICHER.
         * Piste identifiée au désassemblage : `ShowMPBuffer(ctx, idx, p_mode)`
         * lit `*(u16 *) p_mode` (2 par défaut quand l'argument est NULL) et le
         * transmet tel quel à l'appel IOKit **sélecteur 10**, avec `{idx, mode}`.
         * Reste à relever les valeurs de mode qu'emploie le lecteur d'Apple
         * (spy `sp4.c`, en journalisant `*(u16 *)arg3` — le pilote déréférence
         * lui-même ce pointeur, la lecture est donc sûre). `ClearMP` a été
         * écarté : il ne prend pas d'index et ne touche que l'anneau. */
        memmove(ctx->pending, ctx->pending + 1,
                (--ctx->n_pending) * sizeof ctx->pending[0]);
        /* ★★★ LA CORRECTION DES « RETOURS EN ARRIÈRE » (2026-08-05, validée à
         * l'œil) : garder l'APPEL — c'est lui qui vide la file interne du
         * pilote, les deux régressions ci-dessus le prouvent — mais RÉ-AFFICHER
         * LA SURFACE DÉJÀ À L'ÉCRAN au lieu de la périmée. Même nombre d'appels
         * IOKit, au même moment, donc aucune contre-pression ; et l'image
         * affichée ne recule jamais.
         * ★ Fait nouveau qui rend cela possible : **le pilote n'a PAS besoin de
         * l'index exact pour rendre le tampon**, l'appel IOKit suffit. Mesuré :
         * 1363 images décodées sur 55 s (référence ~1265-1351), attente de
         * surface 20,3 s (référence 20,5) — aucune dégradation.
         * `/tmp/hw_drain_last` force ce comportement sur les familles où il
         * n'est pas le défaut (RV200), pour pouvoir l'y éprouver. */
        int shown = p0;
        if (ctx->last_shown >= 0 && ctx->last_shown < 5) {
            static int g = -1;
            if (g < 0) g = (dd_gate_read("/tmp/hw_drain_last") > 0);
            if (ctx->drain_shows_current || g)
                shown = ctx->last_shown;
        }
        ctx->n_show_drain++;
        ctx->Show(ctx->dev_ctx, (uint32_t) shown, NULL, NULL);
        pthread_cond_broadcast(&ctx->surf_cv);
    }
    /* ⚠ RETIRÉ (29/07, établi par DÉSASSEMBLAGE de CoreGraphics 10.3) : une
     * transaction CGSDisableUpdate/ReenableUpdate autour du present est
     * CONTRE-PRODUCTIVE. Dans `CGXFlushSurface`, le blit accéléré
     * (`IOAccelFlushSurfaceOnFramebuffers`) n'est exécuté QUE si
     * `CGXAreUpdatesDisabled` est faux ; et `__CGXActivateSurfaces` DIFFÈRE
     * tout son travail quand les updates sont désactivées. Encadrer chaque
     * present d'une transaction revenait donc à désarmer le chemin GPU. */
    /* ⚠ ANTI-TEARING PAR ATTENTE DU FAISCEAU : ESSAYÉ ET RETIRÉ (29/07).
     * `CGDisplayWaitForBeamPositionOutsideLines` existe bien sur 10.3 et
     * l'attente ne coûtait rien (temps de present inchangé), mais le tearing
     * est resté strictement identique : depuis que la surface est COMPOSÉE,
     * c'est le WindowServer qui blitte vers le framebuffer, dans sa propre
     * passe asynchrone — synchroniser NOTRE écriture ne pilote donc pas le
     * moment où l'image atteint l'écran. Rien à gagner côté client. */
    unsigned long t0 = dd_now_us();
    if (ctx->pres_last_us != 0) {
        const unsigned long d = (t0 - ctx->pres_last_us) / 1000;   /* ms */
        const unsigned b = d < 25 ? 0 : d < 33 ? 1 : d < 37 ? 2 : d < 43 ? 3
                         : d < 50 ? 4 : d < 60 ? 5 : d < 100 ? 6 : 7;
        ctx->pres_hist[b]++;
        ctx->pres_n++;
    }
    ctx->pres_last_us = t0;
    ctx->prev_shown = ctx->last_shown;
    ctx->last_shown = idx;

    /* ⚠ 2e argument de ShowMPBuffer : le lecteur d'Apple y passe TOUJOURS 0
     * (trace sptrace.c), jamais un index. Or c'est cet argument que la routine
     * d'expansion du subpicture DÉRÉFÉRENCE (à +0x204) — lui donner un petit
     * entier revient à lui donner un pointeur invalide, ce qui explique les
     * plantages répétés du plan SP. Le chemin vidéo, lui, ne le déréférence
     * pas : d'où une lecture qui fonctionne malgré tout.
     * /tmp/hw_show_zero adopte la convention d'Apple, le temps de vérifier que
     * l'ordre d'affichage reste correct sans passer l'index ici. */
    static int s_show_zero = -2;
    if (s_show_zero == -2) s_show_zero = (dd_gate_read("/tmp/hw_show_zero") > 0);
    /* SP5c — le blit subpicture s'exécute-t-il ? On lit quatre mots à la
     * destination (ctx[0x204]) juste avant et juste après le Show, sur les
     * premières images seulement. Lecture pure : aucun appel supplémentaire. */
    if (ctx->sp_dest_probes < 3) {
        const volatile uint32_t *dst = dd_sp_dest(ctx);
        if (dst != NULL) {
            /* Empreinte sur 64 Ko : lire seulement les premiers mots ne prouve
             * rien (le coin haut-gauche d'une incrustation est transparent).
             * On échantillonne un mot sur 16 pour rester léger. */
            unsigned w;
            uint32_t h1 = 0, h2 = 0;
            for (w = 0; w < 16384; w += 16)
                h1 = (h1 * 31u) ^ dst[w];
            ctx->n_show_target++;
            ctx->Show(ctx->dev_ctx, s_show_zero ? 0 : (uint32_t) idx, NULL, NULL);
            for (w = 0; w < 16384; w += 16)
                h2 = (h2 * 31u) ^ dst[w];
            ctx->sp_dest_before[ctx->sp_dest_probes][0] = h1;
            ctx->sp_dest_after[ctx->sp_dest_probes][0]  = h2;
            ctx->sp_dest_probes++;
            goto shown;
        }
    }
    ctx->n_show_target++;
    ctx->Show(ctx->dev_ctx, s_show_zero ? 0 : (uint32_t) idx, NULL, NULL);
shown:;
    dd_pending_drop(ctx, idx);        /* buffer MP rendu au driver par ce Show */

    /* ★★★ RÉ-ÉTALEMENT DU SUBPICTURE APRÈS L'IMAGE VIDÉO.
     * Le `ShowMPBuffer` qui vient de s'exécuter a réécrit la surface : sur les
     * familles où le pilote ne ré-étale pas le SP lui-même (Rage 128), il faut
     * le reposer, sinon l'incrustation n'est visible sur AUCUNE image.
     * ⚠⚠ C'EST L'APPEL QUI A FIGÉ UN GPU LE 2026-07-22 — mais dans un cas
     * précis : le plan n'était PAS armé. D'où les quatre gardes, toutes
     * nécessaires :
     *   1. la famille le réclame (le RV200 est donc hors d'atteinte) ;
     *   2. une incrustation est réellement montée (`sp_visible`) ;
     *   3. le plan est armé CÔTÉ LOGICIEL (`sp_armed`) ;
     *   4. et surtout CÔTÉ MATÉRIEL : le drapeau d'affichage `ctx[sp_flag_off]`
     *      est non nul — c'est exactement la condition qui manquait en juillet.
     * On ne fait qu'un ShowSPBuffer : ni ClearSP, ni SetSPBuffer, ni écriture
     * de tampon (le contenu est déjà en place). */
    if (ctx->sp_needs_reshow && ctx->sp_visible && ctx->sp_armed
        && ctx->ShowSPBuffer != NULL && ctx->sp_flag_off != 0
        && ctx->dev_ctx != NULL)
    {
        /* ⚠ `sp_flag_off` peut être un offset d'OCTET non aligné (0x14F sur le
         * pilote 10.2) : dd_ctx_u32 lit le mot qui le contient, ce qui suffit
         * pour un test « non nul », et refuse hors bornes. */
        if (dd_ctx_u32(ctx, ctx->sp_flag_off & ~3u) != 0)   /* armé matériellement */
            ctx->ShowSPBuffer(ctx->dev_ctx, (uint32_t) ctx->sp_show_idx,
                              ctx->sp_rect);
    }
    /* ⚠ RETIRÉ : appeler ShowSPBuffer à CHAQUE image alors que le plan SP
     * n'est PAS armé (ctx+0x1FC == 0) a figé la machine le 2026-07-22 (wedge
     * GPU, extinction complète nécessaire). Aucun appel au plan SP ne doit
     * être fait tant que le mode n'est pas armé — et jamais en boucle sur le
     * chemin de present. Cf. doc/pb-offload/sp-hardware-subtitles-plan.md. */
    if (ctx->on_screen && s_nopres < 1)
    {
        /* Rect effectif : le rect dynamique (U4, suit la fenêtre VLC) s'il est posé,
         * sinon dst_rect (valeur d'ouverture). Le compositeur met la surface native à
         * l'échelle de ce rect. */
        /* ⚠ `sp_needs_native_scale` : ignorer le rect dynamique du vout et garder
         * celui de l'ouverture (taille native). Sans cela, tout rect posé à
         * l'ouverture est réécrit ici à chaque image, et les deux tentatives
         * précédentes de tester la taille native n'ont jamais porté. */
        CGRect r = (ctx->sp_native_scale)
            ? ctx->dst_rect
            : ((ctx->present_w > 0 && ctx->present_h > 0)
               ? CGRectMake(ctx->present_x, ctx->present_y, ctx->present_w, ctx->present_h)
               : ctx->dst_rect);
        /* PERF : ne re-poser les bounds que si le rect a CHANGÉ (en régime établi il
         * est constant → un aller-retour WindowServer synchrone économisé par frame). */
        if (ctx->SetBounds
            && (!ctx->has_bounds
                || r.origin.x    != ctx->last_bounds.origin.x
                || r.origin.y    != ctx->last_bounds.origin.y
                || r.size.width  != ctx->last_bounds.size.width
                || r.size.height != ctx->last_bounds.size.height))
        {
            ctx->SetBounds(ctx->cid, ctx->wid, ctx->sid, r);
            ctx->last_bounds = r;
            ctx->has_bounds  = true;
            /* Région de flush = nouveaux bounds (cf. commentaire du champ) :
             * sans cela la zone recomposée reste celle de l'ouverture. */
            if (ctx->NewRegion) {
                void *nr = NULL;
                CGRect fr = CGRectMake(0, 0, r.origin.x + r.size.width,
                                             r.origin.y + r.size.height);
                if (ctx->NewRegion(&fr, &nr) == 0 && nr != NULL) {
                    void *old_region = ctx->region;
                    ctx->region = nr;
                    if (ctx->ReleaseRegion && old_region)
                        ctx->ReleaseRegion(old_region);
                }
            }
        }
        /* ★★ EXPÉRIENCE /tmp/hw_noflush (10.3, « app active au démarrage ») :
         * le lecteur d'Apple n'importe NI CGSBindSurface NI CGSFlushSurface —
         * il Show et ne flushe jamais. Hypothèse : une surface créée pendant
         * que l'app est ACTIVE est double-bufferisée par le WindowServer, et
         * chaque Flush bascule vers le tampon PÉRIMÉ pendant que le driver
         * dessine dans l'autre → alternance image fraîche / image ancienne,
         * état collant depuis la création, compositeur au repos (mesuré :
         * WindowServer 0,9 % pendant le scintillement). */
        /* ★ 2026-08-04 : l'hypothèse ci-dessus est CONFIRMÉE par la trace du spy
         * interposé sur DVD Player (Rage 128) — pas un seul CGSFlushSurface de
         * toute une lecture. `no_flush` la rend permanente sur les familles qui
         * suivent le protocole d'Apple, le gate restant pour l'A/B ailleurs. */
        static int s_noflush = -2;
        if (s_noflush == -2) s_noflush = (dd_gate_read("/tmp/hw_noflush") > 0);
        if (!s_noflush && !ctx->no_flush && ctx->FlushSurf && ctx->region)
            ctx->FlushSurf(ctx->cid, ctx->wid, ctx->sid, ctx->region);
    }
    ctx->us_present += dd_now_us() - t0;
    ctx->n_present++;
}

/* ★ PLEIN ÉCRAN — ré-attacher la surface décodeur à une autre fenêtre CGS.
 * L'interface legacy bascule la vue vidéo dans une NOUVELLE fenêtre en plein
 * écran ; la surface, elle, reste liée à la fenêtre capturée à l'ouverture, qui
 * n'est plus visible → écran noir. On détache la surface de l'ancienne fenêtre,
 * on en crée une sur la nouvelle, et on la re-lie à la sortie du décodeur avec
 * exactement la même séquence que DVDDriverOpenDevice (CGSBindSurface via le
 * thunk, cf. dd_bind_thunk). Ne touche à rien si la fenêtre n'a pas changé. */
void dvddriver_bind_window(dvddriver_ctx *ctx, int wid)
{
    /* ⚠ NE PAS RÉIMPLÉMENTER LA RÉ-ATTACHE À CHAUD. Tentée et RETIRÉE : détacher
     * la surface de l'ancienne fenêtre puis en créer une sur la nouvelle
     * (CGSRemoveSurface / CGSAddSurface + re-CGSBindSurface) casse
     * DÉFINITIVEMENT la liaison décodeur→surface — écran noir en plein écran ET
     * après retour en fenêtré. La liaison n'est établie de façon fiable que par
     * DVDDriverOpenDevice. Le suivi de fenêtre se fait donc par RÉOUVERTURE du
     * décodeur, côté codec, au prochain STATE_SEQUENCE (cf. libmpeg2.c). */
    (void) ctx; (void) wid;
}

/* PERF (chantier 720×576) — cumuls Decode/present depuis l'ouverture. Sous mutex
 * (les compteurs sont écrits depuis le thread décodeur ET le thread vout). */
/* DIAGNOSTIC — copie les compteurs de types de macroblocs (8) et de DCT (2). */
void dvddriver_mb_stats(dvddriver_ctx *ctx, unsigned *mb8, unsigned *dct2,
                        unsigned *cvt3)
{
    if (ctx == NULL) return;
    pthread_mutex_lock(&ctx->lock);
    for (int i = 0; i < 8; i++) if (mb8) mb8[i] = ctx->mb_stat[i];
    for (int i = 0; i < 2; i++) if (dct2) dct2[i] = ctx->dct_stat[i];
    if (cvt3) { cvt3[0] = ctx->cvt_stat[0]; cvt3[1] = ctx->cvt_stat[1];
                cvt3[2] = ctx->cvt_stat[2]; }
    pthread_mutex_unlock(&ctx->lock);
}

void dvddriver_perf_get(dvddriver_ctx *ctx, unsigned *n_dec, unsigned long *us_dec,
                        unsigned *n_pres, unsigned long *us_pres, unsigned *n_stale)
{
    if (ctx == NULL)
        return;
    pthread_mutex_lock(&ctx->lock);
    if (n_dec)   *n_dec   = ctx->n_decode;
    if (us_dec)  *us_dec  = ctx->us_decode;
    if (n_pres)  *n_pres  = ctx->n_present;
    if (us_pres) *us_pres = ctx->us_present;
    if (n_stale) *n_stale = ctx->n_present_stale;
    pthread_mutex_unlock(&ctx->lock);
}

/* M3 — présente une surface ARBITRAIRE par index (découple present de submit :
 * on affiche la surface correspondant à display_fbuf, pas à current_fbuf). */
void dvddriver_present_index(dvddriver_ctx *ctx, int idx)
{
    if (ctx == NULL || idx < 0)
        return;
    pthread_mutex_lock(&ctx->lock);
    dd_wait_gpu_idle_locked(ctx);
    dd_show_locked(ctx, idx);
    pthread_mutex_unlock(&ctx->lock);
}

/* U4 — présente la surface idx SEULEMENT si sa génération vaut encore `gen`
 * (capturée au submit par le codec). Sinon la surface a été réécrite par une
 * frame plus récente → on saute (la fenêtre garde la dernière image valide).
 * Appelé par le vout (thread vout), en ordre PTS → pacing A/V correct. */
void dvddriver_present_index_gen(dvddriver_ctx *ctx, int idx, unsigned gen)
{
    if (ctx == NULL || idx < 0 || idx >= 5)
        return;
    pthread_mutex_lock(&ctx->lock);
    /* En asynchrone la génération est bumpée à l'enqueue : si le Decode de
     * cette surface est encore en vol, attendre sa fin avant de la montrer
     * (sinon on composerait une image à moitié écrite). */
    dd_wait_gpu_idle_locked(ctx);
    if (ctx->surf_gen[idx] == gen)
        dd_show_locked(ctx, idx);
    else
        ctx->n_present_stale++;
    pthread_mutex_unlock(&ctx->lock);
}

void dvddriver_present(dvddriver_ctx *ctx)
{
    if (ctx == NULL)
        return;
    dvddriver_present_index(ctx, ctx->out_idx);   /* rétro-compat : surface courante */
}

/* ==== FERMETURE ========================================================== */
/* Régularité de la présentation : [0]<25 [1]<33 [2]<37 [3]<43 [4]<50 [5]<60
 * [6]<100 [7]>=100 ms, et le total. */
unsigned long dvddriver_last_surf_wait_us(dvddriver_ctx *ctx)
{
    return ctx != NULL ? ctx->us_last_surf_wait : 0;
}

unsigned long dvddriver_last_submit_wait_us(dvddriver_ctx *ctx)
{
    return ctx != NULL ? ctx->us_last_submit_wait : 0;
}

unsigned long dvddriver_submit_wait_us(dvddriver_ctx *ctx)
{
    return ctx != NULL ? ctx->us_submit_wait : 0;
}

unsigned long dvddriver_surf_wait_total_us(dvddriver_ctx *ctx)
{
    return ctx != NULL ? ctx->us_surf_wait : 0;
}

unsigned long dvddriver_last_decode_us(dvddriver_ctx *ctx)
{
    return ctx != NULL ? ctx->us_last_decode : 0;
}

void dvddriver_decode_times(dvddriver_ctx *ctx, uint32_t out[8], uint32_t *n)
{
    if (n) *n = 0;
    if (ctx == NULL) return;
    uint32_t total = 0;
    for (int i = 0; i < 8; i++) { out[i] = ctx->dec_hist[i]; total += out[i]; }
    if (n) *n = total;
}

void dvddriver_present_intervals(dvddriver_ctx *ctx, uint32_t out[8],
                                 uint32_t *total)
{
    if (ctx == NULL)
        return;
    for (int i = 0; i < 8; i++)
        out[i] = ctx->pres_hist[i];
    *total = ctx->pres_n;
}

/* ★ Escamoter/rendre la SURFACE (et non la fenêtre) : retirer la fenêtre hôte
 * ne suffit pas, le WindowServer continue de composer la surface qui lui est
 * attachée — la vidéo restait affichée par-dessus la liste de lecture. On la
 * fait passer sous le contenu de la fenêtre, ce qui la rend invisible sans
 * rien détruire ; l'ordre est rétabli au retour. */
void dvddriver_set_surface_hidden(dvddriver_ctx *ctx, bool hidden)
{
    if (ctx == NULL || ctx->OrderSurf == NULL || !ctx->ext_win)
        return;
    pthread_mutex_lock(&ctx->lock);
    if (!ctx->closed) {
        ctx->OrderSurf(ctx->cid, ctx->wid, ctx->sid, hidden ? -1 : 1, 0);
        /* ★ MESURÉ sur 10.3 : cet ordre RÉUSSIT (rc=0) et ne retire rien de
         * l'écran. Ce n'est pas l'empilement qui décide de la présence de la
         * surface, c'est sa FORME sur le framebuffer — le désassemblage de
         * CoreGraphics 10.3 montre le blit accéléré gouverné par des champs
         * armés depuis IOAccelSetSurfaceFramebufferShape. On réduit donc les
         * bounds à rien : le serveur n'a plus de région à envoyer. */
        if (hidden && ctx->SetBounds)
            ctx->SetBounds(ctx->cid, ctx->wid, ctx->sid,
                           CGRectMake(0, 0, 0, 0));
        /* ⚠ Le present saute CGSSetSurfaceBounds quand le rect n'a pas changé
         * (cf. last_bounds). Sans cette invalidation, le retour de la vidéo
         * garderait des bounds vides et l'image ne reviendrait jamais. */
        ctx->has_bounds = false;
    }
    pthread_mutex_unlock(&ctx->lock);
}

void dvddriver_close(dvddriver_ctx *ctx)
{
    if (ctx == NULL)
        return;
    /* Arrêter le worker asynchrone AVANT CloseDevice : un Decode encore en vol
     * pendant la fermeture du device serait le wedge assuré. Le worker termine
     * son Decode courant, voit async_quit et sort ; join garantit qu'il n'y a
     * plus AUCUN appel driver en cours quand on ferme. */
    if (ctx->async_started) {
        pthread_mutex_lock(&ctx->lock);
        ctx->async_quit = true;
        pthread_cond_broadcast(&ctx->async_in_cv);
        pthread_mutex_unlock(&ctx->lock);
        pthread_join(ctx->async_th, NULL);
        ctx->async_started = false;
        ctx->async_on = false;
    }
    /* Sérialiser avec un éventuel Show en cours sur le thread vout : l'appelant
     * (codec) DOIT avoir déjà retiré dvddriver-ctx du bus libvlc AVANT d'appeler
     * close, pour qu'aucun nouveau present ne démarre ; le lock couvre celui qui
     * serait déjà entré. */
    pthread_mutex_lock(&ctx->lock);
    /* ★ Rendre TOUS les buffers MP encore en vol avant CloseDevice : fermer avec
     * des buffers non rendus laisse le driver à attendre ses FIFO (« waiting
     * decoder fifos to empty ») → wedge GPU au quit. */
    dd_recycle_locked(ctx, 0);
    /* U4 : retirer la surface de la fenêtre VLC (use_ext) — sinon surface
     * orpheline sur la fenêtre du vout après fermeture du décodeur. */
    if (ctx->ext_win && ctx->dl_as) {
        int (*RemoveSurf)(int, int, int) = dlsym(ctx->dl_as, "CGSRemoveSurface");
        if (RemoveSurf) RemoveSurf(ctx->cid, ctx->wid, ctx->sid);
    }
    if (ctx->Close && ctx->dev_ctx) ctx->Close(ctx->dev_ctx);
    if (ctx->Term) ctx->Term();
    if (ctx->DisposeWin && ctx->win) ctx->DisposeWin(ctx->win);
    ctx->dev_ctx = NULL;
    ctx->closed  = true;         /* plus aucun appel driver après ce point */
    ctx->Show = NULL; ctx->Decode = NULL; ctx->Close = NULL; ctx->Term = NULL;
    ctx->SetBounds = NULL; ctx->FlushSurf = NULL; ctx->DisposeWin = NULL;
    ctx->win = NULL;
    /* Réveiller un éventuel dd_pick_output en attente d'une surface. */
    pthread_cond_broadcast(&ctx->surf_cv);
    if (ctx->dl_bundle) { dlclose(ctx->dl_bundle); ctx->dl_bundle = NULL; }
    if (ctx->dl_as)     { dlclose(ctx->dl_as);     ctx->dl_as = NULL; }
    if (s_dd_instances > 0) s_dd_instances--;
    /* ⚠ On NE libère PAS forcément ici : des picture_context_t de VLC peuvent
     * encore référencer ce ctx et appeler dvddriver_surface_release() après le
     * CloseDecoder. Le dernier qui lâche libère (cf. champ `refs`). */
    dd_unref_unlock(ctx);
}

/* Cf. dvddriver_backend.h : ce que le backend a RETENU, pas ce qu'on lui a
 * proposé. */
/* Nom du greffon effectivement retenu, pour le journal : il dit d'un coup d'œil
 * si la découverte dynamique a fonctionné et sur quelle puce on tourne.
 * Renvoie NULL tant qu'aucune famille n'a été trouvée. */
const char *dvddriver_family_name(void)
{
    const struct dd_family *f = dd_find_family(NULL);
    return f ? f->service : NULL;
}

bool dvddriver_uses_external_window(dvddriver_ctx *ctx)
{
    return ctx != NULL && ctx->ext_win;
}
