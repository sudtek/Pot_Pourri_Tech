#!/usr/bin/env bash
# =============================================================================
# LXC_TEMPLATE_GPU.sh — Création automatisée d'un template LXC Proxmox
#                       avec passthrough GPU (iGPU AMD / carte dédiée).
#
# 23 octobre 2026 
# Version 1.0
#
# RÉSUMÉ
# ------
# Ce script crée un conteneur LXC non privilégié sur Proxmox, configure le
# passthrough GPU (/dev/dri/cardN, /dev/dri/renderDN, /dev/kfd) via cgroup2
# et bind mounts, active le nesting (systemd 257+), réinitialise machine-id
# et clés SSH (pour éviter les doublons dans les clones), puis convertit le
# conteneur en template (`pct template`) SANS le démarrer.
#
# Le script NE FAIT PAS (à faire dans des scripts dédiés) :
#   - installation de Vulkan / llama.cpp / paquets applicatifs
#   - test Go/NoGo du GPU (vulkaninfo)
#   - sauvegarde (vzdump)
#   - configuration du DHCP statique côté pfSense
#
# RÉFÉRENCES
# ----------
#   - INSTALL-LLAMA-CPP-LXC.md         (workflow GPU + Vulkan)
#   - CONTAINER-MAITRE-VIERGE-R7-IGPU.md (template golden image, reset)
#
# INVOCATION
# ----------
#   ./LXC_TEMPLATE_GPU.sh [options]
#
# Options :
#   --id N              ID du conteneur (défaut : 999)
#   --hostname NAME     Hostname (défaut : cont-<timestamp>)
#   --storage STOR      Storage rootfs (défaut : local-zfs)
#   --bridge BR         Bridge réseau (défaut : vmbr0)
#   --cores N           Nombre de cores (défaut : 2)
#   --memory MiB        RAM en MiB (défaut : 2048)
#   --swap MiB          Swap en MiB (défaut : 512)
#   --disk SIZE         Taille disque (défaut : 10, unité Go implicite)
#   --nameserver IP     DNS (défaut : 10.10.10.254)
#   --searchdomain DOM  Search domain (défaut : vide, cf. anomalie Proxmox)
#   --ip CIDR|dhcp      IP statique (ex. 10.10.10.140/24) ou dhcp (défaut)
#   --gw IP             Gateway (requis si --ip statique)
#   --tags LIST         Tags Proxmox, séparés par virgule
#   --template-os VOLID Template OS (défaut : auto-détection debian-13)
#   --root-password     Demander interactivement un mot de passe root
#                       (par défaut : pas de mot de passe → pct enter)
#   --gpu               Activer le passthrough GPU
#   --no-gpu            Désactiver le passthrough GPU
#   --no-reset          Ne PAS reset machine-id + SSH (déconseillé !)
#   --force             Écraser un conteneur existant portant le même ID
#   --dry-run           Afficher les actions sans les exécuter
#   -h, --help          Cette aide
#
# Exemples :
#   ./LXC_TEMPLATE_GPU.sh
#   ./LXC_TEMPLATE_GPU.sh --id 999 --hostname master-r7-igpu
#   ./LXC_TEMPLATE_GPU.sh --id 205 --ip 10.10.10.150/24 --gw 10.10.10.254
#   ./LXC_TEMPLATE_GPU.sh --dry-run --gpu
#
# =============================================================================
# Convention de codes de sortie (à graver)
# Code	Signification	Qui l'émet
# 0	Succès	main
# 1	Erreur de préflight (validation)	die user
# 2	Erreur d'usage (arguments)	die usage
# 3	Dépendance manquante / storage / bridge / template OS	die env
# 4	pct create a échoué	die create
# 5	Config GPU a échoué	die gpu
# 6	Reset machine-id a échoué	die reset
# 7	pct template a échoué	die template
# 255	Réservé : erreur non gérée (ne devrait jamais apparaître après ce patch)   
# =============================================================================

set -euo pipefail

# =============================================================================
# 0. COULEURS + LOGGING + CODES DE SORTIE + HELPERS
# =============================================================================

if [[ -t 1 ]]; then
    C_OK=$'\033[0;32m'; C_WARN=$'\033[1;33m'; C_ERR=$'\033[0;31m'
    C_INFO=$'\033[0;36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_OK=; C_WARN=; C_ERR=; C_INFO=; C_BOLD=; C_OFF=
fi

