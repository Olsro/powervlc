#!/bin/sh
# Install or update a PowerVLC AppImage for the current desktop user.
# No distribution package manager or root privileges are required.
set -eu

usage()
{
    cat <<'EOF'
Usage: ./install-powervlc.sh [--install] [--no-launch] [PowerVLC-*.AppImage]
       ./install-powervlc.sh --uninstall

Installs or updates PowerVLC for the current user and adds it to the desktop
application menu. If no AppImage is specified, the one beside this script is
used. With no action option, an installer window asks whether to install,
update, uninstall or cancel. Existing preferences and media-library data are
preserved.
EOF
}

launch=true
requested_action=
source_app=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --no-launch) launch=false ;;
        --install|--uninstall)
            action=${1#--}
            [ -z "$requested_action" ] || [ "$requested_action" = "$action" ] || {
                echo "Choose only one of --install and --uninstall." >&2
                exit 64
            }
            requested_action=$action
            ;;
        -h|--help) usage; exit 0 ;;
        --) shift; [ "$#" -eq 0 ] || source_app=$1; break ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 64 ;;
        *)
            [ -z "$source_app" ] || {
                echo "Only one AppImage can be installed at a time." >&2
                exit 64
            }
            source_app=$1
            ;;
    esac
    shift
done

: "${HOME:?HOME is not set}"
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
install_dir="$data_home/powervlc"
applications_dir="$data_home/applications"
icons_dir="$data_home/icons/hicolor/256x256/apps"
desktop_file="$applications_dir/com.github.PowerVLC.desktop"
icon_file="$icons_dir/powervlc.png"

case "$(uname -m)" in
    x86_64|amd64) appimage_arch=x86_64 ;;
    i386|i486|i586|i686) appimage_arch=i386 ;;
    aarch64|arm64) appimage_arch=aarch64 ;;
    *)
        echo "Unsupported Linux architecture: $(uname -m)" >&2
        exit 1
        ;;
esac
installed_app="$install_dir/PowerVLC-$appimage_arch.AppImage"
was_installed=false
[ ! -f "$installed_app" ] || was_installed=true

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
installer_i18n="$script_dir/.install-powervlc-i18n.sh"
[ -r "$installer_i18n" ] || {
    echo "Installer translations are missing: $installer_i18n" >&2
    exit 1
}
. "$installer_i18n"
pvlc_installer_set_language

has_gui=false
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    has_gui=true
fi

if $was_installed; then
    action_prompt=$existing_prompt
else
    action_prompt=$new_prompt
fi

if [ -z "$requested_action" ]; then
    if $has_gui && command -v zenity >/dev/null 2>&1; then
        if $was_installed; then
            choice=
            if choice=$(zenity --question --title="PowerVLC" --icon=powervlc \
                --no-markup --text="$action_prompt" --ok-label="$update_label" \
                --cancel-label="$cancel_label" --extra-button="$uninstall_label"); then
                status=0
            else
                status=$?
            fi
            # Zenity deliberately returns 1 for both Cancel and extra buttons,
            # including in 4.x for compatibility with 3.x. Extra buttons also
            # print their label, which is therefore the authoritative result.
            if [ "$choice" = "$uninstall_label" ]; then
                requested_action=uninstall
            elif [ "$status" -eq 0 ]; then
                requested_action=install
            else
                exit 0
            fi
        elif zenity --question --title="PowerVLC" --icon=powervlc \
            --no-markup --text="$action_prompt" --ok-label="$install_label" \
            --cancel-label="$cancel_label"; then
            requested_action=install
        else
            exit 0
        fi
    elif $has_gui && command -v kdialog >/dev/null 2>&1; then
        if $was_installed; then
            if choice=$(kdialog --title "PowerVLC" --menu "$action_prompt" \
                install "$update_label" uninstall "$uninstall_label"); then
                requested_action=$choice
            else
                exit 0
            fi
        elif kdialog --title "PowerVLC" --yesno "$action_prompt" \
            --yes-label "$install_label" --no-label "$cancel_label"; then
            requested_action=install
        else
            exit 0
        fi
    elif $has_gui && command -v xmessage >/dev/null 2>&1; then
        if $was_installed; then
            if xmessage -center -buttons "$update_label":0,"$uninstall_label":2,"$cancel_label":1 \
                -default "$cancel_label" "$action_prompt"; then
                requested_action=install
            else
                status=$?
                case "$status" in
                    2) requested_action=uninstall ;;
                    *) exit 0 ;;
                esac
            fi
        elif xmessage -center -buttons "$install_label":0,"$cancel_label":1 \
            -default "$cancel_label" "$action_prompt"; then
            requested_action=install
        else
            exit 0
        fi
    elif [ -t 0 ]; then
        printf '%s\n' "$action_prompt"
        if $was_installed; then
            printf '[i] %s  [u] %s  [c] %s: ' \
                "$update_label" "$uninstall_label" "$cancel_label"
            read -r choice
            case "$choice" in
                i|I) requested_action=install ;;
                u|U) requested_action=uninstall ;;
                *) exit 0 ;;
            esac
        else
            printf '[i] %s  [c] %s: ' "$install_label" "$cancel_label"
            read -r choice
            case "$choice" in i|I) requested_action=install ;; *) exit 0 ;; esac
        fi
    else
        echo "$no_dialog_error" >&2
        exit 1
    fi
fi

if [ "$requested_action" = uninstall ]; then
    # Selecting Uninstall in the action chooser is reversible with a reinstall,
    # but still deserves a separate confirmation. An explicit --uninstall is
    # intended for scripts and remains non-interactive.
    if $has_gui && [ "${action:-}" != uninstall ]; then
        if command -v zenity >/dev/null 2>&1; then
            zenity --question --title="PowerVLC" --icon=powervlc --no-markup \
                --text="$uninstall_prompt" --ok-label="$uninstall_label" \
                --cancel-label="$cancel_label" || exit 0
        elif command -v kdialog >/dev/null 2>&1; then
            kdialog --title "PowerVLC" --warningyesno "$uninstall_prompt" \
                --yes-label "$uninstall_label" --no-label "$cancel_label" || exit 0
        elif command -v xmessage >/dev/null 2>&1; then
            xmessage -center -buttons "$uninstall_label":0,"$cancel_label":1 \
                -default "$cancel_label" "$uninstall_prompt" || exit 0
        fi
    fi

    rm -f -- "$installed_app" "$desktop_file" "$icon_file"
    rmdir "$install_dir" 2>/dev/null || true
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
    fi
    echo "PowerVLC has been removed for this user. Preferences were preserved."
    if $has_gui; then
        result="$uninstalled_result

$preserved_result"
        if command -v zenity >/dev/null 2>&1; then
            zenity --info --title="PowerVLC" --icon=powervlc --no-markup \
                --text="$result" --ok-label="$close_label" || true
        elif command -v kdialog >/dev/null 2>&1; then
            kdialog --title "PowerVLC" --msgbox "$result" || true
        elif command -v notify-send >/dev/null 2>&1; then
            notify-send --app-name="PowerVLC" --icon=powervlc \
                "PowerVLC" "$result" || true
        fi
    fi
    exit 0
fi

if [ -z "$source_app" ]; then
    # A release ZIP contains exactly one AppImage for its architecture. Refuse
    # an ambiguous Downloads directory instead of installing an older build.
    set -- "$script_dir"/PowerVLC-*-$appimage_arch.AppImage
    if [ "$#" -ne 1 ] || [ ! -f "$1" ]; then
        echo "Place this installer beside exactly one PowerVLC *-$appimage_arch.AppImage," >&2
        echo "or pass the AppImage path explicitly." >&2
        exit 1
    fi
    source_app=$1
fi
[ -f "$source_app" ] || { echo "AppImage not found: $source_app" >&2; exit 1; }

source_dir=$(CDPATH= cd -- "$(dirname -- "$source_app")" && pwd)
source_app="$source_dir/$(basename -- "$source_app")"
case "$(basename -- "$source_app")" in
    PowerVLC-*-$appimage_arch.AppImage) ;;
    *)
        echo "This AppImage does not match the $appimage_arch architecture." >&2
        exit 1
        ;;
esac

