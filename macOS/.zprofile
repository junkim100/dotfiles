##### Homebrew #####
# Homebrew's installer only prints this line under "Next steps" and never writes it to a shell file,
# so on a fresh machine nothing puts the Homebrew prefix on PATH and every brew-installed tool goes missing.
# /etc/paths ships /usr/local/bin but not /opt/homebrew/bin, so a native Apple silicon install needs this line.
# zsh reads .zprofile for login shells, which is what login(1) starts for every Ghostty window and tab.
# Only the Apple silicon prefix is supported; an Intel Homebrew under /usr/local is deliberately ignored
# so a Rosetta leftover can never shadow the native one.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