log_info()  { printf '%s[INFO]%s  %s\n' "$C_INFO" "$C_OFF" "$*" >&2; }
log_ok()    { printf '%s[ OK ]%s  %s\n' "$C_OK"   "$C_OFF" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s  %s\n' "$C_WARN" "$C_OFF" "$*" >&2; }
log_error() { printf '%s[FAIL]%s  %s\n' "$C_ERR"  "$C_OFF" "$*" >&2; }

# --- Codes de sortie nommés (référencés dans --help) ---
readonly EXIT_USER=1 EXIT_USAGE=2 EXIT_ENV=3 EXIT_CREATE=4 \
         EXIT_GPU=5 EXIT_RESET=6 EXIT_TEMPLATE=7

# --- Contexte du dernier échec (rempli par run_step, lu par die) ---

# Exécute une commande en capturant rc + stderr pour diagnostic.
#   $1 = description lisible
#   $@ = commande + arguments
# Retourne 0 si succès, sinon imprime le contexte et retourne le rc.
#
# NB : le pattern `out=$(...) || rc=$?` neutralise set -e le temps de la
# capture — c'est le seul moyen propre de lire le rc ET le stderr sous
# pipefail sans risquer un exit prématuré.
run_step() {
    local desc="$1"; shift
    local out rc=0
    out=$("$@" 2>&1) || rc=$?
    [[ $rc -eq 0 ]] && return 0
    log_error "${desc} a échoué (exit $rc)"
    log_error "  cmd   : $*"
    [[ -n "$out" ]] && log_error "  stderr: ${out//$'\n'/$'\n'          }"
    return "$rc"
}

# $1 = message ; $2 = code (défaut EXIT_USER)
die() {
    local msg="$1" code="${2:-$EXIT_USER}"
    log_error "$msg"
    exit "$code"
}

# Raccourcis sémantiques — un code par étape, pour un diagnostic précis
die_user()     { die "$1" "$EXIT_USER"; }
die_usage()    { die "$1" "$EXIT_USAGE"; }
die_env()      { die "$1" "$EXIT_ENV"; }
die_create()   { die "$1" "$EXIT_CREATE"; }
die_gpu()      { die "$1" "$EXIT_GPU"; }
die_reset()    { die "$1" "$EXIT_RESET"; }
die_template() { die "$1" "$EXIT_TEMPLATE"; }

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly PROG_VERSION="1.0"

# =============================================================================
# 1. VALEURS PAR DÉFAUT (surchargées par arguments)
# =============================================================================


# --- Réseau global ---
DNS_DEFAUT='10.10.10.254'      # DNS = pfSense (cf. doc master §2.1)
SEARCHDOMAIN_DEFAUT=''          # IMPORTANT : vide (cf. anomalie §15.1 doc master)

# --- Chemins Proxmox ---
readonly PROXMOX_UDEV_PATH='/etc/udev/rules.d'
readonly PROXMOX_LXC_CONF_PATH='/etc/pve/lxc'

# --- Paramètres conteneur ---
VMID_DEFAUT='999'
HOSTNAME_DEFAUT="cont-$(date +%Y%m%d-%H%M%S)"
CORES_DEFAUT='2'
MEMORY_DEFAUT='2048'            # MiB
SWAP_DEFAUT='512'               # MiB
DISK_DEFAUT='10'                # Go
STORAGE_DEFAUT='local-zfs'
BRIDGE_DEFAUT='vmbr0'
IP_DEFAUT='dhcp'
GW_DEFAUT=''
FIREWALL_DEFAUT='1'
NAMESERVER_DEFAUT="$DNS_DEFAUT"
SEARCHDOMAIN="$SEARCHDOMAIN_DEFAUT"
TEMPLATE_OS_DEFAUT=''           # auto-détection si vide
FEATURES_DEFAUT='nesting=1'     # nécessaire pour systemd 257
TAGS_DEFAUT='template,gpu,igpu,lxc'

# --- GPU ---
GPU_ENABLE='auto'               # 'auto' (si /dev/dri existe) | 'yes' | 'no'
#
# Pas encore implanté car j'ai un seul IGPU et pas 2 GPU ...
# GPU_PCI_SELECT=''             # optionnel : forcer un PCI (ex. 05:00.0) 

# --- Workflow ---
RESET_MACHINE_ID='yes'          # reset machine-id + SSH (recommandé)
ROOT_PASSWORD='no'              # 'no' | 'ask'
FORCE='no'
DRY_RUN='no'

# Variables effectives (copiées des défauts, puis surchargées par les args)
VMID="$VMID_DEFAUT"
HOSTNAME="$HOSTNAME_DEFAUT"
CORES="$CORES_DEFAUT"
MEMORY="$MEMORY_DEFAUT"
SWAP="$SWAP_DEFAUT"
DISK="$DISK_DEFAUT"
STORAGE="$STORAGE_DEFAUT"
BRIDGE="$BRIDGE_DEFAUT"
IP="$IP_DEFAUT"
GW="$GW_DEFAUT"
FIREWALL="$FIREWALL_DEFAUT"
NAMESERVER="$NAMESERVER_DEFAUT"
TEMPLATE_OS="$TEMPLATE_OS_DEFAUT"
FEATURES="$FEATURES_DEFAUT"
TAGS="$TAGS_DEFAUT"

# Variables d'état (positionnées au fil de l'eau)
declare -A GPU_CARD=() GPU_RENDER=() GPU_KFD=()
GPU_AVAILABLE='no'
GPU_SUMMARY='désactivé'
CONTAINER_CREATED='no'
TEMPLATE_CREATED='no'
UDEV_RULE_FILE=''
LXC_CONF_FILE=''

# =============================================================================
# 2. PARSING DES ARGUMENTS
# =============================================================================

usage() {
    sed -n '/^# INVOCATION/,/^# =====/p' "$0" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

CODES DE SORTIE
  0   succès
  1   erreur de préflight (validation)
  2   erreur d'usage (arguments)
  3   dépendance manquante (storage, bridge, template OS, pct)
  4   pct create a échoué
  5   configuration GPU a échoué
  6   reset machine-id a échoué
  7   pct template a échoué
  255 erreur non gérée (ne devrait plus apparaître)

DIAGNOSTIC
  Relancer avec --debug pour tracer chaque commande (set -x).
  Les erreurs pct/pveam/pvesm incluent désormais leur stderr.
EOF
    exit "${1:-0}"
}

need_arg() {
    [[ $# -ge 2 ]] || die_usage "Option '$1' requiert un argument (voir --help)"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--id)            need_arg "$@"; VMID="$2";        shift 2 ;;
		--hostname)      need_arg "$@"; HOSTNAME="$2";    shift 2 ;;
		--storage)       need_arg "$@"; STORAGE="$2";     shift 2 ;;
		--bridge)        need_arg "$@"; BRIDGE="$2";      shift 2 ;;
		--cores)         need_arg "$@"; CORES="$2";       shift 2 ;;
		--memory)        need_arg "$@"; MEMORY="$2";      shift 2 ;;
		--swap)          need_arg "$@"; SWAP="$2";        shift 2 ;;
		--disk)          need_arg "$@"; DISK="$2";        shift 2 ;;
		--nameserver)    need_arg "$@"; NAMESERVER="$2";  shift 2 ;;
		--searchdomain)  need_arg "$@"; SEARCHDOMAIN="$2"; shift 2 ;;
		--ip)            need_arg "$@"; IP="$2";          shift 2 ;;
		--gw)            need_arg "$@"; GW="$2";          shift 2 ;;
		--tags)          need_arg "$@"; TAGS="$2";        shift 2 ;;
		--template-os)   need_arg "$@"; TEMPLATE_OS="$2"; shift 2 ;;
		--root-password) ROOT_PASSWORD='ask';             shift   ;;
		--gpu)           GPU_ENABLE='yes';                shift   ;;
		--no-gpu)        GPU_ENABLE='no';                 shift   ;;
		--reset)         RESET_MACHINE_ID='yes';          shift   ;;
		--no-reset)      RESET_MACHINE_ID='no';           shift   ;;
		--force)         FORCE='yes';                     shift   ;;
		--dry-run)       DRY_RUN='yes';                   shift   ;;
		-h|--help)       usage 0 ;;
		--debug)         set -x; shift ;;
		*)               die_usage "Option inconnue : '$1' (voir --help)" ;;
	esac
