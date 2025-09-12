#!/usr/bin/env fish

argparse -n 'install.fish' -X 0 \
    'h/help' \
    'noconfirm' \
    'paru' \
    -- $argv
or exit

# Print help
if set -q _flag_h
    echo 'usage: ./install.sh [-h] [--noconfirm] [--paru]'
    echo
    echo 'options:'
    echo '  -h, --help                  show this help message and exit'
    echo '  --noconfirm                 do not confirm package installation'
    echo '  --paru                      uses the aur helper paru instead of default yay'

    exit
end

# Functions
function _out -a colour text
    set_color $colour
    # Pass arguments other than text to echo
    echo $argv[3..] -- ":: $text"
    set_color normal
end

function log -a text
    _out cyan $text $argv[2..]
end

function input -a text
    _out blue $text $argv[2..]
end

function confirm-overwrite -a path use_sudo
    if test -e $path -o -L $path
        # No prompt if noconfirm
        if set -q noconfirm
            input "$path already exists. Overwrite? [Y/n]"

            if test "$use_sudo"
                log 'Removing (SUDO)...'
                sudo rm -rf $path
            else
                log 'Removing...'
                rm -rf $path
            end
        else
            # Prompt user
            read -l -p "input '$path already exists. Overwrite? [Y/n] ' -n" confirm || exit 1

            if test "$confirm" = 'n' -o "$confirm" = 'N'
                log 'Skipping...'
                return 1
            else
                if test "$use_sudo"
                    log 'Removing (SUDO)...'
                    sudo rm -rf $path
                else
                    log 'Removing...'
                    rm -rf $path
                end
            end
        end
    end

    return 0
end

# Variables
set -q _flag_noconfirm && set noconfirm '--noconfirm'
set -q _flag_paru && set -l aur_helper paru || set -l aur_helper yay
set -q XDG_CONFIG_HOME && set -l config $XDG_CONFIG_HOME || set -l config $HOME/.config
set -q XDG_STATE_HOME && set -l state $XDG_STATE_HOME || set -l state $HOME/.local/state

# Startup prompt
set_color cyan
echo '╭──────────────────────────────╮'
echo '│   ____      __     __        │'
echo '│  |  _ \   /\\ \   / //\       │'
echo '│  | |_) | /  \\ \_/ //  \      │'
echo '│  |  _ < / /\ \\   // /\ \     │'
echo '│  | |_) / ____ \| |/ ____ \   │'
echo '│  |____/_/    \_\_/_/    \_\  │'
echo '│                              │'
echo '╰──────────────────────────────╯'
set_color normal

log 'Welcome to the Baya dotfiles installer!'
log 'Before continuing, please ensure you have made a backup of your config directory.'

# Prompt for backup
if ! set -q _flag_noconfirm
    log '[1] No Need!  [2] Backup Needed!'
    read -l -p "input '=> ' -n" choice || exit 1

    if contains -- "$choice" 1 2
        if test $choice = 2
            log "Backing up $config..."

            if test -e $config.bak -o -L $config.bak
                read -l -p "input 'Backup already exists. Overwrite? [Y/n] ' -n" overwrite || exit 1

                if test "$overwrite" = 'n' -o "$overwrite" = 'N'
                    log 'Skipping...'
                else
                    rm -rf $config.bak
                    cp -r $config $config.bak
                end
            else
                cp -r $config $config.bak
            end
        end
    else
        log 'No choice selected. Exiting...'
        exit 1
    end
end

# Install AUR helper if not already installed
if ! pacman -Q $aur_helper &> /dev/null
    log "$aur_helper not installed. Installing..."

    # Install
    sudo pacman -S --needed git base-devel $noconfirm
    cd /tmp
    git clone https://aur.archlinux.org/$aur_helper.git
    cd $aur_helper
    makepkg -si
    cd ..
    rm -rf $aur_helper

    # Setup
    $aur_helper -Y --gendb
    $aur_helper -Y --devel --save
end

# Install metapackage for deps
log 'Installing metapackage...'
$aur_helper -S --needed baya-meta $noconfirm

# Cd into dir
cd (dirname (status filename)) || exit 1

# Install hypr* configs
if confirm-overwrite $config/hypr
    log 'Installing hypr* configs...'
    ln -s (realpath configs/hypr) $config/hypr
    hyprctl reload
end

# Plymouth themes
set plymouth_theme_src (realpath plymouth-themes)
if test -d $plymouth_theme_src
    if confirm-overwrite /usr/share/plymouth/themes/mikuboot true
        log 'Copying Plymouth theme - mikuboot...'
        sudo mkdir -p /usr/share/plymouth/themes/mikuboot
        sudo cp -r $plymouth_theme_src/mikuboot /usr/share/plymouth/themes/mikuboot
    end
end

# Update mkinitcpio hooks for plymouth
set mkinit_file /etc/mkinitcpio.conf
if test -f $mkinit_file
    set hooks (grep -E '^\s*HOOKS=' /etc/mkinitcpio.conf)

    if test -n "$hooks"
        if not contains 'plymouth' $hooks
            log 'Adding plymouth hook to mkinitcpio...'
            set new_hooks (string replace -r 'HOOKS=\((.*)filesystems(.*)\)' 'HOOKS=(\1plymouth filesystems\2)' $hooks)
            sudo sed -i "s|$hooks|$new_hooks|" $mkinit_file

            # Regenerate initramfs only if presets exist
            if test (count (ls /etc/mkinitcpio.d/*.preset 2>/dev/null)) -gt 0
                log 'Regenerating initramfs...'
                sudo mkinitcpio -P
            else
                log 'No mkinitcpio presets found. Skipping initramfs regeneration.'
            end
        else
            log 'Plymouth hook already in mkinitcpio.conf. Skipping...'
        end
    else
        log 'HOOKS line not found in mkinitcpio.conf. Skipping...'
    end
end

# Ensure splash is in kernel parameters (idempotent)
set loader_file /boot/loader/entries/arch.conf

if test -f $loader_file
    log 'Ensuring splash is in kernel parameters...'
    set options_line (grep '^options' $loader_file)
    if not string match -q '*splash*' $options_line
        log 'Adding splash to kernel parameters...'
        sudo sed -i "s|^\(options.*\)|\1 splash|" $loader_file
    else
        log 'Splash already present in kernel parameters. Skipping...'
    end
end

log 'Baya Dots Finished Installing!'