version=${source_app##*/PowerVLC-}
version=${version%-$appimage_arch.AppImage}
mkdir -p -- "$install_dir" "$applications_dir" "$icons_dir"

temporary_app="$install_dir/.PowerVLC-$appimage_arch.AppImage.$$"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/powervlc-install.XXXXXX")
cleanup()
{
    rm -f -- "$temporary_app" "$desktop_file.tmp.$$" "$icon_file.tmp.$$"
    rm -rf -- "$scratch"
}
trap cleanup EXIT HUP INT TERM

cp -- "$source_app" "$temporary_app"
chmod 0755 "$temporary_app"

# The authoritative desktop entry and icon are already embedded in every
# AppImage. Extract just those files without FUSE, then rewrite only the Exec
# path to the stable per-user installation location.
(
    cd "$scratch"
    "$temporary_app" --appimage-extract \
        'usr/share/applications/vlc.desktop' >/dev/null
    "$temporary_app" --appimage-extract \
        'usr/share/icons/hicolor/256x256/apps/powervlc.png' >/dev/null
)
extracted_desktop="$scratch/squashfs-root/usr/share/applications/vlc.desktop"
extracted_icon="$scratch/squashfs-root/usr/share/icons/hicolor/256x256/apps/powervlc.png"
[ -s "$extracted_desktop" ] || { echo "The AppImage has no desktop entry." >&2; exit 1; }
[ -s "$extracted_icon" ] || { echo "The AppImage has no PowerVLC icon." >&2; exit 1; }

escaped_exec=$(printf '%s' "$installed_app" | sed 's/[\\`"$]/\\&/g')
PVLC_DESKTOP_EXEC="Exec=\"$escaped_exec\" --started-from-file %U" \
PVLC_APPIMAGE_VERSION="$version" PVLC_APPIMAGE_ARCH="$appimage_arch" \
awk '
    /^Exec=/ { print ENVIRON["PVLC_DESKTOP_EXEC"]; next }
    /^TryExec=/ { next }
    /^X-AppImage-(Name|Version|Arch)=/ { next }
    { print }
    END {
        print "X-AppImage-Name=PowerVLC"
        print "X-AppImage-Version=" ENVIRON["PVLC_APPIMAGE_VERSION"]
        print "X-AppImage-Arch=" ENVIRON["PVLC_APPIMAGE_ARCH"]
    }
' "$extracted_desktop" >"$desktop_file.tmp.$$"
cp -- "$extracted_icon" "$icon_file.tmp.$$"
chmod 0644 "$desktop_file.tmp.$$" "$icon_file.tmp.$$"

# Publish all three files only after extraction and validation succeeded. The
# stable AppImage filename makes this operation an update as well as an install.
mv -f -- "$temporary_app" "$installed_app"
mv -f -- "$desktop_file.tmp.$$" "$desktop_file"
mv -f -- "$icon_file.tmp.$$" "$icon_file"
trap - EXIT HUP INT TERM
rm -rf -- "$scratch"

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$desktop_file"
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
fi
if [ -f "$data_home/icons/hicolor/index.theme" ] &&
   command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$data_home/icons/hicolor" >/dev/null 2>&1 || true
fi

echo "PowerVLC $version installed for the current user."
echo "Application: $installed_app"
echo "Menu entry:  $desktop_file"

if $launch && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
    # A graphical launch may have no persistent terminal, so report success
    # before starting the player. Prefer the toolkit dialog supplied by the
    # current desktop, then fall back to a freedesktop notification when no
    # dialog helper exists.
    if $was_installed; then
        result=$(printf "$updated_result" "$version")
    else
        result=$(printf "$installed_result" "$version")
    fi
    result="$result

$available_result"

    if command -v zenity >/dev/null 2>&1; then
        zenity --info --title="PowerVLC" --icon=powervlc --no-markup \
            --text="$result" --ok-label="$launch_label" || true
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --title "PowerVLC" --msgbox "$result" || true
    elif command -v notify-send >/dev/null 2>&1; then
        notify-send --app-name="PowerVLC" --icon=powervlc \
            "PowerVLC" "$result" || true
    fi

    if command -v gtk-launch >/dev/null 2>&1; then
        nohup gtk-launch com.github.PowerVLC >/dev/null 2>&1 &
    else
        nohup "$installed_app" >/dev/null 2>&1 &
    fi
fi