done
#
# PAS encore implantés -> afaire mais j'ai qu'un IGP et pas 2 GPU ... pour tester : 
# --verbose|-v)    VERBOSE='yes'; shift ;;
# --gpu-pci)       need_arg "$@"; GPU_PCI_SELECT="$2"; GPU_ENABLE='yes'; shift 2 ;;


# =============================================================================
# 3. PRÉVOL (preflight checks)
# =============================================================================

# Détecte le volid du template Debian 13 sur tous les storages vztmpl.
# Fait défiler chaque storage et retourne le premier match.
# N'échoue QUE si aucun storage n'a de template Debian 13.
detect_template_os() {
    local storage out match
    # Storages ayant le content vztmpl
    local storages
    storages=$(pvesm status --content vztmpl 2>/dev/null \
        | awk 'NR>1 {print $1}') || true
    [[ -z "$storages" ]] && storages='local'

    for storage in $storages; do
        # pveam list <storage> — capture stderr pour diagnostic
        if ! out=$(pveam list "$storage" 2>&1); then
            log_warn "pveam list '$storage' a échoué (ignoré)"
            log_warn "  ${out//$'\n'/$'\n'  }"
            continue
        fi
        match=$(awk '/debian-13.*standard/ {print $1; exit}' <<< "$out")
        if [[ -n "$match" ]]; then
            printf '%s\n' "$match"
            return 0
        fi
    done
    return 1
}

preflight() {
    [[ $EUID -eq 0 ]] || die_user "Ce script doit être exécuté en root."

    command -v pct >/dev/null 2>&1 || die_env "pct introuvable — hôte Proxmox ?"
    command -v pveam >/dev/null 2>&1 || die_env "pveam introuvable — hôte Proxmox ?"
    command -v pvesm >/dev/null 2>&1 || die_env "pvesm introuvable — hôte Proxmox ?"
    [[ -d /etc/pve ]] || die_env "/etc/pve introuvable — Proxmox non détecté."

    # --- Storage rootfs ---
    if ! run_step "pvesm status --storage '$STORAGE'" pvesm status --storage "$STORAGE"; then
        die_env "Storage '$STORAGE' introuvable."
    fi

    # --- Bridge réseau ---
    if ! run_step "ip link show '$BRIDGE'" ip link show "$BRIDGE"; then
        die_env "Bridge '$BRIDGE' introuvable."
    fi

    # --- Validation réseau ---
    if [[ "$IP" != 'dhcp' && -z "$GW" ]]; then
        die_usage "--ip statique requiert --gw"
    fi

    # --- Template OS ---
    if [[ -z "$TEMPLATE_OS" ]]; then
        TEMPLATE_OS=$(detect_template_os) \
            || die_env "Aucun template Debian 13 sur les storages vztmpl. Utilisez --template-os <volid>."
        log_ok "Template OS auto-détecté : $TEMPLATE_OS"
    fi

    # --- Groupes render/video ---
    if [[ "$GPU_ENABLE" != 'no' ]]; then
        getent group render >/dev/null || log_warn "Groupe 'render' absent."
        getent group video  >/dev/null || log_warn "Groupe 'video'  absent."
    fi
	
	# --- ID libre ---
    if pct status "$VMID" &>/dev/null; then
        if [[ "$FORCE" != 'yes' ]]; then
            die_user "ID $VMID déjà utilisé (--force pour écraser)."
        fi
        log_warn "ID $VMID occupé mais --force actif → destruction."
        if [[ "$DRY_RUN" != 'yes' ]]; then
            pct stop    "$VMID" --skiplock 1 &>/dev/null || true
            pct destroy "$VMID" --purge 1 --force 1 &>/dev/null || true
        fi
    fi
}






# =============================================================================
# 4. DÉTECTION GPU (iGPU / dGPU)
# =============================================================================
#
# On utilise /sys/class/drm/<nom>/dev qui contient directement "major:minor"
# en décimal (plus fiable que parser `ls -l`, qui casse dès qu'un fichier a
# plusieurs nœuds ou un format de date inattendu).
#
#   $ cat /sys/class/drm/card0/dev       → 226:0
#   $ cat /sys/class/drm/renderD128/dev  → 226:128
#   $ cat /sys/class/kfd/kfd/dev         → 510:0
#
# Fallback : `ls -l` si sysfs indisponible (noyaux anciens).

lire_dev_id() {
    # $1 = chemin sysfs contenant "major:minor"
    # $2 = chemin /dev/... (fallback)
    local sysfs_dev="$1" dev_path="$2"
    if [[ -r "$sysfs_dev" ]]; then
        cat "$sysfs_dev"
        return 0
    fi
    if [[ -c "$dev_path" ]]; then
        local line major minor
        line=$(ls -l "$dev_path")
        # ls -l : perms links owner group major minor month day time name
        read -r _ _ _ _ major minor _ _ _ _ <<< "$line"
        printf '%s\n' "${major%,}:$minor"
        return 0
    fi
    return 1
}

