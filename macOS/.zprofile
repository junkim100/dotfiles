##### Homebrew #####
# Homebrew's installer only prints this line under "Next steps" and never writes it to a shell file,
# so on a fresh machine nothing puts the Homebrew prefix on PATH and every brew-installed tool goes missing.
# /etc/paths ships /usr/local/bin but not /opt/homebrew/bin, which is why an Intel install appears to work
# without this and a native Apple silicon install does not.
# zsh reads .zprofile for login shells, which is what login(1) starts for every Ghostty window and tab.
# Prefer the Apple silicon prefix and fall back to the Intel one so a machine mid-migration still works.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi
