#!/usr/bin/env fish

argparse -n 'install.fish' -X 0 \
    'h/help' \
    'noconfirm' \
    'paru' \
    'plymouth=' \
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
    echo '  --plymouth=mikuboot       uses the specified plymouth theme (default: mikuboot)'

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
set -q _flag_plymouth && set -l plymouth_theme $_flag_plymouth || set -l plymouth_theme mikuboot

set -q XDG_CONFIG_HOME && set -l config $XDG_CONFIG_HOME || set -l config $HOME/.config
set -q XDG_STATE_HOME && set -l state $XDG_STATE_HOME || set -l state $HOME/.local/state

# Checks
if ! test -d (realpath plymouth-themes/$plymouth_theme 2>/dev/null)
    set plymouth_theme mikuboot
end

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

# Install hypr* configs
if confirm-overwrite $config/hypr
    log 'Installing hypr* configs...'
    ln -s (realpath configs/hypr) $config/hypr
    hyprctl reload
end

# Plymouth themes
set plymouth_theme_src (realpath plymouth-themes)
if test -d $plymouth_theme_src
    for theme_dir in $plymouth_theme_src/*/
        set theme_name (basename $theme_dir)
        set target_path /usr/share/plymouth/themes/$theme_name

        if confirm-overwrite $target_path true
            log "Copying Plymouth theme - $theme_name..."
            sudo mkdir -p $target_path
            sudo cp -r $plymouth_theme_src/$theme_name/* $target_path/
        end
    end
end

# Update mkinitcpio hooks for plymouth
set mkinit_file /etc/mkinitcpio.conf

if test -f $mkinit_file
    # check if HOOKS line already contains plymouth
    if grep -qE '^\s*HOOKS=.*\bplymouth\b' $mkinit_file
        log 'Plymouth hook already in mkinitcpio.conf. Skipping...'
    else
        log 'Adding plymouth hook to mkinitcpio...'

        # backup
        sudo cp $mkinit_file $mkinit_file.bak

        # Insert "plymouth " immediately before the first "filesystems" in the HOOKS line
        sudo sed -i -E "s/^(HOOKS=.*)filesystems/\1plymouth filesystems/" $mkinit_file
    end

    # create/overwrite plymouth conf (expand $plymouth_theme from fish)
    sudo sh -c "cat > /etc/plymouth/plymouth.conf <<EOF
[Daemon]
Theme=$plymouth_theme
ShowDelay=0
DeviceTimeout=30
EOF"

    # regenerate initramfs for all kernels
    sudo mkinitcpio -P
else
    log 'mkinitcpio.conf not found. Skipping...'
end

# Ensure splash is in kernel parameters (idempotent)
for entry in /boot/loader/entries/*.conf
    if test -f $entry
        set options_line (grep '^options' $entry)
        if not string match -q '*splash*' $options_line
            log "Ensuring splash in $entry..."

            sudo sed -i "s|^\(options.*\)|\1 splash|" $entry
        end
    end
end

# Set Plymouth Theme
sudo plymouth-set-default-theme $plymouth_theme

# Final message
log 'Baya Dots Finished Installing!'