detect_gpu() {
    log_info "Détection GPU sur l'hôte…"

    # --- /dev/dri/cardN ---
    local card_path
    card_path=$(compgen -G '/dev/dri/card[0-9]*' | head -1 || true)
    if [[ -n "$card_path" ]]; then
        GPU_CARD[nom]="$(basename "$card_path")"
        GPU_CARD[path]="$card_path"
        GPU_CARD[id]="$(lire_dev_id "/sys/class/drm/${GPU_CARD[nom]}/dev" "$card_path")" || GPU_CARD[id]=''
    fi

    # --- /dev/dri/renderDN ---
    local render_path
    render_path=$(compgen -G '/dev/dri/renderD[0-9]*' | head -1 || true)
    if [[ -n "$render_path" ]]; then
        GPU_RENDER[nom]="$(basename "$render_path")"
        GPU_RENDER[path]="$render_path"
        GPU_RENDER[id]="$(lire_dev_id "/sys/class/drm/${GPU_RENDER[nom]}/dev" "$render_path")" || GPU_RENDER[id]=''
    fi

    # --- /dev/kfd (ROCm, optionnel) ---
    if [[ -c /dev/kfd ]]; then
        GPU_KFD[nom]='kfd'
        GPU_KFD[path]='/dev/kfd'
        GPU_KFD[id]="$(lire_dev_id '/sys/class/kfd/kfd/dev' '/dev/kfd')" || GPU_KFD[id]=''
    fi

    if [[ -n "${GPU_CARD[id]:-}" || -n "${GPU_RENDER[id]:-}" ]]; then
        GPU_AVAILABLE='yes'
        GPU_SUMMARY="${GPU_CARD[nom]:-?} (${GPU_CARD[id]:-?}), ${GPU_RENDER[nom]:-?} (${GPU_RENDER[id]:-?}), ${GPU_KFD[nom]:-?} (${GPU_KFD[id]:-?})"
    fi
}

# =============================================================================
# 5. PATCH /etc/pve/lxc/$VMID.conf (cgroup2 + bind mounts GPU)
# =============================================================================
#
# Format attendu (cf. doc master §2.2) :
#   lxc.cgroup2.devices.allow: c 226:0 rwm
#   lxc.cgroup2.devices.allow: c 226:128 rwm
#   lxc.cgroup2.devices.allow: c 510:0 rwm
#   lxc.mount.entry: /dev/dri/card0 dev/dri/card0 none bind,optional,create=file
#   lxc.mount.entry: /dev/dri/renderD128 dev/dri/renderD128 none bind,optional,create=file
#   lxc.mount.entry: /dev/kfd dev/kfd none bind,optional,create=file
#
# ⚠️ Ne JAMAIS utiliser les liens by-path : le conteneur créerait un nœud au
#    chemin littéral, et la découverte DRM/ROCm (qui parcourt /dev/dri/)
#    ne trouverait rien. Toujours les chemins directs cardN / renderDN / kfd.

patch_lxc_config() {
    local vmid="$1"
    LXC_CONF_FILE="${PROXMOX_LXC_CONF_PATH}/${vmid}.conf"
    [[ -f "$LXC_CONF_FILE" ]] || die_gpu "Fichier $LXC_CONF_FILE introuvable (pct create a échoué ?)"

    log_info "Ajout du passthrough GPU dans $LXC_CONF_FILE"

    {
        echo ''
        echo '# --- GPU passthrough (auto-généré par '"$SCRIPT_NAME"') ---'
        [[ -n "${GPU_CARD[id]:-}"   ]] && echo "lxc.cgroup2.devices.allow: c ${GPU_CARD[id]} rwm"
        [[ -n "${GPU_RENDER[id]:-}" ]] && echo "lxc.cgroup2.devices.allow: c ${GPU_RENDER[id]} rwm"
        [[ -n "${GPU_KFD[id]:-}"    ]] && echo "lxc.cgroup2.devices.allow: c ${GPU_KFD[id]} rwm"
        [[ -n "${GPU_CARD[path]:-}"   ]] && echo "lxc.mount.entry: ${GPU_CARD[path]} ${GPU_CARD[path]#/} none bind,optional,create=file"
        [[ -n "${GPU_RENDER[path]:-}" ]] && echo "lxc.mount.entry: ${GPU_RENDER[path]} ${GPU_RENDER[path]#/} none bind,optional,create=file"
        [[ -n "${GPU_KFD[path]:-}"    ]] && echo "lxc.mount.entry: ${GPU_KFD[path]} ${GPU_KFD[path]#/} none bind,optional,create=file"
    } >> "$LXC_CONF_FILE"
}

