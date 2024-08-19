clear
neofetch

alias clear="command clear; neofetch"

if status is-interactive
    # Commands to run in interactive sessions can go here
end

fish_config theme choose "Rosé Pine" 
thefuck --alias | source

function kitty
    /usr/bin/kitty --session ~/.config/kitty/sessions/startup.conf $argv
end

set fish_greeting ""
