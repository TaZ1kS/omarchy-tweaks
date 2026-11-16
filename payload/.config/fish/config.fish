if status is-interactive
    # Remove greeting
    set -g fish_greeting ""

    # Colours come from the active Omarchy theme. The palette file is
    # regenerated on every theme change by
    # ~/.config/omarchy/hooks/theme-set.d/50-fish-theme.
    if test -f ~/.config/fish/theme.fish
        source ~/.config/fish/theme.fish
    end

    # Aliases
    alias ls='eza --icons=always --color=auto'
    alias ll='eza -la --icons=always --color=auto'
    alias la='eza -a --icons=always --color=auto'
    alias tree='eza --tree --icons=always --color=auto'
    alias materialgram='/usr/bin/materialgram -scale 125'
end

# LS_COLORS / EZA_COLORS are exported from ~/.config/fish/theme.fish, so ls,
# eza and lsblk all follow the current theme instead of a fixed orange.


# Added by Antigravity CLI installer
set -gx PATH "${HOME}/.local/bin" $PATH