# =============================================================================
# 6. RÈGLE UDEV (permissions GPU pour LXC unprivileged)
# =============================================================================
#
# Un conteneur unprivileged mappe root → UID 100000 sur l'hôte.
# Les nœuds /dev/dri/* et /dev/kfd sont créés 0660 root:video ou root:render.
# L'UID 100000 n'appartient pas à ces groupes → pas d'accès.
#
# MODE="0666" rend les nœuds accessibles à tous. Sur un hôte Proxmox
# mono-utilisateur, le compromis est acceptable (cf. doc llama.cpp §4.1).
#
# ⚠️ BUG documenté dans INSTALL-LLAMA-CPP-LXC.md §4.1 :
#    KERNEL=="kfd", SUBSYSTEM=="drm"  ← FAUX
#    Le bon subsystem est "kfd" (vérifiable avec :
#    `udevadm info -q property -n /dev/kfd | grep SUBSYSTEM`)

write_udev_rule() {
    local vmid="$1"
    UDEV_RULE_FILE="${PROXMOX_UDEV_PATH}/99-lxc-gpu-${vmid}.rules"

    log_info "Écriture de la règle udev : $UDEV_RULE_FILE"

    {
        echo "# Auto-généré par $SCRIPT_NAME pour le conteneur LXC $vmid"
        echo "# Permissions GPU (MODE=0666) pour un conteneur non privilégié :"
        echo "# root du conteneur = UID 100000, hors groupes render/video"
        [[ -n "${GPU_CARD[id]:-}"   ]] && echo "KERNEL==\"${GPU_CARD[nom]}\", SUBSYSTEM==\"drm\", MODE=\"0666\""
        [[ -n "${GPU_RENDER[id]:-}" ]] && echo "KERNEL==\"${GPU_RENDER[nom]}\", SUBSYSTEM==\"drm\", MODE=\"0666\""
        [[ -n "${GPU_KFD[id]:-}"    ]] && echo "KERNEL==\"kfd\", SUBSYSTEM==\"kfd\", MODE=\"0666\""
    } > "$UDEV_RULE_FILE"

    chmod 0644 "$UDEV_RULE_FILE"
}

reload_udev() {
    log_info "Rechargement des règles udev"
    udevadm control --reload-rules
    udevadm trigger --subsystem-match=drm 2>/dev/null || true
    udevadm trigger --subsystem-match=kfd 2>/dev/null || true
    udevadm settle --timeout=10 || true
}

# =============================================================================
# 7. RESET machine-id + clés SSH (via pct mount, SANS démarrer)
# =============================================================================
#
# Cf. CONTAINER-MAITRE-VIERGE-R7-IGPU.md §5. Sans ce reset, tous les clones
# héritent du même machine-id (conflits systemd-networkd/journald) et des
# mêmes clés SSH d'hôte (faille de sécurité).
#
# On utilise `pct mount` qui monte le rootfs sans démarrer le conteneur —
# plus propre que start/reset/shutdown, et conforme à la philosophie
# "ne pas démarrer le template".

reset_machine_id_and_ssh() {
    local vmid="$1"
    log_info "Montage du rootfs de $vmid pour reset machine-id + SSH"
    pct mount "$vmid"

    local rootfs="/var/lib/lxc/${vmid}/rootfs"
    [[ -d "$rootfs" ]] || die_reset "pct mount a échoué (rootfs introuvable pour $vmid)."

    # --- machine-id : fichier VIDE = régénération au prochain boot ---
    # `: >` crée le fichier s'il est absent, le tronque sinon.
    log_info "Reset /etc/machine-id (fichier 0 octet = régénération auto)"
    : > "${rootfs}/etc/machine-id"
    ln -sfn /etc/machine-id "${rootfs}/var/lib/dbus/machine-id" 2>/dev/null || true

    # --- Clés SSH d'hôte : suppression ---
    log_info "Suppression des clés SSH d'hôte (régénérées au prochain boot des clones)"
    rm -f "${rootfs}/etc/ssh/ssh_host_"* 2>/dev/null || true

    log_info "Démontage du rootfs"
    pct unmount "$vmid"
}

# =============================================================================
# 8. TRAP DE NETTOYAGE
# =============================================================================

cleanup_on_error() {
    local rc=$?
    [[ $rc -eq 0 ]] && return 0

    # Rien n'a été créé → le preflight a échoué, pas la peine de crier.
    # Le die() a déjà expliqué la cause avec le bon code.
    if [[ "$CONTAINER_CREATED" == 'no' && -z "$UDEV_RULE_FILE" ]]; then
        return 0
    fi

    log_error "Nettoyage après échec (code $rc)…"

    if [[ "$TEMPLATE_CREATED" == 'yes' ]]; then
        log_warn "Template $VMID déjà créé — non détruit (nettoyage manuel si besoin)."
    elif [[ "$CONTAINER_CREATED" == 'yes' ]] && pct status "$VMID" &>/dev/null; then
        log_warn "Destruction du conteneur partiel $VMID"
        pct stop    "$VMID" --skiplock 1 &>/dev/null || true
        pct destroy "$VMID" --purge 1 --force 1 &>/dev/null || true
    fi

    if [[ -n "$UDEV_RULE_FILE" && -f "$UDEV_RULE_FILE" ]]; then
        log_warn "Suppression de la règle udev $UDEV_RULE_FILE"
        rm -f "$UDEV_RULE_FILE"
        udevadm control --reload-rules &>/dev/null || true
    fi
}
trap cleanup_on_error EXIT

# =============================================================================
# 9. RÉCAPITULATIF
# =============================================================================

print_summary() {
    cat <<EOF

${C_BOLD}══════════════════════════════════════════════════════════════════${C_OFF}
${C_BOLD} Template LXC ${C_OK}${VMID}${C_OFF}${C_BOLD} créé avec succès${C_OFF}
${C_BOLD}══════════════════════════════════════════════════════════════════${C_OFF}

  Hostname    : ${HOSTNAME}
  Template OS : ${TEMPLATE_OS}
  Cores       : ${CORES}
  RAM / Swap  : ${MEMORY} MiB / ${SWAP} MiB
  Disque      : ${DISK} Go sur ${STORAGE}
  Réseau      : ${BRIDGE}, ip=${IP}$( [[ -n "$GW" ]] && echo ", gw=$GW" )
  Nameserver  : ${NAMESERVER}
  Searchdomain: $( [[ -z "$SEARCHDOMAIN" ]] && echo '(vide — correct)' || echo "$SEARCHDOMAIN" )
  Features    : ${FEATURES}
  Template    : $([[ "$TEMPLATE_CREATED" == 'yes' ]] && echo 'oui' || echo 'NON')
  Machine-id  : $([[ "$RESET_MACHINE_ID" == 'yes' ]] && echo 'reset (0 octet, régénération au clone)' || echo 'NON reset — ATTENTION clones impurs')
  Clés SSH    : $([[ "$RESET_MACHINE_ID" == 'yes' ]] && echo 'supprimées (régénérées au clone)' || echo 'NON supprimées')
  GPU         : ${GPU_SUMMARY}
  Règle udev  : ${UDEV_RULE_FILE:-'(aucune — pas de GPU configuré)'}

${C_BOLD}Prochaines étapes${C_OFF}
  1. Vérifier  : pct config ${VMID} | grep -E 'cgroup2|mount.entry|template|features'
  2. Cloner    : pct clone ${VMID} 201 --hostname mon-service-r7 --full
  3. Démarrer  : pct start 201 && pct enter 201
  4. Valider   : vulkaninfo --summary   (dans le clone)
  5. Sauver    : vzdump ${VMID} --storage local --mode snapshot --compress zstd

EOF
}

# =============================================================================
# 10. FLUX PRINCIPAL
# =============================================================================

main() {
    log_info "=== ${SCRIPT_NAME} v${PROG_VERSION} — création template LXC ${VMID} ==="

    preflight

    # --- Détection GPU (avant pct create pour échouer tôt si --gpu) ---
    if [[ "$GPU_ENABLE" != 'no' ]]; then
        detect_gpu
        if [[ "$GPU_AVAILABLE" != 'yes' ]]; then
            if [[ "$GPU_ENABLE" == 'yes' ]]; then
                die_gpu "GPU demandé (--gpu) mais aucun /dev/dri détecté sur l'hôte."
            fi
            log_warn "Aucun GPU détecté — template créé SANS passthrough GPU."
            GPU_ENABLE='no'
            GPU_SUMMARY='aucun (pas de GPU détecté sur l hôte)'
        else
            log_ok "GPU détecté : ${GPU_SUMMARY}"
			GPU_ENABLE='yes'   # auto → yes après détection réussie
        fi
    fi

    # --- DRY-RUN : afficher et sortir ---
    if [[ "$DRY_RUN" == 'yes' ]]; then
        log_warn "MODE --dry-run : aucune modification effectuée"
        cat <<EOF

${C_BOLD}Actions qui seraient exécutées :${C_OFF}
  1. pct create ${VMID} ${TEMPLATE_OS} \\
       --hostname ${HOSTNAME} --unprivileged 1 --features ${FEATURES} \\
       --cores ${CORES} --memory ${MEMORY} --swap ${SWAP} \\
       --rootfs ${STORAGE}:${DISK} \\
       --net0 name=eth0,bridge=${BRIDGE},ip=${IP}$( [[ -n "$GW" ]] && echo ",gw=${GW}" ),type=veth,firewall=${FIREWALL} \\
       --nameserver ${NAMESERVER} --ostype debian --tags "${TAGS}" --start 0
  2. Édition ${PROXMOX_LXC_CONF_PATH}/${VMID}.conf (cgroup2 + mount.entry GPU)
  3. Création ${PROXMOX_UDEV_PATH}/99-lxc-gpu-${VMID}.rules + udevadm reload
  4. $( [[ "$RESET_MACHINE_ID" == 'yes' ]] \
         && echo "pct mount ${VMID} → reset machine-id + SSH → pct unmount" \
         || echo "reset machine-id + SSH : IGNORÉ (--no-reset)" )
  5. pct template ${VMID}
EOF
        return 0
    fi

    # --- 1. Création du conteneur (NON démarré) ---
    log_info "Création du conteneur $VMID (start=0)"

    local net_opts="name=eth0,bridge=${BRIDGE},ip=${IP}"
    [[ -n "$GW" ]] && net_opts="${net_opts},gw=${GW}"
    net_opts="${net_opts},type=veth,firewall=${FIREWALL}"

    local create_cmd=(
        pct create "$VMID" "$TEMPLATE_OS"
        --hostname     "$HOSTNAME"
        --unprivileged 1
        --features     "$FEATURES"
        --cores        "$CORES"
        --memory       "$MEMORY"
        --swap         "$SWAP"
        --rootfs       "${STORAGE}:${DISK}"
        --net0         "$net_opts"
        --nameserver   "$NAMESERVER"
        --ostype       debian
        --tags         "$TAGS"
        --description  "Template LXC cree par ${SCRIPT_NAME} le $(date +%F)"
        --start        0
    )
    # NOTE : on ne passe PAS --searchdomain (cf. anomalie §15.1 doc master,
    #        pct peut injecter le DNS dans ce champ par confusion).
    # NOTE : on ne passe PAS --password (template sans mot de passe root ;
    #        accès via `pct enter`, ou --root-password pour opt-in).
    [[ "$ROOT_PASSWORD" == 'ask' ]] && create_cmd+=(--password)

    log_info "Commande : ${create_cmd[*]}"
    if ! run_step "pct create $VMID" "${create_cmd[@]}"; then
        die_create "pct create a échoué (voir contexte ci-dessus)."
    fi
    CONTAINER_CREATED='yes'
    log_ok "Conteneur $VMID créé (non démarré)"

    # --- 2. Config GPU ---
    if [[ "$GPU_ENABLE" == 'yes' ]]; then
        patch_lxc_config "$VMID" \
            || die_gpu "Échec du patch ${PROXMOX_LXC_CONF_PATH}/${VMID}.conf"
        write_udev_rule  "$VMID" \
            || die_gpu "Échec de l'écriture de la règle udev"
        reload_udev      || die_gpu "Échec de udevadm reload"
        log_ok "Passthrough GPU configuré (cgroup2 + mount.entry + udev)"
    fi

    # --- 3. Reset machine-id + SSH (via pct mount, sans démarrer) ---
    if [[ "$RESET_MACHINE_ID" == 'yes' ]]; then
        reset_machine_id_and_ssh "$VMID" \
            || die_reset "Échec du reset machine-id + SSH"
        log_ok "machine-id et clés SSH réinitialisés"
    else
        log_warn "Reset machine-id + SSH IGNORÉ (--no-reset) — clones impurs !"
    fi

    # --- 4. Conversion en template ---
    log_info "Conversion du conteneur $VMID en template"
    if ! run_step "pct template $VMID" pct template "$VMID"; then
        die_template "Échec de la conversion en template."
    fi
    TEMPLATE_CREATED='yes'
    log_ok "Conteneur $VMID converti en template"

    # --- 5. Récapitulatif ---
    print_summary
}

main "$@